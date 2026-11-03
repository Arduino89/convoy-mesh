"""Host-only counterexamples for cloud readback, never a live PostHog test."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
import uuid

from ci_native_trial import validate_public_value
from probe import event
from reconcile_cloud_trial import (PROJECT, READBACK_COLUMNS, SOURCE_SCOPE, TrialBlocked, expected_queries,
                                   load_json, normalize_connector_rows, reconcile_trial)


class CloudReadbackGuards(unittest.TestCase):
    run_id = "synthetic-direct-cloud-readback-host"
    source = "a" * 40

    def setUp(self):
        self.items = {}
        for number in range(1, 142):
            self.items[number] = {
                "event": "cm_lab_probe", "distinct_id": self.run_id,
                "uuid": str(uuid.uuid5(uuid.NAMESPACE_OID, self.run_id + str(number))),
                "timestamp": "2026-11-03T12:34:56.123Z",
                "properties": dict(event(self.run_id, number), **{
                    "$geoip_disable": True, "$process_person_profile": False})}
        self.preflight, self.attempts = [], []
        batches = [list(range(start, start + 20)) for start in range(1, 101, 20)]
        batches.extend([list(range(121, 131)), list(range(131, 141)), list(range(131, 141))])
        reserved = 0
        for index, sequence in enumerate(batches, 1):
            batch = [copy.deepcopy(self.items[number]) for number in sequence]
            reserved += len(batch)
            self.preflight.append({"attempt_id": index, "budget_reserved_rows": reserved,
                                   "rows": len(batch), "credential_redacted": True,
                                   "envelope_keys": ["api_key", "batch"], "payload": {"batch": batch}})
            common = {"attempt_id": index, "budget_reserved_rows": reserved, "rows": len(batch),
                      "event_ids": [item["properties"]["event_id"] for item in batch],
                      "uuids": [item["uuid"] for item in batch]}
            for phase in ("reserved", "body_written", "response", "finished"):
                record = dict(common, phase=phase)
                if phase == "response":
                    record.update(response_code=200, response_accepted=True, quota_limited=False,
                                  ack_discarded=index == 7)
                if phase == "finished":
                    record.update(body_written=True, response_code=200, acknowledged=index != 7,
                                  ack_discarded=index == 7)
                self.attempts.append(record)
        self.transport = {"schema_version": 1, "scope": SOURCE_SCOPE,
                          "status": "TRANSPORT_COMPLETE_READBACK_PENDING", "run_id": self.run_id,
                          "source_commit": self.source, "project_id": PROJECT,
                          "budget": {"reserved_rows": reserved, "limit": 500,
                                     "total_ceiling": 500, "prior_rows_reserved": 0},
                          "started_utc": "2026-11-03T12:34:55.123Z", "finished_utc": "2026-11-03T12:35:00.500Z",
                          "retry_same_uuid_attested": True}
        queries = expected_queries(self.transport, self.preflight)
        self.cloud_items = {n: dict(copy.deepcopy(item), created_at="2026-11-03T12:35:01Z",
                                   person_mode=None, person_id=None) for n, item in self.items.items()}
        self.readback = {"schema_version": 1, "project_id": PROJECT, "run_id": self.run_id,
                         "source_commit": self.source, "query": queries["rows"], "count_query": queries["count"],
                         "row_response_ref": "connector-row-response", "row_response_sha256": "c" * 64,
                         "count_response_ref": "connector-count-response", "count_response_sha256": "d" * 64,
                         "raw_count": None,
                         "queried_at_utc": "2026-11-03T12:40:00Z", "complete": True,
                         "rows": [copy.deepcopy(self.cloud_items[n]) for n in (*range(1, 101), *range(121, 141))]}

    def analyze(self, readback="default"):
        selected = copy.deepcopy(self.readback if readback == "default" else readback)
        if selected is not None and selected.get("raw_count") is None:
            selected["raw_count"] = len(selected["rows"])
        return reconcile_trial(self.transport, self.preflight, self.attempts,
                               selected)

    def test_complete_raw_readback_proves_cohorts_but_not_universal_dedup(self):
        result, rows = self.analyze()
        self.assertEqual(result["status"], "PASSED")
        self.assertEqual(result["raw_rows_seen"], 120)
        self.assertEqual(result["phases"]["normal"]["received_unique"], 100)
        self.assertEqual(result["phases"]["new"]["received_unique"], 10)
        self.assertEqual(result["phases"]["revoked"]["received_rows"], 0)
        self.assertEqual(result["budget"]["body_written_rows"], 130)
        self.assertFalse(result["retry_storage_observation"]["universal_deduplication_guarantee"])
        validate_public_value(result)
        validate_public_value(rows)

    def test_http_transport_without_readback_is_pending_never_passed(self):
        result, rows = self.analyze(None)
        self.assertEqual(result["status"], "PENDING_READBACK")
        self.assertEqual(rows, [])
        self.readback["rows"] = []
        result, _ = self.analyze()
        self.assertEqual(result["status"], "FAILED")
        self.assertEqual(len(result["overall"]["missing_ids"]), 120)

    def test_failed_transport_preserves_actual_cloud_rows_without_acceptance_pass(self):
        self.transport["status"] = "FAILED"
        self.readback["rows"].append(copy.deepcopy(self.cloud_items[101]))
        result, rows = self.analyze()
        self.assertEqual(result["status"], "BLOCKED")
        self.assertFalse(result["client_evidence_complete"])
        self.assertEqual(result["raw_rows_seen"], 121)
        self.assertEqual(result["phases"]["revoked"]["received_rows"], 1)
        self.assertEqual(len(rows), 121)

    def test_raw_retry_duplicates_are_visible_and_not_aggregated_away(self):
        self.readback["rows"].extend(copy.deepcopy(self.cloud_items[n]) for n in range(131, 141))
        result, rows = self.analyze()
        self.assertEqual(result["status"], "PASSED")
        self.assertEqual(len(rows), 130)
        self.assertEqual(result["phases"]["retry"]["duplicate_rows"], 10)
        self.assertEqual(result["overall"]["duplicate_rows"], 10)
        self.assertEqual(result["retry_storage_observation"]["interpretation"], "DUPLICATE_STORED_ROWS_OBSERVED")

    def test_duplicate_normal_row_is_counted_even_when_all_ids_arrived(self):
        self.readback["rows"].append(copy.deepcopy(self.cloud_items[1]))
        result, _ = self.analyze()
        self.assertEqual(result["status"], "FAILED")
        self.assertEqual(result["phases"]["normal"]["received_unique"], 100)
        self.assertEqual(result["phases"]["normal"]["duplicate_rows"], 1)

    def test_revoked_twenty_fail_even_with_all_ten_new_received(self):
        self.readback["rows"].extend(copy.deepcopy(self.cloud_items[n]) for n in range(101, 121))
        result, _ = self.analyze()
        self.assertEqual(result["status"], "FAILED")
        self.assertEqual(result["phases"]["new"]["received_unique"], 10)
        self.assertEqual(result["phases"]["revoked"]["received_rows"], 20)
        self.assertEqual(len(result["overall"]["unexpected_ids"]), 20)
        self.assertIn("REVOKED_EVENTS_RECEIVED", result["failures"])

    def test_missing_and_unexpected_ids_are_not_hidden_by_query_or_phase_selection(self):
        self.readback["rows"] = self.readback["rows"][1:] + [copy.deepcopy(self.cloud_items[141])]
        result, _ = self.analyze()
        self.assertEqual(result["status"], "FAILED")
        self.assertEqual(result["overall"]["missing_ids"], [event(self.run_id, 1)["event_id"]])
        self.assertEqual(result["overall"]["unexpected_ids"], [event(self.run_id, 141)["event_id"]])

    def test_wrong_cloud_uuid_or_changed_timestamp_fails(self):
        self.readback["rows"][0]["uuid"] = str(uuid.uuid4())
        self.readback["rows"][1]["timestamp"] = "2026-11-03T12:34:57.123Z"
        result, rows = self.analyze()
        self.assertEqual(result["status"], "FAILED")
        self.assertEqual(result["row_violation_counts"]["CLOUD_UUID_OR_TIMESTAMP_DIFFERS_FROM_CLIENT"], 2)
        self.assertEqual(rows[0]["uuid"], "<redacted:unattested-uuid>")

    def test_equivalent_timestamp_encoding_is_not_false_mismatch(self):
        self.readback["rows"][0]["timestamp"] = "2026-11-03 12:34:56.123000+00:00"
        result, _ = self.analyze()
        self.assertEqual(result["status"], "PASSED")

    def test_unknown_metadata_is_review_required_and_values_never_exported(self):
        self.readback["rows"][0]["properties"].update({
            "$ip": "203.0.113.47", "url": "https://private.example/location",
            "nested": {"api_key": "phc_secret_secret_secret", "token": "private-value"}})
        result, rows = self.analyze()
        self.assertEqual(result["status"], "REVIEW_REQUIRED")
        self.assertTrue(result["delivery_pass"])
        self.assertIn({"name": "$ip", "rows": 1}, result["metadata_extra_key_counts"])
        public = json.dumps({"result": result, "rows": rows})
        for secret in ("203.0.113.47", "private.example", "phc_secret", "private-value"):
            self.assertNotIn(secret, public)
        validate_public_value(result)
        validate_public_value(rows)

    def test_raw_query_guard_rejects_distinct_event_filter_and_changed_limit(self):
        original = self.readback["query"]
        for query in (original.replace("SELECT ", "SELECT DISTINCT ", 1),
                      original.replace("ORDER BY", "AND event = 'cm_lab_probe' ORDER BY"),
                      original.replace("LIMIT 500", "LIMIT 120")):
            self.readback["query"] = query
            result, _ = self.analyze()
            self.assertEqual(result["status"], "BLOCKED")
            self.assertEqual(result["blocked_reason"], "READBACK_QUERY_NOT_RAW_COMPLETE_RUN")

    def test_truncated_or_mismatched_readback_cannot_pass(self):
        for change in ({"complete": False}, {"source_commit": "b" * 40}, {"project_id": 1},
                       {"rows": [copy.deepcopy(self.cloud_items[1])] * 501}, {"raw_count": 121},
                       {"queried_at_utc": "2026-11-03T12:34:59Z"}, {"row_response_sha256": ""}):
            readback = dict(self.readback, **change)
            result, _ = self.analyze(readback)
            self.assertEqual(result["status"], "BLOCKED")

    def test_client_uuid_regeneration_or_budget_reset_blocks_cloud_pass(self):
        self.preflight[-1]["payload"]["batch"][0]["uuid"] = str(uuid.uuid4())
        queries = expected_queries(self.transport, self.preflight)
        self.readback.update(query=queries["rows"], count_query=queries["count"])
        result, _ = self.analyze()
        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["blocked_reason"], "CLIENT_EVENT_CHANGED_ACROSS_ATTEMPTS")
        self.setUp()
        self.transport["budget"]["prior_rows_reserved"] = 1
        result, _ = self.analyze()
        self.assertEqual(result["status"], "BLOCKED")

    def test_failed_reserved_attempt_is_not_refunded_and_can_recover(self):
        failed = copy.deepcopy(self.preflight[0])
        for receipt in self.preflight:
            receipt["attempt_id"] += 1
            receipt["budget_reserved_rows"] += 20
        for row in self.attempts:
            row["attempt_id"] += 1
            row["budget_reserved_rows"] += 20
        failed.update(attempt_id=1, budget_reserved_rows=20)
        first = failed["payload"]["batch"]
        common = {"attempt_id": 1, "budget_reserved_rows": 20, "rows": 20,
                  "event_ids": [item["properties"]["event_id"] for item in first],
                  "uuids": [item["uuid"] for item in first]}
        self.preflight.insert(0, failed)
        self.attempts[:0] = [dict(common, phase="reserved"), dict(common, phase="finished", body_written=False,
                            response_code=0, acknowledged=False, ack_discarded=False)]
        self.transport["budget"]["reserved_rows"] += 20
        result, _ = self.analyze()
        self.assertEqual(result["status"], "PASSED")
        self.assertEqual(result["budget"]["reserved_rows"], 150)
        self.assertEqual(result["budget"]["body_written_rows"], 130)

    def test_response_without_observed_body_write_cannot_attest_retry(self):
        self.attempts = [row for row in self.attempts if not (row["attempt_id"] == 8 and row["phase"] == "body_written")]
        result, _ = self.analyze()
        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["blocked_reason"], "TRANSPORT_PHASE_SEQUENCE_INCOMPLETE")

    def test_same_uuid_for_two_business_events_is_rejected(self):
        self.preflight[0]["payload"]["batch"][1]["uuid"] = self.items[1]["uuid"]
        # The derived SQL changes only if the removed UUID no longer appears.
        queries = expected_queries(self.transport, self.preflight)
        self.readback.update(query=queries["rows"], count_query=queries["count"])
        result, _ = self.analyze()
        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["blocked_reason"], "CLIENT_UUID_REUSED_FOR_DIFFERENT_EVENT_IDS")

    def test_quota_limited_http_200_never_attests_complete_transport(self):
        response = next(row for row in self.attempts if row["phase"] == "response")
        response.update(quota_limited=True, response_accepted=False)
        result, _ = self.analyze()
        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["blocked_reason"], "CLOUD_RESPONSE_ACCEPTANCE_OR_QUOTA_INVALID")

    def test_person_columns_are_redacted_metadata_not_profile_creation_proof(self):
        self.readback["rows"][0].update(person_mode="propertyless", person_id=str(uuid.uuid4()))
        result, rows = self.analyze()
        self.assertEqual(result["status"], "REVIEW_REQUIRED")
        self.assertTrue(result["person_fields_are_not_proof_of_profile_creation"])
        self.assertNotIn(self.readback["rows"][0]["person_id"], json.dumps(rows))
        self.assertNotIn("propertyless", json.dumps(rows))
        validate_public_value(rows)

    def test_query_has_timestamp_bounds_uuid_fallback_and_raw_count(self):
        queries = expected_queries(self.transport, self.preflight)
        self.assertIn("WHERE timestamp >=", queries["rows"])
        self.assertIn("OR uuid IN (", queries["rows"])
        self.assertIn(self.items[1]["uuid"], queries["rows"])
        self.assertTrue(queries["rows"].endswith("LIMIT 500"))
        self.assertTrue(queries["count"].startswith("SELECT count() AS raw_count"))
        self.assertNotIn("DISTINCT", queries["count"])
        self.assertEqual(queries["window"]["clock_margin_seconds"], 300)

    def test_connector_normalizer_keeps_duplicate_rows_and_parses_properties_strictly(self):
        item = copy.deepcopy(self.cloud_items[1])
        item["properties"] = json.dumps(item["properties"])
        raw = [[item[name] for name in READBACK_COLUMNS]] * 2
        normalized = normalize_connector_rows(READBACK_COLUMNS, raw)
        self.assertEqual(len(normalized), 2)
        self.assertEqual(normalized[0], normalized[1])
        self.assertIsInstance(normalized[0]["properties"], dict)
        raw[0] = list(raw[0]); raw[0][2] = '{"a":1,"a":2}'
        with self.assertRaises(TrialBlocked):
            normalize_connector_rows(READBACK_COLUMNS, raw)

    def test_changed_privacy_control_and_invalid_row_are_counted(self):
        self.readback["rows"][0]["properties"]["$geoip_disable"] = False
        self.readback["rows"][1]["properties"] = "private invalid data"
        result, rows = self.analyze()
        self.assertEqual(result["status"], "FAILED")
        self.assertEqual(result["raw_rows_seen"], 120)
        self.assertEqual(result["invalid_rows"], 2)
        self.assertEqual(len(result["overall"]["missing_ids"]), 1)
        self.assertNotIn("private invalid data", json.dumps(rows))

    def test_duplicate_json_keys_are_rejected_before_analysis(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "readback.json"
            for text in ('{"complete":true,"complete":false}', '{"x":NaN}'):
                path.write_text(text)
                with self.assertRaises(TrialBlocked):
                    load_json(path)


if __name__ == "__main__":
    unittest.main()
