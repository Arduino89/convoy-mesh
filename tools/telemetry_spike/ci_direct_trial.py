#!/usr/bin/env python3
"""Exercise the synthetic direct Android LAB against the unchanged wire auditor.

No build, cloud destination, emulator creation, SDK, Convoy access or publication.
The independent runtime gate must belong to this boot. Command output stays in
memory. Only enumerated, sanitized JSON receipts are exported. A runtime/harness
failure blocks dependent cases; observed acceptance failures preserve controls.
"""
import argparse
from collections import Counter, defaultdict
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import threading
import time
import uuid

from ci_native_trial import (TrialBlocked, load_rows, now, public_write, run,
                             validate_public_value)
from probe import event, reconcile
from run_native_followup import validate_runtime_gate
from runtime_control.build import sha256, valid_sdk_bounds
from runtime_control.smoke import validate_serial
from wire_audit_receiver import AuditReceiver

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PACKAGE = "com.cama.telemetry.direct_lab"
PHASES = ("revoke", "crash-after-intent", "crash-during-purge", "crash-after-purge", "before-intent",
          "normal", "refusal", "retry", "overflow", "inflight")
HOOKS = {"crash-after-intent": "after_intent", "crash-during-purge": "during_purge",
         "crash-after-purge": "after_purge"}
PHASE_FILES = {"expected.jsonl", "revoked-intent.jsonl", "refused-intent.jsonl", "states.jsonl",
               "checkpoints.jsonl", "lifecycle.jsonl", "validation.json"}
WIRE_FILES = {"requests.jsonl", "received.jsonl", "summary.json"}
ROOT_FILES = {"result.json", "runtime-gate-reference.json", "apk-receipt.json", "isolation.json"}
STATE_COUNTS = ("generation", "queue_count", "queue_bytes", "dropped_count", "refused_count",
                "revoked_count", "preflight_count", "preflight_rejected", "requests_started",
                "requests_acked", "in_flight_count")
STATE_REQUIRED = {"action_nonce", "action_ok", "action", "pid", "run_id", "consent",
                  "trace_sha256", "setting_value", *STATE_COUNTS}
SELF_CHECKS = {"valid_fixture_accepted", "foreign_distinct_id_rejected", "extra_property_rejected",
               "wrong_privacy_flag_rejected", "non_fake_token_rejected", "invalid_timestamp_rejected", "all_passed",
               "cloud_budget_490_plus_20_rejected", "cloud_budget_490_plus_10_allowed",
               "cloud_budget_500_plus_1_rejected", "cloud_budget_limit_over_500_rejected",
               "cloud_response_fractional_status_rejected", "cloud_response_quota_limited_rejected",
               "cloud_response_status_1_accepted"}
WIRE_SCOPE = "DIRECT_SENDER_LOOPBACK_WIRE_AUDIT_NOT_CLOUD_NOT_PRODUCTION"
BUILD_SOURCES = {"tools/telemetry_spike/direct_trial/" + name for name in
                 ("AndroidManifest.xml", "MainActivity.java", "DirectQueue.java", "build.py")} | {
                 "tools/telemetry_spike/runtime_control/build.py"}


def write_rows(path, rows):
    for row in rows:
        validate_public_value(row)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row, allow_nan=False) + "\n" for row in rows))


def append_row(path, row):
    validate_public_value(row)
    with path.open("a") as stream:
        stream.write(json.dumps(row, allow_nan=False) + "\n")


def audit_public_directory(out):
    """Closed file allowlist, reused by the external evidence emitter."""
    for path in out.rglob("*"):
        if path.is_symlink():
            raise TrialBlocked("PUBLIC_SYMLINK_REJECTED")
        if path.is_dir():
            if path.relative_to(out).parts not in {(name,) for name in (*PHASES, *("wire-" + p for p in PHASES))}:
                raise TrialBlocked("UNEXPECTED_PUBLIC_DIRECTORY")
            continue
        parts = path.relative_to(out).parts
        permitted = (len(parts) == 1 and parts[0] in ROOT_FILES or
                     len(parts) == 2 and parts[0] in PHASES and parts[1] in PHASE_FILES or
                     len(parts) == 2 and parts[0] in {"wire-" + p for p in PHASES} and parts[1] in WIRE_FILES)
        if not permitted or path.stat().st_size > 10 * 1024 * 1024:
            raise TrialBlocked("UNEXPECTED_PUBLIC_ARTIFACT")
        values = load_rows(path) if path.suffix == ".jsonl" else [json.loads(path.read_text())]
        for value in values:
            validate_public_value(value)


