"""Host evidence guards and local HTTP fault tests; never Android/sender proof."""
import http.client
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
import uuid

from ci_direct_trial import (DirectReceiver, HeldAckReceiver, PHASES, SELF_CHECKS, STATE_COUNTS,
                             TrialBlocked, WIRE_SCOPE, audit_public_directory, classify_phase,
                             export_evidence, final_reconciliation, overall_status,
                             validate_checkpoint, validate_state, valid_sdk_bounds, write_rows)
from probe import event
from wire_audit_receiver import TOKEN, audit_payload


class EvidenceGuards(unittest.TestCase):
    run_id = "synthetic-direct-host-test"

    def rows(self, start, count):
        return [event(self.run_id, n) for n in range(start, start + count)]

    def validation(self, **changes):
        value = {"observed_failures": [], "preflight_checks": dict.fromkeys(SELF_CHECKS, True),
                 "requests_before_grant": 0, "sentinels_unchanged": True,
                 "receiver_closed_after_process_stop": True,
                 "final_state": {"queue_count": 0, "in_flight_count": 0, "preflight_rejected": 0,
                                 "dropped_count": 0, "revoked_count": 20, "consent": True}}
        value.update(changes)
        return value

    def requests(self, rows, *, uuid_salt="", lost_ack=False):
        return [{"violations": [], "wire_body_bytes": 100,
                 "response_mode": "close_without_response_after_fsync" if lost_ack else "http_response",
                 "events": [{"event_id": row["event_id"], "uuid": str(uuid.uuid5(uuid.NAMESPACE_OID,
                                                                                  row["event_id"] + uuid_salt))}
                            for row in rows]}]

    def classify(self, phase, expected, actual=None, revoked=None, validation=None, requests=None):
        actual = expected if actual is None else actual
        return classify_phase(phase, expected, revoked or [], actual,
                              self.requests(actual) if requests is None else requests,
                              self.validation() if validation is None else validation)

    def test_normal_requires_exact_hundred_and_detects_duplicate_substitution(self):
        expected = self.rows(1, 100)
        self.assertEqual(self.classify("normal", expected)["status"], "PASSED")
        result = self.classify("normal", expected, expected[:-1] + expected[:1])
        self.assertEqual(result["status"], "FAILED")
        self.assertEqual(result["missing_ids"], [expected[-1]["event_id"]])
        self.assertEqual(result["duplicate_rows"], 1)
        self.assertIn("ORACLE_COHORT_INVALID", self.classify("normal", expected[:10])["failures"])

    def test_twenty_revoked_cannot_be_replaced_by_ten_new_successes(self):
        expected, revoked = self.rows(21, 10), self.rows(1, 20)
        self.assertEqual(self.classify("revoke", expected, revoked=revoked)["status"], "PASSED")
        result = self.classify("revoke", expected, actual=expected + revoked, revoked=revoked)
        self.assertEqual(result["status"], "FAILED")
        self.assertEqual(result["revoked_ids_reappeared"], [row["event_id"] for row in revoked])
        self.assertIn("ORACLE_COHORT_INVALID", self.classify("revoke", expected, revoked=revoked[:-1])["failures"])

    def test_crash_requires_durable_checkpoint_and_online_denied_window(self):
        expected, revoked = self.rows(21, 10), self.rows(1, 20)
        validation = self.validation(checkpoint_attested="during_purge", revocation_durable=True,
                                     restart_denied=True, pregrant_request_count=0)
        self.assertEqual(self.classify("crash-during-purge", expected, revoked=revoked,
                                       validation=validation)["status"], "PASSED")
        validation["revocation_durable"] = False
        self.assertEqual(self.classify("crash-during-purge", expected, revoked=revoked,
                                       validation=validation)["status"], "FAILED")
        validation["revocation_durable"], validation["pregrant_request_count"] = True, 1
        self.assertEqual(self.classify("crash-during-purge", expected, revoked=revoked,
                                       validation=validation)["status"], "FAILED")

    def test_uncommitted_baseline_never_becomes_accepted_revocation_pass(self):
        validation = self.validation(checkpoint_attested="before_intent_commit", revocation_durable=False,
                                     restart_prior_consent_preserved=True)
        result = self.classify("before-intent", self.rows(1, 20), validation=validation)
        self.assertEqual(result["status"], "BOUNDARY_OBSERVED")
        self.assertFalse(result["accepted_revocation"])
        self.assertEqual(result["revoked_ids_reappeared"], [])
        phases = {name: {"status": "PASSED"} for name in PHASES}
        self.assertEqual(overall_status(phases), "BLOCKED")
        phases["before-intent"] = result
        self.assertEqual(overall_status(phases), "PASSED")
        phases["retry"] = {"status": "FAILED"}
        self.assertEqual(overall_status(phases), "FAILED")
        phases["normal"] = {"status": "BLOCKED"}
        self.assertEqual(overall_status(phases), "BLOCKED")

    def test_overflow_requires_all_45_intents_exact_13_loss_and_counter(self):
        expected = self.rows(1, 45)
        validation = self.validation()
        validation["final_state"]["dropped_count"] = 13
        result = self.classify("overflow", expected, expected[13:], validation=validation)
        self.assertEqual(result["status"], "PASSED")
        self.assertEqual(result["expected_unique"], 45)
        self.assertEqual(result["missing_ids"], [row["event_id"] for row in expected[:13]])
        validation["final_state"]["dropped_count"] = 0
        self.assertEqual(self.classify("overflow", expected, expected[13:], validation=validation)["status"], "FAILED")
        self.assertEqual(self.classify("overflow", expected[13:], expected[13:], validation=validation)["status"], "FAILED")

    def test_retry_requires_one_lost_ack_and_same_uuid_for_every_id(self):
        expected = self.rows(1, 10)
        requests = self.requests(expected, lost_ack=True) + self.requests(expected)
        self.assertEqual(self.classify("retry", expected, expected * 2, requests=requests)["status"], "PASSED")
        changed = self.requests(expected, lost_ack=True) + self.requests(expected, uuid_salt="changed")
        self.assertEqual(self.classify("retry", expected, expected * 2, requests=changed)["status"], "FAILED")
        self.assertEqual(self.classify("retry", expected, expected * 2,
                                       requests=self.requests(expected) * 2)["status"], "FAILED")

    def test_inflight_initial_receipt_is_visible_and_any_later_retry_fails(self):
        expected = self.rows(1, 10)
        validation = self.validation(held_after_fsync_before_revoke=True, requests_at_revocation=1,
                                     inflight_before_revoke=1)
        validation["final_state"]["consent"] = False
        requests = self.requests(expected, lost_ack=True)
        result = self.classify("inflight", expected, validation=validation, requests=requests)
        self.assertEqual(result["status"], "PASSED")
        self.assertEqual(result["already_started_before_revocation_ids"], [r["event_id"] for r in expected])
        late = self.classify("inflight", expected, expected * 2,
                             validation=validation, requests=requests + self.requests(expected))
        self.assertEqual(late["status"], "FAILED")
        self.assertIn("INFLIGHT_BOUNDARY_OR_NO_RETRY_NOT_ATTESTED", late["failures"])

    def test_empty_wire_and_missing_client_negative_checks_cannot_pass(self):
        expected = self.rows(1, 100)
        self.assertEqual(self.classify("normal", expected, requests=[])["status"], "FAILED")
        validation = self.validation(preflight_checks={"all_passed": True})
        self.assertEqual(self.classify("normal", expected, validation=validation)["status"], "FAILED")
        request = self.requests(expected)
        request[0]["violations"] = ["unexpected_property:device_model"]
        self.assertFalse(self.classify("normal", expected, requests=request)["wire"]["privacy_pass"])

    def test_final_reconciliation_reopens_late_revoked_receipts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            phase, wire = root / "revoke", root / "wire-revoke"
            phase.mkdir(); wire.mkdir()
            expected, revoked = self.rows(21, 10), self.rows(1, 20)
            write_rows(phase / "expected.jsonl", expected)
            write_rows(phase / "revoked-intent.jsonl", revoked)
            (phase / "validation.json").write_text(json.dumps(self.validation()))
            write_rows(wire / "received.jsonl", expected + revoked)
            write_rows(wire / "requests.jsonl", self.requests(expected + revoked))
            findings = {"revoke": {"status": "PASSED"}}
            final_reconciliation(root, findings)
            self.assertEqual(findings["revoke"]["status"], "FAILED")
            self.assertEqual(len(findings["revoke"]["revoked_ids_reappeared"]), 20)

    def test_checkpoint_identity_and_commit_label_cannot_be_faked(self):
        nonce = "a" * 32
        value = {"action_nonce": nonce, "stage": "during_purge", "pid": 50,
                 "consent": False, "generation": 2, "revocation_durable": True}
        validate_checkpoint(value, nonce, "during_purge", 50)
        for changed in ({"action_nonce": "b" * 32}, {"pid": 51}, {"revocation_durable": False}, {"consent": True}):
            with self.subTest(changed=changed), self.assertRaises(TrialBlocked):
                validate_checkpoint(dict(value, **changed), nonce, "during_purge", 50)
        value.update(stage="before_intent_commit", revocation_durable=False)
        validate_checkpoint(value, nonce, "before_intent_commit", 50)

    def test_state_requires_live_pid_nonce_and_integer_counters(self):
        value = dict.fromkeys(STATE_COUNTS, 0)
        value.update(action_nonce="a" * 32, action_ok=True, action="state", pid=10,
                     run_id=self.run_id, consent=False, trace_sha256="b" * 64, setting_value="synthetic-setting")
        validate_state(value, "a" * 32, "state", self.run_id, 10)
        for change in ({"pid": 9}, {"action_nonce": "c" * 32}, {"queue_count": True}, {"consent": 0}):
            with self.subTest(change=change), self.assertRaises(TrialBlocked):
                validate_state(dict(value, **change), "a" * 32, "state", self.run_id, 10)

    def test_aapt_sdk_aliases_strictly_accept_one_correct_minimum(self):
        for minimum in ("sdkVersion", "minSdkVersion"):
            self.assertTrue(valid_sdk_bounds(minimum + ":'24'\ntargetSdkVersion:'36'\n"))
        self.assertFalse(valid_sdk_bounds("minSdkVersion:'24'\nsdkVersion:'24'\ntargetSdkVersion:'36'\n"))
        self.assertFalse(valid_sdk_bounds("minSdkVersion:'23'\ntargetSdkVersion:'36'\n"))

    def test_export_ignores_private_logs_but_public_tree_is_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work, out = root / "private", root / "public"
            (work / "normal").mkdir(parents=True)
            (work / "normal" / "stdout.log").write_text("private raw output")
            (work / "normal" / "vm.private.json").write_text('{"url":"http://private/"}')
            write_rows(work / "normal" / "expected.jsonl", self.rows(1, 1))
            export_evidence(work, out)
            self.assertEqual([path.name for path in (out / "normal").iterdir()], ["expected.jsonl"])
            (out / "normal" / "unexpected.json").write_text("{}")
            with self.assertRaises(TrialBlocked):
                audit_public_directory(out)


