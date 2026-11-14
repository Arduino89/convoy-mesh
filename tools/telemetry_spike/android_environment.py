#!/usr/bin/env python3
"""Synthetic EMULATOR-only radio/proxy controls and scoped resource samples.

Never runs on a physical serial. Saves no network names, raw logs or memory dumps.
App data/PSS are debug-emulator observations, not production or battery estimates.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import urllib.parse

from android_lab_control import PACKAGE, adb


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['offline', 'online', 'managed-proxy', 'sample'])
    parser.add_argument('--receipt', type=Path, required=True)
    args = parser.parse_args()
    if not adb('get-serialno').startswith('emulator-'):
        raise SystemExit('Refusing global radio/proxy changes on a non-emulator device')
    receipt = {'utc': datetime.now(timezone.utc).isoformat(), 'action': args.action,
               'scope': 'SYNTHETIC_EMULATOR_ONLY', 'battery': 'NOT_MEASURED'}
    receipt['guest_utc'] = adb('shell','-n','date','-u','+%Y-%m-%dT%H:%M:%SZ')
    if args.action == 'offline':
        adb('shell','-n','svc','wifi','disable')
        adb('shell','-n','svc','data','disable')
        adb('shell','-n','cmd','connectivity','airplane-mode','enable')
    elif args.action == 'online':
        adb('shell','-n','cmd','connectivity','airplane-mode','disable')
        adb('shell','-n','svc','wifi','enable')
        adb('shell','-n','svc','data','enable')
    elif args.action == 'managed-proxy':
        proxy = urllib.parse.urlsplit(os.environ.get('HTTPS_PROXY',''))
        if proxy.hostname != '127.0.0.1' or proxy.username or not proxy.port:
            raise SystemExit('Expected this managed environment\'s loopback proxy; inspect other configurations')
        adb('shell','-n','settings','put','global','http_proxy','10.0.2.2:' + str(proxy.port))
        receipt['managed_proxy_configured'] = True
    else:
        memory = adb('shell','-n','dumpsys','meminfo',PACKAGE)
        for label, key in [('TOTAL PSS','total_pss_kib'), ('TOTAL RSS','total_rss_kib')]:
            match = re.search(re.escape(label) + r':\s*(\d+)',memory)
            receipt[key] = int(match[1]) if match else None
        size = adb('exec-out','run-as',PACKAGE,'du','-sk','.')
        if not re.fullmatch(r'\d+\s+\.',size):
            raise RuntimeError('Cannot attest scoped app-data size')
        receipt['all_lab_app_data_kib'] = int(size.split()[0])
    for key in ('airplane_mode_on','wifi_on','mobile_data'):
        receipt[key] = adb('shell','-n','settings','get','global',key)
    connectivity = adb('shell','-n','dumpsys','connectivity')
    match = re.search(r'Active default network:\s*(\S+)',connectivity)
    receipt['active_default_network'] = match[1] if match else 'UNPARSED'
    with args.receipt.open('a') as output:
        output.write(json.dumps(receipt) + '\n')
    print(json.dumps(receipt))


if __name__ == '__main__':
    main()
