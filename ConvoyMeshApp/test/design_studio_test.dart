import 'dart:math' as math;

import 'package:convoy_mesh/ble/ble_page.dart';
import 'package:convoy_mesh/ble/ble_radar_ui.dart';
import 'package:convoy_mesh/ble/convoy_ble_codec.dart';
import 'package:convoy_mesh/design/design_controller.dart';
import 'package:convoy_mesh/design/design_direction_picker.dart';
import 'package:convoy_mesh/design/design_presets.dart';
import 'package:convoy_mesh/design/design_theme.dart';
import 'package:convoy_mesh/design/design_tokens.dart';
import 'package:convoy_mesh/design/diagnostic/designed_diagnostic_header.dart';
import 'package:convoy_mesh/design/map/designed_map_chrome.dart';
import 'package:convoy_mesh/design/radar/designed_radar_view.dart';
import 'package:convoy_mesh/design/radar/radar_actions.dart';
import 'package:convoy_mesh/design/radar/radar_live_adapter.dart';
import 'package:convoy_mesh/design/radar/radar_scope.dart';
import 'package:convoy_mesh/design/radar/radar_view_data.dart';
import 'package:convoy_mesh/design/shell/designed_app_shell.dart';
import 'package:convoy_mesh/design/studio/frontend_design_studio_page.dart';
import 'package:convoy_mesh/design/studio/synthetic_radar_fixtures.dart';
import 'package:convoy_mesh/location/gps_visual_state.dart';
import 'package:convoy_mesh/pages/diagnostic_page.dart';
import 'package:convoy_mesh/services/background_runtime_service.dart';
import 'package:convoy_mesh/services/convoy_mesh_service.dart';
import 'package:convoy_mesh/services/location_fusion_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _contrastRatio(Color fg, Color bg) {
  final opaqueFg = Color.alphaBlend(fg, bg);
  final l1 = opaqueFg.computeLuminance();
  final l2 = bg.computeLuminance();
  final light = math.max(l1, l2);
  final dark = math.min(l1, l2);
  return (light + 0.05) / (dark + 0.05);
}

