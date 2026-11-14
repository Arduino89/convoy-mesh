#!/usr/bin/env python3
"""Read-only, independent receipt recomputation; never runs Android or imports lab code.

Usage: python recompute_direct_review.py BUNDLE --support SUPPORT --out OUTPUT.json
SUPPORT contains the independent-source-review and two reconstructed original receipts.
"""
import argparse
from collections import Counter, defaultdict
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import uuid

COMMIT = "809caf200f6232b162fee009fa2a7c2b484d7855"
RUN = "synthetic-direct-42299072769"
PHASES = ("revoke", "crash-after-intent", "crash-during-purge", "crash-after-purge",
          "before-intent", "normal", "refusal", "retry", "overflow", "inflight")
HOOKS = {"crash-after-intent": "after_intent", "crash-during-purge": "during_purge",
         "crash-after-purge": "after_purge"}
FIELDS = {"schema_version", "run_id", "event_id", "sequence", "event_name", "synthetic"}
PROPS = FIELDS | {"$geoip_disable", "$process_person_profile"}
ITEM = {"event", "distinct_id", "uuid", "timestamp", "properties"}
SELF = {"all_passed", "valid_fixture_accepted", "foreign_distinct_id_rejected",
        "extra_property_rejected", "wrong_privacy_flag_rejected", "non_fake_token_rejected",
        "invalid_timestamp_rejected", "cloud_budget_490_plus_20_rejected",
        "cloud_budget_490_plus_10_allowed", "cloud_budget_500_plus_1_rejected",
        "cloud_budget_limit_over_500_rejected", "cloud_response_fractional_status_rejected",
        "cloud_response_quota_limited_rejected", "cloud_response_status_1_accepted"}


def check(value, message):
    if not value:
        raise ValueError(message)


