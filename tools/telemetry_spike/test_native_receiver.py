import unittest

from native_receiver import normalize
from probe import event


class NativeReceiptControls(unittest.TestCase):
    def fixture(self):
        row = event('synthetic-native-parser', 1)
        return row, {'api_key': 'phc_synthetic_local_only', 'batch': [
            {'event': 'cm_lab_probe', 'properties': dict(row, sdk_extra='not-persisted')}]}

    def test_receipt_preserves_ids_but_omits_native_metadata_values(self):
        row, payload = self.fixture()
        self.assertEqual(normalize(payload), ([row], ['sdk_extra']))

    def test_non_local_token_is_rejected(self):
        _, payload = self.fixture()
        payload['api_key'] = 'not-a-local-test-token'
        with self.assertRaises(ValueError):
            normalize(payload)

    def test_empty_batch_is_not_a_successful_delivery(self):
        _, payload = self.fixture()
        payload['batch'] = []
        with self.assertRaises(ValueError):
            normalize(payload)

    def test_unexpected_event_invalidates_entire_batch(self):
        row, payload = self.fixture()
        payload['batch'].append({'event': 'unexpected', 'properties': row})
        with self.assertRaises(ValueError):
            normalize(payload)


if __name__ == '__main__':
    unittest.main()
