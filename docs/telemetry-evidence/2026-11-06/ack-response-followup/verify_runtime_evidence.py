#!/usr/bin/env python3
"""Recompute the run16 ACK evidence using only Python's standard library.

Usage: python verify_runtime_evidence.py [android-result.json]
This checks an exported receipt, not APK bytes, Android, GitHub, or PostHog.
No production module, fixture generator, or producer validator is imported.
The exact input hash binds this review to the independently fetched job export.
"""

import datetime
import hashlib
import json
import pathlib
import re
import sys
import uuid


SOURCE = "d93b3095f78f4924e2cf132d82e4bc041a626f7c"
BASE = "75b83254c99f20703f8a4ddbcc0da92a41d9990c"
INPUT_SHA = "83278d90dec731556d8f93580dcec2c44be38ba1b7c64c7c8658d83a932ebeb1"
ACTIVITY_SHA = "c2e152c123bf78ae164afe89e5d761f92053bd700a13a273c37ae24b0cf19aaa"
BUILDER_SHA = "0b7bb1cdd091a955cf7b02f11a3a9f871b84e8a8543e2d186f66a766f9e5eefe"
TOOLCHAIN_SHA = "0965a5ae2f41015ecca8b8c70236f6f074be57388dcc95d6de3f0e32af08c743"
CONTROL_SHA = "e2527ad4e424cf931ac6fb4aa1113fd7607295257e479462f1a9f849d250ade8"
EXPECTED_BUILDS = {
    "before": {
        "package": "com.cama.telemetry.ack_before",
        "queue_source_commit": BASE,
        "queue_source_sha256": "81222e42f65f27d5524ad80b5b66eb5f685b6f3091e5d467a564636ecaa31312",
        "apk_bytes": 49555,
        "apk_sha256": "b4f8c120c4309eaa918eedd77fe18ea1336fc7208657ded2c4f12b25d2db9f11",
        "certificate_sha256": "a8d5bd52f3d8711971de90eed42d87772698c7861c7f802c0bd01a435135cd61",
    },
    "after": {
        "package": "com.cama.telemetry.ack_after",
        "queue_source_commit": SOURCE,
        "queue_source_sha256": "4d983271deb281775ef780ae2e621f297e8432575721f8ecb15141561ea69f0b",
        "apk_bytes": 53651,
        "apk_sha256": "172a76feeb19b2b65fc777c15fc4f06109343c6095f78f5097fabb7e405e6c28",
        "certificate_sha256": "eea1d6d35243cd1551a0afa7d9a8ce4747de257cd4fcfb1e9e0e794245649f46",
    },
}


def require(value, message):
    if not value:
        raise ValueError(message)


def equal(actual, expected, label):
    # JSON booleans must not satisfy integer checks (True == 1 in Python).
    require(type(actual) is type(expected) and actual == expected, label)


def fields(obj, expected, label):
    require(isinstance(obj, dict) and set(obj) == set(expected), label)


def no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def timestamp(value):
    result = datetime.datetime.fromisoformat(value)
    require(result.tzinfo is not None, "timezone missing")
    return result


