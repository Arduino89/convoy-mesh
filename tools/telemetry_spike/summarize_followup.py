#!/usr/bin/env python3
"""Recompute local follow-up findings; absent phases are NOT_RUN, never PASS."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path

from probe import reconcile


def read_rows(path):
    return [json.loads(s) for s in path.read_text().splitlines() if s]


def summarize(root):
    result = {'scope': 'LOCAL_NATIVE_SDK_WIRE_NOT_CLOUD', 'phases': {}, 'wire': {}}
    for phase in ['normal', 'revoke', 'retry', 'overflow']:
        p = root / phase
        if not (p / 'received.jsonl').exists():
            result['phases'][phase] = {'status': 'NOT_RUN_OR_INCOMPLETE'}
            continue
        finding = reconcile(read_rows(p / 'expected.jsonl'), read_rows(p / 'received.jsonl'))
        finding['status'] = 'OBSERVED'
        result['phases'][phase] = finding
    for name in ['wire-normal', 'wire-retry', 'wire-overflow']:
        p = root / name / 'requests.jsonl'
        if not p.exists():
            continue
        requests = read_rows(p)
        violations = Counter()
        uuids = defaultdict(list)
        properties = set()
        headers = set()
        for request in requests:
            violations.update(request['violations'])
            headers.update(request['headers_safe'])
            for event in request['events']:
                properties.update(event['property_keys'])
                if event['event_id']:
                    uuids[event['event_id']].append(event['uuid'])
        repeated = {k: {'rows': len(v), 'distinct_uuids': sorted(set(v), key=str)}
                    for k, v in uuids.items() if len(v) > 1}
        result['wire'][name] = {
            'requests': len(requests), 'event_rows': sum(len(v) for v in uuids.values()),
            'unique_event_ids': len(uuids), 'repeated_business_ids': repeated,
            'property_keys': sorted(properties), 'header_names': sorted(headers),
            'violation_counts': dict(violations),
            'close_without_response_count': sum(r['response_mode'] == 'close_without_response_after_fsync'
                                                for r in requests),
            'wire_body_bytes': sum(r['wire_body_bytes'] for r in requests),
            'privacy_pass': bool(requests) and not violations,
            'privacy_status': 'NOT_RUN' if not requests else 'FAIL' if violations else 'PASS',
        }
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('root', type=Path)
    args = p.parse_args()
    print(json.dumps(summarize(args.root), indent=2))


if __name__ == '__main__':
    main()
