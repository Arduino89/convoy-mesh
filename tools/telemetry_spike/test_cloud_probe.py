import unittest

from cloud_probe import payload
from probe import event


class CloudPayloadControls(unittest.TestCase):
    def setUp(self):
        self.config = {'project_id': 330212, 'POSTHOG_HOST': 'https://eu.i.posthog.com',
                       'POSTHOG_PROJECT_TOKEN': 'phc_unit_test_fixture'}
        self.rows = [event('synthetic-cloud-unit', 1)]

    def test_every_row_disables_geoip_and_person_profiles(self):
        row = payload(self.rows, self.config, 330212)['batch'][0]
        self.assertEqual(row['distinct_id'], 'synthetic-cloud-unit')
        self.assertIs(row['properties']['$geoip_disable'], True)
        self.assertIs(row['properties']['$process_person_profile'], False)
        self.assertEqual(row['properties']['event_id'], self.rows[0]['event_id'])

    def test_mismatched_project_does_not_produce_payload(self):
        with self.assertRaises(ValueError):
            payload(self.rows, self.config, 1)

    def test_non_eu_host_is_rejected(self):
        with self.assertRaises(ValueError):
            payload(self.rows, dict(self.config, POSTHOG_HOST='https://us.i.posthog.com'), 330212)

    def test_unlisted_personal_field_is_rejected(self):
        with self.assertRaises(ValueError):
            payload([{**self.rows[0], 'name': 'synthetic fixture'}], self.config, 330212)

    def test_mixed_runs_cannot_be_mistaken_for_one_case(self):
        with self.assertRaises(ValueError):
            payload(self.rows + [event('synthetic-another-run', 1)], self.config, 330212)

    def test_request_budget_is_bounded(self):
        with self.assertRaises(ValueError):
            payload(self.rows * 1001, self.config, 330212)


if __name__ == '__main__':
    unittest.main()
