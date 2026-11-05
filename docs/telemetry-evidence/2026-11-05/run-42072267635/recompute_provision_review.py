#!/usr/bin/env python3
"""Recompute the run13 offline provisioning review using only four safe JSON files.

Usage: python3 recompute_run13_provision.py RECEIPT_DIRECTORY --out review.json
Uses only Python's standard library. No app imports, ADB, environment reads,
network calls or credential inputs. Output is deterministic for these receipts.
"""
import argparse
from collections import Counter
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re


RUN = 42072267635
JOB = 127403084581
SOURCE = "e094db2d815b10aca3ce49cdd9007304818220b3"
APP_SOURCE = "2d76100fda1df0637e953f4ad90f26073028880c"
RESULT_SHA = "0328decaa72877dcd3e1d793d9cfcde996a685b07324a9ddf3241e2cef82d472"
SOURCE_HASHES = {
    "ci_cloud_trial.py": "93c0ae66f60d4aa1e8f62a6c883492f208e9344440e4f37ce485ded2ee8f5d78",
    "ci_provision_probe.py": "67622cd3e022e9a9805ba8fd55e67aff3ba709a572bf30b6c9f6e8c02e06f205",
}
APP_HASHES = {
    "tools/telemetry_spike/direct_trial/AndroidManifest.xml": "dff2a8c38aab22edb716312e1f47f6368cbfece96dc01c054722cc070d084345",
    "tools/telemetry_spike/direct_trial/MainActivity.java": "e520e97c6639643eb37a95aa60b85241b3d6b82a18824e3943aa1b4c0ff308f4",
    "tools/telemetry_spike/direct_trial/DirectQueue.java": "81222e42f65f27d5524ad80b5b66eb5f685b6f3091e5d467a564636ecaa31312",
    "tools/telemetry_spike/direct_trial/build.py": "c51cbe3989c6ff21b0acdaab68c5e4c372b041e90c99dc2d1bd615a42fcd81d6",
    "tools/telemetry_spike/runtime_control/build.py": "0965a5ae2f41015ecca8b8c70236f6f074be57388dcc95d6de3f0e32af08c743",
}
FILES = ("result.json", "export-manifest.json", "original-control-receipt.json",
         "original-build-receipt.json")


def require(condition, code):
    if not condition:
        raise ValueError(code)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def no_duplicate_keys(pairs):
    value = {}
    for key, item in pairs:
        require(key not in value, "DUPLICATE_JSON_KEY")
        value[key] = item
    return value


def reject_nonfinite(_value):
    raise ValueError("NONFINITE_JSON_NUMBER")


def timestamp(value):
    parsed = datetime.fromisoformat(value)
    require(parsed.tzinfo is not None, "TIMESTAMP_WITHOUT_TIMEZONE")
    return parsed


def privacy_scan(values):
    forbidden_keys = {"api_key", "token", "authorization", "latitude", "longitude",
                      "ip", "endpoint", "raw_dump"}
    forbidden_values = re.compile(
        r"phc_|phx_|sk-[A-Za-z0-9]|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|(?:\d{1,3}\.){3}\d{1,3}")
    def visit(value):
        if isinstance(value, dict):
            require(not forbidden_keys.intersection(value), "FORBIDDEN_PUBLIC_FIELD")
            for item in value.values():
                visit(item)
        elif isinstance(value, list):
            for item in value:
                visit(item)
        elif isinstance(value, str):
            require(forbidden_values.search(value) is None, "FORBIDDEN_PUBLIC_VALUE")
    for value in values:
        visit(value)