def export_evidence(work, out):
    for phase in PHASES:
        for directory, names in ((phase, PHASE_FILES), ("wire-" + phase, WIRE_FILES)):
            for name in sorted(names):
                path = work / directory / name
                if not path.exists():
                    continue
                if path.is_symlink() or path.stat().st_size > 10 * 1024 * 1024:
                    raise TrialBlocked("UNSAFE_EVIDENCE_FILE")
                if path.suffix == ".jsonl":
                    write_rows(out / directory / name, load_rows(path))
                else:
                    public_write(out / directory / name, json.loads(path.read_text()))
    audit_public_directory(out)


def validate_state(value, nonce, action, run_id, pid):
    """Reject stale acknowledgements, malformed counters and foreign processes."""
    if not isinstance(value, dict) or not STATE_REQUIRED <= value.keys():
        raise TrialBlocked("STATE_SCHEMA_INVALID")
    validate_public_value(value)
    if (value["action_nonce"] != nonce or value["action"] != action or
            value["run_id"] != run_id or value["pid"] != pid or value["action_ok"] is not True or
            type(value["consent"]) is not bool or type(value["pid"]) is not int or pid <= 0):
        raise TrialBlocked("STATE_IDENTITY_OR_ACTION_INVALID")
    if any(type(value[k]) is not int or not 0 <= value[k] < 2**63 for k in STATE_COUNTS):
        raise TrialBlocked("STATE_COUNTER_INVALID")
    if (not isinstance(value["trace_sha256"], str) or
            not (re.fullmatch(r"[a-f0-9]{64}", value["trace_sha256"]) or value["trace_sha256"] == "MISSING") or
            not isinstance(value["setting_value"], str) or len(value["setting_value"]) > 128):
        raise TrialBlocked("SENTINEL_STATE_INVALID")
    return value


def validate_checkpoint(value, nonce, stage, pid):
    if (not isinstance(value, dict) or value.get("action_nonce") != nonce or
            value.get("stage") != stage or type(value.get("pid")) is not int or
            value["pid"] != pid or pid <= 0):
        raise TrialBlocked("CHECKPOINT_IDENTITY_INVALID")
    if (stage not in {*HOOKS.values(), "before_intent_commit"} or value.get("consent") is not False or
            value.get("revocation_durable") is not (stage != "before_intent_commit") or
            type(value.get("generation")) is not int or value["generation"] < 1):
        raise TrialBlocked("CHECKPOINT_DURABLE_STATE_INVALID")
    validate_public_value(value)
    return value


class DirectReceiver(AuditReceiver):
    """Correct inherited provenance labels only; keep the audit unchanged."""
    def _append(self, name, records):
        super()._append(name, [dict(row, scope=WIRE_SCOPE) if "scope" in row else row for row in records])

    def _summary(self):
        super()._summary()
        path = self.out / "summary.json"
        summary = json.loads(path.read_text())
        summary["scope"] = WIRE_SCOPE
        temporary = self.out / "summary.tmp"
        temporary.write_text(json.dumps(summary, sort_keys=True) + "\n")
        temporary.replace(path)


class HeldAckReceiver(DirectReceiver):
    """Hold after the base auditor fsyncs both records, then lose that ACK.

    This changes fault timing only. The inherited payload/header verifier,
    normalized rows, redaction and response fault accounting remain unchanged.
    """
    def __init__(self, out, run_id, port=8765):
        self.held = threading.Event()
        self.release_ack = threading.Event()
        self.hold_timed_out = False
        super().__init__(out, run_id, "close-first", port)

    def _summary(self):
        super()._summary()
        if self.counts["ack_faults"] == 1 and not self.held.is_set():
            self.held.set()
            if not self.release_ack.wait(45):
                self.hold_timed_out = True


@contextmanager
def receiver(out, run_id, mode="normal"):
    observer = HeldAckReceiver(out, run_id) if mode == "hold" else DirectReceiver(out, run_id, mode)
    errors = []
    observer.server.handle_error = lambda *_: errors.append("RECEIVER_HANDLER_FAILED")
    thread = threading.Thread(target=observer.server.serve_forever,
                              kwargs={"poll_interval": 0.1}, daemon=True)
    thread.start()
    try:
        yield observer
    finally:
        if isinstance(observer, HeldAckReceiver):
            observer.release_ack.set()
        observer.server.shutdown()
        observer.close()
        thread.join(10)
        if errors or thread.is_alive() or getattr(observer, "hold_timed_out", False):
            raise TrialBlocked("RECEIVER_RUNTIME_FAILED")


def wire_summary(requests):
    violations, identities = Counter(), defaultdict(list)
    for request in requests:
        violations.update(request["violations"])
        for item in request["events"]:
            if item.get("event_id"):
                identities[item["event_id"]].append(item.get("uuid"))
    return {"requests": len(requests), "event_rows": sum(map(len, identities.values())),
            "privacy_pass": bool(requests) and not violations,
            "violation_counts": dict(violations),
            "wire_body_bytes": sum(row["wire_body_bytes"] for row in requests),
            "lost_acks": sum(row["response_mode"] == "close_without_response_after_fsync" for row in requests),
            "event_uuids": {key: {"rows": len(values), "uuids": sorted(set(values), key=str)}
                            for key, values in identities.items()}}


