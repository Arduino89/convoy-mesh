#!/usr/bin/env python3
"""Run a phase of the LOCAL fake-token SDK trial in the emulator namespace.

Receiver must already be listening. No APK installation or data clearing here.
Use distinct output directories for each phase; all unknown outcomes fail closed.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time

from android_lab_control import PACKAGE, adb
from probe import event, reconcile
from runtime_control.smoke import validate_ready, validate_transition

HERE = Path(__file__).resolve().parent
RUNTIME_STAGES = [
    'verify_apk', 'boot_and_package_manager', 'install_verified_control',
    'first_resumed_ready', 'force_stop_pid_absent', 'second_resumed_ready',
    'new_pid_persisted_counter_same_boot', 'control_stopped_data_preserved',
]


def validate_runtime_gate(receipt, serial, boot_id):
    """A historical or different-emulator success cannot authorize this phase."""
    if (type(receipt.get('schema_version')) is not int or receipt['schema_version'] != 1 or
            receipt.get('status') != 'PASS_NATIVE_RUNTIME_CONTROL' or
            receipt.get('scope') != 'NATIVE_RUNTIME_CONTROL_ONLY' or
            receipt.get('gate_pass') is not True or
            receipt.get('telemetry_tested') is not False):
        raise RuntimeError('Successful independent native runtime control required')
    stages = receipt.get('stages', [])
    if (not isinstance(stages, list) or
            any(not isinstance(stage, dict) for stage in stages) or
            [stage.get('name') for stage in stages] != RUNTIME_STAGES or
            any(stage.get('pass') is not True for stage in stages)):
        raise RuntimeError('Complete native runtime observations required')
    identity = receipt.get('identity', {})
    if (identity.get('package') != 'com.cama.telemetry.runtime_control' or
            identity.get('requested_permissions') != [] or
            identity.get('min_sdk') != 24 or identity.get('target_sdk') != 36 or
            identity.get('version_code') != 1 or identity.get('version_name') != '1.0' or
            not re.fullmatch(r'[a-f0-9]{64}', receipt.get('apk_sha256', ''))):
        raise RuntimeError('Verified native control APK identity required')
    observations = [stages[index].get('observation', {}) for index in (3, 5)]
    for observation in observations:
        nonce, pid = observation.get('nonce', ''), observation.get('pid')
        if (not isinstance(nonce, str) or not re.fullmatch(r'[a-f0-9]{32}', nonce) or
                type(pid) is not int or pid <= 0):
            raise RuntimeError('Native control launch observations missing')
        validate_ready(observation, nonce, pid)
    validate_transition(*observations)
    if not re.fullmatch(r'emulator-\d+', serial) or receipt.get('serial') != serial:
        raise RuntimeError('Runtime control belongs to a different emulator')
    if (not re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', boot_id) or
            receipt.get('boot_id') != boot_id):
        raise RuntimeError('Runtime control belongs to a different Android boot')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('phase', choices=['normal', 'revoke', 'retry', 'overflow'])
    p.add_argument('--run-id', required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--wire', type=Path, required=True)
    p.add_argument('--runtime-gate', type=Path, required=True,
                   help='PASS receipt from runtime_control/smoke.py on this Android boot')
    args = p.parse_args()
    event(args.run_id, 1)
    gate_bytes = args.runtime_gate.read_bytes()
    gate = json.loads(gate_bytes)
    serial = adb('get-serialno')
    if not re.fullmatch(r'emulator-\d+', serial):
        raise SystemExit('Synthetic emulator only')
    boot_id = adb('shell', '-n', 'cat', '/proc/sys/kernel/random/boot_id')
    validate_runtime_gate(gate, serial, boot_id)
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    (out / 'runtime-gate-reference.json').write_text(json.dumps({
        'receipt_sha256': hashlib.sha256(gate_bytes).hexdigest(),
        'serial': serial, 'boot_id': boot_id, 'status': gate['status']}, indent=2) + '\n')
    connection = out / 'vm.private.json'
    actions = out / 'actions.jsonl'
    environment = out / 'environment.jsonl'
    lifecycle = out / 'lifecycle.jsonl'

    def command(script, *values):
        result = subprocess.run([sys.executable, str(HERE / script), *map(str, values)],
                                capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise RuntimeError(script + ' failed; ' + result.stderr[-600:])
        return json.loads(result.stdout.strip().splitlines()[-1])

    def vm(action):
        r = command('android_vm_control.py', action, '--connection', connection,
                    '--receipt', actions, '--run-id', args.run_id)
        state = r.get('state')
        if state:
            if state.get('action_ok') is not True or state.get('native_filter') is not True:
                raise RuntimeError('Explicit native action success required')
        return state or r

    def connect():
        deadline = time.monotonic() + 120
        while True:
            try:
                vm('connect')
                return vm('status')
            except (RuntimeError, subprocess.TimeoutExpired):
                if time.monotonic() >= deadline:
                    raise
                time.sleep(2)

    def network(action):
        command('android_environment.py', action, '--receipt', environment)
        deadline = time.monotonic() + 45
        while True:
            sample = command('android_environment.py', 'sample', '--receipt', environment)
            active = sample['active_default_network']
            offline = sample['airplane_mode_on'] == '1' and active == 'none'
            online = sample['airplane_mode_on'] == '0' and active.isdigit()
            if (action == 'offline' and offline) or (action == 'online' and online):
                return sample
            if time.monotonic() >= deadline:
                raise RuntimeError('Network state not independently confirmed')
            time.sleep(2)

    def restart():
        before = adb('shell', '-n', 'pidof', PACKAGE)
        command('android_lab_control.py', 'stop')
        command('android_lab_control.py', 'launch', '--software-rendering')
        state = connect()
        after = adb('shell', '-n', 'pidof', PACKAGE)
        if before == after:
            raise RuntimeError('Process restart not established')
        with lifecycle.open('a') as f:
            f.write(json.dumps({'utc': datetime.now(timezone.utc).isoformat(),
                               'before_pid': before, 'after_pid': after,
                               'state': state}) + '\n')
        return state

    def rows():
        return [json.loads(line) for line in (args.wire / 'received.jsonl').read_text().splitlines()]

    def observe(target, minimum_seconds=5):
        start = time.monotonic()
        while time.monotonic() - start < 150:
            result = rows()
            if len(result) >= target and time.monotonic() - start >= minimum_seconds:
                return result
            time.sleep(2)
        return rows()  # Retain failure evidence; never change the expected oracle.

    state = connect()
    sentinel = state['sentinels']
    if (sentinel.get('preference') != 'synthetic-setting-preserve' or
            sentinel.get('file_sha256') in (None, 'MISSING') or
            sentinel.get('marker_exists') is not True):
        raise RuntimeError('Initial unrelated-data sentinels are invalid')
    print(json.dumps({'phase': args.phase, 'start': state}), flush=True)
    start_seq = state['requested']
    base_rows = len(rows())
    if args.phase in ('normal', 'overflow'):
        oracle_first, oracle_count = 1, (100 if args.phase == 'normal' else 45)
    elif args.phase == 'revoke':
        oracle_first, oracle_count = start_seq + 21, 10
        (out / 'revoked-intent.jsonl').write_text(''.join(json.dumps(event(args.run_id, i)) + '\n'
            for i in range(start_seq + 1, start_seq + 21)))
    else:
        oracle_first, oracle_count = start_seq + 1, 10
    expected = [event(args.run_id, i) for i in range(oracle_first, oracle_first + oracle_count)]
    (out / 'expected.jsonl').write_text(''.join(json.dumps(row) + '\n' for row in expected))
    if args.phase in ('normal', 'overflow'):
        if start_seq != 0 or state['consent']:
            raise RuntimeError('Fresh opted-out LAB installation required')
        network('online')
        vm('generate10')
        state = restart()
        vm('generate10')
        time.sleep(5)
        summary = json.loads((args.wire / 'summary.json').read_text())
        if summary['requests'] != 0:
            raise RuntimeError('Refused install emitted requests')
        network('offline')
        vm('grant')
        count = 100 if args.phase == 'normal' else 45
        vm('generate' + str(count))
        time.sleep(5)  # Orderly queue persistence observation, not crash-during-write.
        state = restart()
        if state['requested'] != count or state['sentinels'] != sentinel:
            raise RuntimeError('Intent or unrelated storage did not survive restart')
        network('offline')
        network('online')
        vm('flush')
        target = count if count == 100 else 32
        received = observe(target)
        expected = [event(args.run_id, i) for i in range(1, count + 1)]
    elif args.phase == 'revoke':
        network('offline')
        vm('generate10'); vm('generate10')
        time.sleep(5)
        revoked = vm('revoke')
        if revoked['consent'] or revoked['sentinels'] != sentinel:
            raise RuntimeError('Revocation state or unrelated storage failed')
        vm('generate10')
        state = restart()
        if state['consent'] or state['sentinels'] != sentinel:
            raise RuntimeError('Revoked state or unrelated storage lost on restart')
        network('offline')
        vm('grant')  # Explicitly BEFORE reconnect.
        vm('generate10')
        network('online')
        vm('flush')
        received = observe(base_rows + 10, 15)[base_rows:]
        expected = [event(args.run_id, i) for i in range(start_seq + 21, start_seq + 31)]
        (out / 'revoked-intent.jsonl').write_text(''.join(json.dumps(event(args.run_id, i)) + '\n'
            for i in range(start_seq + 1, start_seq + 21)))
    else:
        network('online')
        vm('generate10')
        vm('flush')
        received = observe(20, 15)
        expected = [event(args.run_id, i) for i in range(start_seq + 1, start_seq + 11)]
    vm('flush')
    time.sleep(5)
    final_state = vm('status')
    if final_state['sentinels'] != sentinel:
        raise RuntimeError('Unrelated data changed after delivery')
    # Reload after the extra flush so delayed rows are not silently omitted.
    received = rows()[base_rows:]
    expected_path, received_path = out / 'expected.jsonl', out / 'received.jsonl'
    for path, data in [(expected_path, expected), (received_path, received)]:
        path.write_text(''.join(json.dumps(r) + '\n' for r in data))
    result = reconcile(expected, received)
    result.update(phase=args.phase, scope='ACTUAL_NATIVE_SDK_LOCAL_WIRE_NOT_POSTHOG_CLOUD',
                  sentinels_unchanged=True, final_state=final_state)
    result['wire_audit'] = json.loads((args.wire / 'summary.json').read_text())
    (out / 'validation.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)


if __name__ == '__main__':
    main()
