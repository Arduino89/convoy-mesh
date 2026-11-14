#!/usr/bin/env python3
"""One offline install/provision diagnosis; no LAB launch, secret or cloud gate."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import time
from types import SimpleNamespace

from ci_cloud_trial import CloudDevice, sanitize_preparation_error, unknown_budget_receipt
from ci_direct_trial import PACKAGE, verify_apk
from ci_native_trial import TrialBlocked, now, public_write, validate_public_value
from runtime_control.build import sha256
from runtime_control.smoke import validate_serial

PINNED_APP_SOURCE = "2d76100fda1df0637e953f4ad90f26073028880c"
RADIO_KEYS = ("airplane_mode_on", "wifi_on", "mobile_data")
FAKE_CONFIG = {
    "mode": "diagnostic_no_cloud", "endpoint": "https://example.invalid/batch/",
    "api_key": "phc_synthetic_local_only", "run_id": "synthetic-provision-diagnostic",
    "row_limit": 0,
}
PREPARATION_FIELDS = {"schema_version", "observed_utc", "phase", "returncode", "error_category",
                      "stdout_present", "stderr_present"}


def default_network_observation(dump):
    """AOSP ConnectivityService prints one current value; retain no raw dump.

    Source: platform/packages/modules/Connectivity, 7c17c283ea,
    service/src/com/android/server/ConnectivityService.java (defaultNai dump).
    Missing/changed/duplicated formats fail closed rather than implying offline.
    """
    labels = re.findall(r"^[ \t]*Active default network:[ \t]*(.*)$", dump, re.M)
    state = "UNKNOWN"
    if len(labels) > 1:
        state = "AMBIGUOUS"
    elif len(labels) == 1:
        if labels[0].strip() == "none":
            state = "NONE"
        elif re.fullmatch(r"[0-9]+", labels[0].strip()):
            state = "ACTIVE"
    return {"state": state, "label_count": len(labels)}


def no_active_default_network(dump):
    return default_network_observation(dump)["state"] == "NONE"


def adb_version_identity(output):
    """Keep only numeric client identity, never installation paths or raw text."""
    protocol = re.findall(r"^Android Debug Bridge version ([0-9]+\.[0-9]+\.[0-9]+)$", output, re.M)
    build = re.findall(r"^Version ([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)$", output, re.M)
    if len(protocol) != 1 or len(build) != 1:
        raise TrialBlocked("PROBE_ADB_VERSION_UNATTESTED")
    return {"protocol_version": protocol[0], "platform_tools_version": build[0][0],
            "build_number": build[0][1], "raw_output_published": False}


def checked_call(device, records, stage, *args, timeout=15, allow_failure=False):
    if not re.fullmatch(r"[A-Z_]{1,64}", stage):
        raise TrialBlocked("PROBE_STAGE_INVALID")
    try:
        output = device.call(*args, timeout=timeout, allow_failure=True)
    except TrialBlocked as failure:
        category = {"COMMAND_TIMEOUT": "TIMEOUT", "COMMAND_UNAVAILABLE": "UNAVAILABLE"}.get(
            str(failure), "COMMAND_BLOCKED")
        records.append({"stage": stage, "returncode": None, "error_category": category,
                        "stdout_present": False, "stderr_present": False})
        raise TrialBlocked("PROBE_" + stage + "_" + category) from None
    category = "NONE" if output.returncode == 0 else sanitize_preparation_error(output.stderr or output.stdout)
    records.append({"stage": stage, "returncode": output.returncode, "error_category": category,
                    "stdout_present": bool(output.stdout), "stderr_present": bool(output.stderr)})
    if len(output.stdout) > 2 * 1024 * 1024 or len(output.stderr) > 65536:
        raise TrialBlocked("PROBE_COMMAND_OUTPUT_LIMIT")
    if output.returncode and not allow_failure:
        raise TrialBlocked("PROBE_" + stage + "_NONZERO_EXIT")
    return output


def radio_snapshot(device, records):
    values = {}
    for key in RADIO_KEYS:
        value = checked_call(device, records, "READ_" + key.upper(),
                             "shell", "settings", "get", "global", key).stdout.strip()
        if value not in ("0", "1"):
            raise TrialBlocked("PROBE_RADIO_SETTING_UNATTESTED")
        values[key] = value == "1"
    return values


def block_network(device, records):
    for stage, args in (
            ("AIRPLANE_ENABLE", ("cmd", "connectivity", "airplane-mode", "enable")),
            ("WIFI_DISABLE", ("svc", "wifi", "disable")),
            ("DATA_DISABLE", ("svc", "data", "disable"))):
        checked_call(device, records, stage, "shell", *args)
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        radios = radio_snapshot(device, records)
        dump = checked_call(device, records, "CONNECTIVITY_OFFLINE_READ", "shell", "dumpsys", "connectivity").stdout
        network = default_network_observation(dump)
        device.offline_sample_count = getattr(device, "offline_sample_count", 0) + 1
        device.last_offline_observation = {
            "sample_index": device.offline_sample_count,
            "radio_settings": {key: radios[key] for key in RADIO_KEYS},
            "radio_flags_match_requested": radios == {"airplane_mode_on": True, "wifi_on": False, "mobile_data": False},
            "default_network_state": network["state"], "default_network_label_count": network["label_count"],
            "raw_connectivity_dump_published": False,
        }
        if device.last_offline_observation["radio_flags_match_requested"] and network["state"] == "NONE":
            return {"radio_settings": radios, "active_default_network_absent": True,
                    "raw_connectivity_dump_published": False}
        time.sleep(0.5)
    raise TrialBlocked("PROBE_OFFLINE_BARRIER_UNATTESTED")


def restore_radios(device, records, initial):
    for stage, args in (
            ("RESTORE_AIRPLANE", ("cmd", "connectivity", "airplane-mode", "enable" if initial["airplane_mode_on"] else "disable")),
            ("RESTORE_WIFI", ("svc", "wifi", "enable" if initial["wifi_on"] else "disable")),
            ("RESTORE_DATA", ("svc", "data", "enable" if initial["mobile_data"] else "disable"))):
        checked_call(device, records, stage, "shell", *args)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if radio_snapshot(device, records) == initial:
            return
        time.sleep(0.5)
    raise TrialBlocked("PROBE_RADIO_RESTORE_UNATTESTED")


def assert_stopped(device, records, stage):
    checked_call(device, records, stage, "shell", "am", "force-stop", PACKAGE)
    if device.pid(absent_ok=True) is not None:
        raise TrialBlocked("PROBE_LAB_PROCESS_NOT_STOPPED")


def emit_result(path):
    """Export only the reviewed result, not APK/config/diagnostics directories."""
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 262144:
        raise TrialBlocked("PROBE_EXPORT_FILE_REJECTED")
    def unique_keys(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise TrialBlocked("PROBE_EXPORT_DUPLICATE_KEY")
            value[key] = item
        return value

    def reject_constant(_value):
        raise TrialBlocked("PROBE_EXPORT_NONFINITE_VALUE")

    value = json.loads(path.read_text(), object_pairs_hook=unique_keys, parse_constant=reject_constant)
    if value.get("scope") != "OFFLINE_FAKE_PROVISION_DIAGNOSTIC_NO_LAB_LAUNCH_NO_CLOUD":
        raise TrialBlocked("PROBE_EXPORT_SCOPE_REJECTED")
    validate_public_value(value)
    # Only reserialize the inspected object. Never export unvalidated original bytes.
    raw = (json.dumps(value, indent=2, allow_nan=False) + "\n").encode("utf-8")
    encoded = base64.b64encode(raw).decode("ascii")
    chunks = [encoded[i:i + 6000] for i in range(0, len(encoded), 6000)]
    print("CONVOY_PROVISION_DIAGNOSTIC_BEGIN " + json.dumps({"bytes": len(raw),
          "sha256": hashlib.sha256(raw).hexdigest(), "chunks": len(chunks)}, sort_keys=True))
    for index, chunk in enumerate(chunks, 1):
        print(f"CONVOY_PROVISION_DIAGNOSTIC_CHUNK {index}/{len(chunks)} {chunk}")
    print("CONVOY_PROVISION_DIAGNOSTIC_END")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emit", type=Path)
    for name in ("sdk", "jdk", "apk", "build-receipt", "runtime-gate", "out"):
        parser.add_argument("--" + name, type=Path)
    for name in ("serial", "source-commit", "apk-source-commit"):
        parser.add_argument("--" + name)
    args = parser.parse_args()
    if args.emit:
        emit_result(args.emit)
        return
    required = (args.sdk, args.jdk, args.apk, args.build_receipt, args.runtime_gate, args.out,
                args.serial, args.source_commit, args.apk_source_commit)
    if not all(required):
        parser.error("probe arguments required without --emit")
    validate_serial(args.serial)
    if not re.fullmatch(r"[a-f0-9]{40}", args.source_commit) or args.apk_source_commit != PINNED_APP_SOURCE:
        parser.error("exact diagnostic source and pinned application source required")
    args.out.mkdir(parents=True, exist_ok=False)
    result = {"schema_version": 1, "scope": "OFFLINE_FAKE_PROVISION_DIAGNOSTIC_NO_LAB_LAUNCH_NO_CLOUD",
              "diagnostic_source_commit": args.source_commit, "apk_source_commit": args.apk_source_commit,
              "started_utc": now(), "status": "BLOCKED", "legacy_install_provision_argv_unchanged": False,
              "provision_transport": "ADB_SHELL_T_SHELL_V2_REMOTE_EXIT_REQUIRED",
              "transport_change_reason": "PREQUOTED_SCRIPT_REESCAPED_BY_EXEC_IN_AND_REMOTE_EXIT_UNOBSERVED",
              "lab_activity_launched": False, "grant_or_capture_invoked": False,
              "fake_input_only": True, "cloud_send_attempted": False,
              "cloud_budget": {"previous_allowance_conservatively_consumed": 500,
                               "remaining_authorized_rows": 0, "new_allowance": 0,
                               "probe_does_not_refund_previous_run": True},
              "budget_recovery": unknown_budget_receipt("synthetic-provision-diagnostic", args.source_commit),
              "diagnostic_source_sha256": {name: sha256(Path(__file__).resolve().parent / name)
                                           for name in ("ci_provision_probe.py", "ci_cloud_trial.py")},
              "diagnostic_commands": [], "preparation": [],
              "offline_sample_count": 0, "last_offline_observation": None,
              "shell_features_observation": None,
              "limits": ["ONE_PREPARATION_ATTEMPT_ONLY", "NO_APPLICATION_RUNTIME_OR_CLOUD_PROOF",
                         "REBUILT_PINNED_SOURCE_NOT_HISTORICAL_APK_BYTES"]}
    device, radios = None, None
    records = result["diagnostic_commands"]
    cleanup = {"required": False, "install_confirmed": False, "lab_stopped": False,
               "fake_config_removed": False, "initial_radios_restored": False}
    # Persist conservative unknown counters before the first device operation.
    # This fresh no-launch probe cannot recover the old ephemeral runner's ledger.
    public_write(args.out / "result.json", result)
    try:
        if (os.environ.get("CONVOY_LAB_POSTHOG_TOKEN") or os.environ.get("CONVOY_CLOUD_GATE") or
                os.environ.get("CONVOY_CLOUD_ENABLED", "false") != "false"):
            raise TrialBlocked("PROBE_REAL_CLOUD_INPUT_REFUSED")
        env = dict(os.environ, JAVA_HOME=str(args.jdk), ANDROID_SERIAL=args.serial)
        env["PATH"] = str(args.jdk / "bin") + os.pathsep + env.get("PATH", "")
        runtime = json.loads(args.runtime_gate.read_text())
        device = CloudDevice(args.sdk, args.serial, env, runtime)
        device.preparation_path = args.out / "preparation.jsonl"
        device.offline_sample_count, device.last_offline_observation = 0, None
        result["adb_client"] = adb_version_identity(
            checked_call(device, records, "ADB_VERSION", "version").stdout)
        device.check_gate()
        result["runtime_control"] = {"sha256": sha256(args.runtime_gate), "serial": args.serial,
                                     "boot_id": runtime["boot_id"], "status": runtime["status"]}
        apk_args = SimpleNamespace(**vars(args))
        apk_args.source_commit = args.apk_source_commit
        result["apk"] = verify_apk(apk_args, env)
        initial = checked_call(device, records, "FRESH_PACKAGE_CHECK", "shell", "pm", "path", PACKAGE,
                               allow_failure=True)
        if initial.stdout.strip():
            raise TrialBlocked("PROBE_REQUIRES_FRESH_PACKAGE_NO_EXISTING_LEDGER")
        if initial.returncode not in (0, 1):
            raise TrialBlocked("PROBE_FRESH_PACKAGE_NOT_ATTESTED")
        radios = radio_snapshot(device, records)
        result["offline_before_install"] = block_network(device, records)
        # Reuse the instrumented original commands once. No alternative or blind retry follows failure.
        device.install(args.apk.resolve())
        assert_stopped(device, records, "STOP_BEFORE_PROVISION")
        private_bytes = json.dumps(FAKE_CONFIG, separators=(",", ":")).encode("utf-8")
        device.provision(private_bytes)
        result["provision_confirmed"] = bool(device.provision_confirmed)
        result["private_mode_600_and_exact_fake_readback"] = bool(device.provision_confirmed)
        if device.pid(absent_ok=True) is not None:
            raise TrialBlocked("PROBE_UNEXPECTED_LAB_PROCESS")
        result["offline_after_provision"] = block_network(device, records)
        result["status"] = "CORRECTED_PROVISION_PATH_PASSED"
        result["historical_failure_cause"] = "EXEC_IN_QUOTING_CONTRACT_MISMATCH_REPRODUCED_ON_HOST"
    except (TrialBlocked, OSError, ValueError, TypeError, KeyError) as failure:
        reason = str(failure) if isinstance(failure, TrialBlocked) else "PROBE_INPUT_OR_IO_FAILURE"
        result["blocked_reason"] = reason if re.fullmatch(r"[A-Z0-9_]{1,160}", reason) else "PROBE_FAILURE_DETAILS_WITHHELD"
    finally:
        if device is not None:
            result["shell_v2_confirmed"] = bool(getattr(device, "shell_v2_confirmed", False))
            result["shell_features_observation"] = getattr(device, "shell_features_observation", None)
            result["private_write_command_completed"] = bool(getattr(device, "private_write_command_completed", False))
            result["config_write_confirmed"] = bool(getattr(device, "config_write_confirmed", False))
            cleanup["required"] = bool(getattr(device, "cleanup_required", False))
            cleanup["install_confirmed"] = bool(getattr(device, "install_confirmed", False))
            if cleanup["required"]:
                try:
                    assert_stopped(device, records, "CLEANUP_FORCE_STOP")
                    cleanup["lab_stopped"] = True
                    installed = checked_call(device, records, "CLEANUP_PACKAGE_CHECK", "shell", "pm", "path", PACKAGE,
                                             allow_failure=True)
                    if installed.stdout.strip().startswith("package:"):
                        device.prepare_call("PRIVATE_REMOVE", "shell", "run-as", PACKAGE,
                                            "rm", "-f", "files/cloud-config.private.json")
                        device.prepare_call("PRIVATE_REMOVE_VERIFY", "shell", "run-as", PACKAGE,
                                            "test", "!", "-e", "files/cloud-config.private.json")
                        cleanup["fake_config_removed"] = True
                    elif installed.returncode in (0, 1) and not installed.stdout.strip():
                        cleanup["fake_config_removed"] = True
                        cleanup["package_absent"] = True
                    else:
                        raise TrialBlocked("PROBE_CLEANUP_PACKAGE_UNATTESTED")
                except (TrialBlocked, OSError, ValueError, TypeError):
                    result["status"] = "BLOCKED"
                    result["cleanup_error"] = "PROBE_STOP_OR_PRIVATE_CLEANUP_UNATTESTED"
            if radios is not None:
                try:
                    if not cleanup["required"] or (cleanup["lab_stopped"] and cleanup["fake_config_removed"]):
                        restore_radios(device, records, radios)
                        cleanup["initial_radios_restored"] = True
                    else:
                        result["left_offline"] = block_network(device, records)
                except (TrialBlocked, OSError, ValueError, TypeError):
                    result["status"] = "BLOCKED"
                    result["radio_cleanup_error"] = "PROBE_RADIO_CLEANUP_UNATTESTED"
            result["offline_sample_count"] = device.offline_sample_count
            result["last_offline_observation"] = device.last_offline_observation
            for row in getattr(device, "preparation_records", []):
                if not isinstance(row, dict) or set(row) != PREPARATION_FIELDS:
                    result["status"] = "BLOCKED"
                    result["export_error"] = "PROBE_PREPARATION_SCHEMA_UNSAFE"
                    break
                validate_public_value(row)
                result["preparation"].append(row)
        result["cleanup"] = cleanup
        result["finished_utc"] = now()
        public_write(args.out / "result.json", result)
        print(json.dumps({"status": result["status"], "blocked_reason": result.get("blocked_reason"),
                          "preparation_stages": len(result["preparation"]),
                          "cloud_send_attempted": False, "remaining_authorized_rows": 0}))
    if result["status"] != "CORRECTED_PROVISION_PATH_PASSED":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
