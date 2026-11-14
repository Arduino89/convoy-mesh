import 'package:convoy_mesh/pages/diagnostic_page.dart';
import 'package:convoy_mesh/services/diagnostic_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts recording and saves first defect marker without framework errors', (tester) async {
    final recorder = DiagnosticRecorder.instance;
    if (recorder.isActive) {
      recorder.stop(reason: 'test_cleanup');
    }

    await tester.pumpWidget(
      MaterialApp(
        home: DiagnosticPage(
          deviceIdOverride: 12345,
          deviceNameOverride: 'TestPhone',
          captureNowOverride: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Avvia registrazione diagnostica • max 4 min'));
    await tester.pump();

    expect(recorder.isActive, isTrue);
    expect(find.text('Segna qui un problema'), findsOneWidget);

    await tester.tap(find.text('Segna qui un problema'));
    await tester.pumpAndSettle();

    expect(find.text('Segna il problema'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField),
      'Francesca non vede più Cama',
    );
    await tester.tap(find.text('Aggiungi'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Segna il problema'), findsNothing);
    expect(recorder.isActive, isTrue);

    // Stopping the recording must not implicitly open Android's share sheet.
    await tester.tap(find.text('Termina registrazione diagnostica'));
    await tester.pumpAndSettle();
    expect(recorder.isActive, isFalse);
    expect(recorder.hasExport, isTrue);
    expect(recorder.lastStopReason, 'manual_stop');
    expect(find.text('Condividi file (manuale)'), findsOneWidget);
    expect(find.text('Riepilogo tecnico locale'), findsOneWidget);
    expect(find.textContaining('Invio a PostHog non ancora abilitato'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(recorder.lastContent, contains('"event":"marker"'));
    expect(recorder.lastContent, contains('Francesca non vede più Cama'));
  });
}
