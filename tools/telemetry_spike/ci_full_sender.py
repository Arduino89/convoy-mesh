#!/usr/bin/env python3
"""Full native sender, shared HTTP reader, synthetic loopback only."""
import argparse
import base64
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import threading

import ci_direct_trial as direct
from ci_native_trial import TrialBlocked, public_write, validate_public_value
from probe import event, reconcile
from ci_provision_probe import block_network, radio_snapshot, restore_radios

OK = b'{"status":"Ok"}'
SCOPE = "FULL_ANDROID_SENDER_LOOPBACK_SHARED_HTTP_READER_NO_POSTHOG"


class OkReceiver(direct.DirectReceiver):
    def _response_body(self, status):
        return OK if status == 200 else super()._response_body(status)


class OkHeldReceiver(direct.HeldAckReceiver):
    def _response_body(self, status):
        return OK if status == 200 else super()._response_body(status)


class FixtureReceiver(OkReceiver):
    BODIES = {"ok": OK, "quota": b'{"status":"Ok","quota_limited":["product_analytics"]}',
              "malformed": b'{"status":', "utf8": b'\xff', "unknown": b'{"status":"UNKNOWN"}', "truncated": OK}

    def __init__(self, out, run_id, kind, port=8765):
        if kind not in {*self.BODIES, "batch"}: raise TrialBlocked("FIXTURE_CATEGORY_INVALID")
        self.kind = kind
        self.first_held, self.second_held = threading.Event(), threading.Event()
        self.first_release, self.second_release = threading.Event(), threading.Event()
        self.timeout = False
        super().__init__(out, run_id, port=port)

    def _handler(self):
        owner, base = self, super()._handler()
        class Handler(base):
            def send_header(self, name, value):
                if owner.kind == "truncated" and name.lower() == "content-length":
                    value = str(int(value) + 7)
                super().send_header(name, value)
        return Handler

    def _response_body(self, status):
        # Called only after inherited audit and durable receiver writes.
        if self.kind == "batch" and self.accepted_batches in (1, 2):
            ready, release = ((self.first_held, self.first_release) if self.accepted_batches == 1
                              else (self.second_held, self.second_release))
            ready.set()
            if not release.wait(30): self.timeout = True
            return OK
        return self.BODIES[self.kind]


@contextmanager
def fixture(out, run_id, kind):
    observer = FixtureReceiver(out, run_id, kind)
    errors = []
    observer.server.handle_error = lambda *_: errors.append(True)
    thread = threading.Thread(target=observer.server.serve_forever, kwargs={"poll_interval": .1}, daemon=True)
    thread.start()
    try: yield observer
    finally:
        observer.first_release.set(); observer.second_release.set()
        observer.server.shutdown(); observer.close(); thread.join(10)
        if errors or thread.is_alive() or observer.timeout: raise TrialBlocked("FIXTURE_SERVER_FAILED")


def require(condition, reason):
    if not condition: raise TrialBlocked(reason)


def extra_case(device, work, kind, prefix):
    run_id = prefix + "-" + kind
    directory = work / kind; directory.mkdir()
    device.directory, device.run_id = directory, run_id
    # Explicit fresh case isolation, never the revocation mechanism.
    device.stop(); device.network(False)
    require(device.call("shell", "pm", "clear", direct.PACKAGE).stdout.strip() == "Success", "CASE_RESET_FAILED")
    with fixture(work / ("wire-" + kind), run_id, kind) as observer:
        try:
            first = restarted = None
            base = device.command("configure", run_id=run_id, capacity=1000)
            device.command("grant")
            before = device.command("capture", start=1, count=25)
            require(before["transport_mode"] == "local_loopback" and before["queue_count"] == 25 and before["requests_acked"] == 0, "OFFLINE_QUEUE_INVALID")
            device.network(True); device.command("flush")
            if kind == "batch":
                require(observer.first_held.wait(20), "FIRST_BATCH_NOT_HELD")
                first = device.command("state")
                require(first["queue_count"] == 25 and first["requests_acked"] == 0 and
                        first["queue_snapshot_sha256"] == before["queue_snapshot_sha256"], "QUEUE_CHANGED_BEFORE_ACK")
                observer.first_release.set()
                require(observer.second_held.wait(20), "SECOND_BATCH_NOT_HELD")
                retained = device.command("state")
                require(retained["queue_count"] == 5 and retained["requests_acked"] == 1 and
                        retained["queue_snapshot_sha256"] == before["queue_after_batch_sha256"], "ACK_REMOVED_UNSELECTED_ROWS")
                observer.second_release.set()
            else:
                category = {"quota":"QUOTA_LIMITED", "malformed":"MALFORMED_RESPONSE",
                            "utf8":"MALFORMED_RESPONSE", "unknown":"UNRECOGNIZED_RESPONSE", "truncated":"RESPONSE_READ_FAILED"}[kind]
                _, seen = device.observe(20, lambda s: s["last_response_category"] == category)
                require(seen, "RESPONSE_REJECTION_NOT_OBSERVED")
                device.network(False)
                retained, settled = device.observe(35, lambda s: s["in_flight_count"] == 0)
                require(settled and retained["requests_started"] >= 1 and retained["requests_acked"] == 0 and retained["queue_count"] == 25 and
                        retained["queue_snapshot_sha256"] == before["queue_snapshot_sha256"], "REJECTED_RESPONSE_REMOVED_ROWS")
                restarted = device.restart()
                require(restarted["queue_snapshot_sha256"] == before["queue_snapshot_sha256"] and
                        restarted["queue_count"] == 25 and restarted["requests_acked"] == 0, "REJECTED_QUEUE_LOST_ON_RESTART")
                observer.kind = "ok"
                device.network(True); device.command("flush")
            final, drained = device.observe(60, lambda s: s["queue_count"] == 0 and s["in_flight_count"] == 0)
            require(drained and final["requests_acked"] == 2, "RECOVERY_ACK_INVALID")
            require(all(s[k] == base[k] for s in (before, retained, final) for k in ("trace_sha256", "setting_value")), "SENTINELS_CHANGED")
        finally:
            observer.first_release.set(); observer.second_release.set()
            device.stop(); device.network(False)
    requests = direct.load_rows(work / ("wire-"+kind) / "requests.jsonl")
    rows = direct.load_rows(work / ("wire-"+kind) / "received.jsonl")
    finding = reconcile([event(run_id, n) for n in range(1,26)], rows)
    require(not finding["missing_ids"] and not finding["unexpected_ids"] and not finding["conflicting_ids"], "RECEIVER_IDENTITIES_INVALID")
    require(direct.wire_summary(requests)["privacy_pass"], "WIRE_PRIVACY_FAILED")
    # Exact body/UUID equality for all repeated transmissions, not cloud deduplication.
    versions, request_proof = {}, []
    for request in requests:
        items = []
        for item in request["payload_redacted"]["batch"]:
            identity = item["properties"]["event_id"]
            digest = hashlib.sha256(json.dumps(item,sort_keys=True,separators=(",",":")).encode()).hexdigest()
            versions.setdefault(identity,set()).add((item["uuid"],item["timestamp"],digest))
            items.append({"event_id":identity,"uuid":item["uuid"],"timestamp":item["timestamp"],"canonical_item_sha256":digest})
        request_proof.append({"request_index":request["request_index"],"audit_pass":request["audit_pass"],
                              "violations":request["violations"],"items":items})
    require(all(len(v)==1 for v in versions.values()), "RETRY_EVENT_IDENTITY_OR_CONTENT_CHANGED")
    return {"status":"PASS", "fixture":kind, "before":before, "retained":retained, "final":final,
            "state_before_ack":first, "state_restart_offline":restarted,
            "receiver":finding, "requests_proof":request_proof,
            "wire":direct.wire_summary(requests), "synthetic_case_reset_not_revocation":True}


