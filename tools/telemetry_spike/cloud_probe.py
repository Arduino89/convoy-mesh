#!/usr/bin/env python3
"""Send a bounded, validated synthetic export to the verified EU lab project.

This is an API transport control, NOT a mobile SDK offline test. No automatic retry.
Configuration is private; receipts never include the project token or raw payload.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import urllib.error
import urllib.request
import uuid

from probe import validate


def payload(rows, config, project_id):
    if config.get('project_id') != project_id:
        raise ValueError('Project does not match the independently verified target')
    if config.get('POSTHOG_HOST') != 'https://eu.i.posthog.com':
        raise ValueError('This lab permits only the verified EU ingestion host')
    token = config.get('POSTHOG_PROJECT_TOKEN', '')
    if not token.startswith('phc_') or token == 'phc_synthetic_local_only':
        raise ValueError('An ingestion-only project token is required')
    if not 1 <= len(rows) <= 1000:
        raise ValueError('Each explicit invocation permits 1..1000 synthetic rows')
    for row in rows:
        validate(row)
    if len({row['run_id'] for row in rows}) != 1:
        raise ValueError('Do not mix test runs')
    now = datetime.now(timezone.utc).isoformat()
    batch = [{'event': 'cm_lab_probe', 'distinct_id': row['run_id'],
              'uuid': str(uuid.uuid4()), 'timestamp': now,
              'properties': {**row, '$geoip_disable': True,
                             '$process_person_profile': False}} for row in rows]
    return {'api_key': token, 'batch': batch}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--project-id', type=int, required=True)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    rows = [json.loads(line) for line in args.input.read_text().splitlines() if line]
    config = json.loads(args.config.read_text())
    data = payload(rows, config, args.project_id)
    args.out.mkdir(parents=True, exist_ok=False)
    # Preserve all rows, including duplicate event_ids. New UUIDs mean this control
    # does not reproduce mobile UUID deduplication; every invocation is a new send.
    (args.out / 'submitted.jsonl').write_text(''.join(json.dumps(row) + '\n' for row in rows))
    (args.out / 'submission_ids.json').write_text(json.dumps([
        {'event_id': item['properties']['event_id'], 'uuid': item['uuid'],
         'timestamp': item['timestamp']} for item in data['batch']], indent=2) + '\n')
    body = json.dumps(data, separators=(',', ':')).encode()
    request = urllib.request.Request(config['POSTHOG_HOST'] + '/batch/', data=body,
                                     headers={'Content-Type': 'application/json'})
    receipt = {'scope': 'PYTHON_API_CONTROL_NOT_MOBILE_SDK', 'project_id': args.project_id,
               'run_id': rows[0]['run_id'], 'submitted_rows': len(rows),
               'request_body_bytes': len(body), 'started_at': datetime.now(timezone.utc).isoformat(),
               'automatic_retries': 0, 'delivery': 'NOT_YET_QUERIED'}
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            receipt['http_status'] = response.status
            receipt['response'] = response.read(2048).decode(errors='replace')
    except urllib.error.HTTPError as error:
        receipt['http_status'] = error.code
        receipt['delivery'] = 'UNKNOWN_QUERY_BEFORE_ANY_RESEND'
    except (OSError, urllib.error.URLError):
        receipt['http_status'] = None
        receipt['delivery'] = 'UNKNOWN_QUERY_BEFORE_ANY_RESEND'
    receipt['finished_at'] = datetime.now(timezone.utc).isoformat()
    (args.out / 'ingestion-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt, indent=2))
    return 0 if receipt['http_status'] == 200 else 2


if __name__ == '__main__':
    raise SystemExit(main())
