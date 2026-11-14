#!/usr/bin/env python3
"""Emit bounded, scanned synthetic evidence in job logs, without artifact storage."""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import zipfile

from ci_native_trial import audit_public_directory, validate_public_value, TrialBlocked


def public_json(text):
    def unique_pairs(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError('Duplicate evidence key')
            value[key] = item
        return value
    def reject_constant(_):
        raise ValueError('Non-finite evidence scalar')
    value = json.loads(text, object_pairs_hook=unique_pairs, parse_constant=reject_constant)
    validate_public_value(value)
    return value


def collect(root):
    files = {}
    # Explicitly enumerate control/build receipts; never include APKs or logs.
    for relative in ('runtime-control-build/build-receipt.json',
                     'runtime-control-smoke/receipt.json',
                     'lab-build/build-receipt.json',
                     'direct-build/build-receipt.json'):
        path = root / relative
        if path.is_file():
            if path.is_symlink() or path.stat().st_size > 65536:
                raise TrialBlocked('RECEIPT_TYPE_OR_SIZE_REJECTED')
            value = public_json(path.read_text())
            files[relative] = (json.dumps(value, sort_keys=True) + '\n').encode()
    for folder in ('lab-public', 'direct-public', 'cloud-public'):
        public = root / folder
        if not public.exists():
            continue
        if folder == 'cloud-public':
            from ci_cloud_trial import audit_public_directory as audit_cloud
            audit_cloud(public)
        elif folder == 'direct-public':
            from ci_direct_trial import audit_public_directory as audit_direct
            audit_direct(public)
        else:
            audit_public_directory(public)
        for path in sorted(public.rglob('*')):
            if path.is_file():
                if path.suffix == '.jsonl':
                    values = [public_json(line) for line in path.read_text().splitlines() if line]
                    data = ''.join(json.dumps(value, sort_keys=True, allow_nan=False) + '\n'
                                   for value in values).encode()
                else:
                    data = (json.dumps(public_json(path.read_text()), sort_keys=True, allow_nan=False) + '\n').encode()
                files[folder + '/' + path.relative_to(public).as_posix()] = data
    if sum(len(value) for value in files.values()) > 4 * 1024 * 1024:
        raise TrialBlocked('EVIDENCE_SIZE_EXCEEDS_SYNTHETIC_BUDGET')
    if not files:
        return None
    digest_lines = ''.join(hashlib.sha256(data).hexdigest() + '  ' + name + '\n'
                           for name, data in sorted(files.items()))
    files['SHA256SUMS.txt'] = digest_lines.encode()
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(files.items()):
            archive.writestr(name, data)
    data = stream.getvalue()
    if len(data) > 1024 * 1024:
        raise TrialBlocked('COMPRESSED_EVIDENCE_TOO_LARGE')
    return data, sorted(files)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    try:
        result = collect(args.root)
    except (TrialBlocked, ValueError, OSError, TypeError):
        print('CONVOY_EVIDENCE_STATUS=BLOCKED_UNSAFE_OR_INVALID_OUTPUT')
        raise SystemExit(1)
    if result is None:
        print('CONVOY_EVIDENCE_STATUS=NOT_RUN_NO_RECEIPTS')
        return
    data, names = result
    encoded = base64.b64encode(data).decode('ascii')
    chunks = [encoded[i:i + 4096] for i in range(0, len(encoded), 4096)]
    print('CONVOY_EVIDENCE_MANIFEST=' + json.dumps({
        'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data),
        'chunks': len(chunks), 'files': names}, separators=(',', ':')))
    for index, chunk in enumerate(chunks):
        print('CONVOY_EVIDENCE_CHUNK=' + str(index) + ':' + chunk)


if __name__ == '__main__':
    main()
