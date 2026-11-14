#!/usr/bin/env python3
"""Strict wire observer for the real SDK; NOT a sender or PostHog emulator.

CLI binds only 127.0.0.1:8765, accepts only the built-in fake token, and requires
one synthetic run. HTTP 200 acknowledges the experiment even when audit_pass is
false. Unknown values are redacted; violations and complete key shapes remain.
No real token, raw diagnostic log or arbitrary string value is retained.
"""
import argparse
from datetime import datetime
import gzip
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import io
import json
import os
from pathlib import Path
import re
import socket
import time
from urllib.parse import parse_qsl, urlsplit
import uuid

from probe import validate

TOKEN = 'phc_synthetic_local_only'
SCOPE = 'REAL_SDK_LOOPBACK_WIRE_AUDIT_NOT_CLOUD_NOT_PRODUCTION'
LIMIT = 65536
FIELDS = {'schema_version', 'run_id', 'event_id', 'sequence', 'event_name', 'synthetic'}
PROPERTIES = FIELDS | {'$geoip_disable', '$process_person_profile'}
ENVELOPE = {'api_key', 'batch', 'sent_at'}
ITEM = {'event', 'properties', 'distinct_id', 'timestamp', 'uuid'}
HEADERS = {'host', 'user-agent', 'accept', 'accept-encoding', 'connection',
           'content-type', 'content-encoding', 'content-length', 'transfer-encoding'}
HEADER_VALUES = {
    'content-type': {'application/json', 'application/json; charset=utf-8', 'application/json;charset=utf-8'},
    'content-encoding': {'gzip', 'identity'}, 'transfer-encoding': {'chunked'},
    'connection': {'close', 'keep-alive'}, 'accept': {'*/*', 'application/json'},
    'accept-encoding': {'gzip', 'identity', 'gzip, deflate', 'gzip, deflate, br'},
}


def key(value):
    if isinstance(value, str) and re.fullmatch(r'[A-Za-z0-9_$.-]{1,96}', value):
        return value
    return '<key-sha256:' + hashlib.sha256(str(value).encode()).hexdigest() + '>'


def shape(value, depth=0):
    """Preserve unknown structure but never unknown scalar values."""
    if depth >= 10:
        return '<redacted-depth-limit>'
    if isinstance(value, dict):
        return {key(k): shape(v, depth + 1) for k, v in value.items()}
    if isinstance(value, list):
        return [shape(v, depth + 1) for v in value]
    return '<redacted:' + type(value).__name__ + '>'


def is_uuid(value):
    if not isinstance(value, str) or len(value) != 36:
        return False
    try:
        return str(uuid.UUID(value)) == value.lower()
    except ValueError:
        return False


def is_timestamp(value):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9TZ:.+\-]{10,40}', value):
        return False
    try:
        return datetime.fromisoformat(value.replace('Z', '+00:00')).tzinfo is not None
    except ValueError:
        return False


