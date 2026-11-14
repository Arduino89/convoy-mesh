#!/usr/bin/env python3
"""Synthetic-only contract probe. NOT a PostHog/Firebase SDK or production queue.

Python stdlib SQLite + loopback HTTP provide a reproducible analysis control.
No cloud endpoints, names, coordinates, device logs or credentials are accepted.
"""
from __future__ import annotations

import argparse
from collections import Counter
import http.client
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def event(run, seq):
    value = {"schema_version": 1, "run_id": run, "event_id": f"{run}-{seq:06d}",
             "sequence": seq, "event_name": "cm_lab_probe", "synthetic": True}
    validate(value)
    return value


def validate(value):
    keys = {"schema_version", "run_id", "event_id", "sequence", "event_name", "synthetic"}
    if not isinstance(value, dict) or set(value) != keys:
        raise ValueError("Unexpected or missing property; no arbitrary payloads allowed")
    if type(value["schema_version"]) is not int or value["schema_version"] != 1:
        raise ValueError("Bad schema")
    if not isinstance(value["run_id"], str) or not re.fullmatch(r"synthetic-[a-z0-9-]{1,48}", value["run_id"]):
        raise ValueError("Only synthetic run identifiers allowed")
    seq = value["sequence"]
    if type(seq) is not int or not 1 <= seq <= 100000:
        raise ValueError("Bad sequence")
    if value["event_id"] != f"{value['run_id']}-{seq:06d}":
        raise ValueError("Identity does not match run and sequence")
    if value["synthetic"] is not True or value["event_name"] != "cm_lab_probe":
        raise ValueError("Only the synthetic probe event is allowed")


def reconcile(expected, received):
    """Exact set reconciliation; never hide duplicates by counting only unique IDs."""
    for row in expected + received:
        validate(row)
    exp = {r["event_id"]: r for r in expected}
    if len(exp) != len(expected):
        raise ValueError("The oracle itself contains duplicate event IDs")
    counts = Counter(r["event_id"] for r in received)
    actual = set(counts)
    variants = {}
    for row in received:
        variants.setdefault(row["event_id"], set()).add(encode(row))
    conflicts = sorted(k for k, v in variants.items()
                       if len(v) > 1 or (k in exp and encode(exp[k]) not in v))
    missing = sorted(set(exp) - actual)
    unexpected = sorted(actual - set(exp))
    return {"expected_unique": len(exp), "received_rows": len(received),
            "received_unique": len(actual), "missing_ids": missing,
            "unexpected_ids": unexpected, "duplicate_rows": len(received) - len(actual),
            "conflicting_ids": conflicts,
            "delivery_ratio": len(set(exp) & actual) / len(exp) if exp else None}


