"""Static one-use wrapper regressions; no GitHub dispatch or cloud activity."""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import unittest

from ci_cloud_trial import TrialBlocked
from review_cloud_launch import BRANCH, MARKER, WORKFLOW, digest, expected_wrapper, review_wrapper


class CloudLaunchReview(unittest.TestCase):
    source = "a" * 40
    number = 15
    clock = datetime(2026, 11, 6, 12, tzinfo=timezone.utc)

    @classmethod
    def setUpClass(cls):
        cls.repo = Path(__file__).resolve().parents[2]
        cls.original = (cls.repo / "docs/telemetry-evidence/2026-11-06/workflow-original.yml").read_text()

    def gate(self):
        gate = {"schema_version": 2, "status": "PASS", "project_id": 330212,
                "api_host": "https://eu.i.posthog.com", "source_commit": self.source,
                "run_id": "synthetic-cloud-host-wrapper", "execution_id": WORKFLOW + ":15", "run_attempt": 1,
                "quota_rows_available": 999838, "total_ceiling": 700, "prior_rows_conservative_consumed": 500,
                "additional_rows_authorized": 200,
                "remaining_budget": 200, "expires_utc": (self.clock + timedelta(hours=1)).isoformat()}
        for name in ("privacy", "retention", "deletion", "quota", "local_regression"):
            gate[name] = {"status": "VERIFIED", "checked_at_utc": self.clock.isoformat(),
                          "evidence_ref": "synthetic-host-fixture"}
        gate["privacy"].update(anonymize_ips=True, session_recording_opt_in=False)
        gate["quota"]["free_plan"] = True
        gate["local_regression"]["source_commit"] = self.source
        gate["budget_authorization"] = {"status": "VERIFIED", "checked_at_utc": self.clock.isoformat(),
            "evidence_ref": "synthetic-host-fixture", "prior_rows_conservative_consumed": 500,
            "additional_rows_authorized": 200, "total_ceiling": 700}
        return gate

    def review(self, wrapper=None, gate=None, original=None):
        gate = self.gate() if gate is None else gate
        original = self.original if original is None else original
        wrapper = expected_wrapper(original, self.source, gate, self.number) if wrapper is None else wrapper
        return review_wrapper(original, wrapper, self.source, gate, self.number, self.clock)

    def test_exact_guarded_wrapper_and_only_authorized_case_passes(self):
        result = self.review()
        self.assertEqual(result["status"], "APPROVED_FOR_SINGLE_LAUNCH")
        self.assertEqual([item["case"] for item in result["guard_matrix"] if item["job_enabled"]], ["authorized_push"])
        self.assertEqual(result["historical_conservative_consumption"], 500)
        self.assertEqual(result["new_allowance_rows_including_retries"], 200)
        self.assertEqual(result["cumulative_ceiling"], 700)
        self.assertIs(result["android_executed"], False)
        self.assertIs(result["cloud_executed"], False)

    def test_every_removed_guard_and_source_change_is_rejected(self):
        gate = self.gate()
        wrapper = expected_wrapper(self.original, self.source, gate, self.number)
        changes = [
            ("github.repository == 'Arduino89/convoy-mesh' && ", ""),
            ("github.event.repository.private == false && ", ""),
            ("github.event_name == 'push' && ", ""),
            ("github.ref == 'refs/heads/" + BRANCH + "' && ", ""),
            ("github.run_number == 15 && ", ""),
            ("github.run_attempt == 1 && ", ""),
            (" && github.event.head_commit.message == '" + MARKER + "'", ""),
            ("          ref: " + self.source, "          ref: main"),
        ]
        for before, after in changes:
            with self.subTest(before=before):
                self.assertEqual(wrapper.count(before), 1)
                with self.assertRaisesRegex(TrialBlocked, "WRAPPER_HAS_UNREVIEWED_FIELDS_OR_GUARDS"):
                    self.review(wrapper.replace(before, after, 1), gate)

    def test_permissions_secret_scope_and_execution_order_cannot_change(self):
        wrapper = expected_wrapper(self.original, self.source, self.gate(), self.number)
        mutations = [wrapper.replace("contents: read", "contents: write"),
                     wrapper.replace('      CI: "true"', '      CI: "true"\n      TOKEN: ${{ secrets.CONVOY_LAB_POSTHOG_TOKEN }}'),
                     wrapper.replace("script: bash tools/telemetry_spike/run_ci_lab.sh", "script: bash tools/telemetry_spike/run_ci_cloud_lab.sh"),
                     wrapper.replace("timeout-minutes: 45", "timeout-minutes: 90"),
                     wrapper.replace("uses: actions/checkout@v7", "uses: actions/checkout@main")]
        for mutation in mutations:
            with self.subTest(sha=digest(mutation)), self.assertRaises(TrialBlocked):
                self.review(mutation)

    def test_original_snapshot_cannot_be_changed_to_allow_other_fields(self):
        changed = self.original.replace("contents: read", "contents: write")
        with self.assertRaisesRegex(TrialBlocked, "RESTORED_WORKFLOW_BYTES_NOT_PINNED"):
            expected_wrapper(changed, self.source, self.gate(), self.number)

    def test_mismatched_source_run_attempt_and_budget_are_blocked(self):
        changes = [{"source_commit": "b" * 40}, {"execution_id": WORKFLOW + ":16"}, {"run_attempt": 2},
                   {"remaining_budget": 201}, {"prior_rows_conservative_consumed": 499}, {"total_ceiling": 701}]
        for change in changes:
            gate = dict(self.gate(), **change)
            with self.subTest(change=change), self.assertRaises(TrialBlocked):
                self.review(gate=gate)

    def test_old_source_proof_expired_gate_and_pending_controls_are_rejected(self):
        bad = []
        value = self.gate(); value["local_regression"]["source_commit"] = "b" * 40; bad.append(value)
        value = self.gate(); value["expires_utc"] = self.clock.isoformat(); bad.append(value)
        value = self.gate(); value["deletion"]["status"] = "PENDING"; bad.append(value)
        for gate in bad:
            with self.subTest(gate=gate), self.assertRaises(TrialBlocked):
                self.review(gate=gate)

    def test_literal_gate_cannot_inject_github_expressions(self):
        gate = self.gate(); gate["privacy"]["evidence_ref"] = "${{ secrets.EXAMPLE }}"
        with self.assertRaisesRegex(TrialBlocked, "GATE_MUST_NOT_CONTAIN_ACTIONS_EXPRESSIONS"):
            expected_wrapper(self.original, self.source, gate, self.number)

    def test_apostrophe_in_plain_reference_is_yaml_escaped(self):
        gate = self.gate(); gate["privacy"]["evidence_ref"] = "reviewed Cama's synthetic gate"
        wrapper = expected_wrapper(self.original, self.source, gate, self.number)
        self.assertIn("Cama''s", wrapper)
        self.assertEqual(self.review(wrapper, gate)["status"], "APPROVED_FOR_SINGLE_LAUNCH")


if __name__ == "__main__":
    unittest.main()