class LocalReceiverFaults(unittest.TestCase):
    run_id = "synthetic-direct-receiver-host"

    def payload(self, extra=False):
        properties = dict(event(self.run_id, 1), **{"$geoip_disable": True, "$process_person_profile": False})
        if extra:
            properties["device_model"] = "private-unknown-value"
        return {"api_key": TOKEN, "batch": [{"event": "cm_lab_probe", "properties": properties,
                "distinct_id": self.run_id, "timestamp": "2026-11-02T00:00:00Z", "uuid": str(uuid.uuid4())}]}

    def serve(self, receiver):
        errors = []
        receiver.server.handle_error = lambda *_: errors.append("handler")
        thread = threading.Thread(target=receiver.server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
        thread.start()
        return thread, errors

    def post(self, port, payload):
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        try:
            connection.request("POST", "/batch/", json.dumps(payload),
                               headers={"Content-Type": "application/json", "User-Agent": "Java/1.0"})
            return connection.getresponse().status
        finally:
            connection.close()

    def test_held_lost_ack_is_after_durable_observation_and_does_not_change_audit(self):
        with tempfile.TemporaryDirectory() as tmp:
            receiver = HeldAckReceiver(Path(tmp) / "wire", self.run_id, port=0)
            thread, errors = self.serve(receiver)
            completed, outcomes = threading.Event(), []
            payload = self.payload()
            def client():
                try:
                    outcomes.append(self.post(receiver.server.server_port, payload))
                except http.client.RemoteDisconnected:
                    outcomes.append("LOST_ACK")
                finally:
                    completed.set()
            sender = threading.Thread(target=client, daemon=True)
            try:
                sender.start()
                self.assertTrue(receiver.held.wait(3))
                self.assertFalse(completed.is_set())
                records = [json.loads(line) for line in (receiver.out / "requests.jsonl").read_text().splitlines()]
                self.assertEqual(records[0]["scope"], WIRE_SCOPE)
                self.assertEqual(records[0]["normalized_rows"], audit_payload(payload, self.run_id)["normalized_rows"])
                self.assertTrue(records[0]["audit_pass"])
                self.assertEqual(len((receiver.out / "received.jsonl").read_text().splitlines()), 1)
                receiver.release_ack.set()
                self.assertTrue(completed.wait(3))
                self.assertEqual(outcomes, ["LOST_ACK"])
                self.assertFalse(errors)
            finally:
                receiver.release_ack.set(); receiver.server.shutdown(); receiver.close()
                thread.join(3); sender.join(3)

    def test_direct_provenance_does_not_relax_extra_property_redaction(self):
        with tempfile.TemporaryDirectory() as tmp:
            receiver = DirectReceiver(Path(tmp) / "wire", self.run_id, port=0)
            thread, errors = self.serve(receiver)
            try:
                self.assertEqual(self.post(receiver.server.server_port, self.payload(extra=True)), 200)
                raw = (receiver.out / "requests.jsonl").read_text()
                row = json.loads(raw)
                self.assertFalse(row["audit_pass"])
                self.assertIn("event[0]:unexpected_property:device_model", row["violations"])
                self.assertNotIn("private-unknown-value", raw)
                self.assertEqual(json.loads((receiver.out / "summary.json").read_text())["scope"], WIRE_SCOPE)
                self.assertFalse(errors)
            finally:
                receiver.server.shutdown(); receiver.close(); thread.join(3)


if __name__ == "__main__":
    unittest.main()
