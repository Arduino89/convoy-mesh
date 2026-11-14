#!/usr/bin/env python3
"""Build a tiny Android control using installed SDK36/build-tools36.0.0/JDK17 only."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile

PACKAGE = "com.cama.telemetry.runtime_control"
PLATFORM = "36"
BUILD_TOOLS = "36.0.0"
HERE = Path(__file__).resolve().parent


class GateError(RuntimeError):
    pass


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run(argv, *, env=None, timeout=60):
    try:
        result = subprocess.run([str(x) for x in argv], capture_output=True,
                                text=True, timeout=timeout, env=env)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise GateError("tool unavailable or timed out: " + Path(argv[0]).name) from exc
    if result.returncode:
        raise GateError("tool failed: " + Path(argv[0]).name)
    return result.stdout + result.stderr


def revision(path, key):
    if not path.is_file():
        raise GateError("missing installed SDK metadata: " + path.name)
    values = dict(line.split("=", 1) for line in path.read_text().splitlines()
                  if "=" in line and not line.lstrip().startswith("#"))
    return {k.strip(): v.strip() for k, v in values.items()}.get(key)


def installed_tools(sdk, jdk):
    sdk, jdk = Path(sdk).resolve(), Path(jdk).resolve()
    platform = sdk / "platforms" / ("android-" + PLATFORM)
    bt = sdk / "build-tools" / BUILD_TOOLS
    if revision(platform / "source.properties", "AndroidVersion.ApiLevel") != PLATFORM:
        raise GateError("installed platform must be android-36")
    if revision(bt / "source.properties", "Pkg.Revision") != BUILD_TOOLS:
        raise GateError("installed build-tools must be 36.0.0")
    paths = {name: bt / name for name in ("aapt2", "d8", "zipalign", "apksigner")}
    paths.update({name: jdk / "bin" / name for name in ("java", "javac", "keytool")})
    paths["android_jar"] = platform / "android.jar"
    if any(not p.is_file() for p in paths.values()):
        raise GateError("required installed Android/JDK tool missing; no downloads attempted")
    env = dict(os.environ, JAVA_HOME=str(jdk))
    version = run([paths["javac"], "-version"], env=env).strip()
    if not re.fullmatch(r"javac 17(?:\.[0-9A-Za-z+._-]+)?", version):
        raise GateError("JDK17 javac required")
    return paths, env, version


def verify_apk(apk, paths, env):
    badging = run([paths["aapt2"], "dump", "badging", apk], env=env)
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.M)
    if not package or package.groups() != (PACKAGE, "1", "1.0"):
        raise GateError("APK identity mismatch")
    if not valid_sdk_bounds(badging):
        bounds = re.findall(r"^(?:sdkVersion|targetSdkVersion|minSdkVersion):'[^']{0,16}'", badging, re.M)
        raise GateError("APK SDK bounds mismatch: " + json.dumps(bounds))
    if re.search(r"^uses-permission", badging, re.M):
        raise GateError("control APK must request zero permissions")
    signature = run([paths["apksigner"], "verify", "--print-certs", apk], env=env)
    certificates = re.findall(r"Signer #[0-9]+ certificate SHA-256 digest: ([a-fA-F0-9]{64})", signature)
    if len(certificates) != 1:
        raise GateError("exactly one verified signing certificate required")
    return {"package": PACKAGE, "version_code": 1, "version_name": "1.0",
            "min_sdk": 24, "target_sdk": 36, "requested_permissions": [],
            "certificate_sha256": certificates[0].lower()}


def valid_sdk_bounds(badging):
    # aapt2 36 emits minSdkVersion; older aapt emits sdkVersion.
    minimums = re.findall(r"^(?:sdkVersion|minSdkVersion):'([^']+)'$", badging, re.M)
    targets = re.findall(r"^targetSdkVersion:'([^']+)'$", badging, re.M)
    return minimums == ['24'] and targets == ['36']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path, required=True)
    parser.add_argument("--jdk", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True, help="new directory outside this source directory")
    args = parser.parse_args()
    receipt = {"utc": datetime.now(timezone.utc).isoformat(), "status": "NOT_BUILT",
               "scope": "NATIVE_RUNTIME_CONTROL_ONLY", "telemetry_tested": False}
    try:
        paths, env, javac = installed_tools(args.sdk, args.jdk)
        out = args.out.resolve()
        if HERE == out or HERE in out.parents:
            raise GateError("output must be outside source directory")
        out.mkdir(parents=True, exist_ok=False)
        classes, dex = out / "classes", out / "dex"
        classes.mkdir()
        dex.mkdir()
        manifest, java = HERE / "AndroidManifest.xml", HERE / "MainActivity.java"
        run([paths["javac"], "-source", "8", "-target", "8", "-encoding", "UTF-8",
             "-classpath", paths["android_jar"], "-d", classes, java], env=env)
        with zipfile.ZipFile(out / "classes.jar", "w") as jar:
            for item in sorted(classes.rglob("*.class")):
                jar.write(item, item.relative_to(classes).as_posix())
        run([paths["d8"], "--lib", paths["android_jar"], "--min-api", "24",
             "--output", dex, out / "classes.jar"], env=env)
        run([paths["aapt2"], "link", "-o", out / "base.apk", "-I", paths["android_jar"],
             "--manifest", manifest, "--min-sdk-version", "24", "--target-sdk-version", "36"], env=env)
        with zipfile.ZipFile(out / "base.apk") as base, zipfile.ZipFile(out / "unsigned.apk", "w") as apk:
            for info in base.infolist():
                apk.writestr(info, base.read(info.filename))
            apk.write(dex / "classes.dex", "classes.dex")
        run([paths["zipalign"], "-f", "4", out / "unsigned.apk", out / "aligned.apk"], env=env)
        # Deliberately disposable debug signing key; never a Convoy/release identity.
        run([paths["keytool"], "-genkeypair", "-keystore", out / "debug.keystore",
             "-storepass", "android", "-keypass", "android", "-alias", "runtime-control",
             "-keyalg", "RSA", "-keysize", "2048", "-validity", "30",
             "-dname", "CN=Synthetic Runtime Control", "-noprompt"], env=env)
        apk = out / "runtime-control.apk"
        run([paths["apksigner"], "sign", "--ks", out / "debug.keystore",
             "--ks-key-alias", "runtime-control", "--ks-pass", "pass:android",
             "--key-pass", "pass:android", "--out", apk, out / "aligned.apk"], env=env)
        identity = verify_apk(apk, paths, env)
        receipt.update(status="BUILT_VERIFIED_NOT_RUN", apk_sha256=sha256(apk),
                       apk_bytes=apk.stat().st_size, identity=identity, javac=javac,
                       platform=PLATFORM, build_tools=BUILD_TOOLS,
                       sources={p.name: sha256(p) for p in (manifest, java, HERE / "build.py")})
        (out / "build-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps(receipt))
    except (GateError, OSError) as failure:
        receipt.update(status="BUILD_BLOCKED_OR_FAILED", reason=str(failure))
        print(json.dumps(receipt))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
