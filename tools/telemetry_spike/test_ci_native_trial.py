"""Host-only result/export guards; no Android, APK build or live SDK execution."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from ci_native_trial import (TrialBlocked, audit_public_directory, classify_phase,
                            export_evidence, final_reconciliation, overall_status, validate_public_value)
from probe import event


class NativeCIResultGuards(unittest.TestCase):
    run_id = "synthetic-native-ci-test"

    def rows(self, first, count):
        return [event(self.run_id, i) for i in range(first, first + count)]

    def validation(self):
        return {"sentinels_unchanged": True, "final_state": {"native_filter": True, "action_ok": True}}

    def wire(self, **overrides):
        return dict({"privacy_pass": True, "requests": 5, "event_rows": 100,
                     "violation_counts": {}, "repeated_business_ids": {},
                     "close_without_response_count": 0}, **overrides)

    def test_normal_exact_ids_pass_and_duplicate_plus_missing_fails(self):
        expected = self.rows(1, 100)
        self.assertEqual(classify_phase("normal", expected, expected, self.validation(), self.wire())["status"], "PASSED")
        actual = expected[:-1] + expected[:1]
        finding = classify_phase("normal", expected, actual, self.validation(), self.wire())
        self.assertEqual(finding["status"], "FAILED")
        self.assertEqual(finding["duplicate_rows"], 1)
        self.assertEqual(finding["missing_ids"], [expected[-1]["event_id"]])

    def test_revoked_ids_cannot_be_counted_as_successful_new_delivery(self):
        expected = self.rows(121, 10)
        finding = classify_phase("revoke", expected, self.rows(101, 30), self.validation(), self.wire())
        self.assertEqual(finding["status"], "FAILED")
        self.assertEqual(len(finding["unexpected_ids"]), 20)
        self.assertEqual(finding["missing_ids"], [])

    def test_overflow_preserves_45_denominator_and_13_missing(self):
        expected = self.rows(1, 45)
        finding = classify_phase("overflow", expected, expected[13:], self.validation(), self.wire())
        self.assertEqual(finding["status"], "PASSED")
        self.assertEqual(finding["expected_unique"], 45)
        self.assertEqual(len(finding["missing_ids"]), 13)
        wrong_oracle = classify_phase("overflow", expected[13:], expected[13:], self.validation(), self.wire())
        self.assertEqual(wrong_oracle["status"], "FAILED")

    def test_retry_requires_lost_ack_and_same_uuid_for_every_id(self):
        expected = self.rows(131, 10)
        repeated = {row["event_id"]: {"rows": 2, "distinct_uuids": ["b2980000-0000-4000-8000-000000000001"]}
                    for row in expected}
        wire = self.wire(close_without_response_count=1, repeated_business_ids=repeated)
        self.assertEqual(classify_phase("retry", expected, expected * 2, self.validation(), wire)["status"], "PASSED")
        wire["close_without_response_count"] = 0
        self.assertEqual(classify_phase("retry", expected, expected * 2, self.validation(), wire)["status"], "FAILED")

    def test_empty_wire_cannot_pass_even_with_vacuous_true_flag(self):
        expected = self.rows(1, 100)
        result = classify_phase("normal", expected, expected, self.validation(), self.wire(requests=0, event_rows=0))
        self.assertEqual(result["status"], "FAILED")
        self.assertFalse(result["privacy_pass"])

    def test_final_status_distinguishes_failure_and_blocked_controls(self):
        all_pass = {name: {"status": "PASSED"} for name in ("normal", "revoke", "retry", "overflow")}
        self.assertEqual(overall_status(all_pass), "PASSED")
        all_pass["revoke"] = {"status": "FAILED"}
        self.assertEqual(overall_status(all_pass), "FAILED")
        all_pass["retry"] = {"status": "BLOCKED"}
        self.assertEqual(overall_status(all_pass), "BLOCKED")
        self.assertEqual(overall_status({}), "BLOCKED")

    def test_late_revoked_rows_reopen_an_initially_successful_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "revoke").mkdir()
            (root / "wire-normal").mkdir()
            expected, revoked = self.rows(121, 10), self.rows(101, 20)
            for name, rows in (("expected", expected), ("revoked-intent", revoked)):
                (root / "revoke" / (name + ".jsonl")).write_text("".join(json.dumps(r) + "\n" for r in rows))
            validation = dict(self.validation(), received_rows=10)
            (root / "revoke" / "validation.json").write_text(json.dumps(validation))
            (root / "wire-normal" / "received.jsonl").write_text(
                "".join(json.dumps(r) + "\n" for r in expected + revoked))
            phases = {"revoke": {"status": "PASSED"}}
            with patch("ci_native_trial.summarize", return_value={"wire": {"wire-normal": self.wire()}}):
                final_reconciliation(root, phases)
            self.assertEqual(phases["revoke"]["status"], "FAILED")
            self.assertEqual(len(phases["revoke"]["revoked_ids_reappeared"]), 20)
            self.assertEqual(phases["revoke"]["first_receipt_received_rows"], 10)

    def test_revoked_ids_arriving_only_on_retry_wire_fail_revocation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for directory in ("revoke", "wire-normal", "wire-retry", "wire-overflow"):
                (root / directory).mkdir()
            expected, revoked = self.rows(121, 10), self.rows(101, 20)
            for name, rows in (("expected", expected), ("revoked-intent", revoked)):
                (root / "revoke" / (name + ".jsonl")).write_text(
                    "".join(json.dumps(row) + "\n" for row in rows))
            validation = dict(self.validation(), received_rows=10)
            (root / "revoke" / "validation.json").write_text(json.dumps(validation))
            (root / "wire-normal" / "received.jsonl").write_text(
                "".join(json.dumps(row) + "\n" for row in expected))
            unrelated = [event("synthetic-other-run", i) for i in range(101, 121)]
            (root / "wire-retry" / "received.jsonl").write_text(
                "".join(json.dumps(row) + "\n" for row in revoked + self.rows(131, 10) + unrelated))
            # A distinct overflow experiment cannot duplicate the old run's count.
            (root / "wire-overflow" / "received.jsonl").write_text(
                "".join(json.dumps(row) + "\n" for row in revoked))
            phases = {"revoke": {"status": "PASSED"}}
            with patch("ci_native_trial.summarize", return_value={"wire": {"wire-normal": self.wire()}}):
                final_reconciliation(root, phases)
            finding = phases["revoke"]
            self.assertEqual(finding["status"], "FAILED")
            self.assertEqual(finding["revoked_ids_reappeared"], [row["event_id"] for row in revoked])
            self.assertEqual(finding["unexpected_ids"], [row["event_id"] for row in revoked])
            self.assertEqual(finding["received_rows"], 30)
            self.assertEqual(finding["missing_ids"], [])
            self.assertEqual(finding["first_receipt_received_rows"], 10)
            self.assertEqual(finding["revoked_ids_seen_in_wire_retry"], [row["event_id"] for row in revoked])

    def test_public_scan_rejects_debug_urls_credentials_and_private_fields(self):
        for value in ({"state": "http://127.0.0.1:8999/private-code/"}, {"base": "redacted"},
                      {"api_key": "phc_synthetic_local_only"}, {"note": "github_pat_exampletoken"}):
            with self.subTest(value=value), self.assertRaises(TrialBlocked):
                validate_public_value(value)
        validate_public_value({"api_key": "<redacted:fake-token>", "headers_safe": {"host": "10.0.2.2:8765"}})

    def test_allowlist_never_exports_private_connection_or_diagnostic_log(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            work, out = root / "private", root / "public"
            (work / "normal").mkdir(parents=True)
            (work / "normal" / "vm.private.json").write_text('{"base":"http://127.0.0.1:8999/auth/"}')
            (work / "normal" / "full.log").write_text("private diagnostic text")
            (work / "normal" / "expected.jsonl").write_text(json.dumps(self.rows(1, 1)[0]) + "\n")
            export_evidence(work, out)
            self.assertEqual([p.name for p in (out / "normal").iterdir()], ["expected.jsonl"])
            audit_public_directory(out)
            (out / "full.log").write_text("unexpected")
            with self.assertRaises(TrialBlocked):
                audit_public_directory(out)


if __name__ == "__main__":
    unittest.main()
