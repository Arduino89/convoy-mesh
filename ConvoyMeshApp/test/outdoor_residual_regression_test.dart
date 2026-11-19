import 'dart:async';

import 'package:convoy_mesh/ble/ble_page.dart';
import 'package:convoy_mesh/design/design_presets.dart';
import 'package:convoy_mesh/design/design_theme.dart';
import 'package:convoy_mesh/design/outdoor_config.dart';
import 'package:convoy_mesh/design/radar/radar_scope.dart';
import 'package:convoy_mesh/main.dart';
import 'package:convoy_mesh/pages/diagnostic_page.dart';
import 'package:convoy_mesh/pages/map_page.dart';
import 'package:convoy_mesh/services/diagnostic_capture_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('D2 actual AppShell mutes only the hidden pages', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // The production bridge is process-scoped. Capture its timer for cleanup
    // in this isolated test; no diagnostic capture or native service is started.
    Timer? bridgeTimer;
    runZoned(
      () => DiagnosticCaptureBridge.instance.attach(),
      zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          final timer = parent.createPeriodicTimer(zone, duration, callback);
          bridgeTimer = timer;
          return timer;
        },
      ),
    );
    bool enabled(Type type) => TickerMode.of(
          tester.element(find.byType(type, skipOffstage: false)),
        );

    try {
      await tester.pumpWidget(
        const MaterialApp(home: AppShell()),
      );
      await tester.pump();
      expect(enabled(BlePage), isTrue, reason: 'selected radar must be enabled');
      expect(enabled(MapPage), isFalse, reason: 'D2_EXPECT_HIDDEN_MUTED');
      expect(enabled(DiagnosticPage), isFalse);
      for (final index in [1, 2, 0]) {
        final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
        nav.onDestinationSelected!(index);
        await tester.pump();
        expect(enabled(BlePage), index == 0);
        expect(enabled(MapPage), index == 1);
        expect(enabled(DiagnosticPage), index == 2);
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      bridgeTimer?.cancel();
    }
  });

  testWidgets('D9 running radar adopts new period without resetting phase',
      (tester) async {
    Widget view(int period, {bool scanning = true}) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: RadarScope(
                  tokens: DesignPresets.buildOutdoor(
                    OutdoorCustomConfig(radarPeriodMs: period),
                  ),
                  peers: const [],
                  scanning: scanning,
                ),
              ),
            ),
          ),
        );

    Finder paints() => find.descendant(
          of: find.byType(RadarScope),
          matching: find.byType(CustomPaint),
        );
    double phase() {
      final painter = tester.widget<CustomPaint>(paints().first).painter;
      return (painter as dynamic).progress as double;
    }

    await tester.pumpWidget(view(9000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    final before = phase();
    expect(before, closeTo(0.1, 0.02), reason: 'positive control: old speed');

    await tester.pumpWidget(view(2400));
    await tester.pump();
    expect(phase(), closeTo(before, 0.02), reason: 'no discontinuous phase jump');
    await tester.pump(const Duration(milliseconds: 1200));
    final delta = (phase() - before + 1.0) % 1.0;
    expect(delta, closeTo(0.5, 0.03), reason: 'D9_EXPECT_NEW_RATE');

    await tester.pumpWidget(view(2400, scanning: false));
    await tester.pump();
    expect(paints(), findsOneWidget, reason: 'stopped radar has no sweep');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('D11 actual MapPage retains camera in both style directions',
      (tester) async {
    final outdoor = ValueNotifier<bool>(false);
    addTearDown(outdoor.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: outdoor,
        builder: (context, useOutdoor, _) => MaterialApp(
          theme: useOutdoor
              ? buildConvoyTheme(DesignPresets.outdoorPremium)
              : ThemeData(useMaterial3: true),
          themeAnimationDuration: Duration.zero,
          home: const MapPage(),
        ),
      ),
    );
    await tester.pump();
    // Turn off tile requests before the camera/style experiment.
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.byType(TileLayer), findsNothing);

    final mapFinder = find.byType(FlutterMap);
    final initialState = tester.state(mapFinder);
    final controller = tester.widget<FlutterMap>(mapFinder).mapController!;
    const centre = LatLng(46.17, 11.28);
    const zoom = 12.75;
    const rotation = 31.0;
    controller.move(centre, zoom);
    controller.rotate(rotation);
    await tester.pump();

    void expectCamera() {
      expect(controller.camera.center.latitude, closeTo(centre.latitude, 0.000001));
      expect(controller.camera.center.longitude, closeTo(centre.longitude, 0.000001));
      expect(controller.camera.zoom, closeTo(zoom, 0.000001));
      expect(controller.camera.rotation, closeTo(rotation, 0.000001));
    }

    expectCamera(); // positive control: the user actually moved the camera.
    for (final style in [true, false, true]) {
      outdoor.value = style;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(identical(tester.state(mapFinder), initialState), isTrue,
          reason: 'D11_EXPECT_SAME_MAP');
      expectCamera();
      expect(find.byType(TileLayer), findsNothing,
          reason: 'theme changes must not turn online tiles back on');
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
