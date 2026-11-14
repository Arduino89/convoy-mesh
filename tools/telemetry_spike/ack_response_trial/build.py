#!/usr/bin/env python3
"""Compose permissionless Android proofs with the existing pinned toolchain."""
import argparse
import json
from pathlib import Path
import re
import sys
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parent))
from runtime_control.build import GateError, installed_tools, run, sha256, valid_sdk_bounds

BASE_SOURCE = "75b83254c99f20703f8a4ddbcc0da92a41d9990c"
BASE_JAVA_SHA = "81222e42f65f27d5524ad80b5b66eb5f685b6f3091e5d467a564636ecaa31312"
ACTIVITY = "com.cama.telemetry.direct_lab.ResponseProofActivity"


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for key in ("sdk", "jdk", "out", "baseline_java"):
        p.add_argument("--" + key.replace("_", "-"), type=Path, required=True)
    p.add_argument("--source-commit", required=True)
    a = p.parse_args()
    if not re.fullmatch(r"[a-f0-9]{40}", a.source_commit): p.error("exact source required")
    if sha256(a.baseline_java) != BASE_JAVA_SHA: raise GateError("baseline Java bytes differ")
    out = a.out.resolve()
    if out == ROOT or ROOT in out.parents: raise GateError("output must be outside repository")
    out.mkdir(parents=True, exist_ok=False)
    paths, env, javac = installed_tools(a.sdk, a.jdk)
    receipts = []
    for variant, source in (("before", a.baseline_java),
                            ("after", ROOT / "tools/telemetry_spike/direct_trial/DirectQueue.java")):
        build = out / variant; build.mkdir()
        classes, dex = build / "classes", build / "dex"; classes.mkdir(); dex.mkdir()
        package = "com.cama.telemetry.ack_" + variant
        manifest = build / "AndroidManifest.xml"
        manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
            'package="' + package + '" android:versionCode="1" android:versionName="1.0">'
            '<uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36"/>'
            '<application android:label="Offline ACK proof" android:debuggable="true" '
            'android:allowBackup="false" android:usesCleartextTraffic="false">'
            '<activity android:name="' + ACTIVITY + '" android:exported="true"/>'
            '</application></manifest>')
        activity = HERE / "ResponseProofActivity.java"
        run([paths["javac"], "-source", "8", "-target", "8", "-encoding", "UTF-8",
             "-classpath", paths["android_jar"], "-d", classes, source, activity], env=env)
        with zipfile.ZipFile(build / "classes.jar", "w") as jar:
            for item in sorted(classes.rglob("*.class")): jar.write(item, item.relative_to(classes).as_posix())
        run([paths["d8"], "--lib", paths["android_jar"], "--min-api", "24", "--output", dex,
             build / "classes.jar"], env=env)
        run([paths["aapt2"], "link", "-o", build / "base.apk", "-I", paths["android_jar"],
             "--manifest", manifest, "--min-sdk-version", "24", "--target-sdk-version", "36"], env=env)
        with zipfile.ZipFile(build / "base.apk") as src, zipfile.ZipFile(build / "unsigned.apk", "w") as dst:
            for info in src.infolist(): dst.writestr(info, src.read(info.filename))
            dst.write(dex / "classes.dex", "classes.dex")
        run([paths["zipalign"], "-f", "4", build / "unsigned.apk", build / "aligned.apk"], env=env)
        run([paths["keytool"], "-genkeypair", "-keystore", build / "debug.keystore", "-storepass", "android",
             "-keypass", "android", "-alias", "ack-proof", "-keyalg", "RSA", "-keysize", "2048",
             "-validity", "30", "-dname", "CN=Offline Synthetic ACK", "-noprompt"], env=env)
        apk = build / "ack-proof.apk"
        run([paths["apksigner"], "sign", "--ks", build / "debug.keystore", "--ks-key-alias", "ack-proof",
             "--ks-pass", "pass:android", "--key-pass", "pass:android", "--out", apk, build / "aligned.apk"], env=env)
        badging = run([paths["aapt2"], "dump", "badging", apk], env=env)
        identity = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.M)
        if not identity or identity.groups() != (package, "1", "1.0") or not valid_sdk_bounds(badging):
            raise GateError("proof APK identity/SDK differs")
        permissions = re.findall(r"^uses-permission: name='([^']+)'", badging, re.M)
        if permissions: raise GateError("proof APK must have zero permissions")
        signature = run([paths["apksigner"], "verify", "--print-certs", apk], env=env)
        certs = re.findall(r"Signer #[0-9]+ certificate SHA-256 digest: ([a-fA-F0-9]{64})", signature)
        if len(certs) != 1: raise GateError("single verified signer required")
        receipt = {"schema_version": 1, "status": "BUILT_PERMISSIONLESS_PROOF_NOT_RUN",
            "variant": variant, "package": package, "version_name": "1.0", "version_code": 1,
            "min_sdk": 24, "target_sdk": 36, "permissions": permissions,
            "apk_bytes": apk.stat().st_size, "apk_sha256": sha256(apk), "certificate_sha256": certs[0].lower(),
            "harness_source_commit": a.source_commit,
            "queue_source_commit": BASE_SOURCE if variant == "before" else a.source_commit,
            "queue_source_sha256": sha256(source), "activity_source_sha256": sha256(activity),
            "builder_sha256": sha256(Path(__file__)), "toolchain_helper_sha256": sha256(HERE.parent / "runtime_control/build.py"),
            "javac": javac, "platform": "36", "build_tools": "36.0.0", "new_dependencies": []}
        (build / "build-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        receipts.append(receipt)
    (out / "build-receipts.json").write_text(json.dumps(receipts, indent=2) + "\n")
    print(json.dumps({"status": "BOTH_PERMISSIONLESS_PROOFS_BUILT", "permissions": [], "variants": 2}))


if __name__ == "__main__": main()