def classify_phase(phase, expected, revoked, rows, requests, validation):
    """Acceptance is computed from final receiver contents, never HTTP status."""
    finding = reconcile(expected, rows)
    wire = wire_summary(requests)
    failures = list(validation.get("observed_failures", []))
    final = validation.get("final_state", {})
    run_id = expected[0]["run_id"] if expected else None
    first = 21 if phase == "revoke" or phase in HOOKS or phase == "refusal" else 1
    count = 100 if phase == "normal" else 45 if phase == "overflow" else 20 if phase == "before-intent" else 10
    intended = [event(run_id, n) for n in range(first, first + count)] if run_id else []
    intended_revoked = [event(run_id, n) for n in range(1, 21)] if run_id and (phase == "revoke" or phase in HOOKS) else []
    if not expected or expected != intended or revoked != intended_revoked:
        failures.append("ORACLE_COHORT_INVALID")
    if validation.get("preflight_checks") != dict.fromkeys(SELF_CHECKS, True):
        failures.append("CLIENT_PREFLIGHT_COUNTEREXAMPLES_NOT_ATTESTED")
    if validation.get("requests_before_grant") != 0:
        failures.append("REQUEST_BEFORE_INITIAL_GRANT")
    if validation.get("sentinels_unchanged") is not True:
        failures.append("UNRELATED_STORAGE_CHANGED_OR_NOT_ATTESTED")
    if validation.get("receiver_closed_after_process_stop") is not True:
        failures.append("FINAL_OBSERVATION_BOUNDARY_NOT_ATTESTED")
    if final.get("queue_count") != 0 or final.get("in_flight_count") != 0:
        failures.append("FINAL_QUEUE_OR_INFLIGHT_NOT_EMPTY")
    if final.get("preflight_rejected") != 0:
        failures.append("LOCAL_PAYLOAD_GATE_REJECTED")
    if not wire["privacy_pass"] or not wire["event_rows"]:
        failures.append("FINAL_WIRE_PRIVACY_FAILED_OR_EMPTY")
    if finding["unexpected_ids"] or finding["conflicting_ids"]:
        failures.append("UNEXPECTED_OR_CONFLICTING_IDS")
    revoked_ids = {row["event_id"] for row in revoked}
    reappeared = sorted({row["event_id"] for row in rows} & revoked_ids)
    if reappeared:
        failures.append("REVOKED_IDS_REAPPEARED")
    if phase == "overflow":
        intended = [event(expected[0]["run_id"], i) for i in range(1, 46)] if expected else []
        if (expected != intended or len(expected) != 45 or finding["received_unique"] != 32 or
                finding["missing_ids"] != [row["event_id"] for row in intended[:13]] or
                final.get("dropped_count") != 13):
            failures.append("OVERFLOW_NOT_13_VISIBLE_OLDEST_DROPS")
    elif finding["missing_ids"]:
        failures.append("EXPECTED_IDS_MISSING")
    if phase == "retry":
        expected_ids = {row["event_id"] for row in expected}
        same = (len(expected) == 10 and set(wire["event_uuids"]) == expected_ids and all(
            item["rows"] >= 2 and len(item["uuids"]) == 1 and item["uuids"][0] is not None
            for item in wire["event_uuids"].values()))
        if not same or wire["lost_acks"] != 1:
            failures.append("LOST_ACK_RETRY_NOT_SAME_UUID_FOR_ALL_TEN")
        finding["retry_same_uuid_attested"] = same
    elif finding["duplicate_rows"]:
        failures.append("UNEXPECTED_DUPLICATES")
    if phase in HOOKS or phase == "refusal":
        if validation.get("pregrant_request_count") != 0 or validation.get("restart_denied") is not True:
            failures.append("ONLINE_RESTART_BEFORE_GRANT_NOT_SILENT_AND_DENIED")
    if phase in HOOKS:
        if validation.get("checkpoint_attested") != HOOKS[phase] or validation.get("revocation_durable") is not True:
            failures.append("CRASH_CUTPOINT_NOT_ATTESTED")
    if phase == "revoke" or phase in HOOKS:
        if final.get("revoked_count") != 20:
            failures.append("DURABLE_REVOKED_COUNTER_NOT_TWENTY")
    if phase == "before-intent":
        if (validation.get("checkpoint_attested") != "before_intent_commit" or
                validation.get("revocation_durable") is not False or
                validation.get("restart_prior_consent_preserved") is not True):
            failures.append("UNCOMMITTED_BOUNDARY_NOT_ATTESTED")
        finding["accepted_revocation"] = False
        finding["interpretation"] = "REVOKE_NOT_COMMITTED_OLD_DELIVERY_IS_NOT_ACCEPTED_REVOCATION_FAILURE"
    if phase == "inflight":
        boundary = validation.get("requests_at_revocation")
        if (validation.get("held_after_fsync_before_revoke") is not True or boundary != 1 or
                wire["requests"] != boundary or wire["lost_acks"] != 1 or
                final.get("consent") is not False or validation.get("inflight_before_revoke", 0) < 1):
            failures.append("INFLIGHT_BOUNDARY_OR_NO_RETRY_NOT_ATTESTED")
        finding["already_started_before_revocation_ids"] = sorted({row["event_id"] for row in rows})
        finding["already_received_bytes_cannot_be_recalled"] = True
    finding.update(status="FAILED" if failures else "BOUNDARY_OBSERVED" if phase == "before-intent" else "PASSED", failures=sorted(set(failures)),
                   wire=wire, revoked_ids_reappeared=reappeared,
                   observation_window="FINAL_RECEIVER_CONTENT_AFTER_VERIFIED_PROCESS_STOP")
    return finding


