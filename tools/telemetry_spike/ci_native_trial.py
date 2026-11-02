#!/usr/bin/env python3
"""Run pinned native LAB APKs after an independent gate; publish sanitized evidence only.

No build, emulator creation, cloud ingest, workflow mutation or Convoy access.
Semantic failures keep subsequent controls running. Harness/runtime failures block
dependent phases. Private VM connections and captured child output stay in a
temporary directory/memory; only enumerated JSON/JSONL files can be exported.
"""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading

from android_lab_control import PACKAGE
from probe import event, reconcile
from run_native_followup import validate_runtime_gate
from runtime_control.build import sha256
from runtime_control.smoke import validate_serial
from summarize_followup import summarize
from wire_audit_receiver import AuditReceiver

HERE = Path(__file__).resolve().parent
PHASES = ("normal", "revoke", "retry", "overflow")
PHASE_FILES = {"actions.jsonl", "environment.jsonl", "lifecycle.jsonl", "expected.jsonl",
               "received.jsonl", "revoked-intent.jsonl", "validation.json", "runtime-gate-reference.json"}
WIRE_FILES = {"requests.jsonl", "received.jsonl", "summary.json"}
PUBLIC_ROOT_FILES = {"result.json", "runtime-gate-reference.json", "apk-receipts.json",
                     "isolation.json", "aggregate-review.json"}
SECRET_VALUE = re.compile(r"https?://|wss?://|(?:phc_|phx_|sk-|github_pat_|gh[pousr]_)[A-Za-z0-9_-]{8,}|"
                          r"-----BEGIN [A-Z ]*PRIVATE KEY-----", re.I)
SECRET_KEY = re.compile(r"^(?:authorization|password|token|access_token|refresh_token|base|url|isolate_id)$", re.I)


class TrialBlocked(RuntimeError):
    """Only constant, public-safe reason codes belong in this exception."""


def now():
    return datetime.now(timezone.utc).isoformat()


