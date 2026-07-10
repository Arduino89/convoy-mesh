import 'dart:convert';

import 'package:convoy_mesh/services/diagnostic_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records structured UTC and monotonic events and creates an export', () {
    final recorder = DiagnosticRecorder.instance;

    if (recorder.isActive) {
      recorder.stop(reason: 'test_cleanup');
    }

    recorder.start(deviceId: 12345, deviceName: 'Fra');
    recorder.record(
      'ble',
      'rx',
      data: <String, Object?>{
        'seq': 7,
        'kind': 'POS',
      },
    );
    recorder.addMarker('peer scomparso');
    recorder.stop(reason: 'unit_test');

    expect(recorder.isActive, isFalse);
    expect(recorder.hasExport, isTrue);
    expect(recorder.lastFileName, contains('Fra'));
    expect(recorder.lastFileName, endsWith('.jsonl'));
    expect(recorder.lastStopReason, 'unit_test');

    final lines = recorder.lastContent!
        .trim()
        .split('\n')
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList(growable: false);

    expect(lines.first['category'], 'session');
    expect(lines.first['event'], 'start');
    expect(lines.last['event'], 'stop');
    expect(lines.any((line) => line['category'] == 'ble' && line['event'] == 'rx'), isTrue);
    expect(lines.any((line) => line['category'] == 'user' && line['event'] == 'marker'), isTrue);

    for (final line in lines) {
      expect(line['ts_utc'], isA<String>());
      expect(line['elapsed_ms'], isA<int>());
      expect(line['session_id'], isA<String>());
      expect(line['device_id'], 12345);
      expect(line['device_name'], 'Fra');
    }
  });

  test('formats four-minute countdown labels', () {
    expect(DiagnosticRecorder.formatDuration(const Duration(minutes: 4)), '04:00');
    expect(DiagnosticRecorder.formatDuration(const Duration(seconds: 9)), '00:09');
  });
}
