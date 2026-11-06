#!/usr/bin/env python3
"""Gated synthetic Android -> existing PostHog EU project trial, <=500 rows/run.

No automatic activation: verified project/quota/deletion/privacy/retention and
same-source local regression receipts are required before any ADB operation.
Credentials enter only a private app file through stdin, never argv or output.
HTTP acknowledgement is a transport observation; connector readback is separate.
"""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import subprocess
import tempfile
import time

from ci_direct_trial import Device, PACKAGE, SELF_CHECKS, verify_apk
from ci_native_trial import TrialBlocked, load_rows, now, public_write, validate_public_value
from probe import event
from runtime_control.build import sha256
from runtime_control.smoke import validate_serial
from wire_audit_receiver import TOKEN, audit_payload

PROJECT = 330212
HOST = "eu.i.posthog.com"
ENDPOINT = "https://" + HOST + "/batch/"
CONTROLS = ("privacy", "retention", "deletion", "quota", "local_regression")
FILES = {"result.json", "cloud-gate-reference.json", "runtime-gate-reference.json", "apk-receipt.json",
         "states.jsonl", "lifecycle.jsonl", "expected.jsonl", "revoked-intent.jsonl",
         "preflight.jsonl", "transport.jsonl", "network.jsonl", "preparation.jsonl", "budget-recovery.json"}
NETWORK_KEYS = {"probe_available", "active_network", "internet_capable", "validated", "transports"}


def iso(value):
    if not isinstance(value, str):
        raise TrialBlocked("GATE_TIME_INVALID")
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise TrialBlocked("GATE_TIME_INVALID") from exc
    if result.tzinfo is None:
        raise TrialBlocked("GATE_TIMEZONE_REQUIRED")
    return result


def budget_accounting(gate):
    """Bind the one-run cap to an explicitly authorized cumulative allowance.

    Schema 1 retains the historical 500-row authorization for reproducibility.
    Schema 2 never infers previous consumption by subtracting from that old cap.
    Its additional allowance is one-use: unused rows authorize no later launch.
    """
    remaining = gate.get("remaining_budget")
    if type(remaining) is not int or not 130 <= remaining <= 500:
        raise TrialBlocked("CLOUD_QUOTA_OR_GLOBAL_BUDGET_INSUFFICIENT")
    version = gate.get("schema_version")
    if type(version) is not int:
        raise TrialBlocked("CLOUD_QUOTA_OR_GLOBAL_BUDGET_INSUFFICIENT")
    if version == 1:
        if (type(gate.get("total_ceiling")) is not int or gate["total_ceiling"] != 500 or
                any(key in gate for key in ("prior_rows_conservative_consumed", "additional_rows_authorized"))):
            raise TrialBlocked("CLOUD_QUOTA_OR_GLOBAL_BUDGET_INSUFFICIENT")
        return {"limit": remaining, "total_ceiling": 500, "prior_rows_reserved": 500 - remaining}
    prior = gate.get("prior_rows_conservative_consumed")
    additional = gate.get("additional_rows_authorized")
    total = gate.get("total_ceiling")
    if (version != 2 or "prior_rows_reserved" in gate or
            any(type(value) is not int for value in (prior, additional, total)) or
            prior < 0 or additional != remaining or total != prior + additional):
        raise TrialBlocked("CLOUD_QUOTA_OR_GLOBAL_BUDGET_INSUFFICIENT")
    return {"accounting_schema_version": 2, "limit": remaining, "total_ceiling": total,
            "prior_rows_conservative_consumed": prior, "additional_rows_authorized": additional}


def required_controls(gate):
    return CONTROLS + (("budget_authorization",) if gate.get("schema_version") == 2 else ())


def validate_cloud_gate(gate, source, run_id, execution_id, run_attempt, clock=None):
    """Pending/unknown prechecks are never interpreted as permission to ingest."""
    clock = clock or datetime.now(timezone.utc)
    if (not isinstance(gate, dict) or type(gate.get("schema_version")) is not int or gate.get("schema_version") not in (1, 2) or gate.get("status") != "PASS" or
            gate.get("project_id") != PROJECT or gate.get("api_host") != "https://" + HOST or
            gate.get("source_commit") != source or gate.get("run_id") != run_id or
            gate.get("execution_id") != execution_id or type(gate.get("run_attempt")) is not int or
            gate.get("run_attempt") != 1 or type(run_attempt) is not int or run_attempt != 1):
        raise TrialBlocked("CLOUD_PRECHECK_NOT_VERIFIED_FOR_THIS_EXECUTION")
    if not re.fullmatch(r"[a-f0-9]{40}", source) or not re.fullmatch(r"[A-Za-z0-9_.: /()-]{1,150}", execution_id):
        raise TrialBlocked("CLOUD_EXECUTION_IDENTITY_INVALID")
    event(run_id, 140)
    quota, remaining = gate.get("quota_rows_available"), gate.get("remaining_budget")
    if type(quota) is not int or quota < 500:
        raise TrialBlocked("CLOUD_QUOTA_OR_GLOBAL_BUDGET_INSUFFICIENT")
    budget_accounting(gate)
    if not clock < iso(gate.get("expires_utc")) <= clock + timedelta(hours=24):
        raise TrialBlocked("CLOUD_GATE_EXPIRED_OR_VALIDITY_TOO_LONG")
    for name in required_controls(gate):
        value = gate.get(name, {})
        if (not isinstance(value, dict) or value.get("status") != "VERIFIED" or
                not isinstance(value.get("evidence_ref"), str) or not 1 <= len(value["evidence_ref"]) <= 2000 or
                not clock - timedelta(hours=24) <= iso(value.get("checked_at_utc")) <= clock + timedelta(minutes=5)):
            raise TrialBlocked("CLOUD_REQUIRED_CONTROL_NOT_VERIFIED")
    if (gate["privacy"].get("anonymize_ips") is not True or
            gate["privacy"].get("session_recording_opt_in") is not False or
            gate["quota"].get("free_plan") is not True or
            gate["local_regression"].get("source_commit") != source):
        raise TrialBlocked("CLOUD_PRIVACY_OR_SAME_SOURCE_REGRESSION_NOT_ATTESTED")
    if gate["schema_version"] == 2 and any(
            type(gate["budget_authorization"].get(key)) is not int or
            gate["budget_authorization"][key] != gate[key]
            for key in ("prior_rows_conservative_consumed", "additional_rows_authorized", "total_ceiling")):
        raise TrialBlocked("CLOUD_BUDGET_AUTHORIZATION_NOT_ATTESTED")
    return remaining


