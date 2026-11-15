import 'package:convoy_mesh/ble/ble_radar_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ready state is green and scan remains a separate signal', () {
    final view = describeBleStatus('ready');
    expect(view.label, 'Bluetooth pronto');
    expect(view.ready, isTrue);
    expect(view.action, BleStatusAction.readyInfo);
    expect(view.explanation, contains('scansione'));
  });

  test('blocked or unresolved BLE states are red with truthful settings route', () {
    final expected = <String, BleStatusAction>{
      'poweredOff': BleStatusAction.bluetoothSettings,
      'unauthorized': BleStatusAction.appPermissions,
      'unsupported': BleStatusAction.explain,
      'unknown': BleStatusAction.explain,
      'locationServicesDisabled': BleStatusAction.locationSettings,
    };
    for (final e in expected.entries) {
      final p = describeBleStatus(e.key);
      expect(p.ready, isFalse, reason: e.key);
      expect(p.action, e.value, reason: e.key);
      expect(p.label, isNot(contains('ready')));
      expect(p.explanation.isNotEmpty, isTrue);
    }
    expect(describeBleStatus('unknown').explanation,
      contains('causa non è ancora accertata'));
    expect(describeBleStatus('unsupported').label,
      'Bluetooth non supportato');
  });

  testWidgets('status is tappable, translated and updates from green to red',
      (tester) async {
    var taps = 0;
    Future<void> show(String status) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: BleStatusBanner(
        statusName: status,
        onTap: () => taps++,
      ))));
    await show('ready');
    expect(find.text('Bluetooth pronto'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ble-status-tap')));
    expect(taps, 1);
    await show('unknown');
    expect(find.text('Bluetooth da verificare'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ble-status-tap')));
    expect(taps, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('concentric scan waves only render when scan is active',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ScanStatusChip(scanning: false))));
    expect(find.text('Scan OFF'), findsOneWidget);
    expect(find.byType(ScanPulseIcon), findsNothing);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ScanStatusChip(scanning: true))));
    expect(find.text('Scan ON'), findsOneWidget);
    expect(find.byType(ScanPulseIcon), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ScanStatusChip(scanning: false))));
    expect(find.byType(ScanPulseIcon), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
