import unittest

from run_native_followup import RUNTIME_STAGES, validate_runtime_gate


class NativeFollowupGateTests(unittest.TestCase):
    serial = 'emulator-5554'
    boot = '11111111-2222-4333-8444-555555555555'

    def receipt(self):
        stages = [{'name': name, 'pass': True} for name in RUNTIME_STAGES]
        for index, pid, nonce, launches in ((3, 123, 'a' * 32, 1), (5, 124, 'b' * 32, 2)):
            stages[index]['observation'] = {
                'schema_version': 1, 'package': 'com.cama.telemetry.runtime_control',
                'ready': True, 'nonce': nonce, 'pid': pid, 'launches': launches}
        return {'schema_version': 1, 'status': 'PASS_NATIVE_RUNTIME_CONTROL',
                'scope': 'NATIVE_RUNTIME_CONTROL_ONLY',
                'gate_pass': True, 'telemetry_tested': False,
                'serial': self.serial, 'boot_id': self.boot,
                'stages': stages, 'apk_sha256': 'a' * 64,
                'identity': {'package': 'com.cama.telemetry.runtime_control',
                             'requested_permissions': [], 'min_sdk': 24, 'target_sdk': 36,
                             'version_code': 1, 'version_name': '1.0'}}

    def test_matching_native_control_allows_phase(self):
        validate_runtime_gate(self.receipt(), self.serial, self.boot)

    def test_missing_failed_or_python_only_receipt_cannot_pass(self):
        invalid = [{}, {**self.receipt(), 'gate_pass': False},
                   {**self.receipt(), 'status': 'PYTHON_TESTS_PASS'},
                   {**self.receipt(), 'telemetry_tested': True}]
        for receipt in invalid:
            with self.subTest(receipt=receipt), self.assertRaises(RuntimeError):
                validate_runtime_gate(receipt, self.serial, self.boot)

    def test_different_emulator_cannot_reuse_success(self):
        with self.assertRaises(RuntimeError):
            validate_runtime_gate(self.receipt(), 'emulator-5556', self.boot)

    def test_pass_label_without_all_native_observations_is_rejected(self):
        receipt = self.receipt()
        receipt['stages'] = receipt['stages'][:-1]
        with self.assertRaises(RuntimeError):
            validate_runtime_gate(receipt, self.serial, self.boot)
        receipt = self.receipt()
        receipt['stages'][3]['pass'] = False
        with self.assertRaises(RuntimeError):
            validate_runtime_gate(receipt, self.serial, self.boot)

    def test_physical_serial_cannot_use_emulator_gate(self):
        with self.assertRaises(RuntimeError):
            validate_runtime_gate({**self.receipt(), 'serial': 'physical-device'},
                                  'physical-device', self.boot)

    def test_complete_labels_without_identity_and_restart_evidence_are_rejected(self):
        for change in ('missing_observation', 'same_pid', 'cleared_counter', 'wrong_package', 'missing_hash'):
            receipt = self.receipt()
            if change == 'missing_observation':
                del receipt['stages'][3]['observation']
            elif change == 'same_pid':
                receipt['stages'][5]['observation']['pid'] = 123
            elif change == 'cleared_counter':
                receipt['stages'][5]['observation']['launches'] = 1
            elif change == 'wrong_package':
                receipt['identity']['package'] = 'com.example.convoy_mesh'
            else:
                del receipt['apk_sha256']
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                validate_runtime_gate(receipt, self.serial, self.boot)

    def test_reboot_requires_new_control(self):
        with self.assertRaises(RuntimeError):
            validate_runtime_gate(self.receipt(), self.serial,
                                  'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee')


if __name__ == '__main__':
    unittest.main()
