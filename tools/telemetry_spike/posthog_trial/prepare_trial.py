#!/usr/bin/env python3
"""Prepare a NEW lab app only. Never changes ConvoyMeshApp or installs an APK."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import ssl
import subprocess
import sys
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--check-env', action='store_true')
    parser.add_argument('--debug-ca', type=Path, help='Optional managed proxy PUBLIC PEM CA, trusted only in debug builds')
    args = parser.parse_args()
    available = {name: shutil.which(name) is not None for name in ['flutter', 'adb', 'java', 'javac']}
    print(json.dumps({'tools': available, 'required_flutter': '3.47.4',
                      'package': 'com.cama.telemetry.convoy_telemetry_lab'}))
    if not available['flutter']:
        return 2
    # Flutter's bot detector otherwise probes cloud instance metadata before analytics
    # suppression is applied. These supported automation flags avoid that probe.
    trial_env = dict(os.environ)
    trial_env.update(CI='true', BOT='true', FLUTTER_SUPPRESS_ANALYTICS='true',
                     DASH__SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true')
    version = json.loads(subprocess.check_output(
        ['flutter', '--version', '--machine'], text=True, env=trial_env))
    if version.get('frameworkVersion') != '3.47.4':
        raise SystemExit('Use the Convoy-pinned Flutter 3.47.4; do not silently upgrade.')
    if args.check_env:
        return 0 if available['adb'] and available['javac'] else 2
    if args.out is None or args.out.exists():
        raise SystemExit('--out must be a new directory; existing apps are never overwritten.')
    out = args.out.resolve()
    subprocess.run(['flutter', 'create', '--no-pub', '--platforms', 'android',
                    '--org', 'com.cama.telemetry', '--project-name',
                    'convoy_telemetry_lab', str(out)], check=True, env=trial_env)
    source = Path(__file__).resolve().parent
    with (out / '.gitignore').open('a') as ignored:
        ignored.write('\n# Private telemetry lab configuration and debugger authorization\n*.local.json\n*.private.json\n')
    debug_ca = None
    if args.debug_ca:
        debug_ca = args.debug_ca.read_text()
        if len(debug_ca) > 65536 or 'PRIVATE KEY' in debug_ca:
            raise SystemExit('Expected one public PEM certificate, never a private key')
        ssl.PEM_cert_to_DER_cert(debug_ca)
    shutil.copy2(source / 'pubspec.yaml', out / 'pubspec.yaml')
    shutil.copy2(source / 'locks/pubspec.lock', out / 'pubspec.lock')
    shutil.copy2(source / 'main.dart', out / 'lib/main.dart')
    shutil.copy2(source / 'MainActivity.kt', out / 'android/app/src/main/kotlin/com/cama/telemetry/convoy_telemetry_lab/MainActivity.kt')
    # Delete only the template test created above for the template counter app.
    (out / 'test/widget_test.dart').unlink(missing_ok=True)
    namespace = 'http://schemas.android.com/apk/res/android'
    ET.register_namespace('android', namespace)
    manifest_path = out / 'android/app/src/main/AndroidManifest.xml'
    tree = ET.parse(manifest_path)
    root = tree.getroot()
    ET.SubElement(root, 'uses-permission', {f'{{{namespace}}}name': 'android.permission.INTERNET'})
    app = root.find('application')
    app.set(f'{{{namespace}}}label', 'Convoy Telemetry LAB')
    app.set(f'{{{namespace}}}allowBackup', 'false')
    app.set(f'{{{namespace}}}networkSecurityConfig', '@xml/lab_network_security')
    ET.SubElement(app, 'meta-data', {f'{{{namespace}}}name': 'com.posthog.posthog.AUTO_INIT',
                                    f'{{{namespace}}}value': 'false'})
    tree.write(manifest_path, encoding='unicode', xml_declaration=True)
    security = out / 'android/app/src/main/res/xml/lab_network_security.xml'
    security.parent.mkdir(parents=True, exist_ok=True)
    security_text = '''<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
  <base-config cleartextTrafficPermitted="false" />
  <domain-config cleartextTrafficPermitted="true">
    <domain includeSubdomains="false">10.0.2.2</domain>
  </domain-config>
</network-security-config>
'''
    if debug_ca:
        raw = out / 'android/app/src/main/res/raw/lab_proxy_ca.pem'
        raw.parent.mkdir(parents=True, exist_ok=True)
        raw.write_text(debug_ca)
        security_text = security_text.replace('</network-security-config>', '''  <debug-overrides>
    <trust-anchors><certificates src="@raw/lab_proxy_ca" /></trust-anchors>
  </debug-overrides>
</network-security-config>''')
    security.write_text(security_text)
    gradle = out / 'android/app/build.gradle.kts'
    text = gradle.read_text()
    old = 'minSdk = flutter.minSdkVersion'
    if old not in text:
        raise SystemExit('Unknown Flutter template: inspect generated minSdk manually, preparation incomplete.')
    text = text.replace(old, 'minSdk = 24')
    # Public native hook probe; same artifact as the existing Flutter dependency.
    text += '\ndependencies { implementation("com.posthog:posthog-android:3.75.0") }\n'
    text += '\n// Resolve once, retain gradle.lockfile, then build with the same locks.\ndependencyLocking { lockAllConfigurations() }\n'
    gradle.write_text(text)
    # Match the verified Convoy branch rather than new Flutter template versions.
    settings = out / 'android/settings.gradle.kts'
    text = settings.read_text()
    for plugin, version in [('com.android.application', '8.11.1'),
                            ('org.jetbrains.kotlin.android', '2.2.20')]:
        text, changed = re.subn(r'(id\("' + re.escape(plugin) + r'"\) version ")[^"]+(" apply false)',
                               lambda match: match[1] + version + match[2], text)
        if changed != 1:
            raise SystemExit('Unknown Android template: inspect plugin versions manually.')
    settings.write_text(text)
    wrapper = out / 'android/gradle/wrapper/gradle-wrapper.properties'
    wrapper.write_text('distributionBase=GRADLE_USER_HOME\n'
                       'distributionPath=wrapper/dists\nzipStoreBase=GRADLE_USER_HOME\n'
                       'zipStorePath=wrapper/dists\n'
                       'distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14-all.zip\n')
    shutil.copy2(source / 'locks/android-debug.lockfile', out / 'android/app/gradle.lockfile')
    properties = out / 'android/gradle.properties'
    text = properties.read_text().replace('-Xmx8G', '-Xmx2G')
    text = text.replace('-XX:MaxMetaspaceSize=4G', '-XX:MaxMetaspaceSize=1G')
    properties.write_text(text + '\norg.gradle.workers.max=2\nkotlin.compiler.execution.strategy=in-process\n')
    print(f'Prepared only: {out}. No dependency resolution, build, install or cloud call performed.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