def read_private_config(path, run_id, remaining):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 16384 or stat.S_IMODE(path.stat().st_mode) & 0o077:
        raise TrialBlocked("PRIVATE_CONFIG_FILE_SCOPE_OR_MODE_INVALID")
    config = json.loads(path.read_text())
    if (not isinstance(config, dict) or set(config) != {"mode", "endpoint", "api_key", "run_id", "row_limit"} or
            config.get("mode") != "posthog_cloud" or config.get("endpoint") != ENDPOINT or
            config.get("run_id") != run_id or config.get("row_limit") != remaining or
            not isinstance(config.get("api_key"), str) or
            not re.fullmatch(r"phc_[A-Za-z0-9_-]{16,200}", config["api_key"]) or config["api_key"] == TOKEN):
        raise TrialBlocked("PRIVATE_CONFIG_CONTENT_INVALID")
    return json.dumps(config, separators=(",", ":")).encode()


def write_rows(path, rows):
    for row in rows:
        validate_public_value(row)
    path.write_text("".join(json.dumps(row, allow_nan=False) + "\n" for row in rows))


def audit_public_directory(out):
    for path in out.rglob("*"):
        if path.is_symlink() or path.is_dir() or path.parent != out or path.name not in FILES or path.stat().st_size > 2 * 1024 * 1024:
            raise TrialBlocked("UNEXPECTED_CLOUD_PUBLIC_ARTIFACT")
        values = load_rows(path) if path.suffix == ".jsonl" else [json.loads(path.read_text())]
        for value in values:
            validate_public_value(value)


def sanitize_preflight(records, run_id):
    sanitized, failures = [], []
    for record in records:
        payload = record.get("payload")
        if not isinstance(payload, dict) or payload.get("api_key") != "<redacted:project-token>":
            raise TrialBlocked("NATIVE_PREFLIGHT_CREDENTIAL_NOT_REDACTED")
        # Normalize only the already-redacted credential for the unchanged local
        # verifier. This is an audit of native prewrite bytes, not a TLS wire tap.
        checked = audit_payload(dict(payload, api_key=TOKEN), run_id)
        failures.extend(checked["violations"])
        safe = {key: record[key] for key in ("attempt_id", "budget_reserved_rows", "rows", "body_bytes") if key in record}
        safe.update(credential_redacted=True, envelope_keys=sorted(payload),
                    payload={"batch": checked["payload_redacted"].get("batch", [])},
                    prewrite_content_audit={"violations": checked["violations"],
                                            "normalized_rows": checked["normalized_rows"]})
        sanitized.append(safe)
    return sanitized, failures