def overall_status(phases):
    if set(phases) != set(PHASES) or any(v.get("status") not in
            (("BOUNDARY_OBSERVED", "FAILED") if key == "before-intent" else ("PASSED", "FAILED"))
            for key, v in phases.items()):
        return "BLOCKED"
    return "FAILED" if any(v["status"] == "FAILED" for v in phases.values()) else "PASSED"


def final_reconciliation(work, phases):
    """Reopen final files; late arrivals cannot preserve an earlier PASS."""
    for phase in PHASES:
        if phases.get(phase, {}).get("status") not in ("PASSED", "FAILED", "BOUNDARY_OBSERVED"):
            continue
        directory = work / phase
        phases[phase] = classify_phase(phase, load_rows(directory / "expected.jsonl"),
                                      load_rows(directory / "revoked-intent.jsonl"),
                                      load_rows(work / ("wire-" + phase) / "received.jsonl"),
                                      load_rows(work / ("wire-" + phase) / "requests.jsonl"),
                                      json.loads((directory / "validation.json").read_text()))


class Device:
    def __init__(self, sdk, serial, env, gate):
        self.adb = sdk / "platform-tools" / "adb"
        self.serial, self.env, self.gate = serial, env, gate
        self.directory, self.run_id = None, None

    def call(self, *args, **kwargs):
        return run([self.adb, "-s", self.serial, *args], self.env, **kwargs)

    def check_gate(self):
        if self.call("shell", "getprop", "ro.kernel.qemu").stdout.strip() != "1":
            raise TrialBlocked("NOT_SYNTHETIC_EMULATOR")
        try:
            validate_runtime_gate(self.gate, self.call("get-serialno").stdout.strip(),
                                  self.call("shell", "cat", "/proc/sys/kernel/random/boot_id").stdout.strip())
        except (RuntimeError, ValueError, TypeError, KeyError) as exc:
            raise TrialBlocked("RUNTIME_GATE_INVALID_OR_ANDROID_REBOOTED") from exc

    def pid(self, absent_ok=False):
        result = self.call("shell", "pidof", PACKAGE, allow_failure=True)
        if result.returncode == 1 and not result.stdout.strip() and absent_ok:
            return None
        if result.returncode or not re.fullmatch(r"[1-9][0-9]*", result.stdout.strip()):
            raise TrialBlocked("LAB_PROCESS_ABSENT_OR_AMBIGUOUS")
        return int(result.stdout.strip())

    def json_file(self, name):
        result = self.call("shell", "run-as", PACKAGE, "cat", "files/" + name, allow_failure=True)
        if result.returncode:
            return None
        if len(result.stdout) > 65536:
            raise TrialBlocked("LAB_STATE_FILE_TOO_LARGE")
        try:
            return json.loads(result.stdout)
        except (ValueError, TypeError):
            return None

    def command(self, action, stop_at=None, **extras):
        nonce = uuid.uuid4().hex
        args = ["shell", "am", "start", "-W", "-n", PACKAGE + "/.MainActivity",
                "--es", "action", action, "--es", "nonce", nonce]
        for key, value in extras.items():
            args.extend(["--ei" if type(value) is int else "--es", key, str(value)])
        if stop_at:
            args.extend(["--es", "stop_at", stop_at])
        self.call(*args, timeout=25)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            pid = self.pid()
            value = self.json_file("checkpoint.json" if stop_at else "state.json")
            if isinstance(value, dict) and value.get("action_nonce") == nonce:
                if stop_at:
                    validate_checkpoint(value, nonce, stop_at, pid)
                else:
                    validate_state(value, nonce, action, self.run_id, pid)
                append_row(self.directory / ("checkpoints.jsonl" if stop_at else "states.jsonl"), value)
                return value
            time.sleep(0.25)
        raise TrialBlocked("LAB_COMMAND_ACK_TIMEOUT")

    def stop(self):
        previous = self.pid(absent_ok=True)
        self.call("shell", "am", "force-stop", PACKAGE)
        if self.pid(absent_ok=True) is not None:
            raise TrialBlocked("LAB_FORCE_STOP_NOT_ATTESTED")
        if self.directory:
            append_row(self.directory / "lifecycle.jsonl", {"action": "force_stop", "old_pid": previous,
                                                           "pid_absent": True})
        return previous

    def restart(self):
        previous = self.stop()
        value = self.command("state")
        if previous is None or value["pid"] == previous:
            raise TrialBlocked("LAB_RESTART_NEW_PID_NOT_ATTESTED")
        append_row(self.directory / "lifecycle.jsonl", {"action": "restart", "old_pid": previous,
                                                       "new_pid": value["pid"]})
        return value

    def network(self, online):
        if online:
            self.call("reverse", "tcp:8765", "tcp:8765")
        else:
            self.call("reverse", "--remove", "tcp:8765", allow_failure=True)
        listing = self.call("reverse", "--list").stdout
        exists = any(re.search(r"(?:^|\s)tcp:8765\s+tcp:8765(?:$|\s)", line) for line in listing.splitlines())
        if exists != online:
            raise TrialBlocked("LOCAL_REVERSE_STATE_NOT_ATTESTED")
        if self.directory:
            append_row(self.directory / "lifecycle.jsonl", {"action": "local_route", "online": online})

    def observe(self, seconds, predicate=None):
        deadline, final = time.monotonic() + seconds, None
        while True:
            final = self.command("state")
            if predicate is not None and predicate(final):
                return final, True
            if time.monotonic() >= deadline:
                return final, predicate is None
            time.sleep(min(0.5, max(0, deadline - time.monotonic())))


