#!/usr/bin/env python3
"""Build synthetic direct-sender APK from platform APIs; no SDK/dependency download."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import sys
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parent))
from runtime_control.build import GateError, installed_tools, run, sha256, valid_sdk_bounds

PACKAGE = "com.cama.telemetry.direct_lab"


def verify_apk(apk, paths, env):
    badging = run([paths["aapt2"], "dump", "badging", apk], env=env)
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.M)
    if not package or package.groups() != (PACKAGE, "1", "1.0"):
        raise GateError("direct APK identity mismatch")
    if not valid_sdk_bounds(badging):
        raise GateError("direct APK SDK bounds mismatch")
    permissions = re.findall(r"^uses-permission: name='([^']+)'", badging, re.M)
    if permissions != ["android.permission.INTERNET"]:
        raise GateError("direct APK must request only INTERNET")
    signature = run([paths["apksigner"], "verify", "--print-certs", apk], env=env)
    certificates = re.findall(r"Signer #[0-9]+ certificate SHA-256 digest: ([a-fA-F0-9]{64})", signature)
    if len(certificates) != 1:
        raise GateError("one verified signing certificate required")
    return {"package": PACKAGE, "version_code": 1, "version_name": "1.0", "min_sdk": 24,
            "target_sdk": 36, "requested_permissions": permissions,
            "certificate_sha256": certificates[0].lower()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path, required=True)
    parser.add_argument("--jdk", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--source-commit", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-f0-9]{40}", args.source_commit):
        parser.error("an exact source commit is required")
    receipt = {"utc": datetime.now(timezone.utc).isoformat(), "status": "NOT_BUILT",
               "scope": "NATIVE_DIRECT_SYNTHETIC_LOOPBACK_ONLY", "runtime_tested": False,
               "source_commit": args.source_commit, "analytics_sdk": None, "new_dependencies": []}
    out = args.out.resolve()
    created_output = False
    try:
        paths, env, javac = installed_tools(args.sdk, args.jdk)
        if ROOT == out or ROOT in out.parents:
            raise GateError("output must be outside repository")
        out.mkdir(parents=True, exist_ok=False)
        created_output = True
        classes, dex = out / "classes", out / "dex"
        classes.mkdir(); dex.mkdir()
        manifest = HERE / "AndroidManifest.xml"
        java = [HERE / "MainActivity.java", HERE / "DirectQueue.java"]
        run([paths["javac"], "-source", "8", "-target", "8", "-encoding", "UTF-8",
             "-classpath", paths["android_jar"], "-d", classes, *java], env=env)
        with zipfile.ZipFile(out / "classes.jar", "w") as jar:
            for item in sorted(classes.rglob("*.class")):
                jar.write(item, item.relative_to(classes).as_posix())
        run([paths["d8"], "--lib", paths["android_jar"], "--min-api", "24", "--output", dex,
             out / "classes.jar"], env=env)
        run([paths["aapt2"], "link", "-o", out / "base.apk", "-I", paths["android_jar"],
             "--manifest", manifest, "--min-sdk-version", "24", "--target-sdk-version", "36"], env=env)
        with zipfile.ZipFile(out / "base.apk") as base, zipfile.ZipFile(out / "unsigned.apk", "w") as apk:
            for info in base.infolist():
                apk.writestr(info, base.read(info.filename))
            apk.write(dex / "classes.dex", "classes.dex")
        run([paths["zipalign"], "-f", "4", out / "unsigned.apk", out / "aligned.apk"], env=env)
        run([paths["keytool"], "-genkeypair", "-keystore", out / "debug.keystore", "-storepass", "android",
             "-keypass", "android", "-alias", "direct-lab", "-keyalg", "RSA", "-keysize", "2048",
             "-validity", "30", "-dname", "CN=Synthetic Direct LAB", "-noprompt"], env=env)
        apk = out / "direct-lab.apk"
        run([paths["apksigner"], "sign", "--ks", out / "debug.keystore", "--ks-key-alias", "direct-lab",
             "--ks-pass", "pass:android", "--key-pass", "pass:android", "--out", apk, out / "aligned.apk"], env=env)
        sources = [manifest, *java, HERE / "build.py", HERE.parent / "runtime_control" / "build.py"]
        receipt.update(status="BUILT_VERIFIED_NOT_RUN", apk_sha256=sha256(apk), apk_bytes=apk.stat().st_size,
                       identity=verify_apk(apk, paths, env), javac=javac, platform="36", build_tools="36.0.0",
                       source_sha256={p.relative_to(ROOT).as_posix(): sha256(p) for p in sources})
        (out / "build-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps(receipt))
    except (GateError, OSError) as failure:
        receipt.update(status="BUILD_BLOCKED_OR_FAILED", reason=str(failure))
        if created_output:
            (out / "build-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps(receipt))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
