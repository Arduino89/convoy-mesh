#!/usr/bin/env python3
"""Independently recompute exported run17 evidence; stdlib, no producer imports.

Usage: python verify_runtime_evidence.py full-result.json decoded-evidence/
The second argument contains direct-public/ and control/build receipt folders.
This reads saved synthetic evidence. It does not run Android or access a network.
"""
import collections
import datetime
import hashlib
import json
import pathlib
import re
import sys
import uuid

SOURCE = "50386a5c8ce5b0cf628073989a0eaf1549008e79"
PREFIX = "synthetic-http-42389745788"
PHASES = ("revoke", "crash-after-intent", "crash-during-purge", "crash-after-purge",
          "before-intent", "normal", "refusal", "retry", "overflow", "inflight")
NEGATIVES = {"quota": "QUOTA_LIMITED", "malformed": "MALFORMED_RESPONSE",
             "utf8": "MALFORMED_RESPONSE", "unknown": "UNRECOGNIZED_RESPONSE",
             "truncated": "RESPONSE_READ_FAILED"}
FIELDS = {"schema_version", "run_id", "event_id", "sequence", "event_name", "synthetic"}
CLIENT_CHECKS = {"valid_fixture_accepted", "foreign_distinct_id_rejected", "extra_property_rejected",
    "wrong_privacy_flag_rejected", "non_fake_token_rejected", "invalid_timestamp_rejected", "all_passed",
    "cloud_budget_490_plus_20_rejected", "cloud_budget_490_plus_10_allowed", "cloud_budget_500_plus_1_rejected",
    "cloud_budget_limit_over_500_rejected", "cloud_response_fractional_status_rejected",
    "cloud_response_quota_limited_rejected", "cloud_response_status_1_accepted", "cloud_response_status_ok_accepted"}
BUILD_HASHES = {
    "tools/telemetry_spike/direct_trial/AndroidManifest.xml": "dff2a8c38aab22edb716312e1f47f6368cbfece96dc01c054722cc070d084345",
    "tools/telemetry_spike/direct_trial/MainActivity.java": "e520e97c6639643eb37a95aa60b85241b3d6b82a18824e3943aa1b4c0ff308f4",
    "tools/telemetry_spike/direct_trial/DirectQueue.java": "254b6758166111a9b5d90095eba2d7e52caa1d537fa44e4d8a77a120303a60cd",
    "tools/telemetry_spike/direct_trial/build.py": "c51cbe3989c6ff21b0acdaab68c5e4c372b041e90c99dc2d1bd615a42fcd81d6",
    "tools/telemetry_spike/runtime_control/build.py": "0965a5ae2f41015ecca8b8c70236f6f074be57388dcc95d6de3f0e32af08c743",
}