def summarize_transport(preflight, transport, run_id, remaining, final, accounting=None):
    """Evidence from attempted writes, deliberately separate from cloud rows."""
    failures, attempts, reserved, by_id, written, stages, acknowledged_ids = [], {}, 0, {}, set(), {}, set()
    for row in preflight:
        attempt = row.get("attempt_id")
        batch = row.get("payload", {}).get("batch", [])
        count = row.get("rows")
        if (type(attempt) is not int or attempt <= 0 or attempt in attempts or
                type(count) is not int or count != len(batch) or not 1 <= count <= 20 or
                row.get("budget_reserved_rows") != reserved + count):
            failures.append("RESERVATION_LEDGER_INVALID")
            continue
        reserved += count
        attempts[attempt] = row
        if row.get("prewrite_content_audit", {}).get("violations"):
            failures.append("NATIVE_FINAL_CONTENT_AUDIT_FAILED")
    for row in transport:
        attempt = row.get("attempt_id")
        if attempt not in attempts:
            failures.append("TRANSPORT_WITHOUT_DURABLE_RESERVATION")
            continue
        reference = attempts[attempt]
        stages.setdefault(attempt, []).append(row)
        if (row.get("rows") != reference["rows"] or row.get("budget_reserved_rows") != reference["budget_reserved_rows"]):
            failures.append("TRANSPORT_RESERVATION_MISMATCH")
        items = reference["payload"]["batch"]
        if (row.get("phase") not in {"reserved", "body_written", "response", "finished"} or
                row.get("event_ids") != [item["properties"]["event_id"] for item in items] or
                row.get("uuids") != [item["uuid"] for item in items]):
            failures.append("TRANSPORT_IDENTITIES_OR_PHASE_MISMATCH")
        if row.get("quota_limited") is True or (row.get("response_accepted") is False and row.get("response_code", 0) < 500):
            failures.append("CLOUD_HTTP_RESPONSE_NOT_ACCEPTED")
        if row.get("phase") == "body_written":
            if attempt in written:
                failures.append("DUPLICATE_BODY_WRITTEN_RECEIPT")
            written.add(attempt)
            for item in reference["payload"]["batch"]:
                business_id = item.get("properties", {}).get("event_id")
                by_id.setdefault(business_id, []).append(item)
    expected_ids = {event(run_id, n)["event_id"] for n in (*range(1, 101), *range(121, 141))}
    for attempt in attempts:
        records = stages.get(attempt, [])
        phases = [row.get("phase") for row in records]
        if phases not in (["reserved", "finished"], ["reserved", "body_written", "finished"],
                          ["reserved", "body_written", "response", "finished"]):
            failures.append("ATTEMPT_PHASES_INCOMPLETE_DUPLICATED_OR_UNORDERED")
            continue
        end = records[-1]
        has_body = "body_written" in phases
        response = next((row for row in records if row["phase"] == "response"), None)
        if end.get("body_written") is not has_body or type(end.get("acknowledged")) is not bool:
            failures.append("FINISHED_RECEIPT_INCONSISTENT")
        if response is None:
            if end.get("response_code") != 0 or end.get("acknowledged") is not False or end.get("ack_discarded") is not False:
                failures.append("UNKNOWN_RESPONSE_CANNOT_BE_ACKNOWLEDGED")
        else:
            accepted, discarded = response.get("response_accepted"), response.get("ack_discarded")
            if (type(accepted) is not bool or type(discarded) is not bool or type(response.get("quota_limited")) is not bool or
                    end.get("response_code") != response.get("response_code") or end.get("ack_discarded") is not discarded or
                    end.get("acknowledged") is not (accepted and not discarded) or
                    accepted and (response.get("response_code") != 200 or response.get("quota_limited") is not False)):
                failures.append("HTTP_RESPONSE_AND_FINISHED_RECEIPTS_INCONSISTENT")
            if end.get("acknowledged") is True:
                acknowledged_ids.update(end["event_ids"])
    if acknowledged_ids != expected_ids:
        failures.append("EXPECTED_IDS_NOT_ALL_ACKNOWLEDGED_BY_TRANSPORT")
    revoked_ids = {event(run_id, n)["event_id"] for n in range(101, 121)}
    if set(by_id) != expected_ids:
        failures.append("EXPECTED_BODY_WRITES_MISSING_OR_UNEXPECTED")
    attempted_ids = {item.get("properties", {}).get("event_id") for row in attempts.values() for item in row["payload"]["batch"]}
    if attempted_ids & revoked_ids:
        failures.append("REVOKED_ID_RESERVED_OR_WRITTEN")
    retry_ids = {event(run_id, n)["event_id"] for n in range(131, 141)}
    same_retry = all(len(by_id.get(key, [])) >= 2 and len({json.dumps(item, sort_keys=True) for item in by_id[key]}) == 1
                     for key in retry_ids)
    ignored = [row for row in transport if row.get("phase") == "response" and row.get("ack_discarded") is True]
    if not same_retry or len(ignored) != 1 or ignored[0].get("response_code") != 200:
        failures.append("ONE_HTTP200_IGNORED_SAME_UUID_RETRY_NOT_ATTESTED")
    if (reserved > remaining or reserved <= 0 or final.get("cloud_rows_reserved") != reserved or
            final.get("cloud_row_limit") != remaining or final.get("queue_count") != 0 or final.get("in_flight_count") != 0):
        failures.append("GLOBAL_BUDGET_OR_FINAL_QUEUE_NOT_ATTESTED")
    if (any(final.get(key) != 0 for key in ("cloud_budget_blocked", "cloud_transport_blocked", "cloud_audit_failures")) or
            final.get("retry_ack_discarded") != 1 or final.get("cloud_rows_written") != sum(len(by_id[k]) for k in by_id)):
        failures.append("NATIVE_CLOUD_SAFETY_COUNTERS_NOT_ATTESTED")
    accounting = accounting if accounting is not None else {
        "limit": remaining, "total_ceiling": 500, "prior_rows_reserved": 500 - remaining}
    return {"failures": sorted(set(failures)), "budget": dict(accounting, reserved_rows=reserved),
            "retry_same_uuid_attested": same_retry, "body_written_attempts": len(written),
            "body_written_rows": sum(len(by_id[k]) for k in by_id),
            "unique_body_written_ids": len(by_id), "revoked_ids_attempted": sorted(attempted_ids & revoked_ids),
            "http200_deliberately_ignored": len(ignored), "http_status_is_not_cloud_receipt": True}


PREPARATION_PHASES = {"INSTALL_APK", "INSTALL_VERIFY", "PRIVATE_MKDIR", "PRIVATE_WRITE",
                      "PRIVATE_STAT", "PRIVATE_VERIFY", "PRIVATE_REMOVE", "PRIVATE_REMOVE_VERIFY",
                      "PRIVATE_SHELL_FEATURES"}


def sanitize_preparation_error(value):
    """Classify known errors; never return arbitrary command output or secrets."""
    text = value.decode("utf-8", errors="replace") if isinstance(value, bytes) else str(value)
    for marker, category in (
            ("INSTALL_FAILED_UPDATE_INCOMPATIBLE", "INSTALL_FAILED_UPDATE_INCOMPATIBLE"),
            ("INSTALL_FAILED_VERSION_DOWNGRADE", "INSTALL_FAILED_VERSION_DOWNGRADE"),
            ("INSTALL_FAILED_INSUFFICIENT_STORAGE", "INSTALL_FAILED_INSUFFICIENT_STORAGE"),
            ("INSTALL_FAILED_USER_RESTRICTED", "INSTALL_FAILED_USER_RESTRICTED"),
            ("not debuggable", "PACKAGE_NOT_DEBUGGABLE"),
            ("unknown package", "PACKAGE_UNKNOWN"),
            ("Permission denied", "PERMISSION_DENIED"),
            ("No such file or directory", "FILE_NOT_FOUND"),
            ("Bad mode", "STAT_FORMAT_REJECTED"),
            ("device offline", "ADB_DEVICE_OFFLINE")):
        if marker in text:
            return category
    return "OUTPUT_WITHHELD"


