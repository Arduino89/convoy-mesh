"""Host guard counterexamples; native ACK/SQLite proof requires Android."""
from copy import deepcopy
import unittest

from ci_ack_response_trial import validate_native
from ci_cloud_trial import cloud_drain_complete, TrialBlocked


class NativeResponseReceiptGuards(unittest.TestCase):
    def receipt(self):
        return {"schema_version": 1, "scope": "PERMISSIONLESS_ANDROID_ACK_FUNCTIONS_OFFLINE",
            "variant": "before", "nonce": "a" * 32, "passed": True,
            "documented_status_ok_accepted": False, "legacy_integer_one_accepted": True,
            "sender_instantiated": False, "transport_invoked": False,
            "raw_response_body_recorded": False, "case_count": 0, "cases": []}

    def test_original_predicate_rejection_is_recorded_as_red_not_changed_to_acceptance(self):
        value = self.receipt()
        self.assertIs(validate_native(value, "a" * 32, "before"), value)
        value["documented_status_ok_accepted"] = True
        with self.assertRaises(TrialBlocked): validate_native(value, "a" * 32, "before")

    def test_stale_or_transport_or_extra_raw_response_cannot_be_exported_as_proof(self):
        for mutation in ({"nonce": "b" * 32}, {"transport_invoked": True},
                         {"sender_instantiated": True}, {"raw_response_body_recorded": True},
                         {"unknown_response_value": "synthetic-untrusted-value"}, {"schema_version": True}):
            with self.subTest(mutation=mutation), self.assertRaises(TrialBlocked):
                validate_native(dict(self.receipt(), **mutation), "a" * 32, "before")

    def test_candidate_must_supply_all_native_queue_and_negative_cases(self):
        value = dict(self.receipt(), variant="after", documented_status_ok_accepted=True)
        with self.assertRaises(TrialBlocked): validate_native(value, "a" * 32, "after")

    def test_failure_reason_never_echoes_untrusted_status_or_body(self):
        value = {"passed": False, "failed_case": "synthetic-untrusted-response-value"}
        with self.assertRaisesRegex(TrialBlocked, "^ANDROID_ACK_FIXTURE_FAILED_UNKNOWN$"):
            validate_native(value, "a" * 32, "after")

    def test_permanent_flag_types_are_strict_and_precede_empty_queue_success(self):
        state = {"cloud_transport_blocked": 0, "cloud_budget_blocked": 0,
                 "queue_count": 0, "in_flight_count": 0}
        self.assertTrue(cloud_drain_complete(state))
        for value in (True, 1.0, None, "1", -1):
            with self.subTest(value=value), self.assertRaisesRegex(TrialBlocked, "^CLOUD_BLOCK_STATE_INVALID$"):
                cloud_drain_complete(dict(state, cloud_transport_blocked=value))
        with self.assertRaisesRegex(TrialBlocked, "^CLOUD_PERMANENT_BLOCK_QUOTA_LIMITED$"):
            cloud_drain_complete(dict(state, cloud_transport_blocked=1, cloud_block_reason="QUOTA_LIMITED"))


if __name__ == "__main__": unittest.main()