def audit_payload(payload, run_id):
    violations, rows, events = [], [], []
    safe = shape(payload)
    result = {'payload_redacted': safe, 'envelope_keys': [], 'events': events,
              'normalized_rows': rows, 'violations': violations}
    if not isinstance(payload, dict):
        violations.append('payload_not_object')
        return result
    result['envelope_keys'] = sorted(key(k) for k in payload)
    for name in sorted(set(payload) - ENVELOPE):
        violations.append('unexpected_envelope_key:' + key(name))
    if payload.get('api_key') != TOKEN:
        violations.append('non_fake_token_rejected')
        # Never normalize or acknowledge event acceptance from another project.
        return result
    safe['api_key'] = '<redacted:fake-token>'
    if 'sent_at' in payload:
        if is_timestamp(payload['sent_at']):
            safe['sent_at'] = payload['sent_at']
        else:
            violations.append('invalid_sent_at')
    batch = payload.get('batch')
    if not isinstance(batch, list) or not 1 <= len(batch) <= 20:
        violations.append('invalid_batch_size')
        return result
    for index, item in enumerate(batch):
        prefix = f'event[{index}]:'
        observation = {'index': index, 'item_keys': [], 'property_keys': [],
                       'event_id': None, 'uuid': None}
        events.append(observation)
        if not isinstance(item, dict):
            violations.append(prefix + 'not_object')
            continue
        clean = safe['batch'][index]
        observation['item_keys'] = sorted(key(k) for k in item)
        for name in sorted(set(item) - ITEM):
            violations.append(prefix + 'unexpected_item_key:' + key(name))
        for name in sorted(ITEM - set(item)):
            violations.append(prefix + 'missing_item_key:' + name)
        event_ok = item.get('event') == 'cm_lab_probe'
        if event_ok:
            clean['event'] = 'cm_lab_probe'
        else:
            violations.append(prefix + 'unexpected_event')
        if is_uuid(item.get('uuid')):
            observation['uuid'] = item['uuid']
            clean['uuid'] = item['uuid']
        else:
            violations.append(prefix + 'invalid_uuid')
        identity = item.get('distinct_id')
        # The minimum-payload contract permits only this run's synthetic ID.
        # A valid UUID belongs in the separate event uuid field, not here.
        if identity == run_id:
            clean['distinct_id'] = identity
        else:
            violations.append(prefix + 'invalid_distinct_id')
        if is_timestamp(item.get('timestamp')):
            clean['timestamp'] = item['timestamp']
        else:
            violations.append(prefix + 'invalid_timestamp')
        properties = item.get('properties')
        if not isinstance(properties, dict):
            violations.append(prefix + 'properties_not_object')
            continue
        observation['property_keys'] = sorted(key(k) for k in properties)
        for name in sorted(set(properties) - PROPERTIES):
            violations.append(prefix + 'unexpected_property:' + key(name))
        for name, expected in [('$geoip_disable', True), ('$process_person_profile', False)]:
            if properties.get(name) is expected:
                clean['properties'][name] = expected
            else:
                violations.append(prefix + 'invalid_privacy_control:' + name)
        row = {name: properties.get(name) for name in FIELDS}
        try:
            validate(row)
            if row['run_id'] != run_id or not event_ok:
                raise ValueError('Wrong run/event')
        except ValueError:
            violations.append(prefix + 'invalid_business_contract_or_run')
        else:
            rows.append(row)
            observation['event_id'] = row['event_id']
            clean['properties'].update(row)
    return result


