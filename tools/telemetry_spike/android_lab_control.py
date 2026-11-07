#!/usr/bin/env python3
"""Inspect/control only the synthetic LAB package through a local adb server.

Run in the emulator's network namespace. Taps resolve current semantic labels;
no coordinates are guessed. This tool never reads Convoy or global device logs.
"""
import argparse
from datetime import datetime, timezone
import json
import re
import subprocess
import xml.etree.ElementTree as ET

PACKAGE = 'com.cama.telemetry.convoy_telemetry_lab'


def adb(*args):
    return subprocess.check_output(['adb', *args], stdin=subprocess.DEVNULL,
                                   text=True, timeout=45).strip()


def ui():
    output = adb('shell', '-n', 'uiautomator', 'dump', '/sdcard/telemetry-lab-ui.xml')
    if 'dumped to:' not in output or 'ERROR' in output:
        raise RuntimeError('UI snapshot failed; never reuse the previous XML')
    tree = ET.fromstring(adb('exec-out', 'cat', '/sdcard/telemetry-lab-ui.xml'))
    nodes = []
    for node in tree.iter('node'):
        if node.get('package') != PACKAGE:
            continue
        label = node.get('content-desc') or node.get('text')
        if label:
            nodes.append({'label': label, 'bounds': node.get('bounds'),
                          'clickable': node.get('clickable') == 'true',
                          'enabled': node.get('enabled') == 'true'})
    return nodes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['inspect', 'tap', 'status', 'launch', 'stop'])
    parser.add_argument('--label')
    parser.add_argument('--software-rendering', action='store_true')
    args = parser.parse_args()
    result = {'utc': datetime.now(timezone.utc).isoformat(), 'action': args.action,
              'package': PACKAGE}
    if args.action == 'inspect':
        result['nodes'] = ui()
    elif args.action == 'tap':
        matches = [n for n in ui() if n['label'] == args.label and n['enabled'] and n['clickable']]
        if len(matches) != 1:
            raise SystemExit('Expected exactly one visible enabled semantic button: ' + repr(matches))
        node = matches[0]
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', node['bounds']))
        adb('shell', '-n', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
        result['selected'] = node
    elif args.action == 'status':
        raw = adb('exec-out', 'run-as', PACKAGE, 'cat', 'shared_prefs/FlutterSharedPreferences.xml')
        allowed = {'flutter.run_id', 'flutter.sequence', 'flutter.refused', 'flutter.consent'}
        result['intent_preferences'] = {
            n.get('name'): n.get('value', n.text) for n in ET.fromstring(raw)
            if n.get('name') in allowed}
        result['pid'] = adb('shell', '-n', 'pidof', PACKAGE)
        result['scope'] = 'INTENT_NOT_SDK_ACK_OR_DELIVERY'
    elif args.action == 'launch':
        extra = ['--ez', 'enable-software-rendering', 'true', '--ez', 'enable-impeller', 'false'] if args.software_rendering else []
        result['software_rendering'] = args.software_rendering
        result['result'] = adb('shell', '-n', 'am', 'start', '-n', PACKAGE + '/.MainActivity', *extra)
    elif args.action == 'stop':
        result['result'] = adb('shell', '-n', 'am', 'force-stop', PACKAGE)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