def run(argv, env, timeout=45, allow_failure=False):
    try:
        result = subprocess.run([str(v) for v in argv], env=env, text=True,
                                capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired as failure:
        raise TrialBlocked("COMMAND_TIMEOUT") from failure
    except OSError as failure:
        raise TrialBlocked("COMMAND_UNAVAILABLE") from failure
    if result.returncode and not allow_failure:
        raise TrialBlocked("COMMAND_NONZERO_EXIT")
    return result


def load_rows(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line]


def validate_public_value(value):
    """Fail closed on private/auth material even inside an allowed file."""
    if isinstance(value, dict):
        for key, item in value.items():
            if not isinstance(key, str) or SECRET_KEY.fullmatch(key) or SECRET_VALUE.search(key):
                raise TrialBlocked("PUBLIC_FILE_CONTAINS_PRIVATE_FIELD")
            if key == "api_key" and item != "<redacted:fake-token>":
                raise TrialBlocked("PUBLIC_FILE_CONTAINS_UNREDACTED_API_KEY")
            validate_public_value(item)
    elif isinstance(value, list):
        for item in value:
            validate_public_value(item)
    elif isinstance(value, str) and SECRET_VALUE.search(value):
        raise TrialBlocked("PUBLIC_FILE_CONTAINS_URL_OR_CREDENTIAL")
    elif value is not None and not isinstance(value, (str, int, float, bool)):
        raise TrialBlocked("PUBLIC_FILE_NOT_JSON")


def public_write(path, value):
    validate_public_value(value)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


def export_evidence(work, out):
    """Read only enumerated evidence; never read/copy vm.private.json or logs."""
    for directory in (*PHASES, "wire-normal", "wire-retry", "wire-overflow"):
        source = work / directory
        if not source.exists():
            continue
        names = WIRE_FILES if directory.startswith("wire-") else PHASE_FILES
        for name in sorted(names):
            src = source / name
            if not src.exists():
                continue
            if src.is_symlink() or src.stat().st_size > 10 * 1024 * 1024:
                raise TrialBlocked("PUBLIC_FILE_TYPE_OR_SIZE_REJECTED")
            values = load_rows(src) if name.endswith(".jsonl") else [json.loads(src.read_text())]
            for value in values:
                validate_public_value(value)
            dest = out / directory / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            if name.endswith(".jsonl"):
                dest.write_text("".join(json.dumps(value, allow_nan=False) + "\n" for value in values))
            else:
                public_write(dest, values[0])


def audit_public_directory(out):
    for path in out.rglob("*"):
        if path.is_dir():
            continue
        relative = path.relative_to(out)
        if path.is_symlink() or len(relative.parts) > 2:
            raise TrialBlocked("UNEXPECTED_PUBLIC_ARTIFACT")
        permitted = (path.name in PUBLIC_ROOT_FILES if len(relative.parts) == 1 else
                     relative.parts[0] in PHASES and path.name in PHASE_FILES or
                     relative.parts[0] in ("wire-normal", "wire-retry", "wire-overflow") and path.name in WIRE_FILES)
        if not permitted or path.suffix not in (".json", ".jsonl"):
            raise TrialBlocked("UNEXPECTED_PUBLIC_ARTIFACT")
        values = load_rows(path) if path.suffix == ".jsonl" else [json.loads(path.read_text())]
        for value in values:
            validate_public_value(value)


@contextmanager
def receiver(out, run_id, mode="normal"):
    observer = AuditReceiver(out, run_id, mode)
    errors = []
    # Base HTTPServer would print an exception traceback; retain only a category.
    observer.server.handle_error = lambda *_: errors.append("RECEIVER_HANDLER_FAILED")
    thread = threading.Thread(target=observer.server.serve_forever,
                              kwargs={"poll_interval": 0.1}, daemon=True)
    thread.start()
    try:
        yield
        if errors or not thread.is_alive():
            raise TrialBlocked("RECEIVER_FAILED")
    finally:
        observer.server.shutdown()
        observer.close()
        thread.join(timeout=10)
        if thread.is_alive():
            raise TrialBlocked("RECEIVER_STOP_TIMEOUT")


def classify_phase(phase, expected, received, validation, wire):
    """Count actual IDs; normal/revoke require lossless, overflow intentionally not."""
    result = reconcile(expected, received)
    failures = []
    if validation.get("sentinels_unchanged") is not True:
        failures.append("UNRELATED_STORAGE_NOT_ATTESTED")
    final = validation.get("final_state", {})
    if final.get("native_filter") is not True or final.get("action_ok") is not True:
        failures.append("NATIVE_ACTION_NOT_ATTESTED")
    privacy_ok = (wire.get("privacy_pass") is True and wire.get("requests", 0) > 0
                  and wire.get("event_rows", 0) > 0)
    if not privacy_ok:
        failures.append("FINAL_WIRE_PRIVACY_FAILED_OR_EMPTY")
    if result["unexpected_ids"] or result["conflicting_ids"]:
        failures.append("UNEXPECTED_OR_CONFLICTING_IDS")
    if phase == "overflow":
        run_id = expected[0]["run_id"] if expected else ""
        intended = [event(run_id, i) for i in range(1, 46)] if run_id else []
        expected_missing = [r["event_id"] for r in intended[:13]]
        if expected != intended or result["received_unique"] != 32 or result["missing_ids"] != expected_missing:
            failures.append("OVERFLOW_NOT_EXACT_13_OLDEST_MISSING")
        if result["duplicate_rows"]:
            failures.append("UNEXPECTED_DUPLICATES")
        result["loss_visible_against_all_45_intents"] = result["expected_unique"] == 45
    elif phase == "retry":
        repeated = wire.get("repeated_business_ids", {})
        intended_ids = {row["event_id"] for row in expected}
        same_uuids = (set(repeated) == intended_ids and all(
            value.get("rows", 0) >= 2 and len(value.get("distinct_uuids", [])) == 1
            and value["distinct_uuids"][0] is not None for value in repeated.values()))
        if (len(expected) != 10 or result["missing_ids"] or result["duplicate_rows"] < 10 or
                wire.get("close_without_response_count") != 1 or not same_uuids):
            failures.append("LOST_ACK_RETRY_NOT_ATTESTED_FOR_ALL_IDS")
        result["retry_same_uuid_attested"] = same_uuids
    else:
        if len(expected) != (100 if phase == "normal" else 10) or result["missing_ids"]:
            failures.append("EXPECTED_NEW_IDS_MISSING")
        if result["duplicate_rows"]:
            failures.append("UNEXPECTED_DUPLICATES")
    result.update(status="FAILED" if failures else "PASSED", failures=failures,
                  privacy_pass=privacy_ok,
                  privacy_violation_counts=wire.get("violation_counts", {}))
    return result


def overall_status(phases):
    if any(value.get("status") == "BLOCKED" for value in phases.values()):
        return "BLOCKED"
    if set(phases) != set(PHASES) or any(value.get("status") not in ("PASSED", "FAILED") for value in phases.values()):
        return "BLOCKED"
    return "FAILED" if any(value["status"] == "FAILED" for value in phases.values()) else "PASSED"


def final_reconciliation(work, phases):
    """Recheck final wire bytes, including arrivals after a phase's first receipt.

    normal owns IDs1..100. Revocation also checks its forbidden cohort on the
    later retry receiver: the same SDK queue can deliver those IDs there. The
    overflow experiment is a separate run. Keep original receipts unchanged.
    """
    aggregate = summarize(work)
    for phase in PHASES:
        if phases.get(phase, {}).get("status") not in ("PASSED", "FAILED"):
            continue
        wire_name = "wire-normal" if phase in ("normal", "revoke") else "wire-" + phase
        rows = load_rows(work / wire_name / "received.jsonl")
        expected = load_rows(work / phase / "expected.jsonl")
        revoked_ids, retry_revoked = set(), []
        if phase == "normal":
            rows = [row for row in rows if row["sequence"] <= 100]
        elif phase == "revoke":
            rows = [row for row in rows if row["sequence"] > 100]
            revoked_ids = {row["event_id"] for row in load_rows(work / phase / "revoked-intent.jsonl")}
            retry_path = work / "wire-retry" / "received.jsonl"
            if retry_path.exists():
                run_id = expected[0]["run_id"] if expected else None
                retry_revoked = [row for row in load_rows(retry_path)
                                 if row["run_id"] == run_id and row["event_id"] in revoked_ids]
                rows.extend(retry_revoked)
        validation = json.loads((work / phase / "validation.json").read_text())
        finding = classify_phase(phase, expected, rows, validation, aggregate["wire"][wire_name])
        finding["observation_window"] = "FINAL_RECEIVER_CONTENT_AT_TRIAL_END"
        finding["first_receipt_received_rows"] = validation.get("received_rows")
        if phase == "revoke":
            finding["revoked_ids_reappeared"] = sorted({row["event_id"] for row in rows} & revoked_ids)
            finding["revoked_ids_seen_in_wire_retry"] = sorted({row["event_id"] for row in retry_revoked})
            finding["observation_window"] = "FINAL_NORMAL_AND_RETRY_RECEIVERS_AT_TRIAL_END"
        phases[phase] = finding
    return aggregate


def verify_lab_apk(path, digest, aapt2, apksigner, env):
    if not re.fullmatch(r"[a-f0-9]{64}", digest) or sha256(path) != digest:
        raise TrialBlocked("APK_DIGEST_MISMATCH")
    badging = run([aapt2, "dump", "badging", path], env).stdout
    if not re.search(r"^package: name='" + re.escape(PACKAGE) + r"' ", badging, re.M):
        raise TrialBlocked("APK_IS_NOT_LAB_PACKAGE")
    if "native-code: 'x86_64'" not in badging:
        raise TrialBlocked("APK_IS_NOT_X86_64_LAB")
    permissions = re.findall(r"^uses-permission[^:]*: name='([^']+)'", badging, re.M)
    allowed = {"android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE",
               PACKAGE + ".DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"}
    if set(permissions) - allowed:
        raise TrialBlocked("APK_PERMISSION_SCOPE_REJECTED")
    signature = run([apksigner, "verify", "--print-certs", path], env).stdout
    certs = re.findall(r"Signer #[0-9]+ certificate SHA-256 digest: ([a-fA-F0-9]{64})", signature)
    if len(certs) != 1:
        raise TrialBlocked("APK_SIGNATURE_NOT_ATTESTED")
    return {"sha256": digest, "bytes": path.stat().st_size, "package": PACKAGE,
            "permissions": sorted(permissions), "certificate_sha256": certs[0].lower()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("normal-apk", "overflow-apk", "runtime-gate", "out", "aapt2", "apksigner"):
        parser.add_argument("--" + name, required=True, type=Path)
    for name in ("normal-sha256", "overflow-sha256", "run-id", "overflow-run-id", "source-commit", "serial"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--phase-timeout", type=int, default=900)
    args = parser.parse_args()
    validate_serial(args.serial)
    event(args.run_id, 1); event(args.overflow_run_id, 1)
    if args.run_id == args.overflow_run_id or not re.fullmatch(r"[a-f0-9]{40}", args.source_commit):
        parser.error("distinct synthetic runs and a full source commit are required")
    if not 120 <= args.phase_timeout <= 1200:
        parser.error("phase-timeout must be120..1200 seconds")
    args.out.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, ANDROID_SERIAL=args.serial)
    result = {"schema_version": 1, "scope": "ACTUAL_NATIVE_SDK_LOCAL_WIRE_NOT_CLOUD",
              "source_commit": args.source_commit, "started_utc": now(), "status": "BLOCKED",
              "run_id": args.run_id, "overflow_run_id": args.overflow_run_id,
              "phases": {}, "cloud_requests": "NOT_CONFIGURED", "public_artifacts_safe": False}
    installed = False
    current_phase = "preflight"

    def adb(*parts, **kwargs):
        return run(["adb", "-s", args.serial, *parts], env, **kwargs)

    def check_gate():
        serial = adb("get-serialno").stdout.strip()
        if adb("shell", "getprop", "ro.kernel.qemu").stdout.strip() != "1":
            raise TrialBlocked("NOT_SYNTHETIC_EMULATOR")
        boot_id = adb("shell", "cat", "/proc/sys/kernel/random/boot_id").stdout.strip()
        try:
            validate_runtime_gate(gate, serial, boot_id)
        except (RuntimeError, ValueError, TypeError, KeyError) as failure:
            raise TrialBlocked("RUNTIME_GATE_INVALID_OR_ANDROID_REBOOTED") from failure

    with tempfile.TemporaryDirectory(prefix="convoy-ci-native-private-") as temporary:
        work = Path(temporary)
        try:
            gate_bytes = args.runtime_gate.read_bytes()
            gate = json.loads(gate_bytes)
            check_gate()
            public_write(args.out / "runtime-gate-reference.json", {
                "sha256": hashlib.sha256(gate_bytes).hexdigest(), "serial": args.serial,
                "boot_id": gate["boot_id"], "status": gate["status"]})
            receipts = {kind: verify_lab_apk(path, digest, args.aapt2, args.apksigner, env)
                        for kind, path, digest in (("normal", args.normal_apk, args.normal_sha256),
                                                  ("overflow", args.overflow_apk, args.overflow_sha256))}
            public_write(args.out / "apk-receipts.json", receipts)
            existing = adb("shell", "pm", "path", PACKAGE, allow_failure=True)
            if "package:" in existing.stdout:
                raise TrialBlocked("NORMAL_CASE_REQUIRES_FRESH_LAB_INSTALLATION")

            def install(path):
                nonlocal installed
                output = adb("install", "-r", str(path.resolve()), timeout=180).stdout
                if not re.search(r"^Success$", output, re.M):
                    raise TrialBlocked("LAB_INSTALL_NOT_CONFIRMED")
                installed = True
                run([sys.executable, HERE / "android_lab_control.py", "launch", "--software-rendering"], env)

            def phase(name, run_id, wire_name):
                nonlocal current_phase
                current_phase = name
                check_gate()
                execution = run([sys.executable, HERE / "run_native_followup.py", name,
                                 "--run-id", run_id, "--out", work / name,
                                 "--wire", work / wire_name, "--runtime-gate", args.runtime_gate.resolve()],
                                env, timeout=args.phase_timeout, allow_failure=True)
                if execution.returncode:
                    raise TrialBlocked("PHASE_HARNESS_OR_RUNTIME_FAILED")
                check_gate()
                validation_path = work / name / "validation.json"
                if not validation_path.is_file():
                    raise TrialBlocked("PHASE_RECEIPT_MISSING")
                aggregate = summarize(work)
                result["phases"][name] = classify_phase(
                    name, load_rows(work / name / "expected.jsonl"), load_rows(work / name / "received.jsonl"),
                    json.loads(validation_path.read_text()), aggregate["wire"][wire_name])
                export_evidence(work, args.out)

            with receiver(work / "wire-normal", args.run_id):
                install(args.normal_apk)
                phase("normal", args.run_id, "wire-normal")
                phase("revoke", args.run_id, "wire-normal")
            with receiver(work / "wire-retry", args.run_id, "close-first"):
                phase("retry", args.run_id, "wire-retry")
            # Evidence is materialized before clearing only the synthetic LAB.
            export_evidence(work, args.out)
            current_phase = "overflow_isolation"
            check_gate()
            adb("shell", "am", "force-stop", PACKAGE)
            stopped = adb("shell", "pidof", PACKAGE, allow_failure=True)
            if stopped.stdout.strip() or stopped.returncode not in (0, 1):
                raise TrialBlocked("LAB_STOP_BEFORE_ISOLATION_NOT_ATTESTED")
            if adb("shell", "pm", "clear", PACKAGE).stdout.strip() != "Success":
                raise TrialBlocked("PRE_OVERFLOW_LAB_ISOLATION_FAILED")
            public_write(args.out / "isolation.json", {
                "utc": now(), "package": PACKAGE, "action": "pm_clear",
                "scope": "ONLY_BETWEEN_CASES_BEFORE_OVERFLOW_NEVER_REVOCATION",
                "normal_revoke_retry_evidence_saved": True, "changes_convoy": False})
            with receiver(work / "wire-overflow", args.overflow_run_id):
                install(args.overflow_apk)
                phase("overflow", args.overflow_run_id, "wire-overflow")
        except TrialBlocked as failure:
            result["blocked_at"] = current_phase
            result["blocked_reason"] = str(failure)
            if current_phase in PHASES:
                result["phases"][current_phase] = {"status": "BLOCKED", "reason": str(failure)}
        except (OSError, ValueError, TypeError, KeyError) as failure:
            result["blocked_at"] = current_phase
            result["blocked_reason"] = "EVIDENCE_OR_INPUT_INVALID_" + type(failure).__name__
        finally:
            if installed:
                try:
                    stopped = adb("shell", "am", "force-stop", PACKAGE, allow_failure=True)
                    removed = adb("forward", "--remove", "tcp:8999", allow_failure=True)
                    result["cleanup"] = {"lab_stop_exit": stopped.returncode, "debug_forward_remove_exit": removed.returncode}
                    if stopped.returncode:
                        result["blocked_reason"] = "LAB_CLEANUP_FAILED"
                except TrialBlocked:
                    result["blocked_reason"] = "LAB_CLEANUP_FAILED"
            try:
                export_evidence(work, args.out)
                aggregate = final_reconciliation(work, result["phases"])
                public_write(args.out / "aggregate-review.json", aggregate)
                audit_public_directory(args.out)
                result["public_artifacts_safe"] = True
            except (TrialBlocked, OSError, ValueError, TypeError, KeyError):
                result["blocked_reason"] = "PUBLIC_EVIDENCE_VALIDATION_FAILED"
            for name in PHASES:
                result["phases"].setdefault(name, {"status": "NOT_RUN_DEPENDENCY_BLOCKED"})
            result["status"] = "BLOCKED" if "blocked_reason" in result else overall_status(result["phases"])
            result["acceptance_failures_observed"] = any(p["status"] == "FAILED" for p in result["phases"].values())
            result["finished_utc"] = now()
            public_write(args.out / "result.json", result)
            audit_public_directory(args.out)
            # Print only the reviewed summary; child stdout/stderr and auth paths never escape.
            print(json.dumps(result, allow_nan=False))
    if result["status"] != "PASSED":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
