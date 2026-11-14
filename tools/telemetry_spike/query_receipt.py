#!/usr/bin/env python3
"""Normalize a complete PostHog execute-sql JSON receipt, preserving duplicates.

Only the seven-column synthetic query is accepted. This does not run a query or
certify freshness: preserve its execution time/project separately in evidence.
"""
import argparse
import csv
from decimal import Decimal
import io
import json
from pathlib import Path

from probe import validate, write_jsonl

COLUMNS = ['schema_version', 'run_id', 'event_id', 'sequence', 'event_name',
           'synthetic', 'geoip_disabled']


def integer(text):
    number = Decimal(text)
    if not number.is_finite() or number != number.to_integral_value():
        raise ValueError('Expected an exact finite integer')
    return int(number)


def normalize(receipt, limit=500):
    raw = receipt.get('results')
    if not isinstance(raw, str) or '<taxonomy_warnings>' in raw:
        raise ValueError('Inspect warnings or unexpected provider format before normalization')
    reader = csv.DictReader(io.StringIO(raw), delimiter='|')
    if reader.fieldnames != COLUMNS:
        raise ValueError('Unexpected query columns')
    rows = []
    for record in reader:
        if None in record or any(value is None for value in record.values()):
            raise ValueError('Incomplete query row')
        if record.pop('geoip_disabled') != 'True' or record['synthetic'] != 'True':
            raise ValueError('Synthetic/GeoIP controls are not affirmative')
        record['synthetic'] = True
        for key in ('schema_version', 'sequence'):
            record[key] = integer(record[key])
        validate(record)
        rows.append(record)
    if len(rows) >= limit:
        raise ValueError('Result reaches the query cap: completeness is unproven')
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    rows = normalize(json.loads(args.input.read_text()))
    if args.out.exists():
        raise SystemExit('Output must be new; previous evidence is never overwritten')
    write_jsonl(args.out, rows)
    print(json.dumps({'rows': len(rows), 'scope': 'NORMALIZATION_ONLY_NO_FRESHNESS_ATTESTATION'}))


if __name__ == '__main__':
    main()
