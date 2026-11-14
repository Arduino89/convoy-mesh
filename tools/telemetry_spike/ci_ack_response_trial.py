#!/usr/bin/env python3
"""Run old/new native ACK functions in permissionless apps; never send events."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import time
import uuid

from ack_response_trial.build import ACTIVITY, BASE_JAVA_SHA, BASE_SOURCE
from ci_direct_trial import Device
from ci_native_trial import TrialBlocked, now, public_write, validate_public_value
from ci_provision_probe import block_network, radio_snapshot, restore_radios
from reconcile_cloud_trial import parse_json
from runtime_control.build import GateError, installed_tools, run, sha256, valid_sdk_bounds
from runtime_control.smoke import validate_serial

SCOPE = "OFFLINE_PERMISSIONLESS_ANDROID_ACK_RESPONSE_REGRESSION"
CATEGORIES = {"ACKNOWLEDGED", "UNRECOGNIZED_RESPONSE", "QUOTA_LIMITED", "MALFORMED_RESPONSE",
              "HTTP_REJECTED", "HTTP_NOT_ACKNOWLEDGED", "RESPONSE_TOO_LARGE"}
CASE_NAMES = ["documented_ok", "legacy_one", "empty_quota", "false_quota", "null_quota"] + [
    "unknown_status_" + str(n) for n in range(5, 14)] + ["missing_status"] + [
    "limited_quota_" + str(n) for n in range(15, 20)] + ["malformed_" + str(n) for n in range(20, 30)] + [
    "non_200", "server_error", "bounded_size"]


def validate_native(value, nonce, variant):
    expected_keys = {"schema_version", "scope", "variant", "nonce", "passed", "documented_status_ok_accepted",
        "legacy_integer_one_accepted", "sender_instantiated", "transport_invoked", "raw_response_body_recorded",
        "case_count", "cases"}
    if not isinstance(value, dict) or value.get("passed") is not True:
        case = value.get("failed_case", "UNKNOWN") if isinstance(value, dict) else "UNKNOWN"
        case = case if case in CASE_NAMES or case == "predicate" else "UNKNOWN"
        raise TrialBlocked("ANDROID_ACK_FIXTURE_FAILED_" + case)
    if (set(value) != expected_keys or type(value["schema_version"]) is not int or value["schema_version"] != 1 or
            value["scope"] != "PERMISSIONLESS_ANDROID_ACK_FUNCTIONS_OFFLINE" or value["variant"] != variant or
            value["nonce"] != nonce or value["documented_status_ok_accepted"] is not (variant == "after") or
            value["legacy_integer_one_accepted"] is not True or any(value[k] is not False for k in
            ("sender_instantiated", "transport_invoked", "raw_response_body_recorded"))):
        raise TrialBlocked("ANDROID_ACK_PROOF_SCHEMA_OR_NONCE_INVALID")
    cases = value["cases"]
    count = 33 if variant == "after" else 0
    if type(value["case_count"]) is not int or value["case_count"] != count or not isinstance(cases, list) or len(cases) != count:
        raise TrialBlocked("ANDROID_ACK_CASE_COUNT_INVALID")
    for index, case in enumerate(cases):
        accepted = index < 5
        category = ("ACKNOWLEDGED" if accepted else "UNRECOGNIZED_RESPONSE" if index < 15 else
                    "QUOTA_LIMITED" if index < 20 else "MALFORMED_RESPONSE" if index < 30 else
                    ("HTTP_REJECTED", "HTTP_NOT_ACKNOWLEDGED", "RESPONSE_TOO_LARGE")[index - 30])
        if (set(case) != {"case", "response_category", "accepted", "queue_rows_before", "queue_rows_after",
                "ack_counter", "rejected_rows_byte_identical", "unrelated_tail_preserved", "passed"} or
                case["case"] != CASE_NAMES[index] or case["response_category"] != category or
                case["accepted"] is not accepted or case["passed"] is not True or
                case["unrelated_tail_preserved"] is not True or
                any(type(case[k]) is not int for k in ("queue_rows_before", "queue_rows_after", "ack_counter")) or
                case["queue_rows_before"] != 3 or case["queue_rows_after"] != (1 if accepted else 3) or
                case["ack_counter"] != (1 if accepted else 0) or
                (case["rejected_rows_byte_identical"] is not None if accepted else case["rejected_rows_byte_identical"] is not True)):
            raise TrialBlocked("ANDROID_ACK_QUEUE_OR_CATEGORY_PROOF_INVALID")
    validate_public_value(value)
    return value


def verify_proof_apk(apk, receipt, paths, env, variant, source):
    if (receipt.get("variant") != variant or receipt.get("status") != "BUILT_PERMISSIONLESS_PROOF_NOT_RUN" or
            receipt.get("harness_source_commit") != source or receipt.get("permissions") != [] or
            receipt.get("apk_sha256") != sha256(apk) or receipt.get("apk_bytes") != apk.stat().st_size or
            receipt.get("queue_source_commit") != (BASE_SOURCE if variant == "before" else source)):
        raise TrialBlocked("ACK_BUILD_PROVENANCE_INVALID")
    root = Path(__file__).resolve().parent
    expected_queue = BASE_JAVA_SHA if variant == "before" else sha256(root / "direct_trial/DirectQueue.java")
    if (receipt.get("queue_source_sha256") != expected_queue or
            receipt.get("activity_source_sha256") != sha256(root / "ack_response_trial/ResponseProofActivity.java") or
            receipt.get("builder_sha256") != sha256(root / "ack_response_trial/build.py")):
        raise TrialBlocked("ACK_BUILT_SOURCE_DIFFERS")
    badging = run([paths["aapt2"], "dump", "badging", apk], env=env)
    package = "com.cama.telemetry.ack_" + variant
    if (not re.search(r"^package: name='" + re.escape(package) + "' versionCode='1' versionName='1.0'", badging, re.M) or
            re.search(r"^uses-permission", badging, re.M) or not valid_sdk_bounds(badging)):
        raise TrialBlocked("ACK_APK_NOT_PERMISSIONLESS_OR_WRONG_IDENTITY")
    signature = run([paths["apksigner"], "verify", "--print-certs", apk], env=env)
    certs = re.findall(r"Signer #[0-9]+ certificate SHA-256 digest: ([a-fA-F0-9]{64})", signature)
    if len(certs) != 1 or certs[0].lower() != receipt.get("certificate_sha256"):
        raise TrialBlocked("ACK_APK_SIGNER_DIFFERS")
    return package


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ("sdk", "jdk", "build", "runtime-gate", "control-build", "out"):
        p.add_argument("--" + name, type=Path, required=True)
    p.add_argument("--source-commit", required=True); p.add_argument("--serial", required=True)
    a = p.parse_args(); validate_serial(a.serial)
    a.out.mkdir(parents=True, exist_ok=False)
    result = {"schema_version": 1, "scope": SCOPE, "status": "BLOCKED", "started_utc": now(),
        "source_commit": a.source_commit, "new_posthog_rows_authorized": 0,
        "cloud_configuration_or_credential_loaded": False, "sender_instantiated": False,
        "network_sender_exercised": False, "cloud_delivery_retested": False, "native_proofs": {},
        "limits": ["OLD_PREDICATE_AND_NEW_NATIVE_CLASSIFIER_SQLITE_ACK_ONLY", "NO_TLS_OR_CLOUD_DELIVERY_PROOF",
                   "NO_NEW_CLOUD_REVOCATION_RETRY_DEDUPLICATION_OR_PHONE_PROOF"]}
    records, installed, device, initial = [], [], None, None
    try:
        if not re.fullmatch(r"[a-f0-9]{40}", a.source_commit): raise TrialBlocked("ACK_SOURCE_INVALID")
        paths, env, _ = installed_tools(a.sdk, a.jdk)
        gate = parse_json(a.runtime_gate.read_text())
        device = Device(a.sdk, a.serial, env, gate); device.check_gate()
        result["runtime_control"] = {"sha256": sha256(a.runtime_gate), "receipt": gate,
            "build_receipt": parse_json(a.control_build.read_text())}
        initial = radio_snapshot(device, records)
        result["offline_before"] = block_network(device, records)
        for variant in ("before", "after"):
            device.check_gate()
            directory = a.build / variant; apk = directory / "ack-proof.apk"
            receipt = parse_json((directory / "build-receipt.json").read_text())
            package = verify_proof_apk(apk, receipt, paths, env, variant, a.source_commit)
            # The test package is separate from the real LAB and Convoy applications.
            existing = device.call("shell", "pm", "path", package, allow_failure=True)
            if existing.stdout.strip():
                raise TrialBlocked("ACK_PROOF_PACKAGE_NOT_FRESH")
            if existing.returncode not in (0, 1): raise TrialBlocked("ACK_PACKAGE_QUERY_UNAVAILABLE")
            installed.append(package)
            output = device.call("install", "-t", str(apk), timeout=60)
            if "Success" not in output.stdout: raise TrialBlocked("ACK_APK_INSTALL_NOT_ATTESTED")
            nonce = uuid.uuid4().hex
            device.call("shell", "am", "start", "-W", "-n", package + "/" + ACTIVITY,
                "--es", "variant", variant, "--es", "nonce", nonce, timeout=30)
            deadline, value = time.monotonic() + 30, None
            while time.monotonic() < deadline:
                observed = device.call("shell", "run-as", package, "cat", "files/response-proof.json", allow_failure=True)
                if observed.returncode == 0:
                    if len(observed.stdout) > 65536: raise TrialBlocked("ACK_PROOF_OUTPUT_TOO_LARGE")
                    candidate = parse_json(observed.stdout)
                    if candidate.get("nonce") == nonce:
                        value = validate_native(candidate, nonce, variant); break
                time.sleep(0.25)
            if value is None: raise TrialBlocked("ACK_NATIVE_RECEIPT_TIMEOUT")
            result["native_proofs"][variant] = {"build": receipt, "native": value}
            result["offline_after_" + variant] = block_network(device, records)
        result["status"] = "PASSED_OFFLINE_ANDROID_ACK_COMPATIBILITY"
    except (TrialBlocked, GateError, OSError, ValueError, TypeError, KeyError) as failure:
        result["blocked_reason"] = str(failure) if isinstance(failure, TrialBlocked) else "ACK_PROOF_ENVIRONMENT_OR_INPUT_FAILED"
    finally:
        result["cleanup"] = {}
        for package in installed:
            try:
                device.call("shell", "am", "force-stop", package)
                pid = device.call("shell", "pidof", package, allow_failure=True)
                stopped = pid.returncode == 1 and not pid.stdout.strip()
                result["cleanup"][package] = {"process_stopped": stopped}
                if not stopped: raise TrialBlocked("ACK_PROOF_NOT_STOPPED")
            except (TrialBlocked, OSError): result["status"] = "BLOCKED"
        if device is not None and initial is not None:
            try:
                restore_radios(device, records, initial); result["initial_radios_restored"] = True
            except (TrialBlocked, OSError): result["initial_radios_restored"] = False; result["status"] = "BLOCKED"
        result["safe_command_categories"] = records
        result["finished_utc"] = now()
        public_write(a.out / "result.json", result)
    print(json.dumps({"status": result["status"], "new_posthog_rows_authorized": 0,
                      "native_variants_completed": len(result["native_proofs"])}))
    return 0 if result["status"] == "PASSED_OFFLINE_ANDROID_ACK_COMPATIBILITY" else 1


def emit(path):
    raw = path.read_bytes()
    if len(raw) > 262144: raise TrialBlocked("ACK_EXPORT_TOO_LARGE")
    value = parse_json(raw.decode()); validate_public_value(value)
    if value.get("scope") != SCOPE: raise TrialBlocked("ACK_EXPORT_SCOPE_INVALID")
    raw = (json.dumps(value, sort_keys=True, allow_nan=False) + "\n").encode()
    encoded = base64.b64encode(raw).decode(); chunks = [encoded[i:i+4096] for i in range(0, len(encoded), 4096)]
    print("CONVOY_ACK_PROOF_BEGIN " + json.dumps({"sha256": hashlib.sha256(raw).hexdigest(),
          "bytes": len(raw), "chunks": len(chunks)}))
    for n, chunk in enumerate(chunks): print("CONVOY_ACK_PROOF_CHUNK " + str(n+1) + "/" + str(len(chunks)) + " " + chunk)
    print("CONVOY_ACK_PROOF_END")


if __name__ == "__main__":
    import sys
    if len(sys.argv) == 3 and sys.argv[1] == "--emit": emit(Path(sys.argv[2]))
    else: raise SystemExit(main())
