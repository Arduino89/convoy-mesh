import 'dart:convert';

import 'package:convoy_mesh/services/detailed_diagnostic_upload.dart';
import 'package:flutter_test/flutter_test.dart';

const fixedUploadId = '0123456789abcdef0123456789abcdef';
const ts = '2026-11-15T08:00:00.000Z';

String record(int index, String category, String action,
    Map<String, Object?> data,
    {String sessionId = 'CM-test-123', int deviceId = 123}) {
  return jsonEncode({
    'ts_utc': ts, 'elapsed_ms': index * 1000,
    'session_id': sessionId, 'device_id': deviceId,
    'device_name': 'Alpha', 'event_index': index,
    'category': category, 'event': action, 'data': data,
  });
}

String fixture() => [
  record(0, 'session', 'start', {
    'schema_version': 2, 'app_version': '0.7.7-diaglab+13',
    'build_commit': '0123456789abcdef', 'persistent_storage': true,
  }),
  record(1, 'gps', 'fix', {
    'source_ts_utc': ts, 'received_ts_utc': ts,
    'raw_lat': 45.234567, 'raw_lon': 10.987654,
    'display_lat': 45.234560, 'display_lon': 10.987650,
    'accuracy_m': 9.5, 'fresh': true,
    'decision': 'accepted', 'secret_note': 'do not send',
  }),
  record(2, 'ble', 'rx_packet', {
    'peer_id': 222, 'seq': 17, 'kind': 'position', 'rssi': -72,
    'payload_hex': 'secret-hex-byte-string',
  }),
  record(3, 'runtime', 'snapshot', {
    'foreground_service': true,
    'peers': [{
      'id': 222, 'name': 'Bravo',
      'online': true, 'fix_fresh': false,
      'lat': 45.234530, 'lon': 10.987600,
      'last_seen_utc': ts,
      'free_text': 'do not send',
    }],
    'error_text': 'do not send',
  }),
  record(4, 'ble', 'history_attempt', {
    'history_seq': 27, 'target_peer_ids': [222],
    'unacked_peer_ids': [222], 'attempt': 2,
  }),
  record(5, 'user', 'marker', {'note': 'secret detailed personal note'}),
  record(6, 'session', 'stop', {
    'reason': 'manual_stop', 'events': 7, 'dropped_events': 0,
  }),
].join('\n');

void main() {
  test('preserves exact diagnostic GPS, BLE, nickname, history and local times', () {
    final selected = DetailedDiagnosticUpload.fromJsonl(
      fixture(), uploadIdOverride: fixedUploadId);
    expect(selected.recordCount, 6);
    expect(selected.excludedRecords, 1);
    expect(selected.peerLabels, {222: 'Bravo'});
    expect(selected.sessionId, 'CM-test-123');
    final batch = selected.events;
    final gps = (batch[1]['properties'] as Map<String, Object?>);
    expect(gps['raw_lat'], 45.234567);
    expect(gps['raw_lon'], 10.987654);
    expect(gps['display_lat'], 45.234560);
    expect(gps['captured_ts_utc'], ts);
    expect(gps['elapsed_ms'], 1000);
    final radio = batch[2]['properties'] as Map<String, Object?>;
    expect(radio['peer_id'], 222);
    expect(radio['rssi'], -72);
    expect(radio['seq'], 17);
    final snapshot = batch[3]['properties'] as Map<String, Object?>;
    expect((snapshot['peers'] as List).single['name'], 'Bravo');
    final history = batch[4]['properties'] as Map<String, Object?>;
    expect(history['unacked_peer_ids'], [222]);
    expect(batch.every((e) => e['event'] == 'cm_beta_diag_record'), isTrue);
    expect(batch.every((e) => (e['properties'] as Map)[r'$process_person_profile'] == false), isTrue);
    expect(batch.every((e) => (e['properties'] as Map)[r'$geoip_disable'] == true), isTrue);
  });

  test('fixed schema excludes user notes, raw BLE packets and arbitrary errors', () {
    final selected = DetailedDiagnosticUpload.fromJsonl(
      fixture(), uploadIdOverride: fixedUploadId);
    final payload = jsonEncode(selected.preview);
    for (final secret in [
      'secret-hex-byte-string', 'secret detailed personal note',
      'do not send', 'secret_note', 'payload_hex', 'free_text',
      'api_key', 'token'
    ]) {
      expect(payload.contains(secret), isFalse, reason: secret);
    }
    final body = DetailedDiagnosticUploadSender.requestBody(
      selected, 'phc_1234567890abcdefghijklmn');
    expect(body.keys.toSet(), {'token', 'batch'});
    expect(body['batch'], same(selected.events));
  });

  test('rejects malformed, mixed, incomplete and impossible GPS records', () {
    expect(() => DetailedDiagnosticUpload.fromJsonl('not json',
      uploadIdOverride: fixedUploadId), throwsFormatException);
    final noStop = fixture().split('\n')..removeLast();
    expect(() => DetailedDiagnosticUpload.fromJsonl(noStop.join('\n'),
      uploadIdOverride: fixedUploadId), throwsFormatException);
    final mixed = [
      record(0, 'session', 'start', {}),
      record(1, 'session', 'stop', {}, sessionId: 'wrong-session'),
    ];
    expect(() => DetailedDiagnosticUpload.fromJsonl(mixed.join('\n'),
      uploadIdOverride: fixedUploadId), throwsFormatException);
    final invalidGps = [
      record(0, 'session', 'start', {}),
      record(1, 'gps', 'fix', {'raw_lat': 123.0}),
      record(2, 'session', 'stop', {}),
    ];
    expect(() => DetailedDiagnosticUpload.fromJsonl(invalidGps.join('\n'),
      uploadIdOverride: fixedUploadId), throwsFormatException);
  });

  test('fails closed rather than truncating large sessions', () {
    final records = <String>[record(0, 'session', 'start', {})];
    for (var i = 1; i <= DetailedDiagnosticUpload.maxRecords; i++) {
      records.add(record(i, 'ble', 'rx_decision',
        {'peer_id': 222, 'accepted_packet': true}));
    }
    records.add(record(DetailedDiagnosticUpload.maxRecords + 1,
      'session', 'stop', {}));
    expect(() => DetailedDiagnosticUpload.fromJsonl(records.join('\n'),
      uploadIdOverride: fixedUploadId), throwsFormatException);
  });
}
