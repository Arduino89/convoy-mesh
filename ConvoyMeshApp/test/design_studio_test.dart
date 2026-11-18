import 'dart:convert';
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
import 'package:convoy_mesh/design/outdoor_config.dart';
import 'package:convoy_mesh/design/outdoor_copy.dart';
import 'package:convoy_mesh/design/radar/designed_radar_view.dart';
import 'package:convoy_mesh/design/radar/radar_actions.dart';
import 'package:convoy_mesh/design/radar/radar_live_adapter.dart';
import 'package:convoy_mesh/design/radar/radar_scope.dart';
import 'package:convoy_mesh/design/radar/radar_view_data.dart';
import 'package:convoy_mesh/design/shell/designed_app_shell.dart';
import 'package:convoy_mesh/design/studio/frontend_design_studio_page.dart';
import 'package:convoy_mesh/design/studio/synthetic_radar_fixtures.dart';
import 'package:convoy_mesh/location/gps_visual_state.dart';
import 'package:convoy_mesh/pages/detailed_diagnostic_upload_card.dart';
import 'package:convoy_mesh/pages/diagnostic_page.dart';
import 'package:convoy_mesh/pages/manual_ping_card.dart';
import 'package:convoy_mesh/services/background_runtime_service.dart';
import 'package:convoy_mesh/services/convoy_mesh_service.dart';
import 'package:convoy_mesh/services/diagnostic_recorder.dart';
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

String _diagRec(int i, String category, String event, Map<String, Object?> data) =>
    jsonEncode({
      'ts_utc': '2026-11-18T08:00:00.000Z',
      'elapsed_ms': i * 1000,
      'session_id': 'CM-synthetic',
      'device_id': 4096,
      'device_name': 'Chiara M.',
      'event_index': i,
      'category': category,
      'event': event,
      'data': data,
    });

