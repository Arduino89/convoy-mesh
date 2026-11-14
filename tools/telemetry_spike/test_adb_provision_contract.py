"""Host reproduction of the AOSP argument contract, not an ADB/Android run.

The command assembly is from platform/packages/modules/adb at immutable source
1bacec0a271e494d149d5e46f745b04a3c5c7a19: client/commandline.cpp (exec-in,
adb_shell, RemoteShell) and adb_utils.cpp (escape_arg). A real host shell executes
the assembled remote command; a harmless run-as stand-in only execs its argv.
The old client return0 and shell-v2 propagation are SOURCE MODEL conclusions,
not observed execution of an ADB binary. No credentials, device or cloud used.
"""
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

SOURCE = "1bacec0a271e494d149d5e46f745b04a3c5c7a19"
BASE = "https://android.googlesource.com/platform/packages/modules/adb/+/" + SOURCE + "/"
PACKAGE = "com.cama.telemetry.direct_lab"
SCRIPT = "'umask 077; cat > files/cloud-config.private.json'"


def escape_arg(value):
    # AOSP single-quotes every argument and escapes any existing single quote.
    return "'" + value.replace("'", "'\\''") + "'"


def reproduce_transport_contract():
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "files").mkdir()
        stand_in = root / "run-as"
        stand_in.write_text('#!/bin/sh\nshift\nexec "$@"\n')
        stand_in.chmod(0o700)
        env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ.get("PATH", ""))
        arguments = ["run-as", PACKAGE, "sh", "-c", SCRIPT]
        content = b'{"synthetic":"host-provision-test-only"}\n'
        destination = root / "files/cloud-config.private.json"
        # exec-in escapes the arguments after argv[1] before passing to adbd.
        old_command = arguments[0] + "".join(" " + escape_arg(value) for value in arguments[1:])
        old = subprocess.run(["/bin/sh", "-c", old_command], cwd=root, env=env, input=content,
                             capture_output=True, timeout=5)
        old_observation = {"remote_shell_exit_observed": old.returncode,
                           "file_exists": destination.exists(), "stderr_present": bool(old.stderr),
                           "source_model_client_exit": 0, "adb_binary_executed": False}
        # adb_shell joins argv without escaping; shell-v2 carries remote exit.
        new = subprocess.run(["/bin/sh", "-c", " ".join(arguments)], cwd=root, env=env, input=content,
                             capture_output=True, timeout=5)
        new_observation = {"remote_shell_exit_observed": new.returncode,
                           "file_exists": destination.is_file(),
                           "file_mode": format(stat.S_IMODE(destination.stat().st_mode), "o") if destination.exists() else None,
                           "stdin_bytes_match": destination.read_bytes() == content if destination.exists() else False,
                           "stdout_present": bool(new.stdout), "stderr_present": bool(new.stderr),
                           "source_model_client_exit": new.returncode, "adb_binary_executed": False}
        failing = ["run-as", PACKAGE, "sh", "-c", "'exit 37'"]
        error = subprocess.run(["/bin/sh", "-c", " ".join(failing)], cwd=root, env=env,
                               input=b"", capture_output=True, timeout=5)
        return {"schema_version": 1, "scope": "HOST_SHELL_EXECUTION_AOSP_ARGUMENT_MODEL_NOT_ANDROID",
                "source_commit": SOURCE,
                "sources": [BASE + "client/commandline.cpp", BASE + "adb_utils.cpp",
                            BASE + "docs/user/adb.1.md"],
                "legacy_exec_in": old_observation, "corrected_shell_T": new_observation,
                "remote_error": {"remote_shell_exit_observed": error.returncode,
                                 "source_model_client_exit": error.returncode, "adb_binary_executed": False},
                "limits": ["ADB_CLIENT_VERSION_IN_RUN10_NOT_RECORDED",
                           "HOST_RUN_AS_STAND_IN_DOES_NOT_TEST_ANDROID_UID_OR_SELINUX",
                           "SOURCE_MODEL_EXIT_PROPAGATION_REQUIRES_ANDROID_SHELL_V2_RUNTIME_VALIDATION",
                           "NO_STDIN_CONTENT_OR_CREDENTIAL_EXPORTED", "NO_CLOUD_SEND_OR_NEW_ALLOWANCE"]}


class AdbProvisionArgumentContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.result = reproduce_transport_contract()

    def test_exec_in_preserves_literal_quotes_as_a_single_invalid_command(self):
        old = self.result["legacy_exec_in"]
        self.assertEqual(old["remote_shell_exit_observed"], 127)
        self.assertFalse(old["file_exists"])
        self.assertTrue(old["stderr_present"])
        self.assertEqual(old["source_model_client_exit"], 0)

    def test_shell_join_executes_script_and_writes_exact_private_file_mode(self):
        new = self.result["corrected_shell_T"]
        self.assertEqual(new["remote_shell_exit_observed"], 0)
        self.assertTrue(new["file_exists"])
        self.assertEqual(new["file_mode"], "600")
        self.assertTrue(new["stdin_bytes_match"])
        self.assertFalse(new["stdout_present"] or new["stderr_present"])

    def test_remote_failure_remains_nonzero_under_the_shell_v2_exit_contract(self):
        error = self.result["remote_error"]
        self.assertEqual(error["remote_shell_exit_observed"], 37)
        self.assertEqual(error["source_model_client_exit"], 37)
        self.assertFalse(error["adb_binary_executed"])


if __name__ == "__main__":
    unittest.main()
