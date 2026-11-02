#!/usr/bin/env python3
"""Native lifecycle/storage gate on one explicit emulator, without telemetry or wipes."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import time
import uuid

if __package__:
    from .build import GateError, HERE, PACKAGE, installed_tools, sha256, verify_apk
else:
    from build import GateError, HERE, PACKAGE, installed_tools, sha256, verify_apk

COMPONENT = PACKAGE + "/.MainActivity"
FIELDS = {"schema_version", "package", "nonce", "pid", "launches", "ready"}


def validate_serial(serial):
    if not re.fullmatch(r"emulator-[0-9]+", serial):
        raise GateError("explicit emulator-N serial required; physical/network devices refused")
    return serial


def validate_boot_id(value):
    if not re.fullmatch(r"[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}", value):
        raise GateError("guest boot ID unavailable or malformed")
    return value


def parse_pid(value):
    if not re.fullmatch(r"[1-9][0-9]*", value):
        raise GateError("exactly one live control process required")
    return int(value)


def validate_ready(value, nonce, pid):
    if not isinstance(value, dict) or set(value) != FIELDS:
        raise GateError("unexpected ready sentinel schema")
    if (type(value["schema_version"]) is not int or value["schema_version"] != 1
            or value["package"] != PACKAGE or value["ready"] is not True):
        raise GateError("invalid ready sentinel identity/state")
    if value["nonce"] != nonce or type(value["pid"]) is not int or value["pid"] != pid:
        raise GateError("stale sentinel or wrong live process")
    if type(value["launches"]) is not int or not 1 <= value["launches"] < 2**63:
        raise GateError("invalid persisted launch counter")
    return value


def validate_transition(first, second):
    if first["pid"] == second["pid"] or first["nonce"] == second["nonce"]:
        raise GateError("restart not demonstrated by new PID and nonce")
    if second["launches"] != first["launches"] + 1:
        raise GateError("persisted counter did not increment exactly once")


def activity_resumed(dump):
    # Do not mistake historical/backstack entries or launch success for RESUMED.
    return any(re.search(r"\b(?:mResumedActivity|topResumedActivity)\s*[:=]", line)
               and re.search(re.escape(PACKAGE) + r"/(?:\.MainActivity|" + re.escape(PACKAGE)
                             + r"\.MainActivity)(?:[\s}])", line)
               for line in dump.splitlines())


def verify_build_receipt(receipt, apk, identity):
    if receipt.get("status") != "BUILT_VERIFIED_NOT_RUN":
        raise GateError("successful build-only receipt required")
    if receipt.get("scope") != "NATIVE_RUNTIME_CONTROL_ONLY" or receipt.get("telemetry_tested") is not False:
        raise GateError("wrong receipt scope")
    if receipt.get("apk_sha256") != sha256(apk) or receipt.get("apk_bytes") != apk.stat().st_size:
        raise GateError("APK hash/length differs from build receipt")
    if receipt.get("identity") != identity:
        raise GateError("verified APK identity differs from receipt")
    expected = {name: sha256(HERE / name) for name in ("AndroidManifest.xml", "MainActivity.java")}
    if any(receipt.get("sources", {}).get(k) != v for k, v in expected.items()):
        raise GateError("control sources differ from built receipt")


class Device:
    def __init__(self, adb, serial):
        self.adb = str(adb)
        self.serial = validate_serial(serial)

    def call(self, *args, timeout=10, allow_failure=False):
        try:
            result = subprocess.run([self.adb, "-s", self.serial, *map(str, args)],
                                    capture_output=True, text=True, timeout=timeout)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise GateError("ADB unavailable or command timed out") from exc
        if result.returncode and not allow_failure:
            combined = result.stdout + result.stderr
            category = next((s for s in ("Broken pipe", "DeadSystemException", "offline", "unauthorized")
                             if s in combined), "nonzero exit")
            raise GateError("ADB command failed: " + category)
        return result.returncode, result.stdout.strip()

    def read(self, *args, **kwargs):
        return self.call(*args, **kwargs)[1]

    def pid(self):
        code, output = self.call("shell", "pidof", PACKAGE, allow_failure=True)
        if code == 1 and not output:
            return None
        if code:
            raise GateError("cannot attest control process absence")
        return parse_pid(output)


def wait_for(check, seconds, label):
    deadline = time.monotonic() + seconds
    while True:
        value = check()
        if value:
            return value
        if time.monotonic() >= deadline:
            raise GateError("bounded wait expired: " + label)
        time.sleep(min(0.5, max(0.0, deadline - time.monotonic())))


def launch_ready(device, timeout):
    nonce = uuid.uuid4().hex
    device.call("shell", "am", "start", "-W", "-n", COMPONENT,
                "--es", "control_nonce", nonce, timeout=min(timeout, 30))

    def observed():
        pid = device.pid()
        if pid is None:
            return None
        if not activity_resumed(device.read("shell", "dumpsys", "activity", "activities")):
            return None
        code, raw = device.call("exec-out", "run-as", PACKAGE, "cat", "files/ready.json", allow_failure=True)
        if code or len(raw) > 4096:
            return None
        try:
            ready = validate_ready(json.loads(raw), nonce, pid)
        except (json.JSONDecodeError, GateError):
            return None
        # Repeat live state: don't accept a sentinel from a process that died mid-check.
        if device.pid() != pid:
            return None
        return ready

    return wait_for(observed, timeout, "resumed activity and current ready sentinel")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", required=True, type=Path)
    parser.add_argument("--jdk", required=True, type=Path)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--build-receipt", required=True, type=Path)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--out", required=True, type=Path, help="new receipt directory")
    parser.add_argument("--timeout", type=int, default=60, help="per-stage wait,10..300 seconds")
    args = parser.parse_args()
    if not 10 <= args.timeout <= 300:
        parser.error("timeout must be10..300 seconds")
    validate_serial(args.serial)
    args.out.mkdir(parents=True, exist_ok=False)
    receipt = {"schema_version": 1, "utc": datetime.now(timezone.utc).isoformat(),
               "scope": "NATIVE_RUNTIME_CONTROL_ONLY", "telemetry_tested": False,
               "status": "NOT_RUN", "gate_pass": False, "serial": args.serial, "stages": []}
    device = None
    installed = False
    try:
        paths, env, _ = installed_tools(args.sdk, args.jdk)
        identity = verify_apk(args.apk, paths, env)
        verify_build_receipt(json.loads(args.build_receipt.read_text()), args.apk, identity)
        receipt["apk_sha256"] = sha256(args.apk)
        receipt["identity"] = identity
        receipt["stages"].append({"name": "verify_apk", "pass": True})
        device = Device(args.sdk / "platform-tools" / "adb", args.serial)
        if device.read("get-serialno") != args.serial or device.read("shell", "getprop", "ro.kernel.qemu") != "1":
            raise GateError("device identity is not the explicitly selected emulator")
        wait_for(lambda: device.read("shell", "getprop", "sys.boot_completed") == "1", args.timeout, "boot completed")
        if not any(line.startswith("package:") for line in device.read("shell", "pm", "path", "android").splitlines()):
            raise GateError("package manager not ready")
        receipt["boot_id"] = validate_boot_id(device.read("shell", "cat", "/proc/sys/kernel/random/boot_id"))
        receipt["stages"].append({"name": "boot_and_package_manager", "pass": True})
        install = device.read("install", "-r", str(args.apk.resolve()), timeout=min(300, args.timeout * 3))
        if not re.search(r"^Success$", install, re.M):
            raise GateError("installer did not report explicit Success")
        installed = True
        receipt["stages"].append({"name": "install_verified_control", "pass": True})
        device.call("shell", "am", "force-stop", PACKAGE)
        wait_for(lambda: device.pid() is None, args.timeout, "initial process stopped")
        first = launch_ready(device, args.timeout)
        receipt["stages"].append({"name": "first_resumed_ready", "pass": True, "observation": first})
        device.call("shell", "am", "force-stop", PACKAGE)
        wait_for(lambda: device.pid() is None, args.timeout, "force-stop process absence")
        receipt["stages"].append({"name": "force_stop_pid_absent", "pass": True})
        second = launch_ready(device, args.timeout)
        receipt["stages"].append({"name": "second_resumed_ready", "pass": True, "observation": second})
        validate_transition(first, second)
        if validate_boot_id(device.read("shell", "cat", "/proc/sys/kernel/random/boot_id")) != receipt["boot_id"]:
            raise GateError("guest rebooted during process-restart test")
        receipt["stages"].append({"name": "new_pid_persisted_counter_same_boot", "pass": True})
        receipt.update(status="PASS_NATIVE_RUNTIME_CONTROL", gate_pass=True)
    except (GateError, OSError, ValueError) as failure:
        receipt.update(status="BLOCKED_OR_FAILED", gate_pass=False, reason=str(failure))
    finally:
        if device is not None and installed:
            try:
                device.call("shell", "am", "force-stop", PACKAGE)
                wait_for(lambda: device.pid() is None, args.timeout, "cleanup process absence")
                receipt["stages"].append({"name": "control_stopped_data_preserved", "pass": True})
            except GateError as failure:
                receipt.update(status="BLOCKED_OR_FAILED", gate_pass=False, cleanup_error=str(failure))
        receipt["finished_utc"] = datetime.now(timezone.utc).isoformat()
        (args.out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps(receipt))
    if not receipt["gate_pass"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