class Queue:
    """Single-worker reference model. SQLite bounded in count, bytes and pages."""
    def __init__(self, path, capacity=1000, byte_limit=65536):
        self.db = sqlite3.connect(path)
        self.db.execute("PRAGMA journal_mode=DELETE")
        self.db.execute("PRAGMA synchronous=FULL")
        self.db.execute("PRAGMA max_page_count=128")
        self.db.executescript("""
          CREATE TABLE IF NOT EXISTS queue(id INTEGER PRIMARY KEY, body TEXT, size INTEGER);
          CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY, value INTEGER);
        """)
        for key, val in {"consent": 0, "dropped": 0, "refused": 0, "revoked": 0,
                         "capacity": capacity, "byte_limit": byte_limit}.items():
            self.db.execute("INSERT OR IGNORE INTO state VALUES (?,?)", (key, val))
        self.db.commit()

    def get(self, key):
        return self.db.execute("SELECT value FROM state WHERE key=?", (key,)).fetchone()[0]

    def increment(self, key, n=1):
        self.db.execute("UPDATE state SET value=value+? WHERE key=?", (n, key))

    def consent(self, allowed):
        with self.db:
            self.db.execute("UPDATE state SET value=? WHERE key='consent'", (int(allowed),))
            if not allowed:
                self.increment("revoked", self.db.execute("SELECT count(*) FROM queue").fetchone()[0])
                self.db.execute("DELETE FROM queue")

    def put(self, row):
        validate(row)
        body = encode(row)
        size = len(body.encode())
        with self.db:
            if not self.get("consent"):
                self.increment("refused")
                return False
            if size > self.get("byte_limit"):
                self.increment("dropped")
                return False
            self.db.execute("INSERT INTO queue(body,size) VALUES (?,?)", (body, size))
            while True:
                count, nbytes = self.db.execute("SELECT count(*),coalesce(sum(size),0) FROM queue").fetchone()
                if count <= self.get("capacity") and nbytes <= self.get("byte_limit"):
                    break
                self.db.execute("DELETE FROM queue WHERE id=(SELECT min(id) FROM queue)")
                self.increment("dropped")
        return True

    def status(self):
        count, nbytes = self.db.execute("SELECT count(*),coalesce(sum(size),0) FROM queue").fetchone()
        return {"pid": os.getpid(), "queued": count, "payload_bytes": nbytes,
                **{k: self.get(k) for k in ("consent", "dropped", "refused", "revoked")}}

    def flush(self, port, batch_size=20):
        # Intentionally accepts only a loopback port, never a remote URL.
        sent, attempts, body_bytes = 0, 0, 0
        while self.get("consent") and attempts < 100:
            rows = self.db.execute("SELECT id,body FROM queue ORDER BY id LIMIT ?", (batch_size,)).fetchall()
            if not rows:
                break
            body = ("[" + ",".join(r[1] for r in rows) + "]").encode()
            attempts += 1
            body_bytes += len(body)
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
            try:
                conn.request("POST", "/events", body, {"Content-Type": "application/json"})
                response = conn.getresponse()
                response.read()
                if response.status != 200:
                    break  # No unbounded automatic retries.
            except (OSError, http.client.HTTPException):
                break
            finally:
                conn.close()
            with self.db:
                self.db.executemany("DELETE FROM queue WHERE id=?", [(r[0],) for r in rows])
            sent += len(rows)
        return {**self.status(), "acknowledged_rows": sent, "http_attempts": attempts,
                "attempted_json_body_bytes": body_bytes}


def worker(args):
    q = Queue(args.db, args.capacity, args.byte_limit)
    if args.op == "capture":
        if args.grant:
            q.consent(True)
        for seq in range(1, args.count + 1):
            q.put(event(args.run, seq))
        result = q.status()
    elif args.op == "revoke":
        q.consent(False)
        result = q.status()
    elif args.op == "grant":
        q.consent(True)
        result = q.status()
    elif args.op == "flush":
        result = q.flush(args.port)
    else:
        result = q.status()
    print(encode(result), flush=True)
    # Abrupt process exit after committed writes: no destructor/normal close.
    os._exit(0)


def call_worker(db, op, *extra):
    result = subprocess.run([sys.executable, __file__, "worker", "--db", str(db),
                             "--op", op, *map(str, extra)], check=True,
                            capture_output=True, text=True, timeout=15)
    return json.loads(result.stdout)


class Receiver:
    def __init__(self, fail_first_ack=False):
        self.rows, self.requests, self.body_bytes = [], 0, 0
        owner = self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass
            def do_POST(self):
                size = int(self.headers.get("Content-Length", "0"))
                if self.path != "/events" or not 0 < size <= 65536:
                    self.send_error(400)
                    return
                rows = json.loads(self.rfile.read(size))
                for row in rows:
                    validate(row)
                owner.rows.extend(rows)
                owner.requests += 1
                owner.body_bytes += size
                # Simulate accepted data but failed acknowledgement.
                self.send_response(503 if fail_first_ack and owner.requests == 1 else 200)
                self.end_headers()
                self.wfile.write(b"ok")
        self.server = HTTPServer(("127.0.0.1", 0), Handler)
        self.port = self.server.server_address[1]

    def __enter__(self):
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        return self

    def __exit__(self, *args):
        self.server.shutdown()
        self.thread.join()
        self.server.server_close()


def write_jsonl(path, rows):
    path.write_text("".join(encode(r) + "\n" for r in rows))


