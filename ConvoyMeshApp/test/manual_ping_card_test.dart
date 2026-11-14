import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_mesh/pages/manual_ping_card.dart';

void main() {
  testWidgets('no credential field; a missing build config blocks ping',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ManualPingCard(
        configuredOverride: false,
      ))),
    ));
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    final button = find.widgetWithText(FilledButton, 'Invia ping di prova');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(find.textContaining('Invio non configurato'), findsOneWidget);
    expect(find.textContaining('ping_id:'), findsNothing);
  });

  testWidgets('one press triggers one attempt, then the button is disabled',
      (tester) async {
    final ids = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ManualPingCard(
        configuredOverride: true,
        pingSenderOverride: (id) async {
          ids.add(id);
          return 200;
        },
      ))),
    ));
    final button = find.widgetWithText(FilledButton, 'Invia ping di prova');
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(ids, isEmpty);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(ids, hasLength(1));
    expect(RegExp(r'^[a-f0-9]{32}$').hasMatch(ids.single), isTrue);
    expect(find.textContaining('HTTP 200: richiesta accettata'), findsOneWidget);
    expect(find.textContaining('ping_id:'), findsOneWidget);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
  });
}
