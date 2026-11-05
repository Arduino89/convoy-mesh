"""Offline host regressions for stage evidence and private provisioning failures.

All command results are simulated. No Android process, network or real credential
is used. Stage receipts must never contain the simulated sensitive output.
"""
import json
from contextlib import redirect_stdout
from datetime import datetime
import hashlib
import io
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import ci_cloud_trial as cloud
from ci_provision_probe import emit_result
from ci_cloud_trial import (CloudDevice, TrialBlocked, parse_budget_database,
                            sanitize_preparation_error, unknown_budget_receipt)


class CloudPreparationEvidence(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.device = CloudDevice(Path('/synthetic-sdk'), 'emulator-5554', {}, {})
        self.device.preparation_path = self.directory / 'preparation.jsonl'
        self.device.pid = Mock(return_value=None)
        self.canary = 'phc_HostOnlyCanaryDoNotExport123'
        self.private = json.dumps({'api_key': self.canary}).encode()

    def receipts(self):
        return [json.loads(line) for line in self.device.preparation_path.read_text().splitlines() if line]

    def assert_safe_receipt(self, record, phase, returncode):
        self.assertEqual(set(record), {'schema_version', 'observed_utc', 'phase', 'returncode', 'error_category',
                                       'stdout_present', 'stderr_present'})
        self.assertIsNotNone(datetime.fromisoformat(record['observed_utc'].replace('Z', '+00:00')).tzinfo)
        self.assertEqual(record['schema_version'], 1)
        self.assertEqual(record['phase'], phase)
        self.assertEqual(record['returncode'], returncode)
        self.assertIs(type(record['stdout_present']), bool)
        self.assertIs(type(record['stderr_present']), bool)
        self.assertRegex(record['error_category'], r'^[A-Z][A-Z0-9_]{0,79}$')
        self.assertNotIn(self.canary, json.dumps(record))
        self.assertNotIn('person@example.invalid', json.dumps(record))
        self.assertNotIn('https://example.invalid/private', json.dumps(record))

    def test_mkdir_nonzero_identifies_failed_stage_without_exposing_stderr(self):
        def failed_call(*args, **kwargs):
            if kwargs.get('allow_failure'):
                return subprocess.CompletedProcess(args, 17, '', self.canary + ' person@example.invalid')
            raise TrialBlocked('COMMAND_NONZERO_EXIT')
        self.device.call = Mock(side_effect=failed_call)
        with patch('ci_cloud_trial.subprocess.run') as writer:
            with self.assertRaisesRegex(TrialBlocked, '^CLOUD_PRIVATE_MKDIR_NONZERO_EXIT$'):
                self.device.provision(self.private)
            writer.assert_not_called()
        records = self.receipts()
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]['phase'], 'PRIVATE_MKDIR')
        self.assertEqual(records[0]['returncode'], 17)
        public = json.dumps(records)
        self.assertNotIn(self.canary, public)
        self.assertNotIn('person@example.invalid', public)

    def test_prepare_call_nonzero_records_stage_exit_and_redacted_error(self):
        tainted = self.canary + ' person@example.invalid https://example.invalid/private'
        response = subprocess.CompletedProcess(['private-argument-' + self.canary], 23, tainted, tainted)
        with patch('ci_native_trial.subprocess.run', return_value=response):
            with self.assertRaisesRegex(TrialBlocked, '^CLOUD_PRIVATE_STAT_NONZERO_EXIT$'):
                self.device.prepare_call('PRIVATE_STAT', 'shell', 'run-as', 'synthetic-package', 'stat')
        record = self.receipts()[0]
        self.assert_safe_receipt(record, 'PRIVATE_STAT', 23)
        self.assertIs(record['stdout_present'], True)
        self.assertIs(record['stderr_present'], True)

    def test_prepare_call_timeout_and_unavailable_do_not_emit_exception_text(self):
        faults = [
            ('TIMEOUT', subprocess.TimeoutExpired(['private-' + self.canary], 45,
                                                output=self.canary.encode(), stderr=self.canary.encode())),
            ('UNAVAILABLE', OSError(self.canary + ' person@example.invalid')),
        ]
        for label, error in faults:
            with self.subTest(error=label):
                self.device.preparation_path.unlink(missing_ok=True)
                with patch('ci_native_trial.subprocess.run', side_effect=error):
                    with self.assertRaisesRegex(TrialBlocked, '^CLOUD_PRIVATE_STAT_' + label + '$'):
                        self.device.prepare_call('PRIVATE_STAT', 'shell', 'run-as', 'synthetic-package', 'stat')
                self.assert_safe_receipt(self.receipts()[0], 'PRIVATE_STAT', None)

    def test_unknown_phase_never_runs_a_command_or_creates_public_tainted_code(self):
        with patch('ci_native_trial.subprocess.run') as command:
            with self.assertRaises(TrialBlocked):
                self.device.prepare_call('UNTRUSTED_' + self.canary, 'shell', 'true')
            command.assert_not_called()
        if self.device.preparation_path.exists():
            self.assertNotIn(self.canary, self.device.preparation_path.read_text())

    def test_failed_install_requests_cleanup_without_claiming_install_confirmation(self):
        apk = self.directory / 'synthetic.apk'; apk.write_bytes(b'not-executed-apk-fixture')
        failure = subprocess.CompletedProcess([], 19, '', 'Failure [' + self.canary + ']')
        with patch('ci_native_trial.subprocess.run', return_value=failure):
            with self.assertRaisesRegex(TrialBlocked, '^CLOUD_INSTALL_APK_NONZERO_EXIT$'):
                self.device.install(apk)
        self.assertIs(self.device.cleanup_required, True)
        self.assertIs(self.device.install_confirmed, False)
        self.assert_safe_receipt(self.receipts()[0], 'INSTALL_APK', 19)

    def test_zero_exit_without_success_is_not_confirmed_installation(self):
        apk = self.directory / 'synthetic.apk'; apk.write_bytes(b'not-executed-apk-fixture')
        with patch('ci_native_trial.subprocess.run', return_value=subprocess.CompletedProcess([], 0, '', '')) as command:
            with self.assertRaisesRegex(TrialBlocked, '^CLOUD_INSTALL_APK_OUTPUT_REJECTED$'):
                self.device.install(apk)
        self.assertIs(self.device.cleanup_required, True)
        self.assertIs(self.device.install_confirmed, False)
        self.assertEqual(command.call_count, 1)

    def test_install_success_still_requires_package_verification(self):
        apk = self.directory / 'synthetic.apk'; apk.write_bytes(b'not-executed-apk-fixture')
        responses = [subprocess.CompletedProcess([], 0, 'Success\n', ''),
                     subprocess.CompletedProcess([], 31, '', self.canary)]
        with patch('ci_native_trial.subprocess.run', side_effect=responses):
            with self.assertRaisesRegex(TrialBlocked, '^CLOUD_INSTALL_VERIFY_NONZERO_EXIT$'):
                self.device.install(apk)
        self.assertIs(self.device.cleanup_required, True)
        self.assertIs(self.device.install_confirmed, False)
        self.assert_safe_receipt(self.receipts()[-1], 'INSTALL_VERIFY', 31)

    def test_install_success_and_package_path_confirm_only_the_install(self):
        apk = self.directory / 'synthetic.apk'; apk.write_bytes(b'not-executed-apk-fixture')
        responses = [subprocess.CompletedProcess([], 0, 'Success\n', ''),
                     subprocess.CompletedProcess([], 0, 'package:/data/app/synthetic/base.apk\n', '')]
        with patch('ci_native_trial.subprocess.run', side_effect=responses):
            self.device.install(apk)
        self.assertIs(self.device.cleanup_required, True)
        self.assertIs(self.device.install_confirmed, True)
        self.assertIs(self.device.provision_confirmed, False)
        self.assertEqual([r['phase'] for r in self.receipts()], ['INSTALL_APK', 'INSTALL_VERIFY'])

    def provision_responses(self, stat_code=0, mode='600\n', copied=None):
        return [subprocess.CompletedProcess([], 0, '', ''),
                subprocess.CompletedProcess([], 0, b'', b''),
                subprocess.CompletedProcess([], stat_code, mode, '' if not stat_code else self.canary),
                subprocess.CompletedProcess([], 0, self.private.decode() if copied is None else copied, '')]

    def test_stat_failure_after_private_write_preserves_partial_state_and_phase(self):
        with patch('ci_cloud_trial.subprocess.run', side_effect=self.provision_responses(stat_code=42)):
            with self.assertRaisesRegex(TrialBlocked, '^CLOUD_PRIVATE_STAT_NONZERO_EXIT$'):
                self.device.provision(self.private)
        self.assertIs(self.device.config_write_confirmed, True)
        self.assertIs(self.device.provision_confirmed, False)
        self.assert_safe_receipt(self.receipts()[-1], 'PRIVATE_STAT', 42)

    def test_private_write_failure_does_not_reach_stat_or_claim_write(self):
        responses = [subprocess.CompletedProcess([], 0, '', ''),
                     subprocess.CompletedProcess([], 29, b'', self.canary.encode())]
        with patch('ci_cloud_trial.subprocess.run', side_effect=responses) as command:
            with self.assertRaisesRegex(TrialBlocked, '^CLOUD_PRIVATE_WRITE_NONZERO_EXIT$'):
                self.device.provision(self.private)
        self.assertEqual(command.call_count, 2)
        self.assertIs(self.device.config_write_confirmed, False)
        self.assertIs(self.device.provision_confirmed, False)
        self.assert_safe_receipt(self.receipts()[-1], 'PRIVATE_WRITE', 29)

    def test_wrong_mode_and_readback_mismatch_remain_blocked_on_zero_exit(self):
        for label, responses in [('PRIVATE_STAT', self.provision_responses(mode='644\n')),
                                 ('PRIVATE_VERIFY', self.provision_responses(copied='changed-private-file'))]:
            with self.subTest(phase=label):
                self.device.preparation_path.unlink(missing_ok=True)
                with patch('ci_cloud_trial.subprocess.run', side_effect=responses):
                    with self.assertRaisesRegex(TrialBlocked, '^CLOUD_' + label + '_OUTPUT_REJECTED$'):
                        self.device.provision(self.private)
                self.assertIs(self.device.config_write_confirmed, True)
                self.assertIs(self.device.provision_confirmed, False)
                self.assert_safe_receipt(self.receipts()[-1], label, 0)
                self.assertEqual(self.receipts()[-1]['error_category'], 'OUTPUT_REJECTED')

    def test_successful_provision_confirms_byte_equality_without_exporting_private_content(self):
        with patch('ci_cloud_trial.subprocess.run', side_effect=self.provision_responses()):
            self.device.provision(self.private)
        self.assertIs(self.device.config_write_confirmed, True)
        self.assertIs(self.device.provision_confirmed, True)
        self.assertEqual([r['phase'] for r in self.receipts()],
                         ['PRIVATE_MKDIR', 'PRIVATE_WRITE', 'PRIVATE_STAT', 'PRIVATE_VERIFY'])
        self.assertNotIn(self.canary, self.device.preparation_path.read_text())

    def test_known_and_unknown_diagnostics_return_only_public_categories(self):
        for text, expected in [('No such file or directory ' + self.canary, 'FILE_NOT_FOUND'),
                               ('Permission denied person@example.invalid', 'PERMISSION_DENIED'),
                               ('INSTALL_FAILED_UPDATE_INCOMPATIBLE ' + self.canary, 'INSTALL_FAILED_UPDATE_INCOMPATIBLE'),
                               (self.canary + ' https://example.invalid/private', 'OUTPUT_WITHHELD')]:
            with self.subTest(category=expected):
                self.assertEqual(sanitize_preparation_error(text), expected)


