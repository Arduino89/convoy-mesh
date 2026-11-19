import 'dart:convert';
import 'dart:io';

import 'package:convoy_mesh/services/detailed_diagnostic_upload.dart';
import 'package:flutter_test/flutter_test.dart';

// Deliberately outside test/: the regular test suite never sends cloud events.
// The existing workflow authorizes this entry point on one checkpoint only.
void main() {
  test('one explicitly authorized synthetic diagnostic batch', () async {
    const run = String.fromEnvironment('CONVOY_SYNTHETIC_RUN_ID');
    expect(RegExp(r'^[0-9]{1,20}$').hasMatch(run), isTrue);
    expect(DetailedDiagnosticUploadSender.configured, isTrue);
    final uploadId = run.padLeft(32, '0');
    final session = 'CM-CI-SYNTHETIC-$run';
    final ts = DateTime.now().toUtc().toIso8601String();
    String record(int index, String category, String action,
        Map<String, Object?> data) => jsonEncode({
          'ts_utc': ts,
          'elapsed_ms': index * 1000,
          'session_id': session,
          'device_id': 2147483646,
          'device_name': 'CI_SYNTHETIC_NOT_A_PERSON',
          'event_index': index,
          'category': category,
          'event': action,
          'data': data,
        });

    final jsonl = [
      record(0, 'session', 'start', {
        'schema_version': 2, 'app_version': '0.7.7-outdoor+17',
        'persistent_storage': false,
      }),
      record(1, 'test', 'context', {
        'source': 'tester_declared', 'environment': 'indoor',
        'self_movement': 'stationary', 'peers_movement': 'walking',
        'phone_placement': 'surface', 'screen_reported': 'mixed',
      }),
      record(2, 'gps', 'fix', {
        'source_ts_utc': ts, 'received_ts_utc': ts,
        'raw_lat': 0.125, 'raw_lon': 0.25, 'display_lat': 0.125,
        'display_lon': 0.25, 'accuracy_m': 7.5, 'fresh': true,
        'track_added': true, 'decision': 'accepted',
      }),
      record(3, 'ble', 'rx_packet', {
        'peer_id': 2147483645, 'seq': 17, 'kind': 'position', 'rssi': -73,
      }),
      record(4, 'runtime', 'snapshot', {
        'foreground_service': true,
        'peers': [{
          'id': 2147483645, 'name': 'CI_SYNTHETIC_PEER',
          'online': true, 'fix_fresh': false, 'rssi': -73,
          'lat': 0.125, 'lon': 0.25,
        }],
      }),
      record(5, 'gps', 'fix', {
        'raw_lat': 0.5, 'raw_lon': 0.75, 'accuracy_m': 25.0, 'fresh': false,
        'track_added': false, 'decision': 'rejected',
      }),
      record(6, 'user', 'marker', {'note': 'SYNTHETIC_MUST_STAY_LOCAL'}),
      record(7, 'session', 'stop', {
        'reason': 'manual_stop', 'events': 8, 'dropped_events': 0,
      }),
    ].join('\n');
    final payload = DetailedDiagnosticUpload.fromJsonl(
      jsonl, uploadIdOverride: uploadId,
    );
    expect(payload.recordCount, 7);
    expect(payload.excludedRecords, 1);
    final ids = payload.events.map((e) =>
        (e['properties'] as Map<String, Object?>)['event_index']).toList();
    expect(ids, [0, 1, 2, 3, 4, 5, 7]);
    final manifest = payload.preview;
    expect(jsonEncode(manifest), isNot(contains('SYNTHETIC_MUST_STAY_LOCAL')));
    final output = File('../build-evidence/synthetic-cloud-expected.json');
    await output.parent.create(recursive: true);
    await output.writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
    // Print only synthetic correlation metadata, not the ingestion token.
    print('SYNTHETIC_UPLOAD_ID=$uploadId EXPECTED=7 EXCLUDED=1');
    final status = await DetailedDiagnosticUploadSender.sendOnce(payload);
    print('SYNTHETIC_HTTP=$status (storage requires independent readback)');
    expect(status, inInclusiveRange(200, 299));
  }, timeout: const Timeout(Duration(seconds: 65)));
}
