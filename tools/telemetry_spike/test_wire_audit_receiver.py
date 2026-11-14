import gzip
import http.client
import json
from pathlib import Path
import tempfile
import threading
import unittest

from probe import event
from wire_audit_receiver import AuditReceiver, LIMIT, TOKEN, audit_payload, decode_body

RUN = 'synthetic-wire-review'
UUID = '01234567-89ab-4cde-8fab-0123456789ab'


def payload():
    return {'api_key': TOKEN, 'sent_at': '2026-11-01T22:00:00Z', 'batch': [{
        'event': 'cm_lab_probe', 'distinct_id': RUN, 'uuid': UUID,
        'timestamp': '2026-11-01T21:59:00Z', 'properties': {
            **event(RUN, 1), '$geoip_disable': True, '$process_person_profile': False}}]}


class WireContractTests(unittest.TestCase):
    def test_exact_final_contract_preserves_id_uuid_and_redacts_token(self):
        result = audit_payload(payload(), RUN)
        self.assertEqual(result['violations'], [])
        self.assertEqual(result['normalized_rows'], [event(RUN, 1)])
        self.assertEqual(result['events'][0]['uuid'], UUID)
        self.assertNotIn(TOKEN, json.dumps(result))

    def test_distinct_id_must_match_run_and_foreign_uuid_is_redacted(self):
        value = payload()
        forbidden_id = '11111111-2222-4333-8444-555555555555'
        value['batch'][0]['distinct_id'] = forbidden_id
        result = audit_payload(value, RUN)
        self.assertIn('event[0]:invalid_distinct_id', result['violations'])
        self.assertNotIn(forbidden_id, json.dumps(result))
        self.assertEqual(result['payload_redacted']['batch'][0]['distinct_id'], '<redacted:str>')
        # Event UUID is a separate transport field; do not require it to equal
        # the run identifier or destroy it while rejecting the identity.
        self.assertEqual(result['events'][0]['uuid'], UUID)
        self.assertEqual(result['payload_redacted']['batch'][0]['uuid'], UUID)
        self.assertEqual(result['normalized_rows'], [event(RUN, 1)])

    def test_native_enrichment_is_a_failure_and_value_never_persisted(self):
        value = payload()
        value['batch'][0]['properties']['$device_name'] = 'DO_NOT_RETAIN_DEVICE_VALUE'
        result = audit_payload(value, RUN)
        self.assertIn('event[0]:unexpected_property:$device_name', result['violations'])
        self.assertNotIn('DO_NOT_RETAIN_DEVICE_VALUE', json.dumps(result))
        self.assertEqual(len(result['normalized_rows']), 1)

    def test_unknown_envelope_and_item_fields_are_not_hidden(self):
        value = payload()
        value['diagnostics'] = {'secret': 'DO_NOT_RETAIN'}
        value['batch'][0]['latitude'] = 12.34
        result = audit_payload(value, RUN)
        self.assertIn('unexpected_envelope_key:diagnostics', result['violations'])
        self.assertIn('event[0]:unexpected_item_key:latitude', result['violations'])
        self.assertNotIn('DO_NOT_RETAIN', json.dumps(result))
        self.assertNotIn('12.34', json.dumps(result))

    def test_real_token_is_rejected_and_never_recorded(self):
        value = payload()
        value['api_key'] = 'phc_REAL_TOKEN_SENTINEL'
        result = audit_payload(value, RUN)
        self.assertEqual(result['normalized_rows'], [])
        self.assertIn('non_fake_token_rejected', result['violations'])
        self.assertNotIn(value['api_key'], json.dumps(result))

    def test_foreign_run_and_automatic_events_cannot_pass(self):
        value = payload()
        value['batch'][0]['properties'].update(event('synthetic-other-run', 1))
        value['batch'].append({'event': '$screen', 'properties': {'name': 'DO_NOT_RETAIN'}})
        result = audit_payload(value, RUN)
        self.assertEqual(result['normalized_rows'], [])
        self.assertIn('event[0]:invalid_business_contract_or_run', result['violations'])
        self.assertIn('event[1]:unexpected_event', result['violations'])
        self.assertNotIn('DO_NOT_RETAIN', json.dumps(result))

    def test_privacy_controls_require_exact_boolean_types(self):
        value = payload()
        value['batch'][0]['properties']['$geoip_disable'] = 1
        self.assertIn('event[0]:invalid_privacy_control:$geoip_disable', audit_payload(value, RUN)['violations'])

    def test_gzip_decoding_is_bounded_and_duplicate_keys_fail(self):
        self.assertEqual(decode_body(gzip.compress(json.dumps(payload()).encode()), 'gzip'), payload())
        with self.assertRaises(ValueError):
            decode_body(gzip.compress(b' ' * (LIMIT + 1)), 'gzip')
        with self.assertRaises(ValueError):
            decode_body(b'{"api_key":"a","api_key":"b"}')
        with self.assertRaises(ValueError):
            decode_body(b'{"a":NaN}')
        with self.assertRaises(ValueError):
            decode_body(b' ' * (LIMIT + 1))


class WireHTTPTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.receiver = None
        self.thread = None

    def tearDown(self):
        if self.receiver:
            self.receiver.server.shutdown()
            self.thread.join(timeout=5)
            self.receiver.close()
        self.temp.cleanup()

    def start(self, mode='normal'):
        self.out = Path(self.temp.name) / 'new-run'
        self.receiver = AuditReceiver(self.out, RUN, mode, port=0)
        self.thread = threading.Thread(target=self.receiver.server.serve_forever, daemon=True)
        self.thread.start()

    def request(self, value=None, path='/batch/', method='POST', extra_headers=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.receiver.server.server_port, timeout=5)
        body = json.dumps(value if value is not None else payload()).encode()
        headers = {'Content-Type': 'application/json', **(extra_headers or {})}
        try:
            connection.request(method, path, body, headers)
            result = connection.getresponse()
            result.read()
            return result.status
        finally:
            connection.close()

    def records(self):
        return [json.loads(line) for line in (self.out / 'requests.jsonl').read_text().splitlines()]

    def test_empty_receiver_is_not_a_pass_and_valid_request_changes_status(self):
        self.start()
        initial = json.loads((self.out / 'summary.json').read_text())
        self.assertEqual(initial['requests'], 0)
        self.assertIsNone(initial['audit_pass'])
        self.assertEqual(initial['audit_status'], 'NOT_RUN')
        self.assertEqual(self.request(), 200)
        observed = json.loads((self.out / 'summary.json').read_text())
        self.assertEqual(observed['requests'], 1)
        self.assertTrue(observed['audit_pass'])
        self.assertEqual(observed['audit_status'], 'PASS')

    def test_200_does_not_conceal_privacy_failure(self):
        self.start()
        value = payload()
        value['batch'][0]['properties']['name'] = 'NEVER_STORE_NAME'
        self.assertEqual(self.request(value), 200)
        self.assertFalse(self.records()[0]['audit_pass'])
        self.assertFalse(json.loads((self.out / 'summary.json').read_text())['audit_pass'])
        self.assertNotIn('NEVER_STORE_NAME', (self.out / 'requests.jsonl').read_text())

    def test_forbidden_distinct_id_fails_audit_without_retaining_value(self):
        self.start()
        value = payload()
        forbidden_id = '11111111-2222-4333-8444-555555555555'
        value['batch'][0]['distinct_id'] = forbidden_id
        self.assertEqual(self.request(value), 200)
        record = self.records()[0]
        self.assertIn('event[0]:invalid_distinct_id', record['violations'])
        self.assertFalse(record['audit_pass'])
        summary = json.loads((self.out / 'summary.json').read_text())
        self.assertFalse(summary['audit_pass'])
        self.assertEqual(summary['audit_status'], 'FAIL')
        self.assertEqual(summary['distinct_id_policy'], 'exact_synthetic_run_id_only')
        for filename in ('requests.jsonl', 'received.jsonl', 'summary.json'):
            self.assertNotIn(forbidden_id, (self.out / filename).read_text())
        self.assertEqual(record['events'][0]['uuid'], UUID)

    def test_record_then_disconnect_retries_preserve_duplicates_and_uuid(self):
        self.start('close-first')
        with self.assertRaises(http.client.RemoteDisconnected):
            self.request()
        self.assertEqual(self.request(), 200)
        records = self.records()
        self.assertIsNone(records[0]['response_status'])
        self.assertEqual(records[0]['response_mode'], 'close_without_response_after_fsync')
        self.assertEqual([r['events'][0]['uuid'] for r in records], [UUID, UUID])
        rows = (self.out / 'received.jsonl').read_text().splitlines()
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0], rows[1])

    def test_503_is_separate_from_missing_ack(self):
        self.start('503-first')
        self.assertEqual(self.request(), 503)
        self.assertEqual(self.request(), 200)
        self.assertEqual(self.records()[0]['response_mode'], 'http_response')

    def test_unknown_path_query_and_secret_headers_are_visible_but_redacted(self):
        self.start()
        self.assertEqual(self.request(path='/flags/?token=DO_NOT_RETAIN', method='GET',
                                      extra_headers={'Authorization': 'DO_NOT_RETAIN_AUTH'}), 200)
        record = self.records()[0]
        self.assertIn('unexpected_method_path_or_query', record['violations'])
        self.assertIn('unexpected_header:authorization', record['violations'])
        self.assertEqual(record['query_keys'], ['token'])
        self.assertNotIn('DO_NOT_RETAIN', json.dumps(record))

    def test_known_header_cannot_smuggle_arbitrary_secret_value(self):
        self.start()
        self.assertEqual(self.request(extra_headers={'Accept': 'DO_NOT_RETAIN'}), 200)
        record = self.records()[0]
        self.assertIn('unapproved_header_value:accept', record['violations'])
        self.assertNotIn('DO_NOT_RETAIN', json.dumps(record))

    def test_existing_output_directory_refused(self):
        self.start()
        with self.assertRaises(FileExistsError):
            AuditReceiver(self.out, RUN, port=0)

    def test_non_synthetic_run_refused_before_creating_output(self):
        target = Path(self.temp.name) / 'must-not-exist'
        with self.assertRaises(ValueError):
            AuditReceiver(target, 'real-person-name', port=0)
        self.assertFalse(target.exists())


if __name__ == '__main__':
    unittest.main()