def parse_budget_database(path, run_id, expected_binding, remaining):
    """Read only the LAB's committed counters; never expose its private binding."""
    names = ("run_id", "transport_mode", "cloud_binding", "cloud_rows_reserved",
             "dispatch_attempts", "cloud_rows_written", "requests_started", "requests_acked")
    if (not path.is_file() or path.is_symlink() or not 0 < path.stat().st_size <= 4 * 1024 * 1024
            or type(remaining) is not int or not 1 <= remaining <= 500):
        raise TrialBlocked("BUDGET_DATABASE_UNAVAILABLE")
    connection = None
    try:
        connection = sqlite3.connect(path.resolve().as_uri() + "?mode=ro&immutable=1", uri=True)
        connection.execute("PRAGMA query_only=ON")
        if connection.execute("PRAGMA quick_check(1)").fetchall() != [("ok",)]:
            raise TrialBlocked("BUDGET_DATABASE_INVALID")
        rows = connection.execute("SELECT key,value FROM state WHERE key IN (" +
                                  ",".join("?" for _ in names) + ")", names).fetchall()
        values = dict(rows)
        if (len(rows) != len(names) or set(values) != set(names) or values["run_id"] != run_id
                or values["transport_mode"] != "posthog_cloud"
                or not isinstance(expected_binding, str) or not re.fullmatch(r"[a-f0-9]{64}", expected_binding)
                or values["cloud_binding"] != expected_binding):
            raise TrialBlocked("BUDGET_DATABASE_BINDING_OR_SCHEMA_INVALID")
        numeric = names[3:]
        if any(not isinstance(values[name], str) or not re.fullmatch(r"0|[1-9][0-9]{0,3}", values[name])
               for name in numeric):
            raise TrialBlocked("BUDGET_DATABASE_COUNTER_INVALID")
        counts = {name: int(values[name]) for name in numeric}
        reserved, attempts, written, requests, acked = (counts[name] for name in numeric)
        if not (0 <= written <= reserved <= remaining and 0 <= requests <= attempts <= reserved
                and 0 <= acked <= requests):
            raise TrialBlocked("BUDGET_DATABASE_COUNTER_INVALID")
        return {"status": "OBSERVED_COMMITTED_LAB_LEDGER", "reserved_rows": reserved,
                "reserved_attempts": attempts, "body_written_rows": written,
                "body_written_requests": requests, "acknowledged_requests": acked,
                "cloud_received_rows": None,
                "body_written_counter_limit": "MAY_UNDERCOUNT_INTERRUPTION_AFTER_WRITE_BEFORE_COUNTER",
                "automatic_refund_allowed": False}
    except sqlite3.Error:
        raise TrialBlocked("BUDGET_DATABASE_INVALID") from None
    finally:
        if connection is not None:
            connection.close()


def unknown_budget_receipt(run_id, source_commit, remaining=None, accounting=None):
    total = accounting["total_ceiling"] if accounting is not None else 500
    receipt = {"schema_version": 1, "observed_utc": now(), "run_id": run_id,
            "source_commit": source_commit, "status": "UNKNOWN_BLOCK_FUTURE_SENDS",
            "authorized_total_ceiling": total, "current_attempt_limit": remaining,
            "reserved_rows": None, "reserved_attempts": None, "body_written_rows": None,
            "body_written_requests": None, "acknowledged_requests": None, "cloud_received_rows": None,
            "conservative_consumed_for_future_launches": total, "remaining_for_future_launches": 0,
            "automatic_refund_allowed": False}
    if accounting is not None:
        receipt["authorization_accounting"] = dict(accounting)
    return receipt


