import json
from pathlib import Path
import tempfile
import unittest

from probe import Queue, event, reconcile, validate


class QualityControls(unittest.TestCase):
    def test_equal_counts_do_not_hide_missing_and_duplicate(self):
        expected = [event('synthetic-control', i) for i in range(1, 4)]
        received = [expected[0], expected[0], expected[2]]
        result = reconcile(expected, received)
        self.assertEqual(result['missing_ids'], ['synthetic-control-000002'])
        self.assertEqual(result['duplicate_rows'], 1)
        self.assertEqual(result['delivery_ratio'], 2 / 3)

    def test_foreign_run_is_unexpected(self):
        result = reconcile([event('synthetic-a', 1)], [event('synthetic-b', 1)])
        self.assertEqual(len(result['missing_ids']), 1)
        self.assertEqual(len(result['unexpected_ids']), 1)

    def test_duplicate_oracle_is_rejected(self):
        with self.assertRaises(ValueError):
            reconcile([event('synthetic-a', 1)] * 2, [])

    def test_empty_denominator_is_unknown_not_100_percent(self):
        self.assertIsNone(reconcile([], [])['delivery_ratio'])

    def test_unknown_and_sensitive_properties_rejected(self):
        for prop in ['latitude', 'longitude', 'name', 'device_name', 'log', 'screenshot', 'extra']:
            row = event('synthetic-privacy', 1)
            row[prop] = 'SYNTHETIC_FORBIDDEN_SENTINEL'
            with self.assertRaises(ValueError):
                validate(row)

    def test_malformed_identity_and_scalar_types_rejected(self):
        for key, value in [('sequence', True), ('sequence', -1), ('sequence', 1.2),
                           ('run_id', 'Luca'), ('event_id', 'wrong'),
                           ('synthetic', False), ('schema_version', True)]:
            row = event('synthetic-privacy', 1)
            row[key] = value
            with self.assertRaises(ValueError):
                validate(row)

    def test_byte_budget_bounds_payload_not_just_count(self):
        with tempfile.TemporaryDirectory() as tmp:
            q = Queue(Path(tmp) / 'queue.db', capacity=1000, byte_limit=400)
            q.consent(True)
            for i in range(1, 301):
                q.put(event('synthetic-bytes', i))
            state = q.status()
            self.assertLessEqual(state['payload_bytes'], 400)
            self.assertGreater(state['dropped'], 290)
            self.assertEqual(state['queued'] + state['dropped'], 300)
            self.assertLessEqual((Path(tmp) / 'queue.db').stat().st_size, 128 * 4096)
            q.db.close()

    def test_oversize_event_is_explicit_drop(self):
        with tempfile.TemporaryDirectory() as tmp:
            q = Queue(Path(tmp) / 'queue.db', byte_limit=1)
            q.consent(True)
            self.assertFalse(q.put(event('synthetic-oversize', 1)))
            self.assertEqual(q.status()['dropped'], 1)
            self.assertEqual(q.status()['queued'], 0)
            q.db.close()

    def test_refusal_survives_reopen(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'queue.db'
            q = Queue(path)
            self.assertFalse(q.put(event('synthetic-refused', 1)))
            q.db.close()
            q = Queue(path)
            self.assertEqual(q.status()['consent'], 0)
            self.assertEqual(q.status()['refused'], 1)
            self.assertFalse(q.put(event('synthetic-refused', 2)))
            q.db.close()

    def test_revocation_does_not_resurrect_after_regrant(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'queue.db'
            q = Queue(path)
            q.consent(True)
            q.put(event('synthetic-revoked', 1))
            q.consent(False)
            q.db.close()
            q = Queue(path)
            q.consent(True)
            self.assertEqual(q.status()['queued'], 0)
            self.assertEqual(q.status()['revoked'], 1)
            q.db.close()


if __name__ == '__main__':
    unittest.main()
