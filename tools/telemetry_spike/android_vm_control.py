#!/usr/bin/env python3
"""Call the debug-only LAB service extension when emulator UI automation fails.

The authenticated extension executes the same _action methods as LAB buttons.
No SDK internals or stored state are overwritten. Not a UI/release-mode test.
Only the lab process's service announcement is read; logs are never saved.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import urllib.parse
import urllib.request

from android_lab_control import PACKAGE, adb
from probe import event

EXTENSION = 'ext.convoyTelemetryLab.control'
ACTIONS = ['connect', 'status', 'grant', 'revoke', 'generate10', 'generate45', 'generate100', 'flush']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=ACTIONS)
    parser.add_argument('--connection', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--run-id', required=True)
    args = parser.parse_args()
    event(args.run_id, 1)
    pid = adb('shell', '-n', 'pidof', PACKAGE)
    if not re.fullmatch(r'\d+', pid):
        raise RuntimeError('Expected exactly one lab process')
    if args.action == 'connect':
        logs = adb('logcat', '-d', '--pid=' + pid, '-s', 'flutter:I', '*:S')
        urls = re.findall(r'http://127\.0\.0\.1:(\d+)/([A-Za-z0-9_=-]+)/', logs)
        if not urls:
            raise RuntimeError('No debug service for this lab process')
        port, code = urls[-1]
        adb('forward', 'tcp:8999', 'tcp:' + port)
        connection = {'base': 'http://127.0.0.1:8999/' + code + '/', 'pid': pid, 'run_id': args.run_id}
    else:
        connection = json.loads(args.connection.read_text())
        if connection['pid'] != pid or connection['run_id'] != args.run_id:
            raise RuntimeError('Process or run changed; reconnect explicitly')
    base = connection['base']
    if not re.fullmatch(r'http://127\.0\.0\.1:8999/[A-Za-z0-9_=-]+/', base):
        raise ValueError('Only the local authenticated debug forward is allowed')
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def rpc(method, **params):
        with opener.open(base + method + '?' + urllib.parse.urlencode(params), timeout=45) as response:
            result = json.load(response)
        if 'error' in result:
            raise RuntimeError('VM request failed: ' + str(result['error']))
        return result.get('result', result)

    receipt = {'utc': datetime.now(timezone.utc).isoformat(), 'action': args.action,
               'scope': 'ACTUAL_LAB_CALLBACK_VIA_DEBUG_EXTENSION_NOT_UI_TEST', 'pid': pid}
    if args.action == 'connect':
        vm = rpc('getVM')
        isolates = [i for i in vm['isolates'] if i['name'] == 'main']
        if len(isolates) != 1:
            raise RuntimeError('Expected one main isolate')
        isolate = rpc('getIsolate', isolateId=isolates[0]['id'])
        if EXTENSION not in isolate['extensionRPCs']:
            raise RuntimeError('LAB extension not ready: ' + json.dumps({
                'runnable':isolate.get('runnable'),
                'pause_kind':isolate.get('pauseEvent',{}).get('kind'),
                'extension_count':len(isolate['extensionRPCs'])}))
        connection['isolate_id'] = isolate['id']
        with open(args.connection, 'w', opener=lambda p, f: os.open(p, f, 0o600)) as output:
            json.dump(connection, output)
        args.connection.chmod(0o600)
        receipt['connected'] = True
    else:
        result = rpc(EXTENSION, isolateId=connection['isolate_id'], run_id=args.run_id, action=args.action)
        if result.get('run_id') != args.run_id or result.get('action_ok') is False or str(result.get('status','')).startswith('Errore locale:'):
            raise RuntimeError('LAB response does not attest successful action')
        receipt['state'] = result
    with args.receipt.open('a') as output:
        output.write(json.dumps(receipt, ensure_ascii=False) + '\n')
    print(json.dumps(receipt, ensure_ascii=False))


if __name__ == '__main__':
    main()