def verify_apk(args, env):
    receipt = json.loads(args.build_receipt.read_text())
    if (receipt.get("status") != "BUILT_VERIFIED_NOT_RUN" or
            receipt.get("scope") != "NATIVE_DIRECT_SYNTHETIC_DEFAULT_LOOPBACK_CLOUD_PRIVATE_CONFIG_REQUIRED" or
            receipt.get("runtime_tested") is not False or receipt.get("analytics_sdk") is not None or
            receipt.get("new_dependencies") != [] or
            receipt.get("source_commit") != args.source_commit or
            receipt.get("apk_sha256") != sha256(args.apk) or
            receipt.get("apk_bytes") != args.apk.stat().st_size):
        raise TrialBlocked("BUILD_RECEIPT_OR_APK_MISMATCH")
    sources = receipt.get("source_sha256", {})
    if not isinstance(sources, dict) or set(sources) != BUILD_SOURCES:
        raise TrialBlocked("BUILD_SOURCE_HASHES_MISSING")
    for name, digest in sources.items():
        path = REPO / name
        if (not isinstance(name, str) or path.resolve().is_relative_to(REPO) is not True or
                not re.fullmatch(r"[a-f0-9]{64}", digest) or not path.is_file() or sha256(path) != digest):
            raise TrialBlocked("BUILD_SOURCE_HASH_MISMATCH")
    tools = args.sdk / "build-tools" / "36.0.0"
    badging = run([tools / "aapt2", "dump", "badging", args.apk], env).stdout
    match = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.M)
    if not match or match.groups() != (PACKAGE, "1", "1.0"):
        raise TrialBlocked("APK_NOT_DIRECT_LAB")
    if not valid_sdk_bounds(badging):
        raise TrialBlocked("APK_SDK_BOUNDS_MISMATCH")
    permissions = re.findall(r"^uses-permission[^:]*: name='([^']+)'", badging, re.M)
    if permissions != ["android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE"]:
        raise TrialBlocked("APK_PERMISSION_SCOPE_REJECTED")
    signature = run([tools / "apksigner", "verify", "--print-certs", args.apk], env).stdout
    certs = re.findall(r"Signer #[0-9]+ certificate SHA-256 digest: ([a-fA-F0-9]{64})", signature)
    if len(certs) != 1:
        raise TrialBlocked("APK_SIGNATURE_NOT_ATTESTED")
    identity = {"package": PACKAGE, "version_code": 1, "version_name": "1.0", "min_sdk": 24,
                "target_sdk": 36, "requested_permissions": permissions, "certificate_sha256": certs[0].lower()}
    if receipt.get("identity") != identity:
        raise TrialBlocked("APK_IDENTITY_DIFFERS_FROM_BUILD_RECEIPT")
    return {"source_commit": args.source_commit, "apk_sha256": receipt["apk_sha256"],
            "apk_bytes": receipt["apk_bytes"], "identity": identity, "source_sha256": sources,
            "build_receipt_sha256": sha256(args.build_receipt)}