void main() {
  test('all three non-classic presets meet outdoor WCAG contrast thresholds', () {
    for (final d in [
      DesignDirection.outdoorPremium,
      DesignDirection.tacticalExplorer,
      DesignDirection.minimalAdventure,
    ]) {
      final t = DesignPresets.of(d);
      expect(
        _contrastRatio(t.ink, t.canvas),
        greaterThanOrEqualTo(7.0),
        reason: '${d.name}: ink vs canvas must achieve AAA contrast',
      );
      expect(
        _contrastRatio(t.ink, t.surface),
        greaterThanOrEqualTo(7.0),
        reason: '${d.name}: ink vs surface must achieve AAA contrast',
      );
      expect(
        _contrastRatio(t.inkMuted, t.surface),
        greaterThanOrEqualTo(4.5),
        reason: '${d.name}: muted ink vs surface must achieve AA contrast',
      );
      expect(
        _contrastRatio(t.onAccent, t.accent),
        greaterThanOrEqualTo(4.5),
        reason: '${d.name}: onAccent vs accent must achieve AA contrast',
      );
      expect(
        t.minTouchTarget,
        greaterThanOrEqualTo(52),
        reason: '${d.name}: touch targets must be glove-friendly (>= 52 dp)',
      );
      final heroBase = t.heroBackground.colors.first;
      expect(
        _contrastRatio(t.heroInk, heroBase),
        greaterThanOrEqualTo(7.0),
        reason: '${d.name}: heroInk vs heroBackground must achieve AAA contrast',
      );
    }
  });

  test('RadarLiveAdapter faithfully reflects mesh state without mutating it', () {
    final now = DateTime.now();
    final mesh = ConvoyMeshService.forTest(now: () => now);
    mesh.setIdentityForTest(101);
    mesh.ingestForTest(
      ConvoyBleCodec.buildNameManufacturerData(userId: 42, seq: 1, name: 'Elena'),
      rssi: -64,
    );
    mesh.ingestForTest(
      ConvoyBleCodec.buildPositionManufacturerData(
        userId: 42,
        seq: 2,
        lat: 45.8,
        lon: 11.2,
        accuracyM: 9,
        fixAgeSeconds: 4,
      ),
      rssi: -64,
    );

    final rxBefore = mesh.rxValid;
    final view = RadarLiveAdapter.read(
      mesh: mesh,
      location: LocationFusionService.forTest(now: () => now),
      runtime: BackgroundRuntimeService.instance,
      now: now,
    );
    expect(mesh.rxValid, rxBefore);
    expect(view.myId, 101);
    expect(view.onlineCount, 1);
    expect(view.offlineCount, 0);
    expect(view.peers.single.name, 'Elena');
    expect(view.peers.single.locationState, PeerLocationState.fresh);
    expect(view.peers.single.signalLevel, 3);
    expect(view.diagnosticsLines, isNotEmpty);
  });

  testWidgets('all three radar directions render cleanly on narrow phone + 1.3x font scale',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final d in [
      DesignDirection.outdoorPremium,
      DesignDirection.tacticalExplorer,
      DesignDirection.minimalAdventure,
    ]) {
      final tokens = DesignPresets.of(d);
      for (final scenario in SyntheticScenario.values) {
        final triggered = <String>[];
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              textScaler: TextScaler.linear(1.3),
              disableAnimations: true,
            ),
            child: MaterialApp(
              theme: buildConvoyTheme(tokens),
              home: DesignedRadarView(
                tokens: tokens,
                data: SyntheticRadarFixtures.of(scenario),
                actions: RadarActions.recording(triggered.add),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: '${d.name}/${scenario.name} produced layout or runtime exception');

        await tester.tap(find.byKey(const Key('design-ble-status-tap')));
        expect(triggered, contains('status'));
        await tester.tap(find.byKey(const Key('design-edit-name')));
        expect(triggered, contains('editName'));
        await tester.tap(find.byKey(const Key('design-open-studio-btn')));
        expect(triggered, contains('chooseDesign'));
      }
    }
  });

  testWidgets('RadarScope stops animation under disableAnimations and shows empty hint',
      (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 260,
                child: RadarScope(
                  tokens: DesignPresets.outdoorPremium,
                  peers: [],
                  scanning: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('In ascolto nel raggio BLE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DesignedBottomDock, DesignedMapScaffold and DesignedDiagnosticStatusStrip work cleanly',
      (tester) async {
    var selectedIdx = 0;
    var toggledOuting = false;
    var locateTapped = false;
    var basemapOnline = true;
    const tokens = DesignPresets.tacticalExplorer;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildConvoyTheme(tokens),
        home: Scaffold(
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: DesignedDiagnosticStatusStrip(
                tokens: tokens,
                active: true,
                ready: true,
                persistent: true,
                elapsed: const Duration(minutes: 1, seconds: 20),
                remaining: const Duration(minutes: 2, seconds: 40),
                eventCount: 42,
                droppedEvents: 0,
              ),
            ),
            Expanded(
              child: DesignedMapScaffold(
                tokens: tokens,
                gpsVisual: const GpsVisualState(
                  mode: GpsVisualMode.stable,
                  quality: 90,
                  blinkPeriod: null,
                  label: 'GPS agganciato • qualità 90%',
                ),
                gpsStatusText: 'GPS agganciato • qualità 90%.',
                onlineBasemap: basemapOnline,
                peerCountWithFix: 2,
                hasOwnTrail: true,
                mapChild: const SizedBox.expand(),
                onLocate: () => locateTapped = true,
                onToggleBasemap: (v) => basemapOnline = v,
                onClearTrail: () {},
                onChooseDesign: () {},
              ),
            ),
          ]),
          bottomNavigationBar: DesignedBottomDock(
            tokens: tokens,
            selectedIndex: selectedIdx,
            onSelectIndex: (i) => selectedIdx = i,
            outingActive: false,
            busy: false,
            error: null,
            onToggleOuting: () => toggledOuting = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('designed-outing-toggle')));
    expect(toggledOuting, isTrue);
    await tester.tap(find.text('CENTRA SU DI ME'));
    expect(locateTapped, isTrue);
    await tester.tap(find.text('MAPPA'));
    expect(selectedIdx, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DesignDirectionController defaults to classic and Design Studio applies choices',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = DesignDirectionController.forTest();
    expect(controller.direction, DesignDirection.classic);
    expect(controller.isClassic, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: FrontendDesignStudioPage(controller: controller),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.byKey(const Key('studio-dir-outdoorPremium')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Radar BLE'), findsWidgets);

    await tester.tap(find.text('Applica'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.direction, DesignDirection.outdoorPremium);
    expect(controller.isClassic, isFalse);

    await controller.select(DesignDirection.classic);
    expect(controller.isClassic, isTrue);
  });

  testWidgets('showDesignDirectionPicker lists all four directions and launches studio',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = DesignDirectionController.forTest();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDesignDirectionPicker(context, controller: controller),
                child: const Text('Apri'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('design-direction-classic')), findsOneWidget);
    expect(find.byKey(const Key('design-direction-outdoorPremium')), findsOneWidget);
    expect(find.byKey(const Key('design-direction-tacticalExplorer')), findsOneWidget);
    expect(find.byKey(const Key('design-direction-minimalAdventure')), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-design-studio-sheet-btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(FrontendDesignStudioPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a peer entry in DesignedRadarView toggles peer highlight on scope',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const tokens = DesignPresets.outdoorPremium;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844), disableAnimations: true),
        child: MaterialApp(
          theme: buildConvoyTheme(tokens),
          home: DesignedRadarView(
            tokens: tokens,
            data: SyntheticRadarFixtures.of(SyntheticScenario.groupHike),
            actions: RadarActions.recording((_) {}),
          ),
        ),
      ),
    );
    await tester.pump();

    var scope = tester.widget<RadarScope>(find.byType(RadarScope));
    expect(scope.selectedPeerId, isNull);

    // Tap Marco's blip ('MR') directly on RadarScope -> highlights and shows label.
    await tester.tap(find.text('MR'));
    await tester.pump();
    scope = tester.widget<RadarScope>(find.byType(RadarScope));
    expect(scope.selectedPeerId, 1042);

    // Scroll to the peer card, tap it to deselect, then verify after scrolling back up.
    await tester.scrollUntilVisible(
      find.text('Marco R.').last,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Marco R.').last);
    await tester.pump();
    await tester.tap(find.text('Marco R.').last);
    await tester.pump();

    await tester.drag(find.byKey(const Key('designed-radar-list')), const Offset(0, 600));
    await tester.pump();
    scope = tester.widget<RadarScope>(find.byType(RadarScope));
    expect(scope.selectedPeerId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BlePage and DiagnosticPage switch cleanly between classic and redesigned themes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final design = DesignDirectionController.instance;
    await design.select(DesignDirection.classic);
    addTearDown(() async => design.select(DesignDirection.classic));

    await tester.pumpWidget(
      AnimatedBuilder(
        animation: design,
        builder: (context, _) => MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: design.isClassic
                ? ThemeData(
                    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
                    useMaterial3: true,
                  )
                : buildConvoyTheme(DesignPresets.of(design.direction)),
            home: const BlePage(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BleStatusBanner), findsOneWidget);
    expect(find.byKey(const Key('radar-open-design-btn')), findsOneWidget);
    expect(find.byType(DesignedRadarView), findsNothing);

    await design.select(DesignDirection.tacticalExplorer);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(DesignedRadarView), findsOneWidget);
    expect(find.byType(BleStatusBanner), findsNothing);
    expect(find.byKey(const Key('design-open-studio-btn')), findsOneWidget);

    await design.select(DesignDirection.classic);
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: design,
        builder: (context, _) => MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: design.isClassic
                ? ThemeData(
                    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
                    useMaterial3: true,
                  )
                : buildConvoyTheme(DesignPresets.of(design.direction)),
            home: DiagnosticPage(
              deviceIdOverride: 12345,
              deviceNameOverride: 'TestPhone',
              captureNowOverride: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(DesignedDiagnosticStatusStrip), findsNothing);
    expect(find.text('Avvia registrazione diagnostica • max 4 min'), findsOneWidget);

    await design.select(DesignDirection.outdoorPremium);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(DesignedDiagnosticStatusStrip), findsOneWidget);
    expect(find.text('Avvia registrazione diagnostica • max 4 min'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DesignedMapScaffold opens legend sheet and confirms before clearing trail',
      (tester) async {
    var cleared = false;
    const tokens = DesignPresets.minimalAdventure;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildConvoyTheme(tokens),
        home: DesignedMapScaffold(
          tokens: tokens,
          gpsVisual: const GpsVisualState(
            mode: GpsVisualMode.off,
            quality: 0,
            blinkPeriod: null,
            label: 'Posizione non agganciata',
          ),
          gpsStatusText: 'GPS non agganciato.',
          onlineBasemap: false,
          peerCountWithFix: 0,
          hasOwnTrail: true,
          mapChild: const SizedBox.expand(),
          onLocate: () {},
          onToggleBasemap: (_) {},
          onClearTrail: () => cleared = true,
          onChooseDesign: () {},
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('Legenda mappa'), findsOneWidget);
    Navigator.of(tester.element(find.text('Legenda mappa'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Cancellare la tua traccia?'), findsOneWidget);
    expect(cleared, isFalse);

    await tester.tap(find.text('Cancella traccia'));
    await tester.pumpAndSettle();
    expect(cleared, isTrue);
  });
}