class CloudDevice(Device):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.cleanup_required = False
        self.install_confirmed = False
        self.private_write_command_completed = False
        self.config_write_confirmed = False
        self.provision_confirmed = False
        self.shell_v2_confirmed = False
        self.shell_features_observation = None

    def _preparation_record(self, phase, output=None, category=None):
        if phase not in PREPARATION_PHASES:
            raise TrialBlocked("PREPARATION_PHASE_INVALID")
        code = output.returncode if output is not None else None
        row = {"schema_version": 1, "observed_utc": now(), "phase": phase,
               "returncode": code,
               "error_category": category or ("NONE" if code == 0 else sanitize_preparation_error(
                   output.stderr or output.stdout)),
               "stdout_present": bool(output is not None and output.stdout),
               "stderr_present": bool(output is not None and output.stderr)}
        validate_public_value(row)
        if not hasattr(self, "preparation_records"):
            self.preparation_records = []
        self.preparation_records.append(row)
        path = getattr(self, "preparation_path", None)
        if path is not None:
            with path.open("a") as stream:
                stream.write(json.dumps(row, allow_nan=False) + "\n")

    def prepare_call(self, phase, *args, timeout=45):
        if phase not in PREPARATION_PHASES:
            raise TrialBlocked("PREPARATION_PHASE_INVALID")
        try:
            output = self.call(*args, timeout=timeout, allow_failure=True)
        except TrialBlocked as failure:
            category = {"COMMAND_TIMEOUT": "TIMEOUT", "COMMAND_UNAVAILABLE": "UNAVAILABLE"}.get(
                str(failure), "COMMAND_BLOCKED")
            self._preparation_record(phase, category=category)
            raise TrialBlocked("CLOUD_" + phase + "_" + category) from None
        self._preparation_record(phase, output)
        if output.returncode:
            raise TrialBlocked("CLOUD_" + phase + "_NONZERO_EXIT")
        return output

    def install(self, apk):
        self.cleanup_required = True  # Includes partial installs; never success evidence.
        self.install_confirmed = False
        output = self.prepare_call("INSTALL_APK", "install", str(apk), timeout=120)
        if not re.search(r"^Success$", output.stdout, re.M):
            self._preparation_record("INSTALL_APK", output, "OUTPUT_REJECTED")
            raise TrialBlocked("CLOUD_INSTALL_APK_OUTPUT_REJECTED")
        installed = self.prepare_call("INSTALL_VERIFY", "shell", "pm", "path", PACKAGE)
        if not re.fullmatch(r"package:[^\r\n]+\n?", installed.stdout.strip()):
            self._preparation_record("INSTALL_VERIFY", installed, "OUTPUT_REJECTED")
            raise TrialBlocked("CLOUD_INSTALL_VERIFY_OUTPUT_REJECTED")
        self.install_confirmed = True

    def provision(self, private_bytes):
        self.private_write_command_completed = False
        self.config_write_confirmed = False
        self.provision_confirmed = False
        self.shell_v2_confirmed = False
        self.shell_features_observation = None
        if self.pid(absent_ok=True) is not None:
            raise TrialBlocked("PRIVATE_PROVISION_REQUIRES_STOPPED_LAB")
        self.prepare_call("PRIVATE_MKDIR", "shell", "run-as", PACKAGE, "mkdir", "-p", "files")
        features = self.prepare_call("PRIVATE_SHELL_FEATURES", "features")
        # The adb CLI prints one common feature per line, not its wire CSV format.
        lines = [line.strip() for line in features.stdout.splitlines() if line.strip()]
        self.shell_features_observation = {
            "output_format": "ONE_FEATURE_PER_LINE", "line_count": len(lines),
            "exact_shell_v2_count": lines.count("shell_v2"), "raw_output_published": False}
        if self.shell_features_observation["exact_shell_v2_count"] != 1:
            self._preparation_record("PRIVATE_SHELL_FEATURES", features, "OUTPUT_REJECTED")
            raise TrialBlocked("CLOUD_PRIVATE_SHELL_FEATURES_OUTPUT_REJECTED")
        self.shell_v2_confirmed = True
        # adb shell joins arguments for the remote shell: exactly one quoting layer.
        # Unlike exec-in, shell v2 waits for and reports the remote exit status.
        # -T disables terminal transformations; secret bytes remain stdin-only.
        argv = [self.adb, "-s", self.serial, "shell", "-T", "run-as", PACKAGE, "sh", "-c",
                "'umask 077; cat > files/cloud-config.private.json'"]
        try:
            output = subprocess.run([str(part) for part in argv], input=private_bytes,
                                    env=self.env, capture_output=True, timeout=15)
        except (OSError, subprocess.TimeoutExpired) as exc:
            category = "TIMEOUT" if isinstance(exc, subprocess.TimeoutExpired) else "UNAVAILABLE"
            self._preparation_record("PRIVATE_WRITE", category=category)
            raise TrialBlocked("CLOUD_PRIVATE_WRITE_" + category) from None
        self._preparation_record("PRIVATE_WRITE", output)
        if output.returncode:
            raise TrialBlocked("CLOUD_PRIVATE_WRITE_NONZERO_EXIT")
        if output.stdout or output.stderr:
            self._preparation_record("PRIVATE_WRITE", output, "OUTPUT_REJECTED")
            raise TrialBlocked("CLOUD_PRIVATE_WRITE_OUTPUT_REJECTED")
        self.private_write_command_completed = True
        checked = self.prepare_call("PRIVATE_STAT", "shell", "run-as", PACKAGE, "stat", "-c", "%a", "files/cloud-config.private.json")
        if checked.stdout.strip() != "600":
            self._preparation_record("PRIVATE_STAT", checked, "OUTPUT_REJECTED")
            raise TrialBlocked("CLOUD_PRIVATE_STAT_OUTPUT_REJECTED")
        copied = self.prepare_call("PRIVATE_VERIFY", "exec-out", "run-as", PACKAGE,
                                   "cat", "files/cloud-config.private.json")
        if copied.stdout.encode("utf-8") != private_bytes or copied.stderr:
            self._preparation_record("PRIVATE_VERIFY", copied, "OUTPUT_REJECTED")
            raise TrialBlocked("CLOUD_PRIVATE_VERIFY_OUTPUT_REJECTED")
        self.config_write_confirmed = True
        self.provision_confirmed = True

    def recover_budget(self, work, private_bytes, run_id, remaining):
        """Never starts the app or changes its database; temporary copy is private."""
        if self.pid(absent_ok=True) is not None:
            raise TrialBlocked("BUDGET_RECOVERY_REQUIRES_STOPPED_LAB")
        journal = self.call("shell", "run-as", PACKAGE, "test", "-e",
                            "databases/synthetic_telemetry.db-journal", allow_failure=True)
        if journal.returncode != 1 or journal.stdout or journal.stderr:
            raise TrialBlocked("BUDGET_RECOVERY_JOURNAL_OR_ABSENCE_UNATTESTED")
        try:
            output = subprocess.run([str(self.adb), "-s", self.serial, "exec-out", "run-as", PACKAGE,
                                     "cat", "databases/synthetic_telemetry.db"],
                                    env=self.env, capture_output=True, timeout=15)
        except (OSError, subprocess.TimeoutExpired):
            raise TrialBlocked("BUDGET_RECOVERY_READ_FAILED") from None
        if output.returncode or output.stderr or not 0 < len(output.stdout) <= 4 * 1024 * 1024:
            raise TrialBlocked("BUDGET_RECOVERY_READ_FAILED")
        path = work / "budget-snapshot.private.sqlite"
        path.write_bytes(output.stdout)
        path.chmod(0o600)
        config = json.loads(private_bytes)
        binding = hashlib.sha256((config["endpoint"] + "\n" + config["api_key"] + "\n" +
                                  config["run_id"] + "\n" + str(config["row_limit"])).encode()).hexdigest()
        return parse_budget_database(path, run_id, binding, remaining)

    def connectivity(self, state, online):
        value = state.get("connectivity", {})
        if (not isinstance(value, dict) or set(value) != NETWORK_KEYS or value.get("probe_available") is not True or
                any(type(value.get(k)) is not bool for k in NETWORK_KEYS - {"transports"}) or
                not isinstance(value["transports"], list) or
                any(v not in {"wifi", "cellular", "ethernet", "vpn", "other"} for v in value["transports"])):
            raise TrialBlocked("ANDROID_CONNECTIVITY_PROBE_UNAVAILABLE")
        if online:
            return value["active_network"] and value["internet_capable"] and value["validated"]
        return not value["active_network"] and not value["internet_capable"] and not value["validated"] and not value["transports"]

    def network(self, online):
        self.call("shell", "cmd", "connectivity", "airplane-mode", "disable" if online else "enable")
        self.call("shell", "svc", "wifi", "enable" if online else "disable")
        self.call("shell", "svc", "data", "enable" if online else "disable")
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            state = self.command("state")
            if online:
                cloud_drain_complete(state)
            if self.connectivity(state, online):
                row = {"online_requested": online, "connectivity": state["connectivity"],
                       "pid": state["pid"], "action_nonce": state["action_nonce"],
                       "cloud_rows_reserved": state.get("cloud_rows_reserved"),
                       "requests_started": state["requests_started"]}
                with (self.directory / "network.jsonl").open("a") as output:
                    output.write(json.dumps(row) + "\n")
                return state
            time.sleep(0.5)
        raise TrialBlocked("ANDROID_CONNECTIVITY_TRANSITION_NOT_ATTESTED")

    def private_rows(self, filename):
        result = self.call("shell", "run-as", PACKAGE, "cat", "files/" + filename, allow_failure=True)
        if result.returncode or len(result.stdout) > 2 * 1024 * 1024:
            raise TrialBlocked("NATIVE_CLOUD_RECEIPTS_UNAVAILABLE_OR_TOO_LARGE")
        return [json.loads(line) for line in result.stdout.splitlines() if line]


