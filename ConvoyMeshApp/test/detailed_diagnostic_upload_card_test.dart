import 'dart:async';
import 'dart:convert';

import 'package:convoy_mesh/pages/detailed_diagnostic_upload_card.dart';
import 'package:convoy_mesh/services/detailed_diagnostic_upload.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const ts = '2026-11-15T08:00:00.000Z';
String rec(int i, String category, String event, Map<String, Object?> data) =>
    jsonEncode({
      'ts_utc': ts, 'elapsed_ms': i * 1000,
      'session_id': 'CM-synthetic', 'device_id': 123,
      'device_name': 'Alpha', 'event_index': i,
      'category': category, 'event': event, 'data': data,
    });
final session = [
  rec(0, 'session', 'start', {}),
  rec(1, 'runtime', 'snapshot', {
    'peers': [{'id': 222, 'name': 'Bravo', 'lat': 45.12, 'lon': 10.13}]
  }),
  rec(2, 'gps', 'fix', {'raw_lat': 45.12, 'raw_lon': 10.13}),
  rec(3, 'session', 'stop', {}),
].join('\n');

void main() {
  testWidgets('requires own and each peer opt-in, exact preview and second confirmation',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [
      DetailedDiagnosticUploadCard(
        jsonl: session,
        configuredOverride: true,
        senderOverride: (DetailedDiagnosticUpload payload) async {
          attempts++;
          expect(payload.peerLabels.keys.single, 222);
          return 200;
        },
      ),
    ]))));
    await tester.pumpAndSettle();
    final send = find.text('Invia diagnostica a PostHog');
    expect(tester.widget<FilledButton>(find.ancestor(
      of: send, matching: find.byType(FilledButton)).first).onPressed, isNull);
    final checks = find.byType(CheckboxListTile);
    expect(checks, findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      await tester.ensureVisible(checks.at(i));
      await tester.tap(checks.at(i));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(attempts, 0);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(attempts, 0);
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confermo invio a PostHog EU'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.textContaining('Archiviazione ancora da verificare'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.ancestor(
      of: send, matching: find.byType(FilledButton)).first).onPressed, isNull);
  });

  testWidgets('no retry after ambiguous network outcome', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [
      DetailedDiagnosticUploadCard(
        jsonl: [
          rec(0, 'session', 'start', {}),
          rec(1, 'session', 'stop', {}),
        ].join('\n'),
        configuredOverride: true,
        senderOverride: (_) async {
          calls++;
          throw TimeoutException('synthetic');
        },
      ),
    ]))));
    await tester.pumpAndSettle();
    for (final check in find.byType(CheckboxListTile).evaluate().toList()) {
      final finder = find.byWidget(check.widget);
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }
    final send = find.text('Invia diagnostica a PostHog');
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confermo invio a PostHog EU'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('esito incerto'), findsOneWidget);
  });
}