def run_lab(out):
    out.mkdir(parents=True, exist_ok=False)
    receipts = []
    with tempfile.TemporaryDirectory() as tmp:
        for name, count, capacity, revoke, ambiguous in [
            ("restart", 100, 1000, False, False),
            ("overflow", 45, 32, False, False),
            ("ack-retry", 10, 1000, False, True),
            ("revoked", 20, 1000, True, False),
            ("refused", 20, 1000, False, False),
        ]:
            db = Path(tmp) / (name + ".db")
            run_id = "synthetic-" + name
            expected = [event(run_id, i) for i in range(1, count + 1)]
            args = ["--count", count, "--run", run_id, "--capacity", capacity]
            if name != "refused":
                args.append("--grant")
            first = call_worker(db, "capture", *args)
            restarted = call_worker(db, "status")
            assert restarted["queued"] == first["queued"] and restarted["pid"] != first["pid"]
            # A bound but non-listening port provides an actual refused TCP connection.
            import socket
            with socket.socket() as unavailable:
                unavailable.bind(("127.0.0.1", 0))
                offline = call_worker(db, "flush", "--port", unavailable.getsockname()[1])
            assert offline["queued"] == first["queued"]
            if revoke:
                call_worker(db, "revoke")
            with Receiver(ambiguous) as receiver:
                flushed = call_worker(db, "flush", "--port", receiver.port)
                if ambiguous:
                    assert flushed["queued"] == count
                    flushed = call_worker(db, "flush", "--port", receiver.port)
                if revoke:
                    # Re-consent must not resurrect revoked queued records in this model.
                    call_worker(db, "grant")
                    call_worker(db, "flush", "--port", receiver.port)
            # Intentionally denied/revoked records are forbidden, not delivery loss.
            admissible = [] if revoke or name == "refused" else expected
            result = reconcile(admissible, receiver.rows)
            case_dir = out / name
            case_dir.mkdir()
            write_jsonl(case_dir / "attempted.jsonl", expected)
            write_jsonl(case_dir / "expected.jsonl", admissible)
            write_jsonl(case_dir / "received.jsonl", receiver.rows)
            receipts.append({"case": name, "scope": "PYTHON_LOOPBACK_REFERENCE_ONLY",
                             "attempted": count, "after_capture": first,
                             "after_restart": restarted, "offline": offline,
                             "after_flush": flushed, "analysis": result,
                             "receiver_json_body_bytes": receiver.body_bytes,
                             "receiver_requests": receiver.requests,
                             "sqlite_file_bytes": db.stat().st_size,
                             "revoked_or_refused": count if revoke or name == "refused" else 0})
    by_case = {r["case"]: r["analysis"] for r in receipts}
    assert by_case["restart"]["received_unique"] == 100 and not by_case["restart"]["missing_ids"]
    assert len(by_case["overflow"]["missing_ids"]) == 13
    assert by_case["ack-retry"]["duplicate_rows"] == 10
    assert by_case["revoked"]["received_rows"] == by_case["refused"]["received_rows"] == 0
    summary = {"evidence_level": "LOCAL_REFERENCE_EXECUTED_NOT_VENDOR_SDK",
               "python": sys.version.split()[0], "sqlite": sqlite3.sqlite_version,
               "executed_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
               "provider_delivery": "NOT_RUN", "android": "NOT_RUN",
               "battery": "NOT_MEASURED", "cases": receipts}
    (out / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="command", required=True)
    lab = subs.add_parser("lab")
    lab.add_argument("--out", type=Path, required=True)
    w = subs.add_parser("worker")
    w.add_argument("--db", required=True)
    w.add_argument("--op", choices=["capture", "status", "flush", "grant", "revoke"], required=True)
    w.add_argument("--run", default="synthetic-default")
    w.add_argument("--count", type=int, default=0)
    w.add_argument("--capacity", type=int, default=1000)
    w.add_argument("--byte-limit", type=int, default=65536)
    w.add_argument("--port", type=int, default=0)
    w.add_argument("--grant", action="store_true")
    check = subs.add_parser("reconcile")
    check.add_argument("--expected", type=Path, required=True)
    check.add_argument("--received", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "worker":
        worker(args)
    elif args.command == "lab":
        run_lab(args.out)
    else:
        load = lambda p: [json.loads(line) for line in p.read_text().splitlines() if line.strip()]
        print(json.dumps(reconcile(load(args.expected), load(args.received)), indent=2))


if __name__ == "__main__":
    main()