class CloudBudgetRecovery(unittest.TestCase):
    run_id = 'synthetic-cloud-budget-host'
    binding = 'a' * 64

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / 'synthetic_telemetry.db'

    def database(self, **changes):
        values = {'run_id': self.run_id, 'transport_mode': 'posthog_cloud', 'cloud_binding': self.binding,
                  'cloud_rows_reserved': '150', 'dispatch_attempts': '9', 'cloud_rows_written': '130',
                  'requests_started': '8', 'requests_acked': '7',
                  'unrelated_private_value': 'phc_NotARealSecretDoNotPublish123'}
        values.update(changes)
        self.path.unlink(missing_ok=True)
        with sqlite3.connect(self.path) as db:
            db.execute('CREATE TABLE state (key TEXT PRIMARY KEY, value TEXT NOT NULL)')
            db.executemany('INSERT INTO state VALUES (?,?)', values.items())
        return self.path

    def read(self):
        return parse_budget_database(self.path, self.run_id, self.binding, 500)

    def test_committed_ledger_distinguishes_reservations_writes_ack_and_unknown_cloud_receipt(self):
        self.database()
        before = hashlib.sha256(self.path.read_bytes()).hexdigest()
        result = self.read()
        self.assertEqual(result['status'], 'OBSERVED_COMMITTED_LAB_LEDGER')
        self.assertEqual([result[k] for k in ('reserved_rows', 'reserved_attempts', 'body_written_rows',
                                             'body_written_requests', 'acknowledged_requests')], [150, 9, 130, 8, 7])
        self.assertIsNone(result['cloud_received_rows'])
        self.assertIs(result['automatic_refund_allowed'], False)
        self.assertEqual(hashlib.sha256(self.path.read_bytes()).hexdigest(), before)
        self.assertNotIn(self.binding, json.dumps(result))
        self.assertNotIn('phc_NotARealSecretDoNotPublish123', json.dumps(result))

    def test_zero_observed_ledger_never_refunds_the_existing_authorization(self):
        self.database(cloud_rows_reserved='0', dispatch_attempts='0', cloud_rows_written='0',
                      requests_started='0', requests_acked='0')
        observed = self.read()
        self.assertEqual(observed['reserved_rows'], 0)
        self.assertIsNone(observed['cloud_received_rows'])
        unknown = unknown_budget_receipt(self.run_id, 'b' * 40, 500)
        self.assertEqual(unknown['conservative_consumed_for_future_launches'], 500)
        self.assertEqual(unknown['remaining_for_future_launches'], 0)
        self.assertIs(unknown['automatic_refund_allowed'], False)

    def test_missing_database_is_unknown_not_an_empty_ledger(self):
        with self.assertRaises(TrialBlocked):
            self.read()
        unknown = unknown_budget_receipt(self.run_id, 'b' * 40)
        for key in ('reserved_rows', 'reserved_attempts', 'body_written_rows', 'body_written_requests',
                    'acknowledged_requests', 'cloud_received_rows'):
            self.assertIsNone(unknown[key])
        self.assertEqual(unknown['remaining_for_future_launches'], 0)

    def test_malformed_database_never_exposes_its_content_in_error(self):
        canary = 'phc_InvalidPrivateDatabaseCanary123'
        self.path.write_text(canary)
        with self.assertRaisesRegex(TrialBlocked, '^BUDGET_DATABASE_INVALID$'):
            self.read()

    def test_foreign_run_mode_or_binding_is_rejected(self):
        for changes in ({'run_id':'synthetic-other'}, {'transport_mode':'local'}, {'cloud_binding':'c'*64}):
            with self.subTest(keys=sorted(changes)):
                self.database(**changes)
                with self.assertRaisesRegex(TrialBlocked, '^BUDGET_DATABASE_BINDING_OR_SCHEMA_INVALID$'):
                    self.read()

    def test_missing_counter_is_not_defaulted_to_zero(self):
        self.database()
        with sqlite3.connect(self.path) as db:
            db.execute("DELETE FROM state WHERE key='cloud_rows_reserved'")
        with self.assertRaises(TrialBlocked):
            self.read()

    def test_bad_or_inconsistent_counters_are_rejected(self):
        fixtures = [{'cloud_rows_reserved':value} for value in ('-1', 'true', '1.5', '01', '501')]
        fixtures += [{'cloud_rows_written':'151'}, {'dispatch_attempts':'151'},
                     {'requests_started':'10'}, {'requests_acked':'9'}]
        for changes in fixtures:
            with self.subTest(changes=changes):
                self.database(**changes)
                with self.assertRaisesRegex(TrialBlocked, '^BUDGET_DATABASE_COUNTER_INVALID$'):
                    self.read()

    def test_counter_checkpoint_between_write_markers_is_observed_without_claiming_cloud_receipt(self):
        # Native requests_started and cloud_rows_written use separate updates;
        # interruption between them must not fabricate an exact transmitted count.
        self.database(cloud_rows_reserved='20', dispatch_attempts='1', cloud_rows_written='0',
                      requests_started='1', requests_acked='0')
        observed = self.read()
        self.assertEqual(observed['body_written_requests'], 1)
        self.assertEqual(observed['body_written_rows'], 0)
        self.assertIn('UNDERCOUNT', observed['body_written_counter_limit'])
        self.assertIsNone(observed['cloud_received_rows'])
        self.assertIs(observed['automatic_refund_allowed'], False)