def main():
    # Reuse the complete existing command line and all inherited acceptance gates.
    argv = sys.argv[1:]
    p = argparse.ArgumentParser(add_help=False)
    for name in ("sdk","jdk","runtime-gate","out"): p.add_argument("--"+name, type=Path)
    for name in ("serial","run-id","source-commit"): p.add_argument("--"+name)
    a, _ = p.parse_known_args(argv)
    result = {"schema_version":1,"scope":SCOPE,"source_commit":a.source_commit,
              "new_posthog_rows_authorized":0,"project_credentials_loaded":False,
              "status":"BLOCKED","cases":{},"inherited_suite_status":"NOT_RUN",
              "limits":["LOOPBACK_HTTP_NOT_TLS_OR_CLOUD_STORAGE", "NO_OLD20_RETRY", "NO_PHONE_OR_BATTERY_PROOF"]}
    output = a.out.parent / "full-proof-public" / "result.json"
    records, initial, device = [], None, None
    try:
        env=dict(os.environ,JAVA_HOME=str(a.jdk),ANDROID_SERIAL=a.serial)
        device=direct.Device(a.sdk,a.serial,env,json.loads(a.runtime_gate.read_text())); device.check_gate()
        initial=radio_snapshot(device,records)
        result["offline_before"]=block_network(device,records)
        direct.DirectReceiver, direct.HeldAckReceiver = OkReceiver, OkHeldReceiver
        status = direct.main()
        result["inherited_suite_status"]="PASS" if status==0 else "FAILED"
        require(status==0, "INHERITED_REGRESSIONS_FAILED")
        with tempfile.TemporaryDirectory(prefix="full-sender-local-") as temp:
            for kind in ("batch","quota","malformed","utf8","unknown","truncated"):
                result["cases"][kind]=extra_case(device,Path(temp),kind,a.run_id)
        result["offline_after"]=block_network(device,records)
        result["status"]="PASS_FULL_ANDROID_SENDER_LOCAL"
    except (TrialBlocked,OSError,ValueError,KeyError,TypeError) as failure:
        result["blocked_reason"]=str(failure) if isinstance(failure,TrialBlocked) else "LOCAL_HARNESS_INPUT_FAILED"
    finally:
        try:
            if device is not None:
                device.directory=None; device.stop(); device.network(False)
                result["lab_stopped_route_removed"]=True
            if initial is not None:
                restore_radios(device,records,initial); result["radios_restored"]=True
        except (TrialBlocked,OSError):
            result["status"]="BLOCKED"; result["cleanup_failure"]="LOCAL_SENDER_CLEANUP_FAILED"
        result["safe_command_categories"]=records
        public_write(output,result)
    print(json.dumps({"status":result["status"],"new_posthog_rows_authorized":0}))
    return 0 if result["status"]=="PASS_FULL_ANDROID_SENDER_LOCAL" else 1


def emit(path):
    raw=path.read_bytes(); value=json.loads(raw); validate_public_value(value)
    require(value.get("scope")==SCOPE and len(raw)<262144,"EXPORT_INVALID")
    encoded=base64.b64encode(raw).decode(); chunks=[encoded[i:i+4096] for i in range(0,len(encoded),4096)]
    print("CONVOY_FULL_BEGIN "+json.dumps({"bytes":len(raw),"sha256":hashlib.sha256(raw).hexdigest(),"chunks":len(chunks)}))
    for n,c in enumerate(chunks): print("CONVOY_FULL_CHUNK "+str(n)+":"+c)


if __name__ == "__main__":
    if len(sys.argv)==3 and sys.argv[1]=="--emit": emit(Path(sys.argv[2]))
    else: raise SystemExit(main())
