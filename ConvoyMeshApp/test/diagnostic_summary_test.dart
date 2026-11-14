import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_mesh/services/diagnostic_summary.dart';

Map<String, Object?> evt(
  int elapsedMs, String category, String event, Map<String, Object?> data,
) => {
  'elapsed_ms': elapsedMs,
  'ts_utc': '2026-11-14T15:10:00Z',
  'session_id': 'private-session-to-strip',
  'device_id': 77777,
  'device_name': 'private-name',
  'category': category,
  'event': event,
  'data': data,
};

void main() {
  test('real event shapes yield useful metrics, no guessed live percentage', () {
    final log = [
      evt(0, 'session', 'start', {}),
      evt(1000, 'runtime', 'snapshot', {
        'peers': [
          {'id': 1234, 'name': 'Secret A', 'lat': 44.5, 'lon': 10.6,
           'online': true, 'fix_fresh': false},
          {'id': 5678, 'name': 'Secret B', 'online': false, 'fix_fresh': false}
        ]
      }),
      evt(6100, 'runtime', 'snapshot', {
        'peers': [
          {'id': 1234, 'name': 'Secret A', 'online': true, 'fix_fresh': true}
        ]
      }),
      evt(17000, 'runtime', 'snapshot', {'peers': []}),
      evt(20000, 'ble', 'rx_decision', {
        'peer_id': 1234, 'accepted_packet': true, 'seq': 123
      }),
      evt(21000, 'ble', 'rx_decision', {'accepted_packet': false}),
      evt(22000, 'ble', 'rx_parse_rejected', {'reason': 'no_magic'}),
      evt(23000, 'ble', 'tx_native_error', {'error': 'private stack text'}),
      evt(24000, 'gps', 'fix', {
        'raw_lat': 44.5, 'raw_lon': 10.6, 'fresh': true, 'decision': 'accepted'
      }),
      evt(25000, 'gps', 'fix', {'raw_lat': 45.6, 'fresh': false}),
      evt(28000, 'user', 'marker', {'note': 'Private free text'}),
      evt(30000, 'session', 'stop', {'dropped_events': 2})
    ].map(jsonEncode).join('\n');
    final result = DiagnosticSummary.fromJsonl(log);
    final preview = result.toReviewFields();
    expect(preview['schema_version'], 1);
    expect(preview['duration_s'], 30);
    expect(preview['snapshot_count'], 3);
    expect(preview['online_peer_samples'], 2);
    expect(preview['stale_peer_samples'], 1);
    expect(preview['capture_gap_count'], 1);
    expect(preview['max_capture_gap_s'], 10);
    expect(preview['ble_rx_accepted'], 1);
    expect(preview['ble_rx_rejected'], 2);
    expect(preview['ble_tx_native_errors'], 1);
    expect(preview['gps_fix_count'], 2);
    expect(preview['gps_fresh_fix_count'], 1);
    expect(preview['dropped_events'], 2);
    expect(preview['completed'], true);
    final encoded = jsonEncode(preview);
    for (final privateField in [
      'Secret A', 'Secret B', 'Private', 'raw_lat', 'raw_lon',
      'session_id', 'device_id', 'device_name', 'peer_id',
      'ts_utc', '44.5', '10.6', '77777', 'seq'
    ]) {
      expect(encoded.contains(privateField), isFalse,
          reason: 'Sensitive or unapproved content leaked: ' + privateField);
    }
    expect(preview.values.every((x) => x is int || x is bool), isTrue);
  });

  test('malformed/incomplete records are flagged, never treated as success', () {
    final log = [
      jsonEncode(evt(0, 'session', 'start', {})),
      '{not valid json',
      jsonEncode(evt(8000, 'runtime', 'snapshot', {'peers': []})),
      jsonEncode(evt(20000, 'runtime', 'snapshot', {'peers': []})),
      jsonEncode(evt(-1, 'gps', 'fix', {'fresh': true})),
    ].join('\n');
    final fields = DiagnosticSummary.fromJsonl(log).toReviewFields();
    expect(fields['completed'], false);
    expect(fields['invalid_records'], 2);
    expect(fields['capture_gap_count'], 1);
    expect(fields['max_capture_gap_s'], 12);
    expect(fields['gps_fix_count'], 0);
  });

  test('no GPS or peers observed remains zero samples, not false precision', () {
    final log = [
      jsonEncode(evt(0, 'session', 'start', {})),
      jsonEncode(evt(4000, 'session', 'stop', {'dropped_events': 0})),
    ].join('\n');
    final fields = DiagnosticSummary.fromJsonl(log).toReviewFields();
    expect(fields['snapshot_count'], 0);
    expect(fields['online_peer_samples'], 0);
    expect(fields['gps_fix_count'], 0);
    expect(fields['completed'], true);
  });
}