class CloudPreparationMainIntegration(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.out = self.directory / 'public'
        self.source = 'b' * 40
        self.run_id = 'synthetic-cloud-main-host'
        self.gate = self.directory / 'gate.json'
        self.gate.write_text('{}')
        self.runtime = self.directory / 'runtime.json'
        self.runtime.write_text(json.dumps({'boot_id':'00000000-0000-0000-0000-000000000001',
                                           'status':'PASS_NATIVE_RUNTIME_CONTROL'}))
        self.argv = ['ci_cloud_trial.py']
        values = {'sdk':self.directory/'sdk', 'jdk':self.directory/'jdk', 'apk':self.directory/'synthetic.apk',
                  'build-receipt':self.directory/'build.json', 'runtime-gate':self.runtime,
                  'cloud-gate':self.gate, 'private-config':self.directory/'config.private.json', 'out':self.out,
                  'source-commit':self.source, 'run-id':self.run_id, 'serial':'emulator-5554',
                  'execution-id':'Isolated Android telemetry laboratory:1', 'run-attempt':'1'}
        for key, value in values.items():
            self.argv.extend(['--'+key, str(value)])

    def test_invalid_gate_keeps_unknown_budget_receipt_before_any_device_command(self):
        with patch('sys.argv', self.argv), patch('ci_cloud_trial.CloudDevice') as device, \
                patch('ci_cloud_trial.subprocess.run') as command, redirect_stdout(io.StringIO()):
            self.assertEqual(cloud.main(), 1)
        device.assert_not_called()
        command.assert_not_called()
        receipt = json.loads((self.out/'budget-recovery.json').read_text())
        self.assertEqual(receipt['status'], 'UNKNOWN_BLOCK_FUTURE_SENDS')
        self.assertIsNone(receipt['reserved_rows'])
        self.assertEqual(receipt['conservative_consumed_for_future_launches'], 500)
        self.assertEqual(receipt['remaining_for_future_launches'], 0)
        self.assertIs(receipt['automatic_refund_allowed'], False)

    def simulate_stat_failure(self, remove_fails=False):
        canary = 'phc_MainIntegrationCanaryDoNotExport123'
        private = json.dumps({'api_key':canary}).encode()
        gate = {name:{'status':'VERIFIED', 'checked_at_utc':'2026-11-05T12:00:00+00:00',
                      'evidence_ref':'synthetic-host-fixture'} for name in cloud.CONTROLS}
        self.gate.write_text(json.dumps(gate))
        device = CloudDevice(self.directory/'sdk', 'emulator-5554', {}, {})
        device.pid = Mock(return_value=None)
        device.check_gate = Mock()
        device.command = Mock(side_effect=AssertionError('No app launch or capture is allowed'))
        installed = False

        def call(*args, **kwargs):
            nonlocal installed
            if args[0] == 'install':
                installed = True
                return subprocess.CompletedProcess(args, 0, 'Success\n', '')
            if args[:3] == ('shell','pm','path'):
                return subprocess.CompletedProcess(args, 0 if installed else 1,
                                                    'package:/data/app/synthetic/base.apk\n' if installed else '', '')
            if args[:4] == ('shell','settings','get','global'):
                return subprocess.CompletedProcess(args, 0, '0\n' if args[-1]=='airplane_mode_on' else '1\n', '')
            if 'stat' in args:
                return subprocess.CompletedProcess(args, 42, '', 'No such file or directory '+canary)
            if remove_fails and args[:2]==('shell','run-as') and 'rm' in args:
                return subprocess.CompletedProcess(args, 37, '', 'Permission denied '+canary)
            return subprocess.CompletedProcess(args, 0, '', '')

        device.call = Mock(side_effect=call)
        device.recover_budget = Mock(return_value={'status':'OBSERVED_COMMITTED_LAB_LEDGER',
            'reserved_rows':20, 'reserved_attempts':1, 'body_written_rows':0, 'body_written_requests':0,
            'acknowledged_requests':0, 'cloud_received_rows':None, 'automatic_refund_allowed':False})
        device.private_rows = Mock(side_effect=TrialBlocked('NATIVE_CLOUD_RECEIPTS_UNAVAILABLE_OR_TOO_LARGE'))
        writer = subprocess.CompletedProcess([], 0, b'', b'')
        with patch('sys.argv', self.argv), patch('ci_cloud_trial.CloudDevice', return_value=device), \
                patch('ci_cloud_trial.validate_cloud_gate', return_value=500), \
                patch('ci_cloud_trial.read_private_config', return_value=private), \
                patch('ci_cloud_trial.verify_apk', return_value={'source_commit':self.source}), \
                patch('ci_cloud_trial.run_cases') as cases, \
                patch('ci_cloud_trial.subprocess.run', return_value=writer), \
                patch.dict('os.environ', {'GITHUB_RUN_ATTEMPT':'1'}), redirect_stdout(io.StringIO()):
            self.assertEqual(cloud.main(), 1)
        cases.assert_not_called()
        device.command.assert_not_called()
        device.recover_budget.assert_called_once()
        result = json.loads((self.out/'result.json').read_text())
        self.assertEqual(result['blocked_reason'], 'CLOUD_PRIVATE_STAT_NONZERO_EXIT')
        self.assertIs(result['cleanup']['cleanup_required'], True)
        self.assertIs(result['cleanup']['installation_confirmed'], True)
        self.assertIs(result['cleanup']['configuration_write_confirmed'], True)
        self.assertIs(result['cleanup']['provisioned'], False)
        self.assertIs(result['cleanup']['lab_stopped'], True)
        self.assertIs(result['cleanup']['private_config_removed'], not remove_fails)
        receipt = json.loads((self.out/'budget-recovery.json').read_text())
        self.assertEqual(receipt['reserved_rows'], 20)
        self.assertIsNone(receipt['cloud_received_rows'])
        self.assertEqual(receipt['conservative_consumed_for_future_launches'], 500)
        self.assertEqual(receipt['remaining_for_future_launches'], 0)
        self.assertIs(receipt['automatic_refund_allowed'], False)
        public = '\n'.join(path.read_text() for path in self.out.iterdir() if path.is_file())
        self.assertNotIn(canary, public)
        self.assertNotIn('No such file or directory', public)
        return device, result

    def test_stat_failure_after_write_still_cleans_and_recovers_without_successful_provision(self):
        self.simulate_stat_failure()

    def test_cleanup_failure_preserves_primary_error_and_budget_without_restoring_network(self):
        device, result = self.simulate_stat_failure(remove_fails=True)
        self.assertEqual(result['blocked_reason'], 'CLOUD_PRIVATE_STAT_NONZERO_EXIT')
        self.assertEqual(result['cleanup_error'], 'CLOUD_PRIVATE_CLEANUP_NOT_ATTESTED')
        self.assertIs(result['cleanup']['initial_radio_settings_restored'], False)
        self.assertEqual(result['radio_cleanup_error'], 'LEFT_OFFLINE_BECAUSE_STOP_OR_PRIVATE_CLEANUP_UNATTESTED')
        calls = [tuple(call.args) for call in device.call.call_args_list]
        for forbidden in [('shell','cmd','connectivity','airplane-mode','disable'),
                          ('shell','svc','wifi','enable'), ('shell','svc','data','enable')]:
            self.assertNotIn(forbidden, calls)
        for required in [('shell','cmd','connectivity','airplane-mode','enable'),
                         ('shell','svc','wifi','disable'), ('shell','svc','data','disable')]:
            self.assertIn(required, calls)


class ProvisionEvidenceExport(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / 'result.json'
        self.scope = 'OFFLINE_FAKE_PROVISION_DIAGNOSTIC_NO_LAB_LAUNCH_NO_CLOUD'

    def test_duplicate_field_cannot_hide_credential_in_exported_raw_bytes(self):
        self.path.write_text('{"scope":'+json.dumps(self.scope)+
                             ',"detail":"phc_DuplicateFieldCanaryNotReal123","detail":"synthetic-safe"}')
        output = io.StringIO()
        with redirect_stdout(output), self.assertRaises((TrialBlocked, ValueError)):
            emit_result(self.path)
        self.assertEqual(output.getvalue(), '')

    def test_nonfinite_numbers_and_visible_sensitive_values_emit_nothing(self):
        cases = ['{"scope":'+json.dumps(self.scope)+',"value":'+value+'}'
                 for value in ('NaN', 'Infinity', '-Infinity', '"phc_VisibleCanaryNotReal123"')]
        for index, content in enumerate(cases):
            with self.subTest(case=index):
                self.path.write_text(content)
                output = io.StringIO()
                with redirect_stdout(output), self.assertRaises((TrialBlocked, ValueError)):
                    emit_result(self.path)
                self.assertEqual(output.getvalue(), '')


if __name__ == '__main__':
    unittest.main()
