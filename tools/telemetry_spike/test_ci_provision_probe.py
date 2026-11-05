"""Host-only guard regressions: simulated device commands, no Android or cloud."""
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

import ci_provision_probe as probe
BLOCK_NETWORK = probe.block_network


class ProvisionShellEntry(unittest.TestCase):
    """Exercise the action's actual sh entry with a harmless local Python stub."""
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.log = self.root / "calls.jsonl"
        stub = self.root / "python3"
        stub.write_text("#!" + sys.executable + "\n" +
                        "import json, os, sys\n" +
                        "with open(os.environ['PROBE_STUB_LOG'], 'a') as stream:\n" +
                        "    stream.write(json.dumps(sys.argv[1:]) + '\\n')\n" +
                        "if sys.argv[1].endswith(os.environ.get('PROBE_STUB_FAIL', 'never-match')):\n" +
                        "    raise SystemExit(37)\n")
        stub.chmod(0o700)
        self.repo = Path(__file__).resolve().parents[2]
        self.env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ.get("PATH", ""),
                        ANDROID_HOME="/synthetic SDK", JAVA_HOME="/synthetic JDK",
                        RUNNER_TEMP="/synthetic runner", GITHUB_SHA="a" * 40,
                        PROBE_STUB_LOG=str(self.log))

    def execute(self):
        return subprocess.run(["/usr/bin/sh", "-c", "bash tools/telemetry_spike/run_ci_provision_probe.sh"],
                              cwd=self.repo, env=self.env, capture_output=True, text=True, timeout=10)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_previous_action_first_line_reproduces_pipefail_error(self):
        old = subprocess.run(["/usr/bin/sh", "-c", "set -euo pipefail"],
                             capture_output=True, text=True, timeout=10)
        self.assertEqual(old.returncode, 2)
        self.assertIn("pipefail", old.stderr)
        self.assertFalse(self.log.exists())

    def test_single_bash_entry_runs_control_then_build_then_probe_with_quoted_arguments(self):
        result = self.execute()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertEqual([call[0] for call in calls], [
            "pinned-app/tools/telemetry_spike/runtime_control/smoke.py",
            "pinned-app/tools/telemetry_spike/direct_trial/build.py",
            "tools/telemetry_spike/ci_provision_probe.py"])
        for call in calls:
            self.assertEqual(call[call.index("--sdk") + 1], "/synthetic SDK")
            self.assertEqual(call[call.index("--jdk") + 1], "/synthetic JDK")
        self.assertEqual(calls[1][calls[1].index("--source-commit") + 1], probe.PINNED_APP_SOURCE)
        self.assertEqual(calls[2][calls[2].index("--source-commit") + 1], "a" * 40)

    def test_failed_control_stops_before_build_or_provision(self):
        self.env["PROBE_STUB_FAIL"] = "runtime_control/smoke.py"
        result = self.execute()
        self.assertEqual(result.returncode, 37)
        self.assertEqual([call[0] for call in self.calls()], [
            "pinned-app/tools/telemetry_spike/runtime_control/smoke.py"])

    def test_diagnostic_workflow_selects_single_bash_entry_and_only_next_attempt(self):
        workflow = (self.repo / ".github/workflows/telemetry-runtime-control.yml").read_text()
        diagnostic = workflow.split("  diagnostic-provision:\n", 1)[1]
        self.assertIn("github.run_number == 12 && github.run_attempt == 1", diagnostic)
        self.assertIn("github.event.head_commit.message == 'Diagnose isolated LAB provisioning offline (no cloud)'", diagnostic)
        self.assertIn("script: bash tools/telemetry_spike/run_ci_provision_probe.sh", diagnostic)
        self.assertNotIn("script: |", diagnostic)
        self.assertNotIn("secrets.", diagnostic)