def verify(result, digest, size):
    equal(digest, INPUT_SHA, "unexpected exported receipt hash")
    equal(size, 18842, "unexpected exported receipt length")
    equal(result["source_commit"], SOURCE, "source commit")
    equal(result["schema_version"], 1, "schema version")
    equal(result["scope"], "OFFLINE_PERMISSIONLESS_ANDROID_ACK_RESPONSE_REGRESSION", "scope")
    equal(result["status"], "PASSED_OFFLINE_ANDROID_ACK_COMPATIBILITY", "status")
    equal(result["new_posthog_rows_authorized"], 0, "ingestion authorization")
    for name in ["cloud_configuration_or_credential_loaded", "cloud_delivery_retested",
                 "network_sender_exercised", "sender_instantiated"]:
        equal(result[name], False, name)
    equal(result["initial_radios_restored"], True, "radio cleanup")
    expected_offline = {
        "active_default_network_absent": True,
        "radio_settings": {"airplane_mode_on": True, "mobile_data": False, "wifi_on": False},
        "raw_connectivity_dump_published": False,
    }
    for name in ["offline_before", "offline_after_before", "offline_after_after"]:
        equal(result[name], expected_offline, name)
    equal(result["cleanup"], {
        "com.cama.telemetry.ack_before": {"process_stopped": True},
        "com.cama.telemetry.ack_after": {"process_stopped": True},
    }, "proof processes stopped")

    commands = result["safe_command_categories"]
    equal(len(commands), 34, "safe command count")
    for row in commands:
        fields(row, ["stage", "returncode", "stdout_present", "stderr_present", "error_category"],
               "command receipt contains unexpected fields")
        equal(row["returncode"], 0, "command failure")
        equal(row["error_category"], "NONE", "command error")
        require(re.fullmatch(r"[A-Z_]+", row["stage"]) is not None, "command category")
        require(type(row["stdout_present"]) is bool and type(row["stderr_present"]) is bool,
                "command output flags")
    equal([r["stage"] for r in commands].count("CONNECTIVITY_OFFLINE_READ"), 4,
          "offline connectivity check count")
    require([r["stage"] for r in commands][-6:-3] ==
            ["RESTORE_AIRPLANE", "RESTORE_WIFI", "RESTORE_DATA"], "restore command ordering")

    proofs = result["native_proofs"]
    fields(proofs, ["before", "after"], "proof variants")
    for variant, wanted in EXPECTED_BUILDS.items():
        build, native = proofs[variant]["build"], proofs[variant]["native"]
        for key, value in wanted.items():
            equal(build[key], value, variant + " build " + key)
        for key, value in {
            "variant": variant, "schema_version": 1, "status": "BUILT_PERMISSIONLESS_PROOF_NOT_RUN",
            "harness_source_commit": SOURCE, "activity_source_sha256": ACTIVITY_SHA,
            "builder_sha256": BUILDER_SHA, "toolchain_helper_sha256": TOOLCHAIN_SHA,
            "permissions": [], "new_dependencies": [], "version_name": "1.0", "version_code": 1,
            "min_sdk": 24, "target_sdk": 36, "platform": "36", "build_tools": "36.0.0",
            "javac": "javac 17.0.21",
        }.items():
            equal(build[key], value, variant + " build " + key)
        for key, value in {
            "variant": variant, "schema_version": 1, "passed": True,
            "scope": "PERMISSIONLESS_ANDROID_ACK_FUNCTIONS_OFFLINE",
            "legacy_integer_one_accepted": True, "sender_instantiated": False,
            "transport_invoked": False, "raw_response_body_recorded": False,
            "documented_status_ok_accepted": variant == "after",
        }.items():
            equal(native[key], value, variant + " native " + key)
        require(re.fullmatch(r"[0-9a-f]{32}", native["nonce"]) is not None, "fresh proof nonce")
    before, after = proofs["before"]["native"], proofs["after"]["native"]
    require(before["nonce"] != after["nonce"], "proof nonce reused")
    equal(before["case_count"], 0, "baseline classifier did not exist")
    equal(before["cases"], [], "baseline cases")

    expected = [(name, True, "ACKNOWLEDGED") for name in
                ["documented_ok", "legacy_one", "empty_quota", "false_quota", "null_quota"]]
    expected += [("unknown_status_" + str(i), False, "UNRECOGNIZED_RESPONSE") for i in range(5, 14)]
    expected += [("missing_status", False, "UNRECOGNIZED_RESPONSE")]
    expected += [("limited_quota_" + str(i), False, "QUOTA_LIMITED") for i in range(15, 20)]
    expected += [("malformed_" + str(i), False, "MALFORMED_RESPONSE") for i in range(20, 30)]
    expected += [("non_200", False, "HTTP_REJECTED"),
                 ("server_error", False, "HTTP_NOT_ACKNOWLEDGED"),
                 ("bounded_size", False, "RESPONSE_TOO_LARGE")]
    equal(after["case_count"], 33, "candidate case count")
    equal(len(after["cases"]), len(expected), "candidate case rows")
    category_counts = {}
    case_fields = ["case", "accepted", "response_category", "queue_rows_before", "queue_rows_after",
                   "ack_counter", "rejected_rows_byte_identical", "unrelated_tail_preserved", "passed"]
    for row, (name, accepted, category) in zip(after["cases"], expected):
        fields(row, case_fields, "unexpected native case fields")
        for key, value in {
            "case": name, "accepted": accepted, "response_category": category, "queue_rows_before": 3,
            "queue_rows_after": 1 if accepted else 3, "ack_counter": 1 if accepted else 0,
            "rejected_rows_byte_identical": None if accepted else True,
            "unrelated_tail_preserved": True, "passed": True,
        }.items():
            equal(row[key], value, "case " + name + " field " + key)
        category_counts[category] = category_counts.get(category, 0) + 1

    control = result["runtime_control"]
    equal(control["sha256"], CONTROL_SHA, "original control receipt hash reference")
    receipt, build = control["receipt"], control["build_receipt"]
    for key, value in {
        "scope": "NATIVE_RUNTIME_CONTROL_ONLY", "status": "PASS_NATIVE_RUNTIME_CONTROL",
        "schema_version": 1, "gate_pass": True, "telemetry_tested": False,
        "serial": "emulator-5554",
    }.items():
        equal(receipt[key], value, "lifecycle control " + key)
    equal(build["status"], "BUILT_VERIFIED_NOT_RUN", "control build status")
    equal(build["telemetry_tested"], False, "control build scope")
    equal(build["apk_sha256"], receipt["apk_sha256"], "control APK receipt linkage")
    equal(build["identity"], receipt["identity"], "control identity linkage")
    equal(build["apk_bytes"], 12691, "control APK bytes")
    equal(build["apk_sha256"], "49bc3381641701eccb8504d4e487b9bdd48947461ab2bf8ef9a9faca04eb3c99",
          "control APK sha256")
    equal(receipt["identity"], {
        "package": "com.cama.telemetry.runtime_control", "version_name": "1.0", "version_code": 1,
        "min_sdk": 24, "target_sdk": 36, "requested_permissions": [],
        "certificate_sha256": "dca4b0cbb0e1e5944eefc323c1e0c4263f820d3597c3d75e3933f167b7e9909f",
    }, "control identity")
    equal(build["sources"], {
        "AndroidManifest.xml": "131eea018ed9fb2317b342dcbe588d19f3e8f8b447b3b2025969cf80877ebe4f",
        "MainActivity.java": "9226633646f4c75f1755ea5ae8dbc57214efc4271f5a59ef642ac7f8300ff847",
        "build.py": TOOLCHAIN_SHA,
    }, "control sources")
    require(str(uuid.UUID(receipt["boot_id"])) == receipt["boot_id"], "control boot ID")
    stages = receipt["stages"]
    equal([s["name"] for s in stages], [
        "verify_apk", "boot_and_package_manager", "install_verified_control", "first_resumed_ready",
        "force_stop_pid_absent", "second_resumed_ready", "new_pid_persisted_counter_same_boot",
        "control_stopped_data_preserved",
    ], "lifecycle stage order")
    for stage in stages:
        equal(stage["pass"], True, "lifecycle stage result")
    first, second = stages[3]["observation"], stages[5]["observation"]
    for row, count in [(first, 1), (second, 2)]:
        equal(row["launches"], count, "persisted launch count")
        equal(row["ready"], True, "ready after resume")
        equal(row["package"], "com.cama.telemetry.runtime_control", "control package")
        require(type(row["pid"]) is int and row["pid"] > 0, "positive control PID")
        require(re.fullmatch(r"[0-9a-f]{32}", row["nonce"]) is not None, "control nonce")
    require(first["pid"] != second["pid"] and first["nonce"] != second["nonce"],
            "fresh control process")
    require(timestamp(build["utc"]) < timestamp(receipt["utc"]) < timestamp(receipt["finished_utc"])
            < timestamp(result["started_utc"]) < timestamp(result["finished_utc"]),
            "control must finish before ACK fixtures begin")

    return {
        "status": "PASS_EXPORTED_OFFLINE_RUNTIME_RECEIPT",
        "input_sha256": digest, "input_bytes": size, "source_commit": SOURCE,
        "baseline_documented_ok_rejected": True, "candidate_documented_ok_accepted": True,
        "legacy_integer_one_accepted_both": True,
        "candidate_sqlite_cases": {"total": 33, "accepted": 5, "retained_byte_identical": 28,
                                   "category_counts": category_counts},
        "control": {"eight_stages_passed": True, "finished_before_ack_proofs": True,
                    "fresh_process_persisted_launch_count": True, "same_boot_stage_passed": True},
        "permissions_requested_all_three_apks": [], "offline_snapshots_verified": 3,
        "successful_sanitized_command_rows": len(commands), "cleanup_verified": True,
        "apk_bytes_independently_downloaded": False,
        "limits": ["Receipt recomputation only; no new Android execution or network access.",
                   "GitHub origin and original control-receipt bytes were independently checked separately.",
                   "APK hashes, signatures and permission reports are CI observations, not a local APK reinspection.",
                   "No TLS/InputStream/cloud delivery/storage/revocation/retry/deduplication or phone proof."],
    }


def main():
    require(len(sys.argv) <= 2, "usage: verify_runtime_evidence.py [android-result.json]")
    path = pathlib.Path(sys.argv[1]) if len(sys.argv) == 2 else pathlib.Path(__file__).with_name("android-result.json")
    raw = path.read_bytes()
    result = json.loads(raw.decode("utf-8"), object_pairs_hook=no_duplicates,
                        parse_constant=lambda value: (_ for _ in ()).throw(ValueError("nonfinite JSON")))
    checked = verify(result, hashlib.sha256(raw).hexdigest(), len(raw))
    print(json.dumps(checked, indent=2, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError) as error:
        print("FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
