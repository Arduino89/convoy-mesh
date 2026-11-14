import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_mesh/pages/manual_ping_card.dart';

void main() {
  testWidgets('no ping can start without explicit consent and a valid token',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ManualPingCard())),
    ));
    final button = find.widgetWithText(FilledButton, 'Invia ping di prova (una sola volta)');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    final consent = find.byType(CheckboxListTile);
    expect(tester.widget<CheckboxListTile>(consent).value, false);
    await tester.tap(consent);
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    // Invalid token: state is rejected before any network request is created.
    await tester.tap(button);
    await tester.pump();
    expect(find.textContaining('Inserisci soltanto il token di progetto'), findsOneWidget);
    expect(find.textContaining('ping_id:'), findsNothing);
  });
}