def case_run(device, work, phase, run_id, observe_seconds, delivery_seconds):
    directory, wire = work / phase, work / ("wire-" + phase)
    directory.mkdir()
    device.directory, device.run_id = directory, run_id
    for name in ("states.jsonl", "checkpoints.jsonl", "lifecycle.jsonl"):
        (directory / name).write_text("")
    revoke_case = phase == "revoke" or phase in HOOKS
    expected = ([event(run_id, i) for i in range(21, 31)] if revoke_case or phase == "refusal" else
                [event(run_id, i) for i in range(1, (101 if phase == "normal" else 46 if phase == "overflow" else 21 if phase == "before-intent" else 11))])
    revoked = [event(run_id, i) for i in range(1, 21)] if revoke_case else []
    refused = ([event(run_id, i) for i in range(1, 21)] if phase == "refusal" else
               [event(run_id, i) for i in range(31, 41)] if phase == "revoke" else [])
    write_rows(directory / "expected.jsonl", expected)
    write_rows(directory / "revoked-intent.jsonl", revoked)
    write_rows(directory / "refused-intent.jsonl", refused)
    validation = {"observed_failures": [], "observation_seconds": observe_seconds,
                  "before_durable_deny": "NOT_ATTESTED_NOT_COUNTED_AS_ACCEPTED_REVOCATION"}
    mode = "hold" if phase == "inflight" else "close-first" if phase == "retry" else "normal"
    baseline = None

    def check(condition, code):
        if not condition:
            validation["observed_failures"].append(code)

    def observe_sentinels(value):
        if baseline is not None and any(value[k] != baseline[k] for k in ("trace_sha256", "setting_value")):
            validation["observed_failures"].append("SENTINEL_CHANGED_DURING_CASE")

    with receiver(wire, run_id, mode) as observer:
        try:
            device.network(False)
            baseline = device.command("configure", run_id=run_id, capacity=32 if phase == "overflow" else 1000)
            check(baseline["consent"] is False and baseline["queue_count"] == 0, "INITIAL_DENY_EMPTY_NOT_ATTESTED")
            check(baseline["trace_sha256"] != "MISSING" and bool(baseline["setting_value"]), "INITIAL_SENTINELS_MISSING")
            state = device.command("preflight_checks")
            validation["preflight_checks"] = state.get("preflight_checks")
            validation["requests_before_grant"] = len(load_rows(wire / "requests.jsonl"))
            if phase == "refusal":
                device.network(True)
                state = device.command("capture", start=1, count=10)
                check(state["refused_count"] == 10 and state["queue_count"] == 0, "INITIAL_REFUSAL_NOT_ATTESTED")
                original_pid = device.stop()
                state = device.command("state")
                check(state["pid"] != original_pid, "RESTART_PID_UNCHANGED")
                state = device.command("capture", start=11, count=10)
                check(state["refused_count"] == 20 and state["queue_count"] == 0, "REFUSAL_AFTER_RESTART_NOT_ATTESTED")
                validation["restart_denied"] = state["consent"] is False and state["queue_count"] == 0
                state, _ = device.observe(observe_seconds)
                validation["restart_denied"] &= state["consent"] is False and state["queue_count"] == 0
                validation["pregrant_request_count"] = len(load_rows(wire / "requests.jsonl"))
                device.command("grant")
                device.command("capture", start=21, count=10)
            else:
                device.command("grant")
                count = 20 if revoke_case else len(expected)
                state = device.command("capture", start=1, count=count)
                check(state["queue_count"] == min(count, 32 if phase == "overflow" else 1000), "OFFLINE_QUEUE_COUNT_MISMATCH")
                check(not load_rows(wire / "requests.jsonl"), "OFFLINE_ROUTE_STILL_REACHABLE")
                if phase == "overflow":
                    check(state["dropped_count"] == 13, "OFFLINE_OVERFLOW_COUNTER_MISMATCH")
                if revoke_case or phase == "before-intent":
                    original_pid = state["pid"]
                    original_generation = state["generation"]
                    if phase in HOOKS or phase == "before-intent":
                        checkpoint = device.command("revoke", stop_at=HOOKS.get(phase, "before_intent_commit"))
                        validation["checkpoint_attested"] = checkpoint["stage"]
                        validation["revocation_durable"] = checkpoint.get("revocation_durable")
                        check(checkpoint["pid"] == original_pid, "CHECKPOINT_PROCESS_CHANGED")
                        device.stop()
                        device.network(True)  # Receiver is observing before online process bootstrap.
                        state = device.command("state")
                        check(state["pid"] != original_pid, "RESTART_PID_UNCHANGED")
                        if phase == "before-intent":
                            validation["restart_prior_consent_preserved"] = state["consent"] is True
                        else:
                            validation["restart_denied"] = state["consent"] is False and state["queue_count"] == 0
                            state, _ = device.observe(observe_seconds)
                            validation["restart_denied"] &= state["consent"] is False and state["queue_count"] == 0
                            validation["pregrant_request_count"] = len(load_rows(wire / "requests.jsonl"))
                    else:
                        state = device.command("revoke")
                        check(state["consent"] is False and state["queue_count"] == 0, "REVOKE_DID_NOT_DENY_AND_PURGE")
                        state = device.command("capture", start=31, count=10)
                        check(state["refused_count"] == 10 and state["queue_count"] == 0, "REFUSAL_AFTER_REVOKE_NOT_ATTESTED")
                        state = device.restart()
                        check(state["consent"] is False and state["queue_count"] == 0, "RESTART_DID_NOT_PRESERVE_DENY")
                    observe_sentinels(state)
                    if phase != "before-intent":
                        check(state["generation"] == original_generation + 1, "DURABLE_DENY_GENERATION_NOT_INCREMENTED_ONCE")
                        device.command("grant")
                        device.command("capture", start=21, count=10)
                        device.network(True)
                elif phase == "normal":
                    state = device.restart()
                    check(state["consent"] is True and state["queue_count"] == 100, "OFFLINE_RESTART_QUEUE_NOT_PRESERVED")
                    observe_sentinels(state)
                    device.network(True)
                else:
                    device.network(True)
            if phase == "inflight":
                if not observer.held.wait(20):
                    raise TrialBlocked("INFLIGHT_REQUEST_NOT_OBSERVED")
                state = device.command("state")
                validation["inflight_before_revoke"] = state["in_flight_count"]
                check(state["in_flight_count"] > 0, "INFLIGHT_ALREADY_FINISHED_BEFORE_REVOKE")
                validation["requests_at_revocation"] = len(load_rows(wire / "requests.jsonl"))
                validation["held_after_fsync_before_revoke"] = len(load_rows(wire / "received.jsonl")) == 10
                state = device.command("revoke")
                check(state["consent"] is False and state["queue_count"] == 0, "INFLIGHT_REVOKE_DID_NOT_DENY_AND_PURGE")
                observer.release_ack.set()
            minimum_rows = 20 if phase == "retry" else 32 if phase == "overflow" else len(expected)
            state, delivered = device.observe(delivery_seconds, lambda value:
                value["queue_count"] == 0 and value["in_flight_count"] == 0 and
                len(load_rows(wire / "received.jsonl")) >= minimum_rows)
            check(delivered, "DELIVERY_WINDOW_EXPIRED")
            if phase == "inflight":
                device.network(False)
                device.network(True)
                state = device.restart()
                device.command("flush")
                check(state["consent"] is False and state["queue_count"] == 0, "INFLIGHT_DENY_LOST_ON_RESTART")
            state, _ = device.observe(observe_seconds)  # Include delayed/retry arrivals, even after failures.
            observe_sentinels(state)
            validation["final_state"] = state
            validation["sentinels_unchanged"] = not any("SENTINEL" in code for code in validation["observed_failures"])
        finally:
            if isinstance(observer, HeldAckReceiver):
                observer.release_ack.set()
            device.stop()
            device.network(False)
            # Process absence is the end boundary; retain receiver contents through teardown.
            validation["receiver_closed_after_process_stop"] = True
            public_write(directory / "validation.json", validation)
    return classify_phase(phase, expected, revoked, load_rows(wire / "received.jsonl"),
                          load_rows(wire / "requests.jsonl"), validation)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("sdk", "jdk", "apk", "build-receipt", "runtime-gate", "out"):
        parser.add_argument("--" + name, required=True, type=Path)
    for name in ("serial", "source-commit", "run-id"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--observe-seconds", type=int, default=12)
    parser.add_argument("--delivery-seconds", type=int, default=60)
    args = parser.parse_args()
    validate_serial(args.serial)
    for phase in PHASES:
        event(args.run_id + "-" + phase, 1)
    if not re.fullmatch(r"[a-f0-9]{40}", args.source_commit):
        parser.error("full source commit required")
    if not 12 <= args.observe_seconds <= 30 or not 30 <= args.delivery_seconds <= 120:
        parser.error("observation must be12..30 seconds and delivery30..120 seconds")
    args.out.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, JAVA_HOME=str(args.jdk), ANDROID_SERIAL=args.serial)
    env["PATH"] = str(args.jdk / "bin") + os.pathsep + env.get("PATH", "")
    result = {"schema_version": 1, "scope": "DIRECT_SENDER_SYNTHETIC_LOCAL_ONLY_NOT_CONVOY",
              "source_commit": args.source_commit, "run_id": args.run_id, "started_utc": now(),
              "status": "BLOCKED", "phases": {}, "cloud_requests": "NOT_CONFIGURED",
              "before_durable_deny": "REVOCATION_NOT_COMMITTED_NO_SUCCESS_CLAIM",
              "crash_scope": "THREE_NAMED_COMMITTED_CUTPOINTS_NOT_ALL_CRASHES",
              "limits": ["LOCAL_REVERSE_UNAVAILABLE_NOT_ANDROID_RADIO_OFFLINE",
                         "ROW_CAPACITY_SATURATED_BYTE_AND_DATABASE_CAPS_NOT_SATURATED",
                         "NO_PHYSICAL_BATTERY_GNSS_BLE_OR_REAL_USER_TEST",
                         "FINITE_OBSERVATION_WINDOW_NOT_UNBOUNDED_DELIVERY_PROOF"],
              "public_artifacts_safe": False}
    installed, current, device = False, "preflight", None
    isolation = []
    with tempfile.TemporaryDirectory(prefix="direct-lab-private-") as temporary:
        work = Path(temporary)
        try:
            gate_bytes = args.runtime_gate.read_bytes()
            gate = json.loads(gate_bytes)
            device = Device(args.sdk, args.serial, env, gate)
            device.check_gate()
            public_write(args.out / "runtime-gate-reference.json", {
                "sha256": hashlib.sha256(gate_bytes).hexdigest(), "serial": args.serial,
                "boot_id": gate["boot_id"], "status": gate["status"]})
            public_write(args.out / "apk-receipt.json", verify_apk(args, env))
            if "package:" in device.call("shell", "pm", "path", PACKAGE, allow_failure=True).stdout:
                raise TrialBlocked("DIRECT_LAB_REQUIRES_FRESH_INSTALL")
            if not re.search(r"^Success$", device.call("install", str(args.apk.resolve()), timeout=120).stdout, re.M):
                raise TrialBlocked("DIRECT_LAB_INSTALL_NOT_CONFIRMED")
            installed = True
            for index, phase in enumerate(PHASES):
                current = phase
                device.check_gate()
                if index:
                    device.directory = None
                    device.stop()
                    output = device.call("shell", "pm", "clear", PACKAGE).stdout.strip()
                    if output != "Success":
                        raise TrialBlocked("ISOLATED_CASE_RESET_NOT_CONFIRMED")
                    isolation.append({"before_case": phase, "package": PACKAGE,
                                      "purpose": "CASE_ISOLATION_AFTER_PREVIOUS_EVIDENCE_NOT_REVOCATION", "success": True})
                result["phases"][phase] = case_run(device, work, phase, args.run_id + "-" + phase,
                                                   args.observe_seconds, args.delivery_seconds)
            final_reconciliation(work, result["phases"])
            result["status"] = overall_status(result["phases"])
        except (TrialBlocked, OSError, ValueError, TypeError, KeyError) as failure:
            code = str(failure) if isinstance(failure, TrialBlocked) else "HARNESS_INPUT_OR_IO_FAILURE"
            result["blocked_at"] = current
            result["blocked_reason"] = code
            if current in PHASES:
                result["phases"][current] = {"status": "BLOCKED", "reason": code}
            for phase in PHASES:
                result["phases"].setdefault(phase, {"status": "BLOCKED", "reason": "DEPENDENT_RUNTIME_NOT_EXECUTED"})
            result["status"] = "BLOCKED"
        finally:
            cleanup = {"installed": installed, "lab_stopped": False, "local_route_removed": False}
            if installed and device is not None:
                try:
                    device.directory = None
                    device.stop()
                    cleanup["lab_stopped"] = True
                    device.network(False)
                    cleanup["local_route_removed"] = True
                except TrialBlocked:
                    result["status"] = "BLOCKED"
                    result["cleanup_failure"] = "DIRECT_LAB_CLEANUP_NOT_ATTESTED"
            result["cleanup"] = cleanup
            public_write(args.out / "isolation.json", {"resets": isolation, "never_used_for_revocation": True})
            try:
                export_evidence(work, args.out)
                result["public_artifacts_safe"] = True
            except (TrialBlocked, OSError, ValueError, TypeError):
                result["status"] = "BLOCKED"
                result["evidence_failure"] = "PUBLIC_EVIDENCE_EXPORT_REJECTED"
            result["finished_utc"] = now()
            public_write(args.out / "result.json", result)
            audit_public_directory(args.out)
    print(json.dumps({"status": result["status"], "phases": {
        name: value["status"] for name, value in result["phases"].items()},
        "public_artifacts_safe": result["public_artifacts_safe"]}))
    return 0 if result["status"] == "PASSED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