class ProvisionProbeGuards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.out = self.root / "result"
        self.runtime = self.root / "runtime.json"
        self.runtime.write_text(json.dumps({"boot_id": "synthetic-boot", "status": "PASS_NATIVE_RUNTIME_CONTROL"}))
        self.argv = ["ci_provision_probe.py", "--sdk", "/synthetic-sdk", "--jdk", "/synthetic-jdk",
                     "--apk", str(self.root / "lab.apk"), "--build-receipt", str(self.root / "build.json"),
                     "--runtime-gate", str(self.runtime), "--out", str(self.out),
                     "--serial", "emulator-5554", "--source-commit", "a" * 40,
                     "--apk-source-commit", probe.PINNED_APP_SOURCE]
        self.device = Mock(spec=probe.CloudDevice)
        self.device.cleanup_required = False
        self.device.install_confirmed = False
        self.device.provision_confirmed = False
        self.device.shell_v2_confirmed = False
        self.device.private_write_command_completed = False
        self.device.config_write_confirmed = False
        self.device.preparation_records = []
        self.device.pid.return_value = None
        self.factory = self.start(patch.object(probe, "CloudDevice", return_value=self.device))
        self.start(patch("sys.argv", self.argv))
        self.start(patch.dict(probe.os.environ, {}, clear=True))
        self.start(patch.object(probe, "verify_apk", return_value={"synthetic_identity_checked": True}))
        self.initial = {"airplane_mode_on": False, "wifi_on": True, "mobile_data": True}
        self.start(patch.object(probe, "radio_snapshot", return_value=self.initial))
        self.offline = self.start(patch.object(probe, "block_network", return_value={"active_default_network_absent": True}))
        self.stopped = self.start(patch.object(probe, "assert_stopped"))
        self.restore = self.start(patch.object(probe, "restore_radios"))

        def commands(_device, _records, stage, *_args, **_kwargs):
            stdout = ("Android Debug Bridge version 1.0.41\nVersion 35.0.2-12147458\nInstalled as /private/path/adb\n"
                      if stage == "ADB_VERSION" else
                      "package:/synthetic/base.apk\n" if stage == "CLEANUP_PACKAGE_CHECK" else "")
            return subprocess.CompletedProcess([], 0, stdout, "")
        self.commands = self.start(patch.object(probe, "checked_call", side_effect=commands))
        self.output = io.StringIO()
        self.start(redirect_stdout(self.output))

    def start(self, manager):
        value = manager.__enter__()
        self.addCleanup(manager.__exit__, None, None, None)
        return value

    def receipt(self):
        return json.loads((self.out / "result.json").read_text())

    def assert_unknown_budget(self, receipt):
        budget = receipt["budget_recovery"]
        self.assertEqual(budget["status"], "UNKNOWN_BLOCK_FUTURE_SENDS")
        for field in ("reserved_rows", "reserved_attempts", "body_written_rows", "body_written_requests",
                      "acknowledged_requests", "cloud_received_rows"):
            self.assertIsNone(budget[field])
        self.assertEqual(budget["conservative_consumed_for_future_launches"], 500)
        self.assertEqual(budget["remaining_for_future_launches"], 0)
        self.assertIs(budget["automatic_refund_allowed"], False)

    def test_offline_parser_requires_exactly_one_absent_default_network(self):
        self.assertTrue(probe.no_active_default_network("Synthetic heading\n  Active default network: none\n"))
        for value in ("", "Active default network: 101\n", "Active default network: unknown\n",
                      "Active default network: none\nActive default network: 101\n",
                      "Active default network: none\nActive default network: none\n",
                      "Active default network: none\nActive default network: unknown\n"):
            with self.subTest(dump=value):
                self.assertFalse(probe.no_active_default_network(value))

    def test_default_network_observation_classifies_without_exporting_raw_values(self):
        canary = "person@example.invalid phc_HostOnlyCanaryNeverPublish123 192.0.2.99"
        samples = [("Active default network: none\n", "NONE", 1),
                   ("Active default network: 123456789\n" + canary, "ACTIVE", 1),
                   ("Unrecognized format: " + canary, "UNKNOWN", 0),
                   ("Active default network: " + canary, "UNKNOWN", 1),
                   ("Active default network: none\nActive default network: 123456789\n" + canary, "AMBIGUOUS", 2)]
        for raw, state, count in samples:
            with self.subTest(state=state, count=count):
                actual = probe.default_network_observation(raw)
                self.assertEqual(actual, {"state": state, "label_count": count})
                serialized = json.dumps(actual)
                self.assertNotIn(canary, serialized)
                self.assertNotIn("123456789", serialized)

    def test_timeout_retains_radio_booleans_and_sanitized_network_state_in_failure_receipt(self):
        original_commands = self.commands.side_effect
        canary = "person@example.invalid phc_HostOnlyCanaryNeverPublish123 192.0.2.99"
        def commands(device, records, stage, *args, **kwargs):
            if stage == "CONNECTIVITY_OFFLINE_READ":
                return subprocess.CompletedProcess([], 0, "Active default network: 123456789\n" + canary, "")
            return original_commands(device, records, stage, *args, **kwargs)
        self.commands.side_effect = commands
        self.offline.side_effect = BLOCK_NETWORK
        # One actual block_network sample, then its unchanged 45s deadline expires.
        with patch.object(probe.time, "monotonic", side_effect=[0, 1, 46]), patch.object(probe.time, "sleep"):
            with self.assertRaises(SystemExit):
                probe.main()
        receipt = self.receipt()
        self.assertEqual(receipt["blocked_reason"], "PROBE_OFFLINE_BARRIER_UNATTESTED")
        self.assertEqual(receipt["offline_sample_count"], 1)
        sample = receipt["last_offline_observation"]
        self.assertEqual(sample["radio_settings"], self.initial)
        self.assertTrue(all(type(value) is bool for value in sample["radio_settings"].values()))
        self.assertIs(sample["radio_flags_match_requested"], False)
        self.assertEqual(sample["default_network_state"], "ACTIVE")
        self.assertEqual(sample["default_network_label_count"], 1)
        self.assertFalse(sample["raw_connectivity_dump_published"])
        self.device.install.assert_not_called()
        self.device.provision.assert_not_called()
        self.assertEqual(receipt["preparation"], [])
        self.assertNotIn(canary, json.dumps(receipt) + self.output.getvalue())
        self.assertNotIn("123456789", json.dumps(receipt))

    def test_adb_version_exports_only_numeric_identity_and_rejects_ambiguous_output(self):
        raw = "Android Debug Bridge version 1.0.41\nVersion 35.0.2-12147458\nInstalled as /private/path/adb\n"
        identity = probe.adb_version_identity(raw)
        self.assertEqual(identity, {"protocol_version": "1.0.41", "platform_tools_version": "35.0.2",
                                    "build_number": "12147458", "raw_output_published": False})
        self.assertNotIn("private", json.dumps(identity))
        for malformed in ("", raw + "Version 35.0.2-12147458\n", raw.replace("35.0.2", "tainted-value")):
            with self.subTest(value=malformed):
                with self.assertRaisesRegex(probe.TrialBlocked, "PROBE_ADB_VERSION_UNATTESTED"):
                    probe.adb_version_identity(malformed)

    def test_real_credential_is_refused_before_device_and_never_exported(self):
        canary = "phc_HostOnlyCanaryNeverPublish123"
        with patch.dict(probe.os.environ, {"CONVOY_LAB_POSTHOG_TOKEN": canary}):
            with self.assertRaises(SystemExit):
                probe.main()
        self.factory.assert_not_called()
        self.device.install.assert_not_called()
        receipt = self.receipt()
        self.assertEqual(receipt["blocked_reason"], "PROBE_REAL_CLOUD_INPUT_REFUSED")
        self.assert_unknown_budget(receipt)
        self.assertNotIn(canary, json.dumps(receipt) + self.output.getvalue())

    def test_unknown_budget_is_persisted_before_first_device_call_and_survives_failure(self):
        def gate_failure():
            self.assert_unknown_budget(self.receipt())
            raise probe.TrialBlocked("SYNTHETIC_GATE_FAILURE")
        self.device.check_gate.side_effect = gate_failure
        with self.assertRaises(SystemExit):
            probe.main()
        receipt = self.receipt()
        self.assertEqual(receipt["blocked_reason"], "SYNTHETIC_GATE_FAILURE")
        self.assert_unknown_budget(receipt)
        self.device.install.assert_not_called()
        self.device.provision.assert_not_called()

    def test_unattested_offline_barrier_blocks_both_install_and_provision(self):
        self.offline.side_effect = probe.TrialBlocked("PROBE_OFFLINE_BARRIER_UNATTESTED")
        with self.assertRaises(SystemExit):
            probe.main()
        self.device.install.assert_not_called()
        self.device.provision.assert_not_called()
        self.assertEqual(self.receipt()["blocked_reason"], "PROBE_OFFLINE_BARRIER_UNATTESTED")
        self.assert_unknown_budget(self.receipt())

    def test_failed_cleanup_keeps_radios_offline_and_preserves_primary_failure(self):
        def fail_install(_apk):
            self.device.cleanup_required = True
            raise probe.TrialBlocked("CLOUD_INSTALL_APK_NONZERO_EXIT")
        self.device.install.side_effect = fail_install
        self.device.prepare_call.side_effect = probe.TrialBlocked("CLOUD_PRIVATE_REMOVE_NONZERO_EXIT")
        with self.assertRaises(SystemExit):
            probe.main()
        receipt = self.receipt()
        self.assertEqual(receipt["blocked_reason"], "CLOUD_INSTALL_APK_NONZERO_EXIT")
        self.assertEqual(receipt["cleanup_error"], "PROBE_STOP_OR_PRIVATE_CLEANUP_UNATTESTED")
        self.assertFalse(receipt["cleanup"]["install_confirmed"])
        self.assertTrue(receipt["left_offline"]["active_default_network_absent"])
        self.assertEqual(self.offline.call_count, 2)
        self.restore.assert_not_called()
        self.device.provision.assert_not_called()
        self.assert_unknown_budget(receipt)

    def test_success_uses_one_fake_provision_and_never_refunds_or_claims_unchanged_transport(self):
        sequence = []
        def install(_apk):
            self.device.cleanup_required = True
            self.device.install_confirmed = True
        def provision(private_bytes):
            self.assertEqual(json.loads(private_bytes), probe.FAKE_CONFIG)
            self.assertEqual(probe.FAKE_CONFIG["row_limit"], 0)
            self.device.provision_confirmed = True
            self.device.shell_v2_confirmed = True
            self.device.private_write_command_completed = True
            self.device.config_write_confirmed = True
        self.device.install.side_effect = install
        self.device.provision.side_effect = provision
        self.device.prepare_call.side_effect = lambda phase, *_args: sequence.append(phase)
        self.restore.side_effect = lambda *_args: sequence.append("RESTORE_RADIOS")
        probe.main()
        receipt = self.receipt()
        self.device.install.assert_called_once()
        self.device.provision.assert_called_once()
        self.device.command.assert_not_called()
        self.assertEqual(sequence, ["PRIVATE_REMOVE", "PRIVATE_REMOVE_VERIFY", "RESTORE_RADIOS"])
        self.assertEqual(receipt["status"], "CORRECTED_PROVISION_PATH_PASSED")
        self.assertEqual(receipt["historical_failure_cause"], "EXEC_IN_QUOTING_CONTRACT_MISMATCH_REPRODUCED_ON_HOST")
        self.assertTrue(receipt["cleanup"]["fake_config_removed"])
        self.assertTrue(receipt["shell_v2_confirmed"])
        self.assertTrue(receipt["private_write_command_completed"])
        self.assertTrue(receipt["config_write_confirmed"])
        self.assertFalse(receipt["legacy_install_provision_argv_unchanged"])
        self.assert_unknown_budget(receipt)
        self.assertNotIn(probe.FAKE_CONFIG["api_key"], json.dumps(receipt))
        self.assertNotIn(probe.FAKE_CONFIG["endpoint"], json.dumps(receipt))


if __name__ == "__main__":
    unittest.main()
