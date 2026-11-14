#!/usr/bin/env python3
"""Build two pinned synthetic LAB APKs; never launch Android or send telemetry.

Only APKs and a public JSON receipt survive. Generated projects, define files and
captured tool output are private and temporary. A successful build is not a
runtime, revocation, privacy or delivery result.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
SOURCE = HERE / "posthog_trial"
PACKAGE = "com.cama.telemetry.convoy_telemetry_lab"
FLUTTER = "3.47.4"
DART = "3.13.3"
BUILD_TOOLS = "36.0.0"
NATIVE = {"posthog-android": "3.75.0", "posthog": "6.48.0"}
INPUTS = ("prepare_trial.py", "main.dart", "MainActivity.kt", "pubspec.yaml",
          "locks/pubspec.lock", "locks/android-debug.lockfile")
DIAGNOSTICS = (("No space left on device", "DISK_FULL"),
               ("OutOfMemoryError", "TOOL_MEMORY_EXHAUSTED"),
               ("Could not resolve", "DEPENDENCY_RESOLUTION_FAILED"),
               ("version solving failed", "DART_RESOLUTION_FAILED"),
               ("license", "SDK_LICENSE_OR_TOOL_FAILURE"))


class BuildError(RuntimeError):
    """Constant public-safe codes only; never attach raw tool output."""


def digest(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def run(argv, env, cwd=None, timeout=900):
    # Timeout kills the complete build process group, including Gradle children.
    try:
        child = subprocess.Popen([str(value) for value in argv], cwd=cwd, env=env,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 text=True, start_new_session=True)
        try:
            stdout, stderr = child.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            child.communicate()
            raise BuildError("COMMAND_TIMEOUT") from None
    except OSError:
        raise BuildError("COMMAND_UNAVAILABLE") from None
    if child.returncode:
        combined = stdout + stderr
        code = next((code for needle, code in DIAGNOSTICS if needle in combined),
                    "COMMAND_NONZERO_EXIT")
        raise BuildError(code)
    return stdout + stderr


def property_value(path, name):
    values = dict(line.split("=", 1) for line in path.read_text().splitlines()
                  if "=" in line and not line.lstrip().startswith("#"))
    return {key.strip(): value.strip() for key, value in values.items()}.get(name)


def tools_and_environment():
    sdk = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    jdk = os.environ.get("JAVA_HOME")
    if not sdk or not jdk or not shutil.which("flutter"):
        raise BuildError("REQUIRED_TOOLCHAIN_UNAVAILABLE")
    sdk, jdk = Path(sdk), Path(jdk)
    bt = sdk / "build-tools" / BUILD_TOOLS
    if (property_value(sdk / "platforms/android-36/source.properties", "AndroidVersion.ApiLevel") != "36"
            or property_value(bt / "source.properties", "Pkg.Revision") != BUILD_TOOLS):
        raise BuildError("SDK36_BUILD_TOOLS_PIN_MISMATCH")
    tools = {name: bt / name for name in ("aapt2", "apksigner")}
    if any(not path.is_file() for path in tools.values()):
        raise BuildError("SDK_VERIFICATION_TOOLS_MISSING")
    env = dict(os.environ)
    env.update(CI="true", BOT="true", FLUTTER_SUPPRESS_ANALYTICS="true",
               DASH__SUPPRESS_ANALYTICS="true", DART_SUPPRESS_ANALYTICS="true")
    env["PATH"] = str(jdk / "bin") + os.pathsep + env.get("PATH", "")
    java = run([jdk / "bin/javac", "-version"], env, timeout=30).strip()
    if not re.fullmatch(r"javac 17(?:\.[0-9A-Za-z+._-]+)?", java):
        raise BuildError("JDK17_REQUIRED")
    flutter = json.loads(run(["flutter", "--version", "--machine"], env, timeout=90))
    if flutter.get("frameworkVersion") != FLUTTER or flutter.get("dartSdkVersion") != DART:
        raise BuildError("FLUTTER_DART_PIN_MISMATCH")
    engine = flutter.get("engineRevision", "")
    if not re.fullmatch(r"[a-f0-9]{40}", engine):
        raise BuildError("FLUTTER_ENGINE_REVISION_INVALID")
    return tools, env, {"frameworkVersion": FLUTTER, "dartSdkVersion": DART,
                        "engineRevision": engine, "javac": java,
                        "android_platform": 36, "build_tools": BUILD_TOOLS}


def source_snapshot(commit, env):
    if run(["git", "rev-parse", "HEAD"], env, REPO, 30).strip() != commit:
        raise BuildError("CHECKOUT_SOURCE_COMMIT_MISMATCH")
    paths = [SOURCE / name for name in INPUTS] + [Path(__file__).resolve()]
    result = {}
    for path in paths:
        relative = path.relative_to(REPO).as_posix()
        if path.is_symlink() or not path.is_file():
            raise BuildError("SOURCE_FILE_MISSING_OR_SYMLINK")
        committed = run(["git", "rev-parse", commit + ":" + relative], env, REPO, 30).strip()
        actual = run(["git", "hash-object", "--", relative], env, REPO, 30).strip()
        if committed != actual:
            raise BuildError("SOURCE_DIFFERS_FROM_COMMIT")
        result[relative] = digest(path)
    return result


def verify_locks(project):
    mappings = {"pubspec.lock": SOURCE / "locks/pubspec.lock",
                "android/app/gradle.lockfile": SOURCE / "locks/android-debug.lockfile"}
    result = {}
    for relative, pinned in mappings.items():
        installed = project / relative
        if not installed.is_file() or digest(installed) != digest(pinned):
            raise BuildError("LOCKFILE_MISSING_OR_CHANGED")
        result[relative] = digest(installed)
    lock = (project / "android/app/gradle.lockfile").read_text()
    for module, version in NATIVE.items():
        if not re.search(r"^com\.posthog:" + re.escape(module + ":" + version)
                         + r"=debugRuntimeClasspath$", lock, re.M):
            raise BuildError("NATIVE_LOCK_PIN_MISMATCH")
    return result


def selected_native_version(output, module):
    """Read resolved headings and selection arrows, including lock constraints.

    Gradle prints both ``module:3.75.0`` and the request
    ``module:{strictly 3.75.0} -> 3.75.0``. A constraint alone is not evidence
    that a component was resolved: require its ordinary resolved heading too.
    """
    prefix = "com.posthog:" + module + ":"
    selected, resolved_heading = set(), False
    version_pattern = r"([0-9]+(?:\.[0-9]+)+(?:[-+][A-Za-z0-9_.-]+)?)(?:\s+\([^()\r\n]*\))*"
    for line in output.splitlines():
        if not line.startswith(prefix):
            continue
        expression = line[len(prefix):].strip()
        if " -> " in expression:
            expression = expression.rsplit(" -> ", 1)[1].strip()
        else:
            strict = re.fullmatch(r"\{strictly\s+([^\s{}]+)\}(?:\s+\([^()\r\n]*\))*", expression)
            if strict:
                expression = strict[1]
            elif re.fullmatch(version_pattern, expression):
                resolved_heading = True
        version = re.fullmatch(version_pattern, expression)
        if not version:
            raise BuildError("RESOLVED_NATIVE_VERSION_NOT_ATTESTED")
        selected.add(version[1])
    if not resolved_heading or len(selected) != 1 or "FAILED" in output:
        raise BuildError("RESOLVED_NATIVE_VERSION_NOT_ATTESTED")
    return selected.pop()


def resolved_native(project, env):
    versions = {}
    for module, expected in NATIVE.items():
        output = run([project / "android/gradlew", ":app:dependencyInsight",
                      "--dependency", "com.posthog:" + module, "--configuration",
                      "debugRuntimeClasspath", "--console=plain", "--no-daemon"],
                     env, project / "android", 600)
        if selected_native_version(output, module) != expected:
            raise BuildError("RESOLVED_NATIVE_VERSION_NOT_ATTESTED")
        versions[module] = expected
    return versions


def verify_apk(path, tools, env):
    if not path.is_file() or path.is_symlink() or path.stat().st_size == 0:
        raise BuildError("BUILT_APK_MISSING")
    badging = run([tools["aapt2"], "dump", "badging", path], env, timeout=60)
    identity = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'",
                         badging, re.M)
    if not identity or identity.groups() != (PACKAGE, "4001", "0.0.1"):
        raise BuildError("LAB_APK_IDENTITY_MISMATCH")
    if re.findall(r"^native-code: (.*)$", badging, re.M) != ["'x86_64'"]:
        raise BuildError("LAB_APK_ABI_MISMATCH")
    if (re.findall(r"^(?:sdkVersion|minSdkVersion):'([^']+)'$", badging, re.M) != ["24"]
            or re.findall(r"^targetSdkVersion:'([^']+)'$", badging, re.M) != ["36"]):
        raise BuildError("LAB_APK_SDK_BOUNDS_MISMATCH")
    permissions = re.findall(r"^uses-permission[^:]*: name='([^']+)'", badging, re.M)
    allowed = {"android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE",
               PACKAGE + ".DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"}
    if set(permissions) - allowed:
        raise BuildError("LAB_APK_PERMISSION_SCOPE_MISMATCH")
    signature = run([tools["apksigner"], "verify", "--print-certs", path], env, timeout=60)
    certs = re.findall(r"Signer #[0-9]+ certificate SHA-256 digest: ([a-fA-F0-9]{64})", signature)
    if len(certs) != 1:
        raise BuildError("LAB_APK_SIGNATURE_NOT_ATTESTED")
    return {"sha256": digest(path), "bytes": path.stat().st_size,
            "signer_sha256": certs[0].lower(), "package": PACKAGE,
            "version_code": 4001, "version_name": "0.0.1", "abi": "x86_64",
            "min_sdk": 24, "target_sdk": 36, "permissions": sorted(permissions)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path)
    for name in ("source-commit", "run-id", "overflow-run-id"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    receipt = {"schema_version": 1, "utc": datetime.now(timezone.utc).isoformat(),
               "scope": "SYNTHETIC_LAB_APK_BUILD_ONLY", "status": "NOT_BUILT",
               "runtime_tested": False, "telemetry_tested": False,
               "stages": [], "artifacts": {}}
    stage, created = "validate_arguments", False
    out = args.out.resolve()
    try:
        if out == REPO or REPO in out.parents:
            raise BuildError("OUTPUT_MUST_BE_OUTSIDE_REPOSITORY")
        out.mkdir(parents=True, exist_ok=False)
        created = True
        if not re.fullmatch(r"[a-f0-9]{40}", args.source_commit):
            raise BuildError("INVALID_SOURCE_COMMIT")
        if (not all(re.fullmatch(r"synthetic-[a-z0-9-]{1,48}", value)
                    for value in (args.run_id, args.overflow_run_id))
                or args.run_id == args.overflow_run_id):
            raise BuildError("INVALID_OR_EQUAL_SYNTHETIC_RUN_IDS")
        receipt["source_commit"] = args.source_commit
        stage = "verify_installed_toolchain"
        tools, env, receipt["toolchain"] = tools_and_environment()
        receipt["stages"].append({"stage": stage, "pass": True})
        stage = "verify_committed_sources"
        snapshot = source_snapshot(args.source_commit, env)
        receipt["source_sha256"] = snapshot
        receipt["stages"].append({"stage": stage, "pass": True})
        with tempfile.TemporaryDirectory(prefix="telemetry-build-private-", dir=out.parent) as scratch:
            work = Path(scratch)
            project = work / "project"
            stage = "prepare_pinned_project"
            run([sys.executable, SOURCE / "prepare_trial.py", "--out", project], env)
            receipt["lock_sha256"] = verify_locks(project)
            receipt["stages"].append({"stage": stage, "pass": True})
            stage = "pub_get_enforce_lockfile"
            run(["flutter", "pub", "get", "--enforce-lockfile"], env, project)
            verify_locks(project)
            receipt["stages"].append({"stage": stage, "pass": True})
            stage = "flutter_analyze"
            run(["flutter", "analyze", "--no-pub"], env, project)
            verify_locks(project)
            receipt["stages"].append({"stage": stage, "pass": True})
            for name, run_id, queue in (("normal", args.run_id, 1000),
                                        ("overflow", args.overflow_run_id, 32)):
                stage = "build_" + name
                defines = {"LAB_LOCAL_RECEIVER": True, "LAB_NATIVE_FILTER": True,
                           "LAB_REVOKE_MODE": "resetClose", "LAB_RUN_ID": run_id,
                           "LAB_QUEUE_SIZE": queue, "BUILD_COMMIT": args.source_commit}
                config = work / (name + ".private.json")
                config.write_text(json.dumps(defines))
                built = project / "build/app/outputs/flutter-apk/app-x86_64-debug.apk"
                # An old file cannot become evidence if a later build produces none.
                built.unlink(missing_ok=True)
                verify_locks(project)
                # The committed Gradle lock covers all three debug ABIs. Build
                # them together, then retain only the x86_64 emulator artifact.
                run(["flutter", "build", "apk", "--debug", "--no-pub", "--split-per-abi",
                     "--dart-define-from-file=" + str(config)],
                    env, project, 1200)
                verify_locks(project)
                stage = "verify_" + name
                identity = verify_apk(built, tools, env)
                saved = out / (name + ".apk")
                shutil.copyfile(built, saved)
                if digest(saved) != identity["sha256"]:
                    raise BuildError("COPIED_APK_DIGEST_MISMATCH")
                receipt["artifacts"][name] = dict(identity, filename=saved.name,
                    run_id=run_id, queue_size=queue, local_receiver=True,
                    native_filter=True, revoke_mode="resetClose")
                receipt["stages"].append({"stage": "build_and_verify_" + name, "pass": True})
            stage = "verify_resolved_native_versions"
            receipt["resolved_native_versions"] = resolved_native(project, env)
            verify_locks(project)
            receipt["stages"].append({"stage": stage, "pass": True})
            stage = "verify_final_sources_and_artifacts"
            if source_snapshot(args.source_commit, env) != snapshot:
                raise BuildError("SOURCES_CHANGED_DURING_BUILD")
            if receipt["artifacts"]["normal"]["sha256"] == receipt["artifacts"]["overflow"]["sha256"]:
                raise BuildError("VARIANT_APKS_UNEXPECTEDLY_IDENTICAL")
            if receipt["artifacts"]["normal"]["signer_sha256"] != receipt["artifacts"]["overflow"]["signer_sha256"]:
                raise BuildError("VARIANT_SIGNING_CERTIFICATE_CHANGED")
            receipt["stages"].append({"stage": stage, "pass": True})
        receipt["status"] = "PASS_LAB_APK_BUILD"
    except (BuildError, OSError, ValueError) as failure:
        receipt.update(status="BUILD_BLOCKED_OR_FAILED", failed_stage=stage,
                       reason=str(failure) if isinstance(failure, BuildError)
                       else "IO_OR_TOOL_METADATA_FAILURE")
    if created:
        try:
            (out / "build-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        except OSError:
            receipt.update(status="BUILD_BLOCKED_OR_FAILED", failed_stage="write_receipt",
                           reason="PUBLIC_RECEIPT_WRITE_FAILED")
    print(json.dumps(receipt))
    return 0 if receipt["status"] == "PASS_LAB_APK_BUILD" else 1


if __name__ == "__main__":
    sys.exit(main())