def need(condition, message):
    if not condition:
        raise ValueError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def unique(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def load(path):
    return json.loads(path.read_bytes(), object_pairs_hook=unique,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite JSON")))


def rows(path):
    return [json.loads(line, object_pairs_hook=unique) for line in path.read_text().splitlines() if line]


def business(run, sequence):
    return {"schema_version": 1, "run_id": run, "event_id": run + "-" + f"{sequence:06d}",
            "sequence": sequence, "event_name": "cm_lab_probe", "synthetic": True}


def sequence_of(identity, run):
    need(isinstance(identity, str) and re.fullmatch(re.escape(run) + r"-[0-9]{6}", identity), "foreign event ID")
    sequence = int(identity[-6:])
    need(1 <= sequence <= 100000, "event sequence range")
    return sequence


def item(run, identity, uid, timestamp):
    need(str(uuid.UUID(uid)) == uid, "event UUID")
    need(datetime.datetime.fromisoformat(timestamp.replace("Z", "+00:00")).tzinfo is not None, "event time")
    properties = business(run, sequence_of(identity, run))
    properties.update({"$geoip_disable": True, "$process_person_profile": False})
    return {"event": "cm_lab_probe", "properties": properties, "distinct_id": run,
            "uuid": uid, "timestamp": timestamp}


def state(value, run):
    need(value["run_id"] == run and value["action_ok"] is True and type(value["pid"]) is int,
         "state run/action/process")
    need(value["transport_mode"] == "local_loopback", "cloud transport in local proof")
    for key in ("queue_count", "queue_bytes", "requests_acked", "requests_started", "in_flight_count"):
        need(type(value[key]) is int and value[key] >= 0, "state counter " + key)
    for key in ("queue_snapshot_sha256", "queue_after_batch_sha256", "trace_sha256"):
        need(re.fullmatch(r"[0-9a-f]{64}", value[key]), "state digest " + key)
    need(isinstance(value["consent"], bool) and value["setting_value"].startswith("synthetic-setting-"), "state consent/sentinel")


def verify(full_path, archive):
    full = load(full_path)
    need(full["scope"] == "FULL_ANDROID_SENDER_LOOPBACK_SHARED_HTTP_READER_NO_POSTHOG" and
         full["source_commit"] == SOURCE and full["status"] == "PASS_FULL_ANDROID_SENDER_LOCAL", "full sender status/source")
    need(type(full["new_posthog_rows_authorized"]) is int and full["new_posthog_rows_authorized"] == 0 and
         full["project_credentials_loaded"] is False, "zero ingestion/config scope")
    for name in ("offline_before", "offline_after"):
        need(full[name] == {"radio_settings": {"airplane_mode_on": True, "wifi_on": False, "mobile_data": False},
                           "active_default_network_absent": True, "raw_connectivity_dump_published": False}, "offline barrier")
    need(full["lab_stopped_route_removed"] is True and full["radios_restored"] is True, "sender/radio cleanup")
    need(all(r["returncode"] == 0 and r["error_category"] == "NONE" for r in full["safe_command_categories"]), "radio command failure")

    # The decoded archive's SHA256SUMS is independently checked before using data.
    sums = (archive / "SHA256SUMS.txt").read_text().splitlines()
    for line in sums:
        wanted, name = line.split("  ", 1)
        path = pathlib.PurePosixPath(name)
        need(not path.is_absolute() and ".." not in path.parts, "unsafe archive path")
        need(digest((archive / path).read_bytes()) == wanted, "archive entry hash " + name)

    inherited = load(archive / "direct-public/result.json")
    need(inherited["status"] == "PASSED" and inherited["source_commit"] == SOURCE and
         full["inherited_suite_status"] == "PASS" and inherited["public_artifacts_safe"] is True, "inherited suite")
    need(inherited["cleanup"]["lab_stopped"] is True and inherited["cleanup"]["local_route_removed"] is True,
         "inherited sender cleanup")
    build = load(archive / "direct-build/build-receipt.json")
    apk = load(archive / "direct-public/apk-receipt.json")
    need(build["source_sha256"] == BUILD_HASHES and apk["source_sha256"] == BUILD_HASHES, "native build source hashes")
    need(build["source_commit"] == apk["source_commit"] == SOURCE and build["status"] == "BUILT_VERIFIED_NOT_RUN", "native build source/status")
    for key in ("identity", "apk_sha256", "apk_bytes"):
        need(build[key] == apk[key], "APK build/runtime receipt linkage")
    identity = apk["identity"]
    need(identity["package"] == "com.cama.telemetry.direct_lab" and identity["version_code"] == 1 and
         identity["version_name"] == "1.0" and identity["min_sdk"] == 24 and identity["target_sdk"] == 36 and
         identity["requested_permissions"] == ["android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE"], "LAB identity/permissions")
    need(re.fullmatch(r"[0-9a-f]{64}", identity["certificate_sha256"]) and
         re.fullmatch(r"[0-9a-f]{64}", apk["apk_sha256"]) and apk["apk_bytes"] > 0, "LAB APK identity digests")
    control = load(archive / "runtime-control-smoke/receipt.json")
    control_build = load(archive / "runtime-control-build/build-receipt.json")
    need(control["status"] == "PASS_NATIVE_RUNTIME_CONTROL" and control["gate_pass"] is True and
         control["telemetry_tested"] is False and control["identity"]["requested_permissions"] == [], "control gate")
    need(control["identity"] == control_build["identity"] and control["apk_sha256"] == control_build["apk_sha256"], "control build linkage")
    stages = control["stages"]
    need([s["name"] for s in stages] == ["verify_apk", "boot_and_package_manager", "install_verified_control",
         "first_resumed_ready", "force_stop_pid_absent", "second_resumed_ready", "new_pid_persisted_counter_same_boot",
         "control_stopped_data_preserved"] and all(s["pass"] is True for s in stages), "eight lifecycle stages")
    first, second = stages[3]["observation"], stages[5]["observation"]
    need(first["launches"] == 1 and second["launches"] == 2 and first["pid"] != second["pid"] and
         first["nonce"] != second["nonce"] and first["ready"] is True and second["ready"] is True, "control stop/reopen persistence")
    need(datetime.datetime.fromisoformat(control["finished_utc"]) < datetime.datetime.fromisoformat(inherited["started_utc"]), "control must precede LAB")

    phase_results = {}
    for phase in PHASES:
        run = PREFIX + "-" + phase
        directory, wire = archive / ("direct-public/" + phase), archive / ("direct-public/wire-" + phase)
        validation = load(directory / "validation.json")
        final = validation["final_state"]
        state(final, run)
        observations = rows(directory / "states.jsonl")
        need(bool(observations), "missing native state observations")
        for observed in observations:
            state(observed, run)
        nonces = [s["action_nonce"] for s in observations]
        need(len(set(nonces)) == len(nonces) and all(re.fullmatch(r"[0-9a-f]{32}", n) for n in nonces), "fresh native observations")
        baseline = observations[0]
        need(all((s["trace_sha256"], s["setting_value"]) == (baseline["trace_sha256"], baseline["setting_value"])
                 for s in [*observations, final]), "sentinels across native observations")
        need(validation["preflight_checks"] == dict.fromkeys(CLIENT_CHECKS, True) and
             any(s.get("preflight_checks") == dict.fromkeys(CLIENT_CHECKS, True) for s in observations), "native preflight counterexamples")
        need(final["queue_count"] == final["in_flight_count"] == 0 and final["preflight_rejected"] == 0 and
             validation["sentinels_unchanged"] is True and validation["receiver_closed_after_process_stop"] is True,
             "inherited final state " + phase)
        start = 21 if phase in ("revoke", "crash-after-intent", "crash-during-purge", "crash-after-purge", "refusal") else 1
        count = 100 if phase == "normal" else 45 if phase == "overflow" else 20 if phase == "before-intent" else 10
        expected = [business(run, n) for n in range(start, start + count)]
        need(rows(directory / "expected.jsonl") == expected, "oracle cohort " + phase)
        received = rows(wire / "received.jsonl")
        sequences = [r["sequence"] for r in received]
        for row in received:
            need(type(row["sequence"]) is int and set(row) == FIELDS and row == business(run, row["sequence"]), "received contract " + phase)
        wanted = set(range(14, 46)) if phase == "overflow" else set(range(start, start + count))
        need(set(sequences) == wanted and (phase == "retry" or len(sequences) == len(wanted)), "received exact cohort " + phase)
        versions, normalized = collections.defaultdict(set), []
        requests = rows(wire / "requests.jsonl")
        need(bool(requests), "missing wire requests")
        for request in requests:
            need(request["audit_pass"] is True and request["violations"] == [], "wire privacy " + phase)
            payload = request["payload_redacted"]
            need(payload["api_key"] == "<redacted:fake-token>" and set(payload) == {"api_key", "batch"}, "wire envelope")
            need(1 <= len(payload["batch"]) <= 20, "wire batch bound")
            for actual in payload["batch"]:
                identity_id = actual["properties"]["event_id"]
                golden = item(run, identity_id, actual["uuid"], actual["timestamp"])
                need(actual == golden, "complete transmitted item contract " + phase)
                versions[identity_id].add(digest(canonical(actual)))
                normalized.append({k: actual["properties"][k] for k in FIELDS})
        need(normalized == received and all(len(v) == 1 for v in versions.values()), "wire/receiver consistency and UUID/content " + phase)
        status = inherited["phases"][phase]["status"]
        need(status == ("BOUNDARY_OBSERVED" if phase == "before-intent" else "PASSED"), "phase verdict " + phase)
        if phase.startswith("crash-"):
            need(validation["revocation_durable"] is True and validation["restart_denied"] is True and
                 validation["pregrant_request_count"] == 0 and final["revoked_count"] == 20, "committed revoke restart")
        if phase == "revoke":
            need(final["revoked_count"] == 20, "revoked count")
        if phase == "refusal":
            need(final["refused_count"] == 20 and validation["pregrant_request_count"] == 0 and
                 validation["restart_denied"] is True, "refusal before consent and after restart")
        if phase == "before-intent":
            need(validation["revocation_durable"] is False and validation["checkpoint_attested"] == "before_intent_commit" and
                 validation["restart_prior_consent_preserved"] is True and
                 inherited["phases"][phase]["accepted_revocation"] is False, "uncommitted boundary is not accepted revocation")
        if phase == "overflow":
            need(final["dropped_count"] == 13, "visible saturation losses")
        if phase == "retry":
            need(len(received) >= 20 and sum(r["response_mode"] == "close_without_response_after_fsync" for r in requests) == 1,
                 "lost acknowledgement retry")
        if phase == "inflight":
            need(final["consent"] is False and len(requests) == validation["requests_at_revocation"] == 1 and
                 validation["held_after_fsync_before_revoke"] is True and validation["inflight_before_revoke"] >= 1 and
                 requests[0]["response_mode"] == "close_without_response_after_fsync", "inflight durable boundary")
        phase_results[phase] = {"status": status, "received_rows": len(received), "unique_events": len(wanted)}

    need(set(full["cases"]) == {"batch", *NEGATIVES}, "six extra cases")
    extra_results = {}
    for kind, case in full["cases"].items():
        need(case["status"] == "PASS" and case["fixture"] == kind, "extra case verdict")
        run = PREFIX + "-" + kind
        before, retained, final = (case[k] for k in ("before", "retained", "final"))
        for value in (before, retained, final):
            state(value, run)
        need(before["queue_count"] == 25 and before["requests_acked"] == 0 and
             final["queue_count"] == final["in_flight_count"] == 0 and final["requests_acked"] == 2 and
             final["queue_snapshot_sha256"] == digest(b"[]"), "extra queue bounds/drain")
        if kind == "batch":
            held = case["state_before_ack"]
            state(held, run)
            need(held["queue_count"] == 25 and held["requests_acked"] == 0 and held["queue_snapshot_sha256"] == before["queue_snapshot_sha256"] and
                 retained["queue_count"] == 5 and retained["requests_acked"] == 1 and
                 retained["queue_snapshot_sha256"] == before["queue_after_batch_sha256"], "selected-batch ACK boundary")
        else:
            restarted = case["state_restart_offline"]
            state(restarted, run)
            need(retained["last_response_category"] == NEGATIVES[kind] and retained["in_flight_count"] == 0 and
                 retained["requests_started"] >= 1 and retained["requests_acked"] == restarted["requests_acked"] == 0 and
                 retained["queue_count"] == restarted["queue_count"] == 25 and
                 retained["queue_snapshot_sha256"] == restarted["queue_snapshot_sha256"] == before["queue_snapshot_sha256"] and
                 restarted["pid"] != retained["pid"], "rejection and offline restart preservation")
        samples = [before, retained, final, case.get("state_before_ack"), case.get("state_restart_offline")]
        need(all(s is None or (s["trace_sha256"], s["setting_value"]) == (before["trace_sha256"], before["setting_value"]) for s in samples), "extra sentinels")
        versions, seen = collections.defaultdict(set), []
        proofs = case["requests_proof"]
        need([r["request_index"] for r in proofs] == list(range(1, len(proofs) + 1)), "request indices")
        for request in proofs:
            need(request["audit_pass"] is True and request["violations"] == [], "extra request privacy")
            for compact in request["items"]:
                golden = item(run, compact["event_id"], compact["uuid"], compact["timestamp"])
                calculated = digest(canonical(golden))
                need(calculated == compact["canonical_item_sha256"], "canonical transmitted item digest")
                versions[compact["event_id"]].add(calculated)
                seen.append(sequence_of(compact["event_id"], run))
        need(set(seen) == set(range(1, 26)) and all(len(v) == 1 for v in versions.values()), "extra exact identities/UUID/content")
        need(case["wire"]["privacy_pass"] is True and case["receiver"]["received_rows"] == len(seen), "extra wire/receiver consistency")
        if kind == "batch":
            need(len(proofs) == 2 and seen == list(range(1, 26)), "two positive batches")
        else:
            need(len(seen) >= 45, "rejected batch must be transmitted again")
        extra_results[kind] = {"status": "PASS", "request_count": len(proofs), "received_rows": len(seen),
                               "category": NEGATIVES.get(kind, "ACKNOWLEDGED")}
    return {"status": "PASS_INDEPENDENT_SAVED_LOCAL_SENDER_EVIDENCE", "source_commit": SOURCE,
            "full_result_sha256": digest(full_path.read_bytes()), "archive_manifest_entries_checked": len(sums),
            "native_source_hashes_checked": len(BUILD_HASHES), "apk_identity": apk,
            "control_eight_stages_before_lab": True, "inherited_phases": phase_results,
            "extra_cases": extra_results, "cloud_ingestion_authorized": 0,
            "limits": ["Saved receipt recomputation; no new Android or network execution.",
                       "APK bytes were not independently downloaded or reinspected.",
                       "Canonical item hashes prove equal values/UUID/timestamp, not HTTP body byte ordering.",
                       "No TLS/cloud storage/deduplication, old20 retry, physical phone or battery proof."]}


if __name__ == "__main__":
    try:
        need(len(sys.argv) == 3, "usage: verify_runtime_evidence.py full-result.json decoded-evidence/")
        print(json.dumps(verify(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])), indent=2, sort_keys=True))
    except (ValueError, KeyError, TypeError, OSError) as error:
        print("FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