void main() {
  test('all four Outdoor Premium palettes meet outdoor WCAG contrast & glove targets',
      () {
    for (final preset in OutdoorPalettePreset.values) {
      final t = DesignPresets.paletteOf(preset);
      expect(
        _contrastRatio(t.ink, t.canvas),
        greaterThanOrEqualTo(7.0),
        reason: '${preset.name}: ink vs canvas must achieve AAA contrast',
      );
      expect(
        _contrastRatio(t.ink, t.surface),
        greaterThanOrEqualTo(7.0),
        reason: '${preset.name}: ink vs surface must achieve AAA contrast',
      );
      expect(
        _contrastRatio(t.inkMuted, t.surface),
        greaterThanOrEqualTo(4.5),
        reason: '${preset.name}: muted ink vs surface must achieve AA contrast',
      );
      expect(
        _contrastRatio(t.onAccent, t.accent),
        greaterThanOrEqualTo(4.5),
        reason: '${preset.name}: onAccent vs accent must achieve AA contrast',
      );
      expect(
        _contrastRatio(t.heroInk, t.heroBackground.colors.first),
        greaterThanOrEqualTo(7.0),
        reason: '${preset.name}: heroInk vs heroBackground must achieve AAA contrast',
      );
      expect(
        t.minTouchTarget,
        greaterThanOrEqualTo(52),
        reason: '${preset.name}: touch targets must be glove-friendly (>= 52 dp)',
      );
    }
  });

  test('OutdoorCustomConfig serialises cleanly and clamps invalid ranges safely',
      () {
    final custom = OutdoorCustomConfig(
      palettePreset: OutdoorPalettePreset.crestaAlba,
      accentArgb: 0xFF683722,
      displayFamily: 'JetBrainsMono',
      bodyFamily: null,
      dataFamily: 'JetBrainsMono',
      fontScale: 1.12,
      displayBold: false,
      uppercaseLabels: true,
      radiusSmall: 10,
      radiusMedium: 16,
      radiusLarge: 24,
      borderWidth: 1.5,
      minTouchTarget: 58,
      avatarSize: 54,
      iconScale: 1.15,
      radarScopeScale: 0.85,
      elevated: false,
      spaceUnit: 4.5,
      screenPaddingScale: 1.1,
      cardPaddingScale: 1.2,
      sectionGapScale: 1.25,
      animationsEnabled: true,
      radarRotationEnabled: false,
      livePulseEnabled: false,
      showTopoContours: false,
      radarPeriodMs: 6500,
      motionFastMs: 160,
      motionMediumMs: 320,
      copy: const OutdoorCopyTokens(
        radarTitle: 'Radar Gruppo',
        mapSearchCta: 'Trova posizione',
      ),
    );

    final roundTrip = OutdoorCustomConfig.fromJson(custom.toJson());
    expect(roundTrip, custom);

    final tokens = DesignPresets.buildOutdoor(roundTrip);
    expect(tokens.displayFamily, 'JetBrainsMono');
    expect(tokens.bodyFamily, isNull);
    expect(tokens.fontScale, 1.12);
    expect(tokens.minTouchTarget, 58);
    expect(tokens.avatarSize, 54);
    expect(tokens.shouldRotateRadar, isFalse);
    expect(tokens.shouldPulseLive, isFalse);
    expect(tokens.showTopoContours, isFalse);
    expect(tokens.copy.radarTitle, 'Radar Gruppo');
    expect(_contrastRatio(tokens.onAccent, tokens.accent), greaterThanOrEqualTo(4.5));

    // Invalid / out-of-range inputs clamp instead of throwing.
    final clamped = OutdoorCustomConfig.fromJson({
      'palettePreset': 'unknown_preset',
      'displayFamily': 'UnsupportedFont',
      'fontScale': 99.0,
      'minTouchTarget': 5.0,
      'radarPeriodMs': 999999,
      'copy': {'radarTitle': '   '},
    });
    expect(clamped.palettePreset, OutdoorPalettePreset.pinoECarta);
    expect(clamped.displayFamily, OutdoorCustomConfig.defaults.displayFamily);
    expect(clamped.fontScale, 1.24);
    expect(clamped.minTouchTarget, 48.0);
    expect(clamped.radarPeriodMs, 9500);
    expect(clamped.copy.radarTitle, OutdoorCopyTokens.defaultRadarTitle);
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

  testWidgets(
      'all four Outdoor Premium palettes render cleanly on narrow 360x780 @ 1.3x scale',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final preset in OutdoorPalettePreset.values) {
      final tokens = DesignPresets.paletteOf(preset);
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
        expect(
          tester.takeException(),
          isNull,
          reason: '${preset.name}/${scenario.name} caused exception/overflow',
        );

        await tester.tap(find.byKey(const Key('design-ble-status-tap')));
        expect(triggered, contains('status'));
        await tester.tap(find.byKey(const Key('design-edit-name')));
        expect(triggered, contains('editName'));
        await tester.tap(find.byKey(const Key('design-open-studio-btn')));
        expect(triggered, contains('chooseDesign'));
      }
    }
  });

  testWidgets('RadarScope stops animation when animations are disabled and shows empty hint',
      (tester) async {
    final disabledTokens = DesignPresets.buildOutdoor(
      const OutdoorCustomConfig(animationsEnabled: false),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: false),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 260,
                child: RadarScope(
                  tokens: disabledTokens,
                  peers: const [],
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

  testWidgets(
      'DesignedBottomDock and DesignedMapScaffold preserve smoke Semantics labels even with uppercaseLabels',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      var selectedIdx = 0;
      var toggledOuting = false;
      var locateTapped = false;
      var basemapOnline = true;
      final tokens = DesignPresets.buildOutdoor(
        const OutdoorCustomConfig(
          palettePreset: OutdoorPalettePreset.abeteNotturno,
          uppercaseLabels: true,
        ),
      );

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
                    mode: GpsVisualMode.off,
                    quality: 0,
                    blinkPeriod: null,
                    label: 'Posizione non agganciata',
                  ),
                  gpsStatusText: 'GPS non agganciato.',
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

      expect(
        find.bySemanticsLabel('Posizione non agganciata • tocca per localizzarti'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Avvia uscita'), findsOneWidget);
      expect(find.bySemanticsLabel('Mappa'), findsOneWidget);
      expect(find.bySemanticsLabel('Test log'), findsOneWidget);

      await tester.tap(find.byKey(const Key('designed-outing-toggle')));
      expect(toggledOuting, isTrue);
      await tester.tap(find.text('CERCA GPS'));
      expect(locateTapped, isTrue);
      await tester.tap(find.text('MAPPA'));
      expect(selectedIdx, 1);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'DiagnosticPage Start CTA stays above the fold on compact 360x640 phone with DesignedBottomDock',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final recorder = DiagnosticRecorder.instance;
    if (recorder.isActive) {
      recorder.stop(reason: 'test_cleanup');
    }

    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final design = DesignDirectionController.instance;
    await design.select(DesignDirection.outdoorPremium);
    addTearDown(() async => design.select(DesignDirection.classic));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 640),
          textScaler: TextScaler.linear(1.2),
          disableAnimations: true,
        ),
        child: MaterialApp(
          theme: buildConvoyTheme(design.outdoorTokens),
          home: Scaffold(
            body: DiagnosticPage(
              deviceIdOverride: 12345,
              deviceNameOverride: 'TestPhone',
              captureNowOverride: () {},
            ),
            bottomNavigationBar: DesignedBottomDock(
              tokens: design.outdoorTokens,
              selectedIndex: 2,
              onSelectIndex: (_) {},
              outingActive: false,
              busy: false,
              error: null,
              onToggleOuting: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final startFinder = find.text('Avvia registrazione diagnostica • max 4 min');
    expect(startFinder, findsOneWidget);
    final startRect = tester.getRect(startFinder);
    final dockTop = tester.getTopLeft(find.byType(DesignedBottomDock)).dy;
    expect(
      startRect.bottom,
      lessThanOrEqualTo(dockTop),
      reason: 'Start CTA must remain visible above the dock without swiping',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'DetailedDiagnosticUploadCard and ManualPingCard render cleanly in Outdoor dark palette at 360x780 @ 1.3x',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final darkTokens = DesignPresets.paletteOf(OutdoorPalettePreset.abeteNotturno);
    final session = [
      _diagRec(0, 'session', 'start', {}),
      _diagRec(1, 'runtime', 'snapshot', {
        'peers': [
          {'id': 222, 'name': 'Bravo', 'lat': 45.12, 'lon': 10.13},
        ],
      }),
      _diagRec(2, 'gps', 'fix', {'raw_lat': 45.12, 'raw_lon': 10.13}),
      _diagRec(3, 'session', 'stop', {}),
    ].join('\n');

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 780),
          textScaler: TextScaler.linear(1.3),
          disableAnimations: true,
        ),
        child: MaterialApp(
          theme: buildConvoyTheme(darkTokens),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DetailedDiagnosticUploadCard(
                  jsonl: session,
                  configuredOverride: true,
                  senderOverride: (_) async => 200,
                ),
                ManualPingCard(
                  configuredOverride: true,
                  pingSenderOverride: (_) async => 200,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CheckboxListTile), findsNWidgets(3));
    await tester.scrollUntilVisible(
      find.text('Invia ping di prova'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Invia ping di prova'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invia ping di prova'));
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP 200: richiesta accettata'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'DesignDirectionController persists OutdoorCustomConfig and maps legacy IDs safely',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      DesignDirectionController.storageKey: 'tacticalExplorer',
    });
    final controller = DesignDirectionController.forTest();
    await controller.load();
    expect(controller.direction, DesignDirection.outdoorPremium);

    const updatedCfg = OutdoorCustomConfig(
      palettePreset: OutdoorPalettePreset.terraERame,
      minTouchTarget: 60,
      displayFamily: 'Manrope',
      copy: OutdoorCopyTokens(radarTitle: 'Radar Sentiero'),
    );
    await controller.updateConfig(updatedCfg);

    final reloaded = DesignDirectionController.forTest();
    await reloaded.load();
    expect(reloaded.direction, DesignDirection.outdoorPremium);
    expect(reloaded.config, updatedCfg);
    expect(reloaded.outdoorTokens.copy.radarTitle, 'Radar Sentiero');

    await reloaded.select(DesignDirection.classic);
    expect(reloaded.isClassic, isTrue);
    await reloaded.resetConfig();
    expect(reloaded.config, OutdoorCustomConfig.defaults);
  });

  testWidgets('showDesignDirectionPicker switches Outdoor/Originale and opens Studio',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = DesignDirectionController.forTest(
      DesignDirection.outdoorPremium,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildConvoyTheme(controller.outdoorTokens),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () =>
                    showDesignDirectionPicker(context, controller: controller),
                child: const Text('Apri'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('design-direction-outdoorPremium')), findsOneWidget);
    expect(find.byKey(const Key('design-direction-classic')), findsOneWidget);
    expect(find.text('Originale (LAB +15)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-design-studio-sheet-btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(FrontendDesignStudioPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'FrontendDesignStudioPage previews classic vs Outdoor and customises all 6 axes cleanly',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = DesignDirectionController.forTest(DesignDirection.classic);

    await tester.pumpWidget(
      MaterialApp(
        home: FrontendDesignStudioPage(controller: controller),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Anteprima UI workspace: switch from classic to outdoorPremium
    await tester.tap(find.byKey(const Key('studio-dir-outdoorPremium')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Radar BLE'), findsWidgets);

    // Switch to Personalizza workspace and test every category
    await tester.tap(find.byKey(const Key('studio-mode-customize')));
    await tester.pumpAndSettle();

    final customScrollable = find
        .descendant(
          of: find.byKey(const Key('studio-customize-list')),
          matching: find.byType(Scrollable),
        )
        .first;

    Future<void> selectCat(String name) async {
      final chip = find.byKey(Key('custom-cat-$name'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    // 1. Colors: select Cresta Alba preset
    await tester.tap(find.byKey(const Key('preset-crestaAlba')));
    await tester.pump();

    // 2. Fonts
    await selectCat('fonts');
    await tester.tap(find.byKey(const Key('font-display-JetBrainsMono')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('slider-font-scale')),
      200,
      scrollable: customScrollable,
    );
    await tester.ensureVisible(find.byKey(const Key('slider-font-scale')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('slider-font-scale')),
      const Offset(80, 0),
    );
    await tester.pump();

    // 3. Dimensions
    await selectCat('dimensions');
    expect(find.byKey(const Key('slider-touch-target')), findsOneWidget);

    // 4. Spacing
    await selectCat('spacing');
    expect(find.byKey(const Key('slider-space-unit')), findsOneWidget);

    // 5. Motion
    await selectCat('motion');
    await tester.ensureVisible(find.byKey(const Key('switch-radar-rotation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('switch-radar-rotation')));
    await tester.pump();

    // 6. Copy
    await selectCat('copy');
    await tester.scrollUntilVisible(
      find.byKey(const Key('copy-field-radarTitle')),
      200,
      scrollable: customScrollable,
    );
    await tester.ensureVisible(find.byKey(const Key('copy-field-radarTitle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('copy-field-radarTitle')),
      'Radar Dolomiti',
    );
    await tester.pump();

    // Export JSON modal
    await tester.tap(find.byKey(const Key('studio-export-json-btn')));
    await tester.pumpAndSettle();
    expect(find.textContaining('"Radar Dolomiti"'), findsOneWidget);
    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();

    // Apply all changes
    await tester.tap(find.text('Applica'));
    await tester.pumpAndSettle();
    expect(controller.direction, DesignDirection.outdoorPremium);
    expect(controller.config.palettePreset, OutdoorPalettePreset.crestaAlba);
    expect(controller.config.displayFamily, 'JetBrainsMono');
    expect(controller.config.radarRotationEnabled, isFalse);
    expect(controller.config.copy.radarTitle, 'Radar Dolomiti');
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

    await tester.tap(find.text('MR'));
    await tester.pump();
    scope = tester.widget<RadarScope>(find.byType(RadarScope));
    expect(scope.selectedPeerId, 1042);

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

  testWidgets('BlePage and DiagnosticPage switch cleanly between classic and Outdoor Premium',
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
                : buildConvoyTheme(design.outdoorTokens),
            home: const BlePage(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BleStatusBanner), findsOneWidget);
    expect(find.byKey(const Key('radar-open-design-btn')), findsOneWidget);
    expect(find.byType(DesignedRadarView), findsNothing);

    await design.select(DesignDirection.outdoorPremium);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(DesignedRadarView), findsOneWidget);
    expect(find.byType(BleStatusBanner), findsNothing);
    expect(find.byKey(const Key('design-open-studio-btn')), findsOneWidget);

    // Open Outdoor themed Radar help dialog & close without exceptions.
    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();
    expect(find.text('Come funziona il Radar BLE?'), findsOneWidget);
    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();

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
                : buildConvoyTheme(design.outdoorTokens),
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
    final tokens = DesignPresets.paletteOf(OutdoorPalettePreset.crestaAlba);
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