def review(directory):
    raw = {}
    values = {}
    for name in FILES:
        path = directory / name
        require(path.is_file() and not path.is_symlink(), "MISSING_OR_SYMLINK_INPUT")
        raw[name] = path.read_bytes()
        require(len(raw[name]) <= 262144, "INPUT_TOO_LARGE")
        values[name] = json.loads(raw[name], object_pairs_hook=no_duplicate_keys,
                                  parse_constant=reject_nonfinite)
    r, m, c, b = (values[name] for name in FILES)
    require(digest(raw["result.json"]) == m["sha256"] == RESULT_SHA, "RESULT_DIGEST")
    require(len(raw["result.json"]) == m["bytes"] == 13863 and m["chunks"] == 4, "EXPORT_SIZE")
    require(digest(raw["original-control-receipt.json"]) == r["runtime_control"]["sha256"], "CONTROL_DIGEST")
    require(digest(raw["original-build-receipt.json"]) == r["apk"]["build_receipt_sha256"], "BUILD_DIGEST")
    require(r["diagnostic_source_commit"] == SOURCE, "DIAGNOSTIC_SOURCE")
    require(r["diagnostic_source_sha256"] == SOURCE_HASHES, "DIAGNOSTIC_SOURCE_HASHES")
    require(r["apk_source_commit"] == b["source_commit"] == r["apk"]["source_commit"] == APP_SOURCE, "APP_SOURCE")
    require(r["apk"]["source_sha256"] == b["source_sha256"] == APP_HASHES, "APP_SOURCE_HASHES")
    for field in ("identity", "apk_sha256", "apk_bytes"):
        require(r["apk"][field] == b[field], "APK_BUILD_REFERENCE")
    identity = b["identity"]
    require(identity["package"] == "com.cama.telemetry.direct_lab" and
            identity["version_code"] == 1 and identity["version_name"] == "1.0" and
            identity["min_sdk"] == 24 and identity["target_sdk"] == 36 and
            identity["requested_permissions"] == ["android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE"], "APK_IDENTITY")
    require(b["apk_bytes"] == 45459 and b["apk_sha256"] == "76731f705128803e7b7936de1e7848a2acf9ee1cb92f13ad0503618adf827777", "APK_HASH_SIZE")
    require(identity["certificate_sha256"] == "9046b4110ab2a3a0fdac0b078d8a532474e278ccf577f61ff804d2c7a4cc8557", "APK_CERTIFICATE")
    require(b["runtime_tested"] is False and b["analytics_sdk"] is None and b["new_dependencies"] == [], "BUILD_SCOPE")

    stage_names = ["verify_apk", "boot_and_package_manager", "install_verified_control",
                   "first_resumed_ready", "force_stop_pid_absent", "second_resumed_ready",
                   "new_pid_persisted_counter_same_boot", "control_stopped_data_preserved"]
    require(c["status"] == "PASS_NATIVE_RUNTIME_CONTROL" and c["gate_pass"] is True and
            c["telemetry_tested"] is False and c["scope"] == "NATIVE_RUNTIME_CONTROL_ONLY", "CONTROL_SCOPE")
    require([s["name"] for s in c["stages"]] == stage_names and all(s["pass"] is True for s in c["stages"]), "CONTROL_STAGES")
    first, second = c["stages"][3]["observation"], c["stages"][5]["observation"]
    for state in (first, second):
        require(state["ready"] is True and state["package"] == "com.cama.telemetry.runtime_control", "CONTROL_READY")
        require(type(state["pid"]) is int and state["pid"] > 0 and type(state["launches"]) is int and state["launches"] > 0, "CONTROL_NUMBERS")
        require(re.fullmatch("[a-f0-9]{32}", state["nonce"]) is not None, "CONTROL_NONCE")
    require(first["pid"] != second["pid"] and first["nonce"] != second["nonce"] and
            second["launches"] == first["launches"] + 1, "CONTROL_RESTART")
    require(c["boot_id"] == r["runtime_control"]["boot_id"] and c["serial"] == r["runtime_control"]["serial"], "SAME_BOOT_CONTROL")
    require(timestamp(c["finished_utc"]) < timestamp(b["utc"]) < timestamp(r["started_utc"]) < timestamp(r["finished_utc"]), "CONTROL_BUILD_PROBE_ORDER")

    expected_prep = ["INSTALL_APK", "INSTALL_VERIFY", "PRIVATE_MKDIR", "PRIVATE_SHELL_FEATURES",
                     "PRIVATE_WRITE", "PRIVATE_STAT", "PRIVATE_VERIFY", "PRIVATE_REMOVE", "PRIVATE_REMOVE_VERIFY"]
    prep = r["preparation"]
    require([row["phase"] for row in prep] == expected_prep, "PREPARATION_ORDER")
    expected_fields = {"schema_version", "observed_utc", "phase", "returncode", "error_category", "stdout_present", "stderr_present"}
    for row in prep:
        require(set(row) == expected_fields and row["schema_version"] == 1, "PREPARATION_SCHEMA")
        require(type(row["returncode"]) is int and row["returncode"] == 0 and row["error_category"] == "NONE", "PREPARATION_RETURN")
        require(type(row["stdout_present"]) is bool and type(row["stderr_present"]) is bool, "PREPARATION_FLAGS")
    times = [timestamp(row["observed_utc"]) for row in prep]
    require(times == sorted(set(times)) and timestamp(r["started_utc"]) < times[0] < times[-1] < timestamp(r["finished_utc"]), "PREPARATION_TIME")
    require(not prep[4]["stdout_present"] and not prep[4]["stderr_present"], "WRITE_SILENT")
    require(prep[5]["stdout_present"] and prep[6]["stdout_present"] and
            not prep[5]["stderr_present"] and not prep[6]["stderr_present"], "STAT_READBACK_CHANNELS")
    require(r["shell_features_observation"] == {"output_format": "ONE_FEATURE_PER_LINE", "line_count": 19,
            "exact_shell_v2_count": 1, "raw_output_published": False}, "FEATURE_OBSERVATION")
    for field in ("shell_v2_confirmed", "private_write_command_completed", "config_write_confirmed",
                  "provision_confirmed", "private_mode_600_and_exact_fake_readback"):
        require(r[field] is True, "PROVISION_ATTESTATION")
    require(r["status"] == "CORRECTED_PROVISION_PATH_PASSED" and "blocked_reason" not in r, "RESULT_STATUS")
    require(r["provision_transport"] == "ADB_SHELL_T_SHELL_V2_REMOTE_EXIT_REQUIRED" and
            r["legacy_install_provision_argv_unchanged"] is False, "TRANSPORT_SCOPE")

    radios = {"airplane_mode_on": True, "wifi_on": False, "mobile_data": False}
    for field in ("offline_before_install", "offline_after_provision"):
        state = r[field]
        require(state == {"radio_settings": radios, "active_default_network_absent": True,
                          "raw_connectivity_dump_published": False}, "OFFLINE_PREDICATE")
    require(r["offline_sample_count"] == 4 and r["last_offline_observation"] == {
        "sample_index": 4, "radio_settings": radios, "radio_flags_match_requested": True,
        "default_network_state": "NONE", "default_network_label_count": 1,
        "raw_connectivity_dump_published": False}, "LAST_NETWORK_SAMPLE")
    commands = r["diagnostic_commands"]
    counts = dict(Counter(row["stage"] for row in commands))
    require(len(commands) == 39 and counts["CONNECTIVITY_OFFLINE_READ"] == 4 and
            all(counts[x] == 2 for x in ("AIRPLANE_ENABLE", "WIFI_DISABLE", "DATA_DISABLE")), "NETWORK_COMMAND_COUNTS")
    for row in commands:
        require(set(row) == {"stage", "returncode", "error_category", "stdout_present", "stderr_present"}, "COMMAND_SCHEMA")
        require(type(row["returncode"]) is int and type(row["stdout_present"]) is bool and type(row["stderr_present"]) is bool, "COMMAND_TYPES")
    nonzero = [row for row in commands if row["returncode"] != 0]
    require(nonzero == [{"stage": "FRESH_PACKAGE_CHECK", "returncode": 1, "error_category": "OUTPUT_WITHHELD",
                        "stdout_present": False, "stderr_present": False}], "UNEXPECTED_COMMAND_FAILURE")
    names = [row["stage"] for row in commands]
    require(names.index("STOP_BEFORE_PROVISION") < names.index("CLEANUP_FORCE_STOP") <
            names.index("CLEANUP_PACKAGE_CHECK") < names.index("RESTORE_AIRPLANE"), "CLEANUP_COMMAND_ORDER")
    require(r["cleanup"] == {"required": True, "install_confirmed": True, "lab_stopped": True,
                             "fake_config_removed": True, "initial_radios_restored": True}, "CLEANUP_ATTESTATION")
    require(r["fake_input_only"] is True and all(r[f] is False for f in
            ("lab_activity_launched", "grant_or_capture_invoked", "cloud_send_attempted")), "NO_APP_OR_CLOUD_SCOPE")
    budget = r["budget_recovery"]
    require(all(budget[f] is None for f in ("reserved_rows", "reserved_attempts", "body_written_rows",
            "body_written_requests", "acknowledged_requests", "cloud_received_rows")), "UNKNOWN_COUNTERS")
    require(budget["status"] == "UNKNOWN_BLOCK_FUTURE_SENDS" and
            budget["conservative_consumed_for_future_launches"] == 500 and
            budget["remaining_for_future_launches"] == 0 and budget["automatic_refund_allowed"] is False, "NO_BUDGET_REFUND")
    require(r["cloud_budget"] == {"previous_allowance_conservatively_consumed": 500,
            "remaining_authorized_rows": 0, "new_allowance": 0, "probe_does_not_refund_previous_run": True}, "BUDGET_SCOPE")
    privacy_scan(values.values())
    return {
        "schema_version": 1,
        "scope": "INDEPENDENT_SAFE_RECEIPT_RECOMPUTATION_NO_NEW_ANDROID_OR_CLOUD",
        "status": "RUN13_CORRECTED_OFFLINE_PROVISION_PASS_INDEPENDENTLY_CONFIRMED",
        "run_id": RUN, "job_id": JOB, "run_number": 13, "attempt": 1,
        "diagnostic_source_commit": SOURCE, "apk_source_commit": APP_SOURCE,
        "input_sha256": {name: digest(raw[name]) for name in FILES},
        "review_script_sha256": digest(Path(__file__).read_bytes()),
        "export": m, "source_hashes_match_reviewed_fix": True,
        "control": {"status": c["status"], "boot_id": c["boot_id"], "first_pid": first["pid"],
                    "second_pid": second["pid"], "first_launches": first["launches"],
                    "second_launches": second["launches"], "eight_stages_ordered_pass": True},
        "apk": r["apk"], "adb_client": r["adb_client"],
        "preparation": {"ordered_phases": expected_prep, "command_count": 9, "all_returncodes_zero": True,
                        "all_error_categories_none": True, "write_completed": True,
                        "file_mode_600_and_exact_fake_readback": True,
                        "readback_evidence_kind": "Reviewed source oracle attestation plus matching phase receipts; raw private bytes intentionally not exported."},
        "shell_features_observation": r["shell_features_observation"],
        "offline_before_install": r["offline_before_install"],
        "offline_after_provision": r["offline_after_provision"],
        "last_offline_observation": r["last_offline_observation"],
        "diagnostic_command_count": len(commands), "command_stage_counts": counts,
        "cleanup": r["cleanup"], "budget": budget,
        "privacy": {"credential_email_nonloopback_ip_coordinate_key_findings": 0,
                    "raw_network_feature_or_private_file_contents_exported": False,
                    "scan_not_claimed_complete_for_arbitrary_unknown_pii": True},
        "application_telemetry_cloud_execution": "NOT_RUN_BY_THIS_OFFLINE_NO_LAUNCH_PROBE",
        "new_cloud_or_budget_authorization": False,
        "limitations": [
            "This review reads the original safe receipts and recomputes their consistency; it does not rerun device commands.",
            "The APK binary is not included in this four-file bundle; identity/hash/size/signature are matched between the runner's verified build and probe receipts.",
            "File mode and exact bytes were checked on Android by the reviewed source; the safe export retains the attestation rather than private contents.",
            "The separate control restarts do not prove LAB telemetry, revocation, cloud delivery or deduplication.",
            "Success on this emulator does not retroactively establish run8/run10 remote errors, run11 network state or run12 feature names.",
            "Historical run8 counters stay unknown:500 conservatively consumed,0 remaining; no automatic refund.",
            "Future cloud allowances, deletion, merge and production activation remain separate decisions."
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt_directory", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    try:
        result = review(args.receipt_directory)
    except (ValueError, TypeError, KeyError, OSError, IndexError):
        raise SystemExit("REVIEW_VALIDATION_FAILED") from None
    rendered = json.dumps(result, indent=2, allow_nan=False) + "\n"
    if args.out:
        args.out.write_text(rendered)
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
