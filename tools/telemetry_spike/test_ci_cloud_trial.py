"""Host-only cloud gating, private provisioning input and receipt regressions."""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import stat
import tempfile
import unittest
import uuid

from ci_cloud_trial import (CloudDevice, ENDPOINT, HOST, TrialBlocked, read_private_config,
                            sanitize_preflight, summarize_transport, validate_cloud_gate,
                            validate_public_value)
from prepare_ci_cloud import prepare
from probe import event


class CloudGates(unittest.TestCase):
    source = "a" * 40
    run_id = "synthetic-cloud-host"
    execution = "Isolated Android telemetry laboratory:42"
    clock = datetime(2026, 11, 3, 12, tzinfo=timezone.utc)

    def gate(self):
        value = {"schema_version": 1, "status": "PASS", "project_id": 330212,
                 "api_host": "https://" + HOST, "source_commit": self.source, "run_id": self.run_id,
                 "execution_id": self.execution, "run_attempt": 1, "quota_rows_available": 999838,
                 "total_ceiling": 500, "remaining_budget": 500,
                 "expires_utc": (self.clock + timedelta(hours=1)).isoformat()}
        for name in ("privacy", "retention", "deletion", "quota", "local_regression"):
            value[name] = {"status": "VERIFIED", "checked_at_utc": self.clock.isoformat(),
                           "evidence_ref": "synthetic-host-fixture"}
        value["privacy"].update(anonymize_ips=True, session_recording_opt_in=False)
        value["quota"]["free_plan"] = True
        value["local_regression"]["source_commit"] = self.source
        return value

    def validate(self, value):
        return validate_cloud_gate(value, self.source, self.run_id, self.execution, 1, self.clock)

    def test_all_controls_are_required_before_any_execution(self):
        self.assertEqual(self.validate(self.gate()), 500)
        for name in ("privacy", "retention", "deletion", "quota", "local_regression"):
            value = self.gate(); value[name]["status"] = "PENDING"
            with self.subTest(name=name), self.assertRaises(TrialBlocked):
                self.validate(value)

    def test_wrong_commit_destination_run_or_repeated_execution_is_blocked(self):
        for change in ({"source_commit": "b" * 40}, {"api_host": "https://example.invalid"},
                       {"run_id": "synthetic-other"}, {"execution_id": self.execution + "2"},
                       {"run_attempt": 2}, {"run_attempt": True}, {"schema_version": True}, {"status": "BLOCKED"}):
            with self.subTest(change=change), self.assertRaises(TrialBlocked):
                self.validate(dict(self.gate(), **change))

    def test_global_budget_and_free_quota_are_not_replaced_by_http_success(self):
        for change in ({"remaining_budget": 501}, {"remaining_budget": 129}, {"remaining_budget": True},
                       {"quota_rows_available": 499}, {"total_ceiling": 501}):
            with self.subTest(change=change), self.assertRaises(TrialBlocked):
                self.validate(dict(self.gate(), **change))
        value = self.gate(); value["quota"]["free_plan"] = False
        with self.assertRaises(TrialBlocked): self.validate(value)

    def test_stale_and_expired_evidence_is_blocked(self):
        value = self.gate(); value["expires_utc"] = self.clock.isoformat()
        with self.assertRaises(TrialBlocked): self.validate(value)
        value = self.gate(); value["privacy"]["checked_at_utc"] = (self.clock - timedelta(days=2)).isoformat()
        with self.assertRaises(TrialBlocked): self.validate(value)
        value = self.gate(); value["expires_utc"] = "2026-11-03T13:00:00"
        with self.assertRaises(TrialBlocked): self.validate(value)

    def environment(self):
        return {"CONVOY_CLOUD_GATE": json.dumps(self.gate()), "CONVOY_LAB_POSTHOG_TOKEN": "phc_" + "hostfixture" * 4,
                "GITHUB_WORKFLOW": "Isolated Android telemetry laboratory", "GITHUB_RUN_NUMBER": "42",
                "GITHUB_RUN_ATTEMPT": "1"}

    def test_prepare_creates_private_files_and_never_returns_credential(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "cloud-private"
            environment = self.environment()
            result = prepare(out, environment, self.source, self.clock)
            self.assertEqual(stat.S_IMODE(out.stat().st_mode), 0o700)
            for name in ("gate.json", "config.json"):
                self.assertEqual(stat.S_IMODE((out / name).stat().st_mode), 0o600)
            config = json.loads(read_private_config(out / "config.json", self.run_id, 500))
            self.assertEqual(config["endpoint"], ENDPOINT)
            self.assertNotIn(environment["CONVOY_LAB_POSTHOG_TOKEN"], json.dumps(result))
            validate_public_value(result)

    def test_pending_deletion_never_creates_private_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            environment = self.environment()
            gate = self.gate(); gate["deletion"]["status"] = "PENDING"
            environment["CONVOY_CLOUD_GATE"] = json.dumps(gate)
            out = Path(tmp) / "cloud-private"
            with self.assertRaises(TrialBlocked): prepare(out, environment, self.source, self.clock)
            self.assertFalse(out.exists())

    def test_read_private_config_rejects_public_permissions_and_wrong_host(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "cloud-private"
            prepare(out, self.environment(), self.source, self.clock)
            path = out / "config.json"
            path.chmod(0o644)
            with self.assertRaises(TrialBlocked): read_private_config(path, self.run_id, 500)
            path.chmod(0o600)
            value = json.loads(path.read_text()); value["endpoint"] = "https://example.invalid/batch/"
            path.write_text(json.dumps(value))
            with self.assertRaises(TrialBlocked): read_private_config(path, self.run_id, 500)

    def test_airplane_intent_alone_is_not_proof_without_no_active_network(self):
        device = CloudDevice.__new__(CloudDevice)
        offline = {"connectivity": {"probe_available": True, "active_network": False,
                   "internet_capable": False, "validated": False, "transports": []}}
        self.assertTrue(device.connectivity(offline, False))
        active = deepcopy(offline)
        active["connectivity"].update(active_network=True, internet_capable=True, validated=True, transports=["ethernet"])
        self.assertFalse(device.connectivity(active, False))
        self.assertTrue(device.connectivity(active, True))
        active["connectivity"]["probe_available"] = False
        with self.assertRaises(TrialBlocked): device.connectivity(active, False)


class CloudTransportEvidence(unittest.TestCase):
    run_id = "synthetic-cloud-host"

    def fixtures(self):
        preflight, transport, reserved = [], [], 0
        groups = [range(n, n + 20) for n in range(1, 101, 20)] + [range(121, 131), range(131, 141), range(131, 141)]
        for attempt, group in enumerate(groups, 1):
            batch = [{"event": "cm_lab_probe", "distinct_id": self.run_id,
                      "uuid": str(uuid.uuid5(uuid.NAMESPACE_OID, str(n))), "timestamp": "2026-11-03T12:00:00.000Z",
                      "properties": dict(event(self.run_id, n), **{"$geoip_disable": True, "$process_person_profile": False})}
                     for n in group]
            reserved += len(batch)
            base = {"attempt_id": attempt, "rows": len(batch), "budget_reserved_rows": reserved}
            preflight.append(dict(base, body_bytes=100, payload={"api_key": "<redacted:project-token>", "batch": batch}))
            identity = dict(base, event_ids=[item["properties"]["event_id"] for item in batch], uuids=[item["uuid"] for item in batch])
            for phase in ("reserved", "body_written", "response", "finished"):
                receipt = dict(identity, phase=phase)
                if phase == "response": receipt.update(response_code=200, response_accepted=True, quota_limited=False)
                if phase in ("response", "finished"): receipt["ack_discarded"] = attempt == 7
                if phase == "finished": receipt.update(response_code=200, body_written=True, acknowledged=attempt != 7)
                transport.append(receipt)
        public, violations = sanitize_preflight(preflight, self.run_id)
        self.assertFalse(violations)
        final = {"cloud_rows_reserved": 130, "cloud_row_limit": 500, "queue_count": 0, "in_flight_count": 0,
                 "cloud_budget_blocked": 0, "cloud_transport_blocked": 0, "cloud_audit_failures": 0,
                 "retry_ack_discarded": 1, "cloud_rows_written": 130}
        return public, transport, final

    def test_http200_is_only_transport_and_retry_finished_is_not_counted_twice(self):
        preflight, transport, final = self.fixtures()
        result = summarize_transport(preflight, transport, self.run_id, 500, final)
        self.assertFalse(result["failures"])
        self.assertTrue(result["http_status_is_not_cloud_receipt"])
        self.assertNotIn("PASSED", json.dumps(result))
        self.assertEqual(result["http200_deliberately_ignored"], 1)
        self.assertEqual(result["body_written_rows"], 130)
        self.assertEqual(result["unique_body_written_ids"], 120)

    def test_cloud_receipt_redaction_keeps_event_fields_without_fake_credential_claim(self):
        preflight, _, _ = self.fixtures()
        for row in preflight:
            self.assertTrue(row["credential_redacted"])
            self.assertEqual(row["envelope_keys"], ["api_key", "batch"])
            self.assertNotIn("api_key", row["payload"])
            validate_public_value(row)

    def test_unknown_metadata_values_are_redacted_and_failing(self):
        private = {"attempt_id": 1, "rows": 1, "budget_reserved_rows": 1, "body_bytes": 100,
                   "payload": {"api_key": "<redacted:project-token>", "batch": [{
                       "event": "cm_lab_probe", "distinct_id": self.run_id, "uuid": str(uuid.uuid4()),
                       "timestamp": "2026-11-03T12:00:00Z", "properties": dict(event(self.run_id, 1), **{
                           "$geoip_disable": True, "$process_person_profile": False, "device_model": "do-not-publish"})}]}}
        public, errors = sanitize_preflight([private], self.run_id)
        self.assertTrue(errors)
        self.assertNotIn("do-not-publish", json.dumps(public))
        private["payload"]["api_key"] = "phc_" + "secret" * 10
        with self.assertRaises(TrialBlocked): sanitize_preflight([private], self.run_id)

    def test_retry_changed_uuid_or_reservation_refund_fails(self):
        preflight, transport, final = self.fixtures()
        preflight[-1]["payload"]["batch"][0]["uuid"] = str(uuid.uuid4())
        result = summarize_transport(preflight, transport, self.run_id, 500, final)
        self.assertIn("ONE_HTTP200_IGNORED_SAME_UUID_RETRY_NOT_ATTESTED", result["failures"])
        preflight, transport, final = self.fixtures()
        final["cloud_rows_reserved"] = 120
        self.assertIn("GLOBAL_BUDGET_OR_FINAL_QUEUE_NOT_ATTESTED",
                      summarize_transport(preflight, transport, self.run_id, 500, final)["failures"])

    def test_unknown_writes_budget_overrun_and_quota_limited200_fail(self):
        preflight, transport, final = self.fixtures()
        transport.append(dict(transport[0], attempt_id=999, phase="body_written"))
        self.assertIn("TRANSPORT_WITHOUT_DURABLE_RESERVATION",
                      summarize_transport(preflight, transport, self.run_id, 500, final)["failures"])
        preflight, transport, final = self.fixtures()
        transport[2].update(response_code=200, quota_limited=True, response_accepted=False)
        self.assertIn("CLOUD_HTTP_RESPONSE_NOT_ACCEPTED",
                      summarize_transport(preflight, transport, self.run_id, 500, final)["failures"])
        self.assertIn("GLOBAL_BUDGET_OR_FINAL_QUEUE_NOT_ATTESTED",
                      summarize_transport(preflight, transport, self.run_id, 120, final)["failures"])

    def test_missing_ack_or_finished_rows_cannot_be_transport_complete(self):
        preflight, transport, final = self.fixtures()
        for removed in (2, 3):
            shortened = transport[:removed] + transport[removed + 1:]
            finding = summarize_transport(preflight, shortened, self.run_id, 500, final)
            self.assertTrue(finding["failures"])
        transport[3]["acknowledged"] = False
        self.assertIn("HTTP_RESPONSE_AND_FINISHED_RECEIPTS_INCONSISTENT",
                      summarize_transport(preflight, transport, self.run_id, 500, final)["failures"])

    def test_unknown_response_zero_attempt_keeps_budget_after_successful_recovery(self):
        preflight, transport, final = self.fixtures()
        failed_preflight = deepcopy(preflight[0])
        failed_reserved = deepcopy(transport[0])
        failed_finished = dict(failed_reserved, phase="finished", response_code=0,
                               body_written=False, acknowledged=False, ack_discarded=False)
        for row in preflight + transport:
            row["attempt_id"] += 1
            row["budget_reserved_rows"] += 20
        preflight.insert(0, failed_preflight)
        transport[:0] = [failed_reserved, failed_finished]
        final["cloud_rows_reserved"] = 150
        finding = summarize_transport(preflight, transport, self.run_id, 500, final)
        self.assertFalse(finding["failures"])
        self.assertEqual(finding["budget"]["reserved_rows"], 150)
        self.assertEqual(finding["body_written_rows"], 130)


if __name__ == "__main__":
    unittest.main()