def decode_body(body, encoding=''):
    if len(body) > LIMIT:
        raise ValueError('wire_body_limit')
    if encoding not in ('', 'gzip', 'identity'):
        raise ValueError('unsupported_content_encoding')
    if encoding == 'gzip' or body.startswith(b'\x1f\x8b'):
        # Read a bounded expansion, never gzip.decompress an unbounded payload.
        with gzip.GzipFile(fileobj=io.BytesIO(body)) as stream:
            decoded = stream.read(LIMIT + 1)
    else:
        decoded = body
    if len(decoded) > LIMIT:
        raise ValueError('decoded_body_limit')
    def no_duplicate_keys(pairs):
        result = {}
        for name, value in pairs:
            if name in result:
                raise ValueError('duplicate_json_key')
            result[name] = value
        return result
    return json.loads(decoded, object_pairs_hook=no_duplicate_keys,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite_json')))


class AuditReceiver:
    def __init__(self, out, run_id, ack_mode='normal', port=8765):
        if not re.fullmatch(r'synthetic-[a-z0-9-]{1,48}', run_id):
            raise ValueError('Expected a synthetic run ID')
        if ack_mode not in ('normal', 'close-first', '503-first'):
            raise ValueError('Unknown acknowledgement mode')
        self.out, self.run_id, self.ack_mode = Path(out), run_id, ack_mode
        self.out.mkdir(parents=True, exist_ok=False)
        self.counts = {'requests': 0, 'observed_rows': 0, 'violating_requests': 0,
                       'ack_faults': 0, 'audit_pass': None}
        self.accepted_batches = 0
        self.server = HTTPServer(('127.0.0.1', port), self._handler())
        for name in ('requests.jsonl', 'received.jsonl'):
            (self.out / name).write_text('')
        self._summary()

    def _summary(self):
        state = {'scope': SCOPE, 'run_id': self.run_id, 'ack_mode': self.ack_mode,
                 'port': self.server.server_port, 'business_fields': sorted(FIELDS),
                 'allowed_property_keys': sorted(PROPERTIES),
                 'allowed_envelope_keys': sorted(ENVELOPE), 'allowed_item_keys': sorted(ITEM),
                 'distinct_id_policy': 'exact_synthetic_run_id_only',
                 'http_200_is_not_audit_pass': True,
                 'audit_status': ('NOT_RUN' if not self.counts['requests'] else
                                  'PASS' if self.counts['audit_pass'] else 'FAIL'), **self.counts}
        temporary = self.out / 'summary.tmp'
        temporary.write_text(json.dumps(state, sort_keys=True) + '\n')
        temporary.replace(self.out / 'summary.json')

    def _append(self, name, records):
        with (self.out / name).open('a') as output:
            for record in records:
                output.write(json.dumps(record, sort_keys=True) + '\n')
            output.flush()
            os.fsync(output.fileno())

    def _handler(self):
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *unused):
                pass

            def _body(self):
                self.connection.settimeout(5)
                transfer = self.headers.get('Transfer-Encoding', '').lower()
                if transfer:
                    if transfer != 'chunked' or 'Content-Length' in self.headers:
                        raise ValueError('ambiguous_or_unsupported_transfer_encoding')
                    chunks, total = [], 0
                    while True:
                        line = self.rfile.readline(128)
                        if not line.endswith(b'\r\n') or b';' in line:
                            raise ValueError('bad_chunk_header')
                        size = int(line.strip(), 16)
                        if size < 0 or total + size > LIMIT:
                            raise ValueError('wire_body_limit')
                        if size == 0:
                            if self.rfile.readline(128) != b'\r\n':
                                raise ValueError('chunk_trailers_not_supported')
                            break
                        chunk = self.rfile.read(size)
                        if len(chunk) != size or self.rfile.read(2) != b'\r\n':
                            raise ValueError('incomplete_chunk')
                        chunks.append(chunk)
                        total += size
                    return b''.join(chunks)
                lengths = self.headers.get_all('Content-Length', [])
                if len(lengths) > 1:
                    raise ValueError('duplicate_content_length')
                length = int(lengths[0]) if lengths else 0
                if not 0 <= length <= LIMIT:
                    raise ValueError('wire_body_limit')
                body = self.rfile.read(length)
                if len(body) != length:
                    raise ValueError('incomplete_body')
                return body

            def observe(self):
                owner.counts['requests'] += 1
                violations = []
                try:
                    parts = urlsplit(self.path)
                    safe_path = parts.path if re.fullmatch(r'/[A-Za-z0-9_./-]{0,160}', parts.path) else '<redacted-path>'
                    query_keys = [key(k) for k, _ in parse_qsl(parts.query, keep_blank_values=True, max_num_fields=100)]
                    known_destination = self.command == 'POST' and parts.path in ('/batch/', '/batch') and not any(
                        (parts.query, parts.fragment, parts.scheme, parts.netloc))
                except ValueError:
                    safe_path, query_keys, known_destination = '<redacted-invalid-target>', [], False
                headers = {}
                for name in self.headers:
                    lower, value = name.lower(), self.headers[name]
                    headers[key(lower)] = '<redacted>'
                    if lower not in HEADERS:
                        violations.append('unexpected_header:' + key(lower))
                    elif lower in HEADER_VALUES:
                        if value.lower() in HEADER_VALUES[lower]:
                            headers[lower] = value
                        else:
                            violations.append('unapproved_header_value:' + lower)
                    elif lower == 'content-length' and value.isdigit():
                        headers[lower] = int(value)
                    elif lower == 'host' and re.fullmatch(r'(127\.0\.0\.1|10\.0\.2\.2|localhost)(:[0-9]{1,5})?', value):
                        headers[lower] = value
                    elif lower == 'user-agent':
                        # Expose only the exact SDK/runtime family/version, never a
                        # device/model-bearing UA or arbitrary application string.
                        if re.fullmatch(r'(PostHog|posthog-android|okhttp|Java)/[0-9.]+', value):
                            headers[lower] = value
                        else:
                            violations.append('unapproved_user_agent_value')
                    else:
                        violations.append('unapproved_header_value:' + lower)
                    if len(self.headers.get_all(name, [])) > 1:
                        violations.append('duplicate_header:' + key(lower))
                if not known_destination:
                    violations.append('unexpected_method_path_or_query')
                record = {'scope': SCOPE, 'request_index': owner.counts['requests'],
                          'unix_time': time.time(), 'method': self.command, 'path': safe_path,
                          'query_keys': query_keys, 'headers_safe': headers,
                          'wire_body_bytes': 0, 'violations': violations,
                          'normalized_rows': [], 'events': [], 'payload_redacted': None}
                try:
                    body = self._body()
                    record['wire_body_bytes'] = len(body)
                    if body:
                        parsed = decode_body(body, self.headers.get('Content-Encoding', '').lower())
                        audit = audit_payload(parsed, owner.run_id)
                        violations.extend(audit.pop('violations'))
                        record.update(audit)
                    else:
                        violations.append('empty_body')
                except (ValueError, TypeError, OSError, EOFError, RecursionError):
                    # No exception text: it can include body contents/credentials.
                    violations.append('body_rejected_or_decode_failed')
                rows = record['normalized_rows']
                record['audit_pass'] = not violations
                owner.counts['observed_rows'] += len(rows)
                if violations:
                    owner.counts['audit_pass'] = False
                    owner.counts['violating_requests'] += 1
                elif owner.counts['audit_pass'] is None:
                    owner.counts['audit_pass'] = True
                status = 200
                close_without_response = False
                if rows and known_destination:
                    owner.accepted_batches += 1
                    if owner.accepted_batches == 1 and owner.ack_mode != 'normal':
                        owner.counts['ack_faults'] += 1
                        close_without_response = owner.ack_mode == 'close-first'
                        status = 503 if owner.ack_mode == '503-first' else None
                record['response_status'] = status
                record['response_mode'] = 'close_without_response_after_fsync' if close_without_response else 'http_response'
                owner._append('received.jsonl', rows)
                owner._append('requests.jsonl', [record])
                owner._summary()
                self.close_connection = True
                if close_without_response:
                    try:
                        self.connection.shutdown(socket.SHUT_RDWR)
                    except OSError:
                        pass
                    self.connection.close()
                    return
                # Rejection concerns audit only. Fake-token violations never enter
                # received.jsonl. HTTP success must never be interpreted as PASS.
                response = owner._response_body(status)
                self.send_response(status)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(response)))
                self.end_headers()
                try:
                    self.wfile.write(response)
                except OSError:
                    pass

            do_POST = do_GET = do_PUT = do_DELETE = do_PATCH = do_OPTIONS = do_HEAD = observe

        return Handler

    def _response_body(self, status):
        return b'{"status":1}' if status == 200 else b'{"status":0}'

    def close(self):
        self.server.server_close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--run-id', required=True)
    acknowledgement = parser.add_mutually_exclusive_group()
    acknowledgement.add_argument('--ack-mode', choices=['normal', 'close-first', '503-first'], default='normal')
    acknowledgement.add_argument('--drop-first-response', dest='ack_mode', action='store_const', const='close-first',
                                 help='Alias for --ack-mode close-first; persist then close without an HTTP response')
    args = parser.parse_args()
    receiver = AuditReceiver(args.out, args.run_id, args.ack_mode)
    print(json.dumps({'scope': SCOPE, 'run_id': args.run_id, 'bind': '127.0.0.1:8765',
                      'ack_mode': args.ack_mode, 'http_200_is_not_audit_pass': True}), flush=True)
    try:
        receiver.server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        receiver.close()


if __name__ == '__main__':
    main()
