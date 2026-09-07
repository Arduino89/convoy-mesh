import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_mesh/services/diagnostic_recorder.dart';

void main() {
  test('a flushed session prefix survives without pressing Stop', () async {
    final directory = await Directory.systemTemp.createTemp('convoy-recorder-');
    final recorder = DiagnosticRecorder.forTest();
    addTearDown(() async { recorder.stop(reason: 'cleanup'); await recorder.flush(); await directory.delete(recursive: true); });
    await recorder.initialize(directory: directory);
    recorder.start(deviceId: 42, deviceName: 'Fra');
    recorder.record('gps', 'synthetic', data: {'accuracy': double.nan});
    await recorder.flush();
    final files = await directory.list().where((f) => f.path.endsWith('.jsonl')).toList();
    expect(files, hasLength(1));
    final prefix = (await File(files.single.path).readAsLines()).map((line) => jsonDecode(line) as Map).toList();
    expect(prefix, hasLength(2));
    expect((prefix.last['data'] as Map)['accuracy'], isNull);
    final recovered = DiagnosticRecorder.forTest();
    await recovered.initialize(directory: directory);
    expect(recovered.hasExport, isTrue);
    expect(recovered.lastContent, contains('synthetic'));
    expect(recovered.lastStopReason, 'recovered_file_check_session_stop');
    recorder.stop(reason: 'unit_test'); await recorder.flush();
    final last = jsonDecode((await File(files.single.path).readAsLines()).last) as Map;
    expect(last['event'], 'stop');
  });
  test('full buffer still retains the terminal record and dropped-event count', () {
    final recorder = DiagnosticRecorder.forTest();
    recorder.start(deviceId: 42, deviceName: 'Synthetic');
    for (var i = 0; i < DiagnosticRecorder.maxEvents + 5; i++) { recorder.record('test', 'sample'); }
    recorder.stop(reason: 'limit_test');
    final lines = recorder.lastContent!.trim().split('\n');
    expect(lines, hasLength(DiagnosticRecorder.maxEvents));
    final last = jsonDecode(lines.last) as Map;
    expect(last['event'], 'stop');
    expect((last['data'] as Map)['dropped_events'], greaterThan(0));
  });
  test('uninitialised identity cannot create an ambiguous device-zero log', () {
    final recorder = DiagnosticRecorder.forTest();
    recorder.start(deviceId: 0, deviceName: 'User');
    expect(recorder.isActive, isFalse);
    expect(recorder.hasExport, isFalse);
  });
}
