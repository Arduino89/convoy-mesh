"""Host-only anti-false-PASS checks. No Android build, ADB or SDK is executed."""
import json
from pathlib import Path
import tempfile
import unittest

from runtime_control.build import GateError, PACKAGE, sha256, valid_sdk_bounds
from runtime_control.smoke import (activity_resumed, parse_pid, validate_boot_id,
                                   validate_ready, validate_serial, validate_transition,
                                   verify_build_receipt)


class RuntimeControlGuards(unittest.TestCase):
    def test_current_aapt2_sdk_labels_preserve_exact_bounds(self):
        observed = "minSdkVersion:'24'\ntargetSdkVersion:'36'\n"
        self.assertTrue(valid_sdk_bounds(observed))
        self.assertTrue(valid_sdk_bounds(observed.replace('minSdkVersion', 'sdkVersion')))
        self.assertFalse(valid_sdk_bounds(observed.replace("'24'", "'23'")))
        self.assertFalse(valid_sdk_bounds(observed.replace("'36'", "'35'")))
        self.assertFalse(valid_sdk_bounds("targetSdkVersion:'36'\n"))

    def ready(self, **updates):
        result = {"schema_version": 1, "package": PACKAGE, "nonce": "a" * 32,
                  "pid": 123, "launches": 4, "ready": True}
        result.update(updates)
        return result

    def test_physical_and_network_serials_refused(self):
        self.assertEqual(validate_serial("emulator-5554"), "emulator-5554")
        for serial in ("", "device123", "127.0.0.1:5555", "emulator-5554;id", "emulator-5554\n"):
            with self.subTest(serial=serial), self.assertRaises(GateError):
                validate_serial(serial)

    def test_empty_multiple_or_invalid_pid_cannot_prove_live_process(self):
        self.assertEqual(parse_pid("123"), 123)
        for pid in ("", "0", "123 456", "123\n456", "-1", "true"):
            with self.subTest(pid=pid), self.assertRaises(GateError):
                parse_pid(pid)

    def test_stale_sentinel_and_boolean_counter_rejected(self):
        self.assertEqual(validate_ready(self.ready(), "a" * 32, 123)["launches"], 4)
        invalid = [self.ready(nonce="b" * 32), self.ready(pid=122), self.ready(ready=False),
                   self.ready(launches=True), self.ready(schema_version=True),
                   self.ready(package="com.example.convoy_mesh"), self.ready(extra="unknown")]
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(GateError):
                validate_ready(value, "a" * 32, 123)

    def test_backstack_or_launch_output_is_not_resumed(self):
        valid = "mResumedActivity: ActivityRecord{abc u0 " + PACKAGE + "/.MainActivity t4}"
        self.assertTrue(activity_resumed(valid))
        self.assertTrue(activity_resumed(valid.replace("mResumedActivity:", "topResumedActivity=")))
        for text in ("Status: ok", valid.replace("mResumedActivity:", "mLastPausedActivity:"),
                     valid.replace(PACKAGE, PACKAGE + ".other"), ""):
            with self.subTest(text=text):
                self.assertFalse(activity_resumed(text))

    def test_restart_needs_new_pid_nonce_and_exact_increment(self):
        first = self.ready()
        second = self.ready(pid=124, nonce="b" * 32, launches=5)
        validate_transition(first, second)
        for update in ({"pid": 123}, {"nonce": "a" * 32}, {"launches": 4}, {"launches": 6}):
            with self.subTest(update=update), self.assertRaises(GateError):
                validate_transition(first, dict(second, **update))

    def test_boot_identity_must_be_a_guest_uuid(self):
        value = "5dfbe401-7329-4cc5-b678-123456789abc"
        self.assertEqual(validate_boot_id(value), value)
        for value in ("", "unknown", "1", "5dfbe401-7329-4cc5-b678-123456789abc\n"):
            with self.subTest(value=value), self.assertRaises(GateError):
                validate_boot_id(value)

    def test_apk_bytes_not_matching_receipt_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "control.apk"
            apk.write_bytes(b"fixture-not-an-apk")
            receipt = {"status": "BUILT_VERIFIED_NOT_RUN", "scope": "NATIVE_RUNTIME_CONTROL_ONLY",
                       "telemetry_tested": False, "apk_sha256": "0" * 64,
                       "apk_bytes": apk.stat().st_size, "identity": {}}
            with self.assertRaisesRegex(GateError, "hash/length"):
                verify_build_receipt(receipt, apk, {})
            receipt["apk_sha256"] = sha256(apk)
            with self.assertRaisesRegex(GateError, "sources"):
                verify_build_receipt(receipt, apk, {})


if __name__ == "__main__":
    unittest.main()