PERMANENT_BLOCK_CATEGORIES = {"QUOTA_LIMITED", "UNRECOGNIZED_RESPONSE", "MALFORMED_RESPONSE",
    "RESPONSE_TOO_LARGE", "RESPONSE_READ_FAILED", "HTTP_REJECTED", "AUDIT_WRITE_FAILED", "ROW_BUDGET"}


def cloud_drain_complete(state):
    """A fresh permanent block wins even when the queue appears empty."""
    flags = [state.get(key) for key in ("cloud_transport_blocked", "cloud_budget_blocked")]
    if any(type(value) is not int or value not in (0, 1) for value in flags):
        raise TrialBlocked("CLOUD_BLOCK_STATE_INVALID")
    if any(flags):
        raw = state.get("cloud_block_reason")
        category = raw if type(raw) is str and raw in PERMANENT_BLOCK_CATEGORIES else "UNKNOWN"
        raise TrialBlocked("CLOUD_PERMANENT_BLOCK_" + category)
    return state["queue_count"] == 0 and state["in_flight_count"] == 0


def run_cases(device, work, run_id, remaining):
    findings, failures = {}, []
    device.directory, device.run_id = work, run_id
    for name in ("states.jsonl", "lifecycle.jsonl", "network.jsonl"):
        (work / name).write_text("")
    baseline = device.command("configure", run_id=run_id, capacity=1000)
    if baseline.get("transport_mode") != "posthog_cloud_https" or baseline.get("cloud_row_limit") != remaining or baseline.get("cloud_rows_reserved") != 0:
        raise TrialBlocked("FRESH_BOUND_CLOUD_LEDGER_NOT_ATTESTED")
    if baseline["consent"] is not False or baseline["queue_count"] != 0:
        raise TrialBlocked("INITIAL_CLOUD_DENY_NOT_ATTESTED")
    precheck = device.command("preflight_checks")
    if precheck.get("preflight_checks") != dict.fromkeys(SELF_CHECKS, True):
        raise TrialBlocked("NATIVE_PREFLIGHT_COUNTEREXAMPLES_FAILED")
    def check(condition, reason):
        if not condition:
            failures.append(reason)
            # Never re-enable the cloud path after an unverified offline/deny,
            # restart, sentinel or transport boundary. Partial receipts survive.
            raise TrialBlocked(reason)
    def sentinels(state):
        check(all(state[key] == baseline[key] for key in ("trace_sha256", "setting_value")), "SENTINELS_CHANGED")
    def offline_window(state):
        end, _ = device.observe(12)
        check(device.connectivity(end, False) and end["cloud_rows_reserved"] == state["cloud_rows_reserved"] and
              end["requests_started"] == state["requests_started"], "OFFLINE_ATTEMPT_OR_CONNECTIVITY_VIOLATION")
        return end
    def drain():
        cloud_drain_complete(device.command("state"))
        cloud_drain_complete(device.network(True))
        cloud_drain_complete(device.command("flush"))
        end, completed = device.observe(120, cloud_drain_complete)
        check(completed, "HTTP_TRANSPORT_DRAIN_WINDOW_EXPIRED")
        sentinels(end)
        return end

    offline = device.network(False)
    device.command("grant")
    state = device.command("capture", start=1, count=100)
    check(state["queue_count"] == 100, "NORMAL_OFFLINE_QUEUE_NOT_HUNDRED")
    offline_window(offline)
    state = device.restart()
    check(device.connectivity(state, False) and state["queue_count"] == 100 and state["consent"] is True,
          "NORMAL_OFFLINE_RESTART_NOT_ATTESTED")
    sentinels(state)
    findings["normal"] = {"transport_state": drain(), "expected_ids": [event(run_id, n)["event_id"] for n in range(1, 101)]}

    offline = device.network(False)
    state = device.command("capture", start=101, count=20)
    check(state["queue_count"] == 20, "REVOKE_OFFLINE_QUEUE_NOT_TWENTY")
    offline_window(offline)
    state = device.command("revoke")
    check(state["consent"] is False and state["queue_count"] == 0 and state["revoked_count"] == 20,
          "REVOKE_DURABLE_DENY_PURGE_NOT_ATTESTED")
    state = device.restart()
    check(device.connectivity(state, False) and state["consent"] is False and state["queue_count"] == 0,
          "REVOKE_RESTART_DENY_NOT_ATTESTED")
    sentinels(state)
    device.command("grant")
    device.command("capture", start=121, count=10)
    findings["revoke"] = {"transport_state": drain(), "revoked_ids": [event(run_id, n)["event_id"] for n in range(101, 121)],
                          "new_ids": [event(run_id, n)["event_id"] for n in range(121, 131)]}

    device.network(False)
    device.command("arm_retry", start=131, count=10)
    device.command("capture", start=131, count=10)
    findings["retry"] = {"transport_state": drain(), "mode": "ONE_HTTP200_DELIBERATELY_IGNORED_NOT_A_NETWORK_ACK_LOSS"}
    final, _ = device.observe(12)
    sentinels(final)
    # No additional capture, clearing, reinstallation or budget reset follows.
    device.command("revoke")
    final = device.command("state")
    return findings, failures, final


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("sdk", "jdk", "apk", "build-receipt", "runtime-gate", "cloud-gate", "private-config", "out"):
        parser.add_argument("--" + name, type=Path, required=True)
    for name in ("source-commit", "run-id", "serial", "execution-id"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--run-attempt", type=int, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    result = {"schema_version": 1, "scope": "DIRECT_CLOUD_SYNTHETIC_POSTHOG", "project_id": PROJECT,
              "source_commit": args.source_commit, "run_id": args.run_id, "execution_id": args.execution_id,
              "started_utc": now(), "status": "BLOCKED", "cloud_receipt": "PENDING_READBACK",
              "limits": ["NO_REAL_USERS_NO_CONVOY_INTEGRATION", "HTTP_STATUS_IS_NOT_RECEIPT",
                         "PRECOMMIT_REVOCATION_UNACKNOWLEDGED_REQUESTS_ALREADY_STARTED_NOT_RECALLABLE",
                         "EMULATOR_CONNECTIVITY_NOT_PHYSICAL_RADIO_BATTERY_PROOF"]}
    device, cleanup_required, provisioned, radios, remaining, accounting = None, False, False, None, None, None
    budget_recovery = unknown_budget_receipt(args.run_id, args.source_commit)
    public_write(args.out / "budget-recovery.json", budget_recovery)
    result["budget_recovery_ref"] = "budget-recovery.json"
    with tempfile.TemporaryDirectory(prefix="convoy-cloud-private-") as temporary:
        work = Path(temporary)
        try:
            gate = json.loads(args.cloud_gate.read_text())
            remaining = validate_cloud_gate(gate, args.source_commit, args.run_id, args.execution_id, args.run_attempt)
            accounting = budget_accounting(gate)
            result["budget"] = dict(accounting, reserved_rows=None, unattested_consume_full_remaining=True)
            # Once the one-use gate has been accepted, even an immediate failure
            # preserves the complete cumulative reservation before any ADB call.
            public_write(args.out / "budget-recovery.json", unknown_budget_receipt(
                args.run_id, args.source_commit, remaining, accounting))
            if os.environ.get("GITHUB_RUN_ATTEMPT", "1") != "1":
                raise TrialBlocked("CLOUD_AUTOMATIC_RERUN_REFUSED")
            private_bytes = read_private_config(args.private_config, args.run_id, remaining)
            validate_serial(args.serial)
            env = dict(os.environ, JAVA_HOME=str(args.jdk), ANDROID_SERIAL=args.serial)
            for secret_name in ("CONVOY_LAB_POSTHOG_TOKEN", "CONVOY_CLOUD_GATE"):
                env.pop(secret_name, None)
            env["PATH"] = str(args.jdk / "bin") + os.pathsep + env.get("PATH", "")
            runtime = json.loads(args.runtime_gate.read_text())
            device = CloudDevice(args.sdk, args.serial, env, runtime)
            device.preparation_path = args.out / "preparation.jsonl"
            device.check_gate()
            public_write(args.out / "cloud-gate-reference.json", {
                "sha256": sha256(args.cloud_gate), "status": "PASS", "project_id": PROJECT, "host": HOST,
                "path": "/batch/", "execution_id": args.execution_id, "run_attempt": 1,
                "remaining_budget": remaining, "total_ceiling": accounting["total_ceiling"],
                "authorization_accounting": accounting,
                "controls": {key: {"status": gate[key]["status"], "checked_at_utc": gate[key]["checked_at_utc"],
                                   "evidence_reference_sha256": hashlib.sha256(gate[key]["evidence_ref"].encode()).hexdigest()}
                             for key in required_controls(gate)}})
            public_write(args.out / "runtime-gate-reference.json", {"sha256": sha256(args.runtime_gate),
                         "serial": args.serial, "boot_id": runtime["boot_id"], "status": runtime["status"]})
            public_write(args.out / "apk-receipt.json", verify_apk(args, env))
            if "package:" in device.call("shell", "pm", "path", PACKAGE, allow_failure=True).stdout:
                raise TrialBlocked("CLOUD_REQUIRES_FRESH_LAB_INSTALL_NOT_CLEARED_CLOUD_LEDGER")
            initial_radios = {}
            for key in ("airplane_mode_on", "wifi_on", "mobile_data"):
                value = device.call("shell", "settings", "get", "global", key).stdout.strip()
                if value not in ("0", "1"):
                    raise TrialBlocked("INITIAL_RADIO_SETTING_NOT_ATTESTED")
                initial_radios[key] = value == "1"
            radios = initial_radios
            cleanup_required = True
            device.install(args.apk.resolve())
            device.provision(private_bytes)
            provisioned = True
            del private_bytes
            expected = [event(args.run_id, n) for n in (*range(1, 101), *range(121, 141))]
            write_rows(args.out / "expected.jsonl", expected)
            write_rows(args.out / "revoked-intent.jsonl", [event(args.run_id, n) for n in range(101, 121)])
            phases, failures, final = run_cases(device, work, args.run_id, remaining)
            result.update(phases=phases, final_state=final)
            device.stop()
            preflight, preflight_errors = sanitize_preflight(device.private_rows("cloud-preflight.jsonl"), args.run_id)
            transport = device.private_rows("cloud-transport.jsonl")
            for row in transport:
                validate_public_value(row)
            write_rows(args.out / "preflight.jsonl", preflight)
            write_rows(args.out / "transport.jsonl", transport)
            finding = summarize_transport(preflight, transport, args.run_id, remaining, final, accounting)
            finding["failures"] = sorted(set(finding["failures"] + failures + preflight_errors))
            result.update(finding)
            result["status"] = "FAILED" if finding["failures"] else "TRANSPORT_COMPLETE_READBACK_PENDING"
        except (TrialBlocked, OSError, ValueError, TypeError, KeyError) as exc:
            result["status"] = "BLOCKED"
            result["blocked_reason"] = str(exc) if isinstance(exc, TrialBlocked) else "CLOUD_HARNESS_INPUT_OR_IO_FAILURE"
        finally:
            cleanup = {"cleanup_required": cleanup_required,
                       "installation_confirmed": bool(device and getattr(device, "install_confirmed", False)),
                       "private_write_command_completed": bool(device and getattr(device, "private_write_command_completed", False)),
                       "configuration_write_confirmed": bool(device and getattr(device, "config_write_confirmed", False)),
                       "provisioned": provisioned, "lab_stopped": False,
                       "private_config_removed": False, "initial_radio_settings_restored": False}
            if cleanup_required and device is not None:
                try:
                    device.stop()
                    cleanup["lab_stopped"] = True
                    if provisioned:
                        try:
                            snapshot = device.json_file("state.json")
                            if isinstance(snapshot, dict):
                                validate_public_value(snapshot)
                                result["last_persisted_state"] = snapshot
                                result["last_state_is_snapshot_not_budget_refund_authority"] = True
                        except (TrialBlocked, OSError, ValueError, TypeError, KeyError):
                            result["last_snapshot_status"] = "UNAVAILABLE_OR_UNSAFE_NO_BUDGET_REFUND"
                    device.prepare_call("PRIVATE_REMOVE", "shell", "run-as", PACKAGE,
                                        "rm", "-f", "files/cloud-config.private.json")
                    device.prepare_call("PRIVATE_REMOVE_VERIFY", "shell", "run-as", PACKAGE,
                                        "test", "!", "-e", "files/cloud-config.private.json")
                    cleanup["private_config_removed"] = True
                except (TrialBlocked, OSError, ValueError, TypeError, KeyError):
                    result["status"] = "BLOCKED"
                    result["cleanup_error"] = "CLOUD_PRIVATE_CLEANUP_NOT_ATTESTED"
            # Always keep a receipt, including an install/stat failure before provisioned=true.
            # Missing/unreadable counters remain unknown. No local observation authorizes a refund.
            budget_recovery = unknown_budget_receipt(args.run_id, args.source_commit, remaining, accounting)
            if cleanup_required and device is not None and cleanup["lab_stopped"] and remaining is not None:
                try:
                    observed = device.recover_budget(work,
                        read_private_config(args.private_config, args.run_id, remaining), args.run_id, remaining)
                    budget_recovery.update(observed)
                    budget_recovery["observed_utc"] = now()
                except (TrialBlocked, OSError, ValueError, TypeError, KeyError):
                    budget_recovery["recovery_observation"] = "LEDGER_UNAVAILABLE_OR_UNBOUND_NO_REFUND"
                # Recovery of partial receipts is independent of the provision success flag.
                try:
                    if not (args.out / "preflight.jsonl").exists():
                        partial, _ = sanitize_preflight(device.private_rows("cloud-preflight.jsonl"), args.run_id)
                        write_rows(args.out / "preflight.jsonl", partial)
                    if not (args.out / "transport.jsonl").exists():
                        rows = device.private_rows("cloud-transport.jsonl")
                        for row in rows:
                            validate_public_value(row)
                        write_rows(args.out / "transport.jsonl", rows)
                except (TrialBlocked, OSError, ValueError, TypeError, KeyError):
                    budget_recovery["partial_transport_receipts"] = "UNAVAILABLE_OR_INCOMPLETE"
            public_write(args.out / "budget-recovery.json", budget_recovery)
            if device is not None and radios is not None and (not cleanup_required or
                    (cleanup["lab_stopped"] and cleanup["private_config_removed"])):
                try:
                    device.call("shell", "cmd", "connectivity", "airplane-mode", "enable" if radios["airplane_mode_on"] else "disable")
                    device.call("shell", "svc", "wifi", "enable" if radios["wifi_on"] else "disable")
                    device.call("shell", "svc", "data", "enable" if radios["mobile_data"] else "disable")
                    cleanup["initial_radio_settings_restored"] = all(device.call("shell", "settings", "get", "global", key).stdout.strip() == str(int(value))
                                                                    for key, value in radios.items())
                    if not cleanup["initial_radio_settings_restored"]:
                        raise TrialBlocked("RADIO_RESTORE_FAILED")
                except (TrialBlocked, OSError, ValueError, TypeError, KeyError):
                    result["status"] = "BLOCKED"
                    result["radio_cleanup_error"] = "INITIAL_RADIOS_NOT_RESTORED"
            elif device is not None and cleanup_required and (
                    not cleanup["lab_stopped"] or not cleanup["private_config_removed"]):
                try:
                    for parts in (("cmd", "connectivity", "airplane-mode", "enable"), ("svc", "wifi", "disable"), ("svc", "data", "disable")):
                        device.call("shell", *parts, allow_failure=True)
                except (TrialBlocked, OSError, ValueError, TypeError, KeyError):
                    result["offline_cleanup_error"] = "OFFLINE_FALLBACK_NOT_ATTESTED"
                result["radio_cleanup_error"] = "LEFT_OFFLINE_BECAUSE_STOP_OR_PRIVATE_CLEANUP_UNATTESTED"
            try:
                for name in ("states.jsonl", "lifecycle.jsonl", "network.jsonl"):
                    path = work / name
                    if path.exists():
                        write_rows(args.out / name, load_rows(path))
            except (TrialBlocked, OSError, ValueError, TypeError, KeyError):
                result["status"] = "BLOCKED"
                result["public_export_error"] = "CLOUD_STATE_EXPORT_INCOMPLETE_OR_UNSAFE"
            result["cleanup"], result["finished_utc"] = cleanup, now()
            result["shell_v2_confirmed"] = bool(device and getattr(device, "shell_v2_confirmed", False))
            result["shell_features_observation"] = getattr(device, "shell_features_observation", None)
            public_write(args.out / "result.json", result)
            try:
                audit_public_directory(args.out)
            except (TrialBlocked, OSError, ValueError, TypeError):
                result["status"] = "BLOCKED"
                result["public_export_error"] = "CLOUD_PUBLIC_TREE_REJECTED"
                public_write(args.out / "result.json", result)
    print(json.dumps({"status": result["status"], "cloud_receipt": "PENDING_READBACK",
                      "budget": result.get("budget"), "blocked_reason": result.get("blocked_reason")}))
    return 0 if result["status"] == "TRANSPORT_COMPLETE_READBACK_PENDING" else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (TrialBlocked, OSError, ValueError, TypeError, KeyError):
        print(json.dumps({"status": "BLOCKED", "reason": "CLOUD_HARNESS_FINALIZATION_FAILED"}))
        raise SystemExit(1)
