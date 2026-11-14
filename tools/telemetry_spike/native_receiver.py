#!/usr/bin/env python3
"""Loopback-only mock ingestion for the real SDK. Does not emulate PostHog Cloud.

Save normalized synthetic fields and request sizes, never raw SDK payloads/tokens.
Start in the same network namespace as the Android emulator. No deduplication.
"""
import argparse
import gzip
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
import time

from probe import validate

FIELDS = {'schema_version', 'run_id', 'event_id', 'sequence', 'event_name', 'synthetic'}
LIMIT = 1024 * 1024


def normalize(payload):
    if payload.get('api_key') != 'phc_synthetic_local_only':
        raise ValueError('Only the synthetic local token is accepted')
    batch = payload.get('batch')
    if not isinstance(batch, list) or not 1 <= len(batch) <= 20:
        raise ValueError('Expected one SDK batch, maximum 20 events')
    rows, metadata = [], set()
    for item in batch:
        if item.get('event') != 'cm_lab_probe':
            raise ValueError('Unexpected SDK event')
        properties = item['properties']
        row = {key: properties[key] for key in FIELDS}
        validate(row)
        rows.append(row)
        metadata.update(set(properties) - FIELDS)
    return rows, sorted(metadata)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--fail-first-ack', action='store_true')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    received = args.out / 'received.jsonl'
    received.write_text('')
    requests = args.out / 'requests.jsonl'
    requests.write_text('')

    class Handler(BaseHTTPRequestHandler):
        accepted_requests = 0

        def log_message(self, *unused):
            pass

        def do_POST(self):
            status, rows, keys, body = 400, [], [], b''
            try:
                if self.headers.get('Transfer-Encoding', '').lower() == 'chunked':
                    while True:
                        size = int(self.rfile.readline(100).split(b';', 1)[0], 16)
                        if size == 0:
                            self.rfile.readline(100)
                            break
                        if len(body) + size > LIMIT:
                            raise ValueError('Request too large')
                        body += self.rfile.read(size)
                        if self.rfile.read(2) != b'\r\n':
                            raise ValueError('Bad chunk')
                else:
                    size = int(self.headers.get('Content-Length', '0'))
                    if not 0 < size <= LIMIT:
                        raise ValueError('Invalid length')
                    body = self.rfile.read(size)
                decoded = gzip.decompress(body) if body.startswith(b'\x1f\x8b') else body
                if len(decoded) > LIMIT:
                    raise ValueError('Decoded request too large')
                rows, keys = normalize(json.loads(decoded))
                with received.open('a') as out:
                    out.writelines(json.dumps(row, sort_keys=True) + '\n' for row in rows)
                Handler.accepted_requests += 1
                status = 503 if args.fail_first_ack and Handler.accepted_requests == 1 else 200
            except (ValueError, KeyError, TypeError, OSError):
                status = 400
            with requests.open('a') as out:
                out.write(json.dumps({'unix_time': time.time(), 'status': status,
                                      'wire_body_bytes': len(body), 'accepted_rows': len(rows),
                                      'extra_property_keys': keys}) + '\n')
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status":1}' if status == 200 else b'{"status":0}')

    server = HTTPServer(('127.0.0.1', args.port), Handler)
    print(json.dumps({'scope': 'REAL_SDK_LOCAL_MOCK_NOT_CLOUD', 'port': args.port}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
