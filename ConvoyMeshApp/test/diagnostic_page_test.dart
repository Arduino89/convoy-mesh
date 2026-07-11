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

    await tester.tap(find.text('Avvia test • max 4 min'));
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

    recorder.stop(reason: 'widget_test');
    expect(recorder.lastContent, contains('"event":"marker"'));
    expect(recorder.lastContent, contains('Francesca non vede più Cama'));
  });
}