def pairs(items):
    result = {}
    for key, value in items:
        check(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def parse(text):
    return json.loads(text, object_pairs_hook=pairs,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite JSON")))


def read(path):
    return parse(path.read_text())


def rows(path):
    return [parse(line) for line in path.read_text().splitlines() if line]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def event(run, seq):
    return {"schema_version": 1, "run_id": run, "event_id": f"{run}-{seq:06d}",
            "sequence": seq, "event_name": "cm_lab_probe", "synthetic": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--support", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--source-review", required=True, type=Path)
    args = parser.parse_args()
    bundle, support = args.bundle, args.support
    public = bundle / "direct-public"
    manifest = {}
    for line in (bundle / "SHA256SUMS.txt").read_text().splitlines():
        sha, name = line.split("  ", 1)
        check(name not in manifest and re.fullmatch(r"[a-f0-9]{64}", sha), "manifest schema")
        check(not Path(name).is_absolute() and ".." not in Path(name).parts, "manifest path")
        path = bundle / name
        check(path.is_file() and not path.is_symlink() and digest(path) == sha, "manifest hash " + name)
        manifest[name] = sha
    check(len(manifest) == 107, "manifest count")
    check({str(p.relative_to(bundle)) for p in bundle.rglob("*") if p.is_file()} ==
          set(manifest) | {"SHA256SUMS.txt"}, "unlisted file")
    exported = read(support / "export-manifest.json")
    check(set(exported["files"]) == set(manifest) | {"SHA256SUMS.txt"}, "export file list")
    source = read(args.source_review)
    check(source["status"] == "PASS_STATIC_SOURCE_REVIEW_ONLY" and len(source["native_source_sha256"]) == 5, "source linkage")
    original_gate = support / "original-control-receipt.json"
    gate = read(bundle / "runtime-control-smoke/receipt.json")
    gate_ref = read(public / "runtime-gate-reference.json")
    check(read(original_gate) == gate and digest(original_gate) == gate_ref["sha256"], "gate normalization")
    check(gate["status"] == gate_ref["status"] == "PASS_NATIVE_RUNTIME_CONTROL" and
          gate["gate_pass"] is True and gate["telemetry_tested"] is False, "control gate status/scope")
    check(gate["serial"] == gate_ref["serial"] == "emulator-5554" and
          gate["boot_id"] == gate_ref["boot_id"] and str(uuid.UUID(gate["boot_id"])) == gate["boot_id"],
          "same boot gate")
    stages = gate["stages"]
    check([s["name"] for s in stages] == ["verify_apk", "boot_and_package_manager", "install_verified_control",
          "first_resumed_ready", "force_stop_pid_absent", "second_resumed_ready",
          "new_pid_persisted_counter_same_boot", "control_stopped_data_preserved"] and
          all(s["pass"] is True for s in stages), "control stages")
    first, second = stages[3]["observation"], stages[5]["observation"]
    check(first["ready"] is second["ready"] is True and type(first["launches"]) is int and
          type(second["launches"]) is int and 1 <= first["launches"] < 2**63 - 1 and
          second["launches"] == first["launches"] + 1
          and first["pid"] != second["pid"] and first["pid"] > 0 and second["pid"] > 0
          and first["nonce"] != second["nonce"] and
          first["package"] == second["package"] == "com.cama.telemetry.runtime_control", "control observations")
    build = read(bundle / "direct-build/build-receipt.json")
    apk = read(public / "apk-receipt.json")
    original_build = support / "original-build-receipt.json"
    check(read(original_build) == build and digest(original_build) == apk["build_receipt_sha256"], "build normalization")
    for key in ("source_commit", "apk_sha256", "apk_bytes", "identity", "source_sha256"):
        check(build[key] == apk[key], "build/runtime APK identity " + key)
    check(build["source_commit"] == COMMIT and build["analytics_sdk"] is None and
          build["new_dependencies"] == [] and build["identity"]["package"] == "com.cama.telemetry.direct_lab"
          and build["identity"]["requested_permissions"] == ["android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE"], "build scope")
    hashes = source["native_source_sha256"]
    for name, sha in build["source_sha256"].items():
        if name in hashes:
            check(hashes[name] == sha, "published source build hash " + name)
    report = {"schema_version": 1, "review_status": "INDEPENDENT_RECOMPUTATION_COMPLETE",
              "scope": "ACTUAL_ANDROID_LOCAL_REGRESSION_OF_CLOUD_CAPABLE_SOURCE_NOT_CLOUD_NOT_CONVOY",
              "cloud_execution_status": "NOT_CONFIGURED_LOCAL_ONLY_RUN",
              "source_commit": COMMIT, "github_run_id": 42299072769, "github_job_id": 128171820455,
              "manifest_entries_verified": len(manifest), "manifest_sha256": digest(bundle / "SHA256SUMS.txt"),
              "export_zip_sha256_reported_by_decoder": exported["sha256"],
              "export_zip_bytes_reported_by_decoder": exported["bytes"],
              "method": "Reconstruct fixed cohorts, parse final payload_redacted, cross-check normalized records and every native state; no lab classifier or summary PASS imported.",
              "control": {"first_pid": first["pid"], "second_pid": second["pid"], "launches": [first["launches"], second["launches"]],
                          "same_boot": True, "original_sha256": digest(original_gate),
                          "normalized_sha256": digest(bundle / "runtime-control-smoke/receipt.json"),
                          "semantic_equal": True, "original_hash_matches_runtime_gate_reference": True},
              "build": {"apk_sha256": apk["apk_sha256"], "original_receipt_sha256": digest(original_build),
                        "normalized_receipt_sha256": digest(bundle / "direct-build/build-receipt.json"),
                        "semantic_equal": True, "original_hash_matches_runtime_reference": True}, "phases": {}}
    host = read(support / "host-test-observation.json")
    check(host["run_id"] == 42299072769 and host["job_id"] == 128171820455 and
          host["run_attempt"] == 1 and host["source_commit"] == COMMIT and
          (host["total"], host["passed"], host["skipped"], host["failed"]) == (193, 193, 0, 0),
          "host control observation")
    check(len(host["stdout_summary_lines"]) == 2 and
          re.search(r"Z Ran 193 tests in [0-9.]+s$", host["stdout_summary_lines"][0]) and
          re.search(r"Z OK$", host["stdout_summary_lines"][1]), "host log summary")
    report["host_controls"] = {"total": 193, "passed": 193, "skipped": 0, "failed": 0,
                              "observation_sha256": digest(support / "host-test-observation.json"),
                              "private_log_value_not_published": True}
    total_requests = total_rows = total_states = total_wire = total_refused = total_revoked = 0
    global_uuid = defaultdict(set)
    all_nonces = []
    sentinel_pairs = set()
    for phase in PHASES:
        directory = public / phase
        run = RUN + "-" + phase
        start, count = ((21, 10) if phase == "revoke" or phase in HOOKS or phase == "refusal" else
                        (1, 100 if phase == "normal" else 45 if phase == "overflow" else 20 if phase == "before-intent" else 10))
        expected = [event(run, n) for n in range(start, start + count)]
        revoked = [event(run, n) for n in range(1, 21)] if phase == "revoke" or phase in HOOKS else []
        refused = ([event(run, n) for n in range(1, 21)] if phase == "refusal" else
                   [event(run, n) for n in range(31, 41)] if phase == "revoke" else [])
        for filename, intended in [("expected.jsonl", expected), ("revoked-intent.jsonl", revoked),
                                   ("refused-intent.jsonl", refused)]:
            check(rows(directory / filename) == intended, phase + " exact oracle " + filename)
        requests = rows(public / ("wire-" + phase) / "requests.jsonl")
        received = rows(public / ("wire-" + phase) / "received.jsonl")
        normalized, copies = [], defaultdict(list)
        for index, request in enumerate(requests, 1):
            check(request["request_index"] == index and request["scope"] ==
                  "DIRECT_SENDER_LOOPBACK_WIRE_AUDIT_NOT_CLOUD_NOT_PRODUCTION", phase + " request identity")
            check(request["method"] == "POST" and request["path"] == "/batch/" and request["query_keys"] == [],
                  phase + " destination")
            check(request["violations"] == [] and request["audit_pass"] is True, phase + " observer violations")
            headers = request["headers_safe"]
            fixed = {"accept": "application/json", "accept-encoding": "identity", "connection": "close",
                     "content-type": "application/json", "host": "127.0.0.1:8765", "user-agent": "Java/1.8"}
            check(set(headers) == set(fixed) | {"content-length"} and all(headers[k] == v for k, v in fixed.items()),
                  phase + " exact headers")
            check(type(headers["content-length"]) is int and headers["content-length"] == request["wire_body_bytes"]
                  and 0 < request["wire_body_bytes"] <= 65536, phase + " body bound")
            body = request["payload_redacted"]
            check(set(body) == {"api_key", "batch"} and body["api_key"] == "<redacted:fake-token>"
                  and 1 <= len(body["batch"]) <= 20 and request["envelope_keys"] == sorted(body), phase + " envelope")
            batch_rows = []
            for item, shape in zip(body["batch"], request["events"], strict=True):
                check(set(item) == ITEM and item["event"] == "cm_lab_probe" and item["distinct_id"] == run,
                      phase + " exact event envelope identity")
                check(str(uuid.UUID(item["uuid"])) == item["uuid"], phase + " UUID")
                check(re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z", item["timestamp"]),
                      phase + " timestamp shape")
                datetime.fromisoformat(item["timestamp"].replace("Z", "+00:00"))
                props = item["properties"]
                check(set(props) == PROPS and props["$geoip_disable"] is True and props["$process_person_profile"] is False,
                      phase + " exact property whitelist")
                check(type(props["sequence"]) is int and type(props["schema_version"]) is int
                      and props["synthetic"] is True, phase + " business types")
                row = {key: props[key] for key in FIELDS}
                check(row == event(run, props["sequence"]) and 1 <= props["sequence"] <= 100000,
                      phase + " exact business row")
                check(shape["item_keys"] == sorted(ITEM) and shape["property_keys"] == sorted(PROPS)
                      and shape["event_id"] == row["event_id"] and shape["uuid"] == item["uuid"], phase + " shape consistency")
                batch_rows.append(row)
                copies[row["event_id"]].append(item)
                global_uuid[item["uuid"]].add(row["event_id"])
            check(batch_rows == request["normalized_rows"], phase + " request normalization")
            normalized.extend(batch_rows)
            total_wire += request["wire_body_bytes"]
        check(normalized == received, phase + " independent normalized stream")
        intended_ids = {e["event_id"] for e in expected}
        seen = Counter(e["event_id"] for e in normalized)
        missing = sorted(intended_ids - seen.keys())
        check(not seen.keys() - intended_ids, phase + " unexpected IDs")
        check(not ({e["event_id"] for e in revoked + refused} & seen.keys()), phase + " revoked/refused IDs received")
        check(missing == ([e["event_id"] for e in expected[:13]] if phase == "overflow" else []), phase + " missing IDs")
        duplicates = sum(seen.values()) - len(seen)
        lost = sum(r["response_mode"] == "close_without_response_after_fsync" for r in requests)
        if phase == "retry":
            check(len(requests) == 2 and lost == 1 and len(seen) == 10 and duplicates == 10
                  and all(len(items) == 2 and items[0] == items[1] for items in copies.values()), "exact retry copies")
        else:
            check(duplicates == 0 and lost == (1 if phase == "inflight" else 0), phase + " unexpected duplicates/ACK fault")
        states = rows(directory / "states.jsonl")
        checkpoints = rows(directory / "checkpoints.jsonl")
        all_nonces.extend(s["action_nonce"] for s in states + checkpoints)
        life = rows(directory / "lifecycle.jsonl")
        validation = read(directory / "validation.json")
        check(states and len({s["action_nonce"] for s in states}) == len(states), phase + " state nonces")
        for state in states:
            check(state.get("transport_mode") == "local_loopback", phase + " cloud mode unexpectedly active")
            check(not any(k.startswith("cloud_") or k in {"retry_armed", "retry_ack_discarded"} for k in state),
                  phase + " cloud ledger unexpectedly present")
            check(state["action_ok"] is True and state["error"] == "" and state["run_id"] == run
                  and type(state["pid"]) is int and state["pid"] > 0, phase + " state identity/action")
            check(state["preflight_rejected"] == 0 and state["database_max_bytes"] == 4194304
                  and state["queue_byte_limit"] == 1048576, phase + " native preflight/bounds")
        sentinel = {(s["setting_value"], s["trace_sha256"]) for s in states}
        check(len(sentinel) == 1, phase + " sentinel changed")
        setting, trace = next(iter(sentinel))
        check(setting.startswith("synthetic-setting-") and re.fullmatch(r"[a-f0-9]{64}", trace), phase + " sentinel shape")
        synthetic_uuid = setting.removeprefix("synthetic-setting-")
        check(str(uuid.UUID(synthetic_uuid)) == synthetic_uuid and hashlib.sha256(
            ("SYNTHETIC TRACE SENTINEL WITHOUT COORDINATES " + synthetic_uuid + "\n").encode()).hexdigest() == trace,
              phase + " sentinel actual trace hash")
        sentinel_pairs.add((setting, trace))
        selfchecks = [s for s in states if s["action"] == "preflight_checks"]
        check(len(selfchecks) == 1 and selfchecks[0]["preflight_checks"] == dict.fromkeys(SELF, True), phase + " native counterexamples")
        final = states[-1]
        check(validation["final_state"] == final and final["queue_count"] == 0 and final["in_flight_count"] == 0,
              phase + " final state")
        check(validation["observed_failures"] == [] and validation["requests_before_grant"] == 0
              and validation["receiver_closed_after_process_stop"] is True, phase + " observation receipts")
        check(life[0] == {"action": "local_route", "online": False} and life[-1] == life[0]
              and life[-2] == {"action": "force_stop", "old_pid": final["pid"], "pid_absent": True}, phase + " lifecycle end")
        check(all(s["requests_started"] == 0 for s in states[:next(i for i,s in enumerate(states) if s["action"] == "grant")]),
              phase + " initial deny dispatch")
        phases = {"result": "OBSERVED_WITHIN_LAB_SCOPE", "intended_count": len(expected), "requests": len(requests),
                  "received_rows": len(normalized), "received_unique": len(seen), "duplicate_rows": duplicates,
                  "missing_ids": missing, "revoked_unsent_count": len(revoked), "revoked_reappeared": 0,
                  "refused_count": len(refused), "refused_received": 0, "state_observations": len(states),
                  "sentinel_values_identical_all_states": True, "synthetic_trace_hash_recomputed": True,
                  "preflight_positive_and_five_negative_controls": True,
                  "native_preflight_result_flags": 14, "native_non_summary_checks": 13,
                  "seven_cloud_helpers_executed_without_cloud_transport": True,
                  "all_states_local_loopback": True, "cloud_ledger_fields_absent": True,
                  "wire_exact_keys_and_values": True,
                  "final_queue": final["queue_count"], "final_inflight": final["in_flight_count"], "lost_acks": lost}
        if phase in HOOKS or phase == "before-intent":
            check(len(checkpoints) == 1, phase + " checkpoint count")
            cp = checkpoints[0]
            stage = HOOKS.get(phase, "before_intent_commit")
            check(cp["stage"] == stage and cp["revocation_durable"] is (phase != "before-intent")
                  and cp["consent"] is False and cp["generation"] == 1 and cp["pid"] == states[0]["pid"],
                  phase + " checkpoint")
            restarted = next(i for i,s in enumerate(states) if s["pid"] != cp["pid"])
            check(life[1] == {"action": "force_stop", "old_pid": cp["pid"], "pid_absent": True}
                  and life[2] == {"action": "local_route", "online": True}, phase + " online recovery route")
            if phase in HOOKS:
                granted = next(i for i in range(restarted, len(states)) if states[i]["action"] == "grant")
                window = states[restarted:granted]
                check(window and all(s["consent"] is False and s["generation"] == 1 and s["queue_count"] == 0
                      and s["revoked_count"] == 20 and s["requests_started"] == 0 for s in window), phase + " recovery deny window")
                check(validation["pregrant_request_count"] == 0 and final["revoked_count"] == 20, phase + " pregrant receiver")
                phases["denied_online_recovery_observations_before_new_grant"] = len(window)
            else:
                check(states[restarted]["consent"] is True and states[restarted]["generation"] == 0
                      and states[restarted]["queue_count"] == 20 and final["revoked_count"] == 0, "precommit rollback")
                phases.update(result="BOUNDARY_OBSERVED_NOT_ACCEPTED_REVOCATION", accepted_revocation=False,
                              prior_consent_recovered=True, old_events_delivered=20)
            phases["pid_transition"] = [cp["pid"], states[restarted]["pid"]]
        else:
            check(not checkpoints, phase + " unexpected checkpoint")
        if phase == "revoke":
            rev = next(i for i,s in enumerate(states) if s["action"] == "revoke")
            granted = next(i for i in range(rev + 1, len(states)) if states[i]["action"] == "grant")
            window = states[rev:granted]
            check(all(s["consent"] is False and s["generation"] == 1 and s["queue_count"] == 0
                  and s["revoked_count"] == 20 for s in window) and len({s["pid"] for s in window}) == 2,
                  "ordinary revoke/restart")
            check(final["refused_count"] == 10 and final["revoked_count"] == 20, "post-revoke refusal")
        if phase == "refusal":
            granted = next(i for i,s in enumerate(states) if s["action"] == "grant")
            window = states[:granted]
            capture = [s for s in window if s["action"] == "capture"]
            check([s["refused_count"] for s in capture] == [10, 20] and capture[0]["pid"] != capture[1]["pid"]
                  and all(s["consent"] is False and s["queue_count"] == 0 and s["dispatch_attempts"] == 0 for s in window)
                  and validation["pregrant_request_count"] == 0, "online refusal/restart")
            phases["online_denied_observations_before_first_grant"] = len(window)
        if phase == "normal":
            first_new = next(s for s in states if s["pid"] != states[0]["pid"])
            check(first_new["queue_count"] == 100 and first_new["consent"] is True, "normal offline restart persistence")
        if phase == "overflow":
            check(final["capacity"] == 32 and final["dropped_count"] == 13 and len(seen) == 32, "visible FIFO overflow")
            phases["observed_drop_counter"] = 13
            phases["drop_counter_restart_durability_tested"] = False
        if phase == "retry":
            phases["retry_preserves_entire_event_uuid_timestamp_properties"] = True
        if phase == "inflight":
            rev = next(i for i,s in enumerate(states) if s["action"] == "revoke")
            check(states[rev-1]["in_flight_count"] == 1 and states[rev]["in_flight_count"] == 1
                  and states[rev]["consent"] is False and states[rev]["queue_count"] == 0
                  and states[rev]["requests_started"] == 1 and states[rev]["requests_acked"] == 0
                  and validation["held_after_fsync_before_revoke"] is True and validation["requests_at_revocation"] == 1
                  and len(requests) == 1 and final["consent"] is False and final["requests_acked"] == 0
                  and final["pid"] != states[rev]["pid"], "inflight received before deny/no retry after restart")
            phases.update(already_received_before_durable_revocation=10, requests_after_boundary=0,
                          evidence_basis="Receiver fsync hold handshake plus native inflight before/after revoke and final one-request stream")
        report["phases"][phase] = phases
        total_requests += len(requests)
        total_rows += len(normalized)
        total_states += len(states)
        total_refused += len(refused)
        total_revoked += len(revoked)
    check(all(len(ids) == 1 for ids in global_uuid.values()), "UUID collision across business IDs")
    check(len(sentinel_pairs) == 10, "case sentinel independence")
    check(len(all_nonces) == len(set(all_nonces)) == total_states + 4, "all command/checkpoint nonces unique")
    isolation = read(public / "isolation.json")
    check([r["before_case"] for r in isolation["resets"]] == list(PHASES[1:]) and
          all(r["success"] is True and r["package"] == "com.cama.telemetry.direct_lab" and
              r["purpose"] == "CASE_ISOLATION_AFTER_PREVIOUS_EVIDENCE_NOT_REVOCATION" for r in isolation["resets"]),
          "case-only storage isolation")
    check(not any("cloud-" in name or "private" in name for name in manifest if name.startswith("direct-public/")), "unexpected cloud/private local exported path")
    check(not any(name.startswith("cloud-public/") for name in manifest), "cloud must be absent in this local-only run")
    report["totals"] = {"requests": total_requests, "received_rows": total_rows,
                        "unique_business_ids_and_uuids": len(global_uuid), "wire_body_bytes": total_wire,
                        "state_observations": total_states, "revoked_unsent_intents": total_revoked,
                        "unique_command_and_checkpoint_nonces": len(all_nonces),
                        "revoked_reappeared": 0, "refused_intents": total_refused, "refused_received": 0,
                        "independent_sentinel_pairs": len(sentinel_pairs)}
    report["limitations"] = [
        "This verifies the local loopback regression within run14 on exact prepared source809caf200f6232b162fee009fa2a7c2b484d7855. All reviewed direct-public native states report local_loopback and no cloud ledger fields. Cloud preparation was skipped and cloud-public inventory is absent; no HTTPS acceptance or ingestion is established by these local receipts.",
        "All fourteen native preflight result flags were true in ten cases: thirteen checks plus all_passed. Seven added checks exercise pure budget/response helpers only, not the actual cloud transport path.",
        "Not a new Android execution: this script recomputes the provided synthetic receipts.",
        "The first observed control counter was2 and second3. The existing contract requires a positive first counter and exact+1 after a new PID/nonce on the same boot, not an initial1. The preceding activity creation is not explained by these two observations.",
        "Original gate/build JSON was reconstructed by root from job stdout; this review independently verifies semantic equality and the exact referenced byte hashes.",
        "ZIP bytes are not an input to this script; per-file manifest hashes and the decoded export inventory are independently checked.",
        "Host test counts are checked against bounded extracted log summary lines and their private connector response digest; the complete job log is not a public recomputation input.",
        "Lifecycle/state/checkpoint files have no shared monotonic timestamps; cross-file causal order also relies on the exact reviewed harness call order and hold handshake, not an independent wall-clock trace.",
        "Receiver payload has a redacted token; original fake-token acceptance relies on the unchanged auditor whose violations are retained. All other final synthetic values and field shapes are rechecked.",
        "Requests are bounded loopback observations; adb-reverse removal is endpoint unreachability, not physical radio offline.",
        "Three named post-commit process-kill boundaries passed; arbitrary crashes, power loss, corrupt storage and forensic deletion remain untested.",
        "Before durable intent commit the request is not accepted, prior consent recovers and twenty old events were delivered; this is not counted as successful accepted revocation.",
        "Ten inflight events were already received before revocation and cannot be recalled; no later request appeared in the finite observation window.",
        "Row cap32/45 overflow was exercised, not byte-cap saturation, storage-full behavior, RAM, device battery, GNSS/BLE, iOS, cloud ingestion or cloud deduplication.",
        "Overflow counter is stored in SQLite but this overflow case did not restart the process after the drop; restart durability of that counter is not directly established by this case."]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"output": str(args.out), "sha256": digest(args.out), "totals": report["totals"]}, sort_keys=True))


if __name__ == "__main__":
    main()
