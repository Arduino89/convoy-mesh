import 'dart:async';
import 'dart:convert';

import 'package:convoy_mesh/ble/ble_page.dart';
import 'package:convoy_mesh/design/design_controller.dart';
import 'package:convoy_mesh/design/design_presets.dart';
import 'package:convoy_mesh/design/design_theme.dart';
import 'package:convoy_mesh/design/design_tokens.dart';
import 'package:convoy_mesh/design/outdoor_components.dart';
import 'package:convoy_mesh/design/outdoor_config.dart';
import 'package:convoy_mesh/design/outdoor_copy.dart';
import 'package:convoy_mesh/design/radar/radar_components.dart';
import 'package:convoy_mesh/design/radar/radar_scope.dart';
import 'package:convoy_mesh/design/radar/radar_view_data.dart';
import 'package:convoy_mesh/design/shell/designed_app_shell.dart';
import 'package:convoy_mesh/design/studio/frontend_design_studio_page.dart';
import 'package:convoy_mesh/pages/detailed_diagnostic_upload_card.dart';
import 'package:convoy_mesh/pages/diagnostic_page.dart';
import 'package:convoy_mesh/pages/manual_ping_card.dart';
import 'package:convoy_mesh/services/detailed_diagnostic_upload.dart';
import 'package:convoy_mesh/services/manual_ping_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _diagRec(
  int i,
  String category,
  String event,
  Map<String, Object?> data, {
  String sessionId = 'CM-hardening-1',
}) =>
    jsonEncode({
      'ts_utc': '2026-11-19T08:00:00.000Z',
      'elapsed_ms': i * 1000,
      'session_id': sessionId,
      'device_id': 321,
      'device_name': 'Alpha',
      'event_index': i,
      'category': category,
      'event': event,
      'data': data,
    });

String _sampleSession({String sessionId = 'CM-hardening-1', int? peerId}) => [
      _diagRec(0, 'session', 'start', {}, sessionId: sessionId),
      if (peerId != null)
        _diagRec(
          1,
          'runtime',
          'snapshot',
          {
            'peers': [
              {'id': peerId, 'name': 'Bravo', 'lat': 45.12, 'lon': 10.13},
            ],
          },
          sessionId: sessionId,
        ),
      _diagRec(
        2,
        'gps',
        'fix',
        {'raw_lat': 45.12, 'raw_lon': 10.13},
        sessionId: sessionId,
      ),
      _diagRec(3, 'session', 'stop', {}, sessionId: sessionId),
    ].join('\n');

void main() {
  // ── 1. PostHog offline pause & process-scoped single-shot upload guards ──

  group('PostHog offline pause and single-shot upload guards (simulated only)', () {
    testWidgets(
      'ManualPingCard shows calm neutral notice when temporarily disabled',
      (tester) async {
        final tracker = ManualPingAttemptTracker();
        var calls = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildConvoyTheme(DesignPresets.outdoorPremium),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ManualPingCard(
                  temporarilyDisabledOverride: true,
                  attemptTrackerOverride: tracker,
                  pingSenderOverride: (_) async {
                    calls++;
                    return 200;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('temporaneamente disattivato'),
          findsOneWidget,
        );
        expect(find.textContaining('Invio non configurato'), findsNothing);
        final callouts = tester.widgetList<OutdoorCallout>(
          find.byType(OutdoorCallout),
        );
        expect(
          callouts.any((c) => c.tone == OutdoorTone.critical),
          isFalse,
          reason: 'Paused state must not render a red critical error banner',
        );
        final button = find.widgetWithText(FilledButton, 'Invia ping di prova');
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        expect(calls, 0);
      },
    );

    testWidgets(
      'ManualPingCard launch-scoped guard survives unmount, style switch and mid-flight timeout',
      (tester) async {
        final tracker = ManualPingAttemptTracker();
        final pending = Completer<int>();
        var calls = 0;

        Widget buildHost(bool outdoor) => MaterialApp(
              theme: outdoor
                  ? buildConvoyTheme(DesignPresets.outdoorPremium)
                  : ThemeData(useMaterial3: true),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ManualPingCard(
                    key: ValueKey('ping-$outdoor'),
                    configuredOverride: true,
                    attemptTrackerOverride: tracker,
                    pingSenderOverride: (_) {
                      calls++;
                      return pending.future;
                    },
                  ),
                ),
              ),
            );

        await tester.pumpWidget(buildHost(true));
        await tester.pumpAndSettle();

        final sendBtn = find.widgetWithText(FilledButton, 'Invia ping di prova');
        await tester.tap(sendBtn);
        await tester.pump();
        expect(calls, 1);
        expect(tracker.state.inFlight, isTrue);

        // Unmount completely (simulating ListView eviction / tab destroy) then
        // remount under Classic theme while the request is still mid-flight.
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        await tester.pumpWidget(buildHost(false));
        await tester.pump();

        expect(tester.widget<FilledButton>(sendBtn).onPressed, isNull);
        expect(find.textContaining('Invio singolo in corso'), findsOneWidget);

        // Settle with an ambiguous timeout: still locked at exactly 1 attempt.
        pending.completeError(TimeoutException('simulated ambiguous timeout'));
        await tester.pumpAndSettle();

        expect(calls, 1);
        expect(tracker.state.inFlight, isFalse);
        expect(tracker.state.attempted, isTrue);
        expect(tester.widget<FilledButton>(sendBtn).onPressed, isNull);
        expect(find.textContaining('fallita o incerta'), findsOneWidget);
      },
    );

    testWidgets(
      'DetailedDiagnosticUploadCard shows calm notice when temporarily disabled and blocks send',
      (tester) async {
        final store = DetailedDiagnosticUploadAttemptStore();
        final jsonl = _sampleSession(peerId: 222);
        var calls = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildConvoyTheme(DesignPresets.outdoorPremium),
            home: Scaffold(
              body: ListView(
                children: [
                  DetailedDiagnosticUploadCard(
                    jsonl: jsonl,
                    temporarilyDisabledOverride: true,
                    attemptStoreOverride: store,
                    senderOverride: (_) async {
                      calls++;
                      return 200;
                    },
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('temporaneamente disattivato'),
          findsOneWidget,
        );
        expect(find.textContaining('non configurato'), findsNothing);
        final callouts = tester.widgetList<OutdoorCallout>(
          find.byType(OutdoorCallout),
        );
        expect(callouts.any((c) => c.tone == OutdoorTone.critical), isFalse);

        // Even after ticking every consent checkbox, send remains disabled.
        final checks = find.byType(CheckboxListTile);
        for (var i = 0; i < 3; i++) {
          await tester.ensureVisible(checks.at(i));
          await tester.tap(checks.at(i));
          await tester.pumpAndSettle();
        }
        final sendFinder = find.text('Invia diagnostica a PostHog');
        final sendBtn = tester.widget<FilledButton>(
          find.ancestor(of: sendFinder, matching: find.byType(FilledButton)).first,
        );
        expect(sendBtn.onPressed, isNull);
        expect(calls, 0);
      },
    );

    testWidgets(
      'DetailedDiagnosticUploadCard blocks duplicate send after ambiguous timeout even across unmount/remount',
      (tester) async {
        final store = DetailedDiagnosticUploadAttemptStore();
        final jsonl = _sampleSession(sessionId: 'CM-timeout-evict');
        var calls = 0;

        Widget buildHost(bool outdoor) => MaterialApp(
              theme: outdoor
                  ? buildConvoyTheme(
                      DesignPresets.paletteOf(OutdoorPalettePreset.abeteNotturno),
                    )
                  : ThemeData(useMaterial3: true),
              home: Scaffold(
                body: ListView(
                  children: [
                    DetailedDiagnosticUploadCard(
                      key: ValueKey('upload-$outdoor'),
                      jsonl: jsonl,
                      configuredOverride: true,
                      attemptStoreOverride: store,
                      senderOverride: (_) async {
                        calls++;
                        throw TimeoutException('simulated network timeout');
                      },
                    ),
                  ],
                ),
              ),
            );

        await tester.pumpWidget(buildHost(true));
        await tester.pumpAndSettle();

        final checks = find.byType(CheckboxListTile);
        for (var i = 0; i < 2; i++) {
          await tester.ensureVisible(checks.at(i));
          await tester.tap(checks.at(i));
          await tester.pumpAndSettle();
        }
        final sendText = find.text('Invia diagnostica a PostHog');
        await tester.ensureVisible(sendText);
        await tester.tap(sendText);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confermo invio a PostHog EU'));
        await tester.pumpAndSettle();

        expect(calls, 1);
        expect(find.textContaining('esito incerto'), findsOneWidget);

        // Fully evict widget (simulating ListView scroll-away + Classic switch).
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        await tester.pumpWidget(buildHost(false));
        await tester.pumpAndSettle();

        // Remounted widget restores attempted state and locks button + checkboxes.
        expect(find.textContaining('esito incerto'), findsOneWidget);
        final remountedBtn = tester.widget<FilledButton>(
          find.ancestor(of: sendText, matching: find.byType(FilledButton)).first,
        );
        expect(remountedBtn.onPressed, isNull);
        final remountedChecks = tester.widgetList<CheckboxListTile>(
          find.byType(CheckboxListTile),
        );
        expect(remountedChecks.every((c) => c.onChanged == null), isTrue);
        expect(calls, 1);
      },
    );

    testWidgets(
      'DetailedDiagnosticUploadCard blocks duplicate mid-flight send across unmount/remount',
      (tester) async {
        final store = DetailedDiagnosticUploadAttemptStore();
        final jsonl = _sampleSession(sessionId: 'CM-inflight-evict');
        final inflight = Completer<int>();
        var calls = 0;

        Widget buildHost(int generation) => MaterialApp(
              theme: buildConvoyTheme(DesignPresets.outdoorPremium),
              home: Scaffold(
                body: ListView(
                  children: [
                    DetailedDiagnosticUploadCard(
                      key: ValueKey('gen-$generation'),
                      jsonl: jsonl,
                      configuredOverride: true,
                      attemptStoreOverride: store,
                      senderOverride: (_) {
                        calls++;
                        return inflight.future;
                      },
                    ),
                  ],
                ),
              ),
            );

        await tester.pumpWidget(buildHost(1));
        await tester.pumpAndSettle();

        final checks = find.byType(CheckboxListTile);
        for (var i = 0; i < 2; i++) {
          await tester.ensureVisible(checks.at(i));
          await tester.tap(checks.at(i));
          await tester.pumpAndSettle();
        }
        final sendText = find.text('Invia diagnostica a PostHog');
        await tester.ensureVisible(sendText);
        await tester.tap(sendText);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confermo invio a PostHog EU'));
        await tester.pump();

        expect(calls, 1);

        // Unmount and remount while request is still pending.
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        await tester.pumpWidget(buildHost(2));
        await tester.pump();

        final sendBtn = tester.widget<FilledButton>(
          find.ancestor(of: sendText, matching: find.byType(FilledButton)).first,
        );
        expect(sendBtn.onPressed, isNull);

        inflight.complete(200);
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(find.textContaining('HTTP 200'), findsOneWidget);
      },
    );

    test(
      'DetailedDiagnosticUploadAttemptStore isolates distinct captures and locks duplicates',
      () {
        final store = DetailedDiagnosticUploadAttemptStore();
        final k1 = DetailedDiagnosticUploadAttemptStore.fingerprintFor(
          'S1',
          'line1\nline2',
        );
        final k2 = DetailedDiagnosticUploadAttemptStore.fingerprintFor(
          'S2',
          'line1\nline2',
        );
        final k3 = DetailedDiagnosticUploadAttemptStore.fingerprintFor(
          'S1',
          'line1\nline3',
        );

        expect(k1, isNot(k2));
        expect(k1, isNot(k3));
        expect(
          store.beginAttempt(
            k1,
            uploadId: 'u1',
            ownerConsent: true,
            ackStoredData: true,
            approvedPeers: const {},
          ),
          isTrue,
        );
        // Second attempt on same capture must be rejected immediately.
        expect(
          store.beginAttempt(
            k1,
            uploadId: 'u1-dup',
            ownerConsent: true,
            ackStoredData: true,
            approvedPeers: const {},
          ),
          isFalse,
        );
        // Different capture remains independently uploadable once.
        expect(
          store.beginAttempt(
            k2,
            uploadId: 'u2',
            ownerConsent: true,
            ackStoredData: true,
            approvedPeers: const {},
          ),
          isTrue,
        );
      },
    );
  });

  // ── 2. WCAG contrast, token safety, fonts and shadows ────────────────────

  group('WCAG contrast, token safety, font weights and shadows', () {
    test('all four Outdoor presets pass full 12-pair WCAG AA and AAA body checks', () {
      for (final preset in OutdoorPalettePreset.values) {
        final tokens = DesignPresets.buildOutdoor(
          OutdoorCustomConfig(palettePreset: preset),
        );
        final report = DesignPresets.evaluateContrast(tokens);
        expect(
          report.checks.length,
          12,
          reason: '${preset.name} must evaluate all 12 contrast pairs',
        );
        expect(
          report.allPassAa,
          isTrue,
          reason:
              '${preset.name} failed checks: ${report.failures.map((f) => '${f.label}=${f.ratio.toStringAsFixed(2)}').join(', ')}',
        );
        expect(report.bodyIsAaa, isTrue, reason: '${preset.name} body AAA');
      }
    });

    test('adversarial custom color overrides keep canvas/surface/hero/critical legible and opaque', () {
      // Dark canvas + light surface + light hero + light coral critical + translucent inputs
      final cfg = const OutdoorCustomConfig().copyWith(
        canvasArgb: 0x00101814, // alpha stripped -> coerced to opaque dark
        surfaceArgb: 0x40FFFDF8, // coerced to opaque light
        heroBaseArgb: 0x80F4F0E4, // light hero
        criticalArgb: 0xFFF28579, // light coral critical
      );
      final t = DesignPresets.buildOutdoor(cfg);

      expect(t.canvas.a, 1.0);
      expect(t.surface.a, 1.0);
      expect(t.critical.a, 1.0);
      expect(DesignPresets.contrastRatio(t.inkOnCanvas, t.canvas), greaterThanOrEqualTo(7.0));
      expect(DesignPresets.contrastRatio(t.ink, t.surface), greaterThanOrEqualTo(7.0));
      expect(DesignPresets.contrastRatio(t.onCritical, t.critical), greaterThanOrEqualTo(4.5));
      for (final stop in t.heroBackground.colors) {
        expect(DesignPresets.contrastRatio(t.heroInk, stop), greaterThanOrEqualTo(7.0));
        expect(DesignPresets.contrastRatio(t.heroOfflineInk, stop), greaterThanOrEqualTo(4.5));
      }

      // Inverse: light canvas + dark surface
      final inverse = DesignPresets.buildOutdoor(
        const OutdoorCustomConfig().copyWith(
          canvasArgb: 0xFFF7F4EC,
          surfaceArgb: 0xFF14201A,
        ),
      );
      expect(
        DesignPresets.contrastRatio(inverse.inkOnCanvas, inverse.canvas),
        greaterThanOrEqualTo(7.0),
      );
      expect(
        DesignPresets.contrastRatio(inverse.ink, inverse.surface),
        greaterThanOrEqualTo(7.0),
      );
    });

    test('dark mode shadow uses black alpha instead of cream ink, and tokens implement value equality', () {
      final elevatedDark = DesignPresets.buildOutdoor(
        const OutdoorCustomConfig(
          palettePreset: OutdoorPalettePreset.abeteNotturno,
          elevated: true,
        ),
      );
      expect(elevatedDark.shadow, isNotEmpty);
      for (final s in elevatedDark.shadow) {
        expect(s.color.r, 0.0);
        expect(s.color.g, 0.0);
        expect(s.color.b, 0.0);
      }

      final same = DesignPresets.buildOutdoor(
        const OutdoorCustomConfig(
          palettePreset: OutdoorPalettePreset.abeteNotturno,
          elevated: true,
        ),
      );
      final diff = elevatedDark.copyWith(borderWidth: 2.0);
      expect(elevatedDark, equals(same));
      expect(elevatedDark.hashCode, equals(same.hashCode));
      expect(elevatedDark, isNot(equals(diff)));
    });

    test('ConvoyDesignTokens.resolveWeight maps requested weights to bundled font assets', () {
      expect(
        ConvoyDesignTokens.resolveWeight('Manrope', FontWeight.w500),
        FontWeight.w600,
      );
      expect(
        ConvoyDesignTokens.resolveWeight('Manrope', FontWeight.w700),
        FontWeight.w800,
      );
      expect(
        ConvoyDesignTokens.resolveWeight('Manrope', FontWeight.w400),
        FontWeight.w400,
      );
      expect(
        ConvoyDesignTokens.resolveWeight('Fraunces', FontWeight.w400),
        FontWeight.w500,
      );
      expect(
        ConvoyDesignTokens.resolveWeight('Fraunces', FontWeight.w800),
        FontWeight.w700,
      );
      expect(
        ConvoyDesignTokens.resolveWeight('JetBrainsMono', FontWeight.w600),
        FontWeight.w700,
      );
      expect(
        ConvoyDesignTokens.resolveWeight(null, FontWeight.w500),
        FontWeight.w500,
      );
    });

    testWidgets('OutdoorCallout and OutdoorStatusBadge enforce AA text fallback on low-contrast custom tone', (tester) async {
      // Adversarial: near-white warning color on white surface.
      final hostile = DesignPresets.buildOutdoor(
        const OutdoorCustomConfig().copyWith(
          surfaceArgb: 0xFFFFFFFF,
          warningArgb: 0xFFF2F2F2,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildConvoyTheme(hostile),
          home: Scaffold(
            body: Column(
              children: [
                OutdoorCallout(
                  tokens: hostile,
                  icon: Icons.warning_amber,
                  tone: OutdoorTone.warning,
                  text: 'Avviso leggibile',
                ),
                OutdoorStatusBadge(
                  tokens: hostile,
                  label: 'Badge leggibile',
                  tone: OutdoorTone.warning,
                ),
              ],
            ),
          ),
        ),
      );

      final calloutText = tester.widget<Text>(find.text('Avviso leggibile'));
      final badgeText = tester.widget<Text>(find.text('Badge leggibile'));
      expect(
        DesignPresets.contrastRatio(calloutText.style!.color!, hostile.surfaceRaised),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        DesignPresets.contrastRatio(badgeText.style!.color!, hostile.surface),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  // ── 3. Config & Copy validation + JSON import hardening ──────────────────

  group('OutdoorCustomConfig and OutdoorCopyTokens validation', () {
    test('enforces monotonic radii, monotonic motion durations, and preset border/elevation inheritance', () {
      final cfg = const OutdoorCustomConfig().copyWith(
        radiusSmall: 20,
        radiusMedium: 12,
        radiusLarge: 14,
        motionFastMs: 400,
        motionMediumMs: 200,
      );
      expect(cfg.radiusSmall, lessThanOrEqualTo(cfg.radiusMedium));
      expect(cfg.radiusMedium, lessThanOrEqualTo(cfg.radiusLarge));
      expect(cfg.motionFastMs, lessThanOrEqualTo(cfg.motionMediumMs));

      final alba = const OutdoorCustomConfig()
          .copyWith(borderWidth: 2.0, elevated: false)
          .withPalettePreset(OutdoorPalettePreset.crestaAlba);
      expect(alba.borderWidth, isNull);
      expect(alba.effectiveBorderWidth, 1.2);
      expect(alba.elevated, isNull);
      expect(alba.effectiveElevated, isTrue);

      final night = alba.withPalettePreset(OutdoorPalettePreset.abeteNotturno);
      expect(night.effectiveElevated, isFalse);
      expect(night.effectiveBorderWidth, 1.0);
    });

    test('tryParseJsonString accepts valid JSON and rejects malformed/oversized/unknown payloads', () {
      const original = OutdoorCustomConfig(
        palettePreset: OutdoorPalettePreset.terraERame,
        accentArgb: 0xFF683722,
        minTouchTarget: 58,
        copy: OutdoorCopyTokens(radarTitle: 'Radar Dolomiti'),
      );
      final encoded = jsonEncode(original.toJson());
      final ok = OutdoorCustomConfig.tryParseJsonString(encoded);
      expect(ok.isOk, isTrue);
      expect(ok.config, equals(original));

      expect(OutdoorCustomConfig.tryParseJsonString('   ').isOk, isFalse);
      expect(OutdoorCustomConfig.tryParseJsonString('{bad json').isOk, isFalse);
      expect(OutdoorCustomConfig.tryParseJsonString('[1, 2, 3]').isOk, isFalse);
      expect(
        OutdoorCustomConfig.tryParseJsonString(
          '{"palettePreset": "${'a' * 17000}"}',
        ).isOk,
        isFalse,
      );
      final unknownTop = OutdoorCustomConfig.tryParseJsonString(
        '{"palettePreset":"pinoECarta","injectedKey":true}',
      );
      expect(unknownTop.isOk, isFalse);
      expect(unknownTop.error, contains('injectedKey'));

      final unknownCopy = OutdoorCustomConfig.tryParseJsonString(
        '{"copy":{"bogusField":"x"}}',
      );
      expect(unknownCopy.isOk, isFalse);
      expect(unknownCopy.error, contains('bogusField'));

      final nonMapCopy = OutdoorCustomConfig.tryParseJsonString(
        '{"copy":"not-an-object"}',
      );
      expect(nonMapCopy.isOk, isFalse);
    });

    test('OutdoorCopyTokens locks radarCaption and sanitizes control chars / graphemes safely', () {
      const fromCtor = OutdoorCopyTokens(radarCaption: 'Anelli = metri esatti');
      expect(fromCtor.radarCaption, OutdoorCopyTokens.defaultRadarCaption);

      final fromCopy = fromCtor.copyWith(radarCaption: 'Distanza precisa');
      expect(fromCopy.radarCaption, OutdoorCopyTokens.defaultRadarCaption);

      final fromJson = OutdoorCopyTokens.fromJson({
        'radarTitle': '  Radar\n\tSentiero\r\n  Est  ',
        'radarCaption': 'Falso disclaimer',
        'appKicker': '🏔️' * 40,
      });
      expect(fromJson.radarCaption, OutdoorCopyTokens.defaultRadarCaption);
      expect(fromJson.radarTitle, 'Radar Sentiero Est');
      expect(
        fromJson.appKicker.characters.length,
        lessThanOrEqualTo(OutdoorCopyTokens.maxLengthFor('appKicker')),
      );
      // Verify grapheme slicing did not emit unpaired UTF-16 surrogates.
      expect(() => utf8.encode(fromJson.appKicker), returnsNormally);
    });
  });

  // ── 4. DesignDirectionController caching, epoch guard & atomic apply ─────

  group('DesignDirectionController caching, concurrency and atomic persistence', () {
    test('outdoorTokens is memoized until config changes and applySelection notifies once', () async {
      SharedPreferences.setMockInitialValues({});
      final ctrl = DesignDirectionController.forTest();
      final t1 = ctrl.outdoorTokens;
      final t2 = ctrl.outdoorTokens;
      expect(identical(t1, t2), isTrue);

      var notifications = 0;
      ctrl.addListener(() => notifications++);

      const nextCfg = OutdoorCustomConfig(
        palettePreset: OutdoorPalettePreset.crestaAlba,
        minTouchTarget: 56,
      );
      final ok = await ctrl.applySelection(
        DesignDirection.outdoorPremium,
        nextCfg,
      );
      expect(ok, isTrue);
      expect(notifications, 1);
      expect(ctrl.direction, DesignDirection.outdoorPremium);
      expect(ctrl.config, nextCfg);
      expect(identical(ctrl.outdoorTokens, t1), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(DesignDirectionController.storageKey),
        DesignDirection.outdoorPremium.storageId,
      );
      expect(
        prefs.getString(DesignDirectionController.configStorageKey),
        isNotNull,
      );
    });

    test('concurrent user mutation wins over stale in-flight load()', () async {
      SharedPreferences.setMockInitialValues({
        DesignDirectionController.storageKey: DesignDirection.classic.storageId,
      });
      final ctrl = DesignDirectionController.forTest(DesignDirection.classic);

      // Start load() without awaiting, then immediately perform user selection.
      final loadFuture = ctrl.load();
      await ctrl.select(DesignDirection.outdoorPremium);
      await loadFuture;

      expect(ctrl.hasLoaded, isTrue);
      expect(ctrl.direction, DesignDirection.outdoorPremium);
    });

    test('rapid back-to-back updateConfig calls serialize so latest state persists', () async {
      SharedPreferences.setMockInitialValues({});
      final ctrl = DesignDirectionController.forTest();

      final f1 = ctrl.updateConfig(
        const OutdoorCustomConfig(palettePreset: OutdoorPalettePreset.crestaAlba),
      );
      final f2 = ctrl.updateConfig(
        const OutdoorCustomConfig(palettePreset: OutdoorPalettePreset.terraERame),
      );
      final f3 = ctrl.updateConfig(
        const OutdoorCustomConfig(palettePreset: OutdoorPalettePreset.abeteNotturno),
      );
      final results = await Future.wait([f1, f2, f3]);
      expect(results, everyElement(isTrue));

      final reloaded = DesignDirectionController.forTest();
      await reloaded.load();
      expect(reloaded.config.palettePreset, OutdoorPalettePreset.abeteNotturno);
    });
  });

  // ── 5. Radar, Navigation & Reduced Motion edge cases ─────────────────────

  group('Radar, Navigation and Accessibility edge cases', () {
    test('RadarPeerView.initials handles emojis, unicode, whitespace and empty names safely', () {
      RadarPeerView peer(String name) => RadarPeerView(
            userId: 1,
            name: name,
            color: 0xFF24503F,
            online: true,
            gpsLine: 'GPS OK',
            accuracyLine: '±5 m',
            historyLine: null,
            signalQuality: 'Buono',
            rssi: -60,
            lastPacketLine: 'ora',
            locationState: PeerLocationState.fresh,
          );

      expect(peer('🏔️ Montagna').initials, '🏔️M');
      expect(peer('🧭').initials, '🧭');
      expect(peer('   ').initials, '?');
      expect(peer('').initials, '?');
      expect(peer('Marco Rossi').initials, 'MR');
      expect(peer('Al').initials, 'AL');
      expect(() => utf8.encode(peer('🏔️ Montagna').initials), returnsNormally);
    });

    testWidgets('LiveDot suppresses pulse ring when disableAnimations is true', (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: LiveDot(
                  active: true,
                  color: Colors.green,
                  pulseEnabled: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // Only the static inner dot Container exists; animated pulse ring is omitted.
      final dotContainers = find.descendant(
        of: find.byType(LiveDot),
        matching: find.byType(Container),
      );
      expect(dotContainers, findsOneWidget);
    });

    testWidgets('RadarScope renders cleanly with light custom hero background and offline peer', (tester) async {
      final lightHero = DesignPresets.buildOutdoor(
        const OutdoorCustomConfig().copyWith(heroBaseArgb: 0xFFEFECE2),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: buildConvoyTheme(lightHero),
            home: Scaffold(
              body: Center(
                child: RadarScope(
                  tokens: lightHero,
                  scanning: true,
                  showLabels: true,
                  peers: const [
                    RadarPeerView(
                      userId: 101,
                      name: '🏔️ Guida',
                      color: 0xFFE5C158,
                      online: true,
                      gpsLine: 'GPS attivo',
                      accuracyLine: '±4 m',
                      historyLine: null,
                      signalQuality: 'Ottimo',
                      rssi: -52,
                      lastPacketLine: '2s fa',
                      locationState: PeerLocationState.fresh,
                    ),
                    RadarPeerView(
                      userId: 102,
                      name: 'Sara B.',
                      color: 0xFF2B6CB0,
                      online: false,
                      gpsLine: 'Ultima posizione',
                      accuracyLine: null,
                      historyLine: null,
                      signalQuality: 'Scarso',
                      rssi: -92,
                      lastPacketLine: '2m fa',
                      locationState: PeerLocationState.off,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('🏔️G'), findsOneWidget);
      expect(find.text('Sara B.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('DiagnosticPage and BlePage expose style button in Classic mode and dock targets >= 48dp', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiagnosticPage(
              deviceIdOverride: 42,
              deviceNameOverride: 'Pixel',
              captureNowOverride: () {},
            ),
            bottomNavigationBar: DesignedBottomDock(
              tokens: DesignPresets.outdoorPremium,
              selectedIndex: 2,
              outingActive: false,
              busy: false,
              error: null,
              onToggleOuting: () {},
              onSelectIndex: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('diag-open-design-btn')), findsOneWidget);

      final radarTabSize = tester.getSize(
        find.ancestor(
          of: find.text('Radar BLE'),
          matching: find.byType(AnimatedContainer),
        ).first,
      );
      expect(radarTabSize.height, greaterThanOrEqualTo(48.0));

      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(home: BlePage()),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('radar-open-design-btn')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ── 6. Outdoor Studio E2E: 8 color roles, WCAG diagnostics, JSON import,
  //       protected radarCaption, PopScope discard guard, narrow layout ────

  group('Outdoor Studio customiser E2E hardening', () {
    testWidgets(
      'exposes all 8 color roles, live WCAG diagnostics, protected radarCaption and JSON import',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final controller = DesignDirectionController.forTest(
          DesignDirection.outdoorPremium,
        );

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              home: FrontendDesignStudioPage(
                controller: controller,
                initialCustomizeTab: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final listScrollable = find
            .descendant(
              of: find.byKey(const Key('studio-customize-list')),
              matching: find.byType(Scrollable),
            )
            .first;

        // Verify all 8 color role pickers exist (including positive, warning, critical).
        for (final pair in [
          ('canvas', DesignPresets.customCanvasSwatches.first),
          ('surface', DesignPresets.customSurfaceSwatches.first),
          ('accent', DesignPresets.customAccentSwatches.first),
          ('highlight', DesignPresets.customHighlightSwatches.first),
          ('hero', DesignPresets.customHeroSwatches.first),
          ('positive', DesignPresets.customPositiveSwatches.first),
          ('warning', DesignPresets.customWarningSwatches.first),
          ('critical', DesignPresets.customCriticalSwatches.first),
        ]) {
          final hex =
              pair.$2.toARGB32().toRadixString(16).padLeft(8, '0');
          final key = Key('swatch-${pair.$1}-$hex');
          await tester.scrollUntilVisible(
            find.byKey(key),
            200,
            scrollable: listScrollable,
          );
          expect(find.byKey(key), findsOneWidget);
          final swatchSize = tester.getSize(find.byKey(key));
          expect(swatchSize.width, greaterThanOrEqualTo(48.0));
          expect(swatchSize.height, greaterThanOrEqualTo(48.0));
        }

        // Scroll to live WCAG diagnostics card.
        await tester.scrollUntilVisible(
          find.byKey(const Key('studio-contrast-diagnostics')),
          250,
          scrollable: listScrollable,
        );
        expect(
          find.byKey(const Key('studio-contrast-diagnostics')),
          findsOneWidget,
        );
        expect(find.textContaining('12/12 AA'), findsOneWidget);

        // Pick dark-mode light green positive swatch on light surface -> triggers WCAG warning.
        final lightGreenHex = DesignPresets.customPositiveSwatches.last
            .toARGB32()
            .toRadixString(16)
            .padLeft(8, '0');
        final lightGreenFinder = find.byKey(Key('swatch-positive-$lightGreenHex'));
        await tester.drag(
          find.byKey(const Key('studio-customize-list')),
          const Offset(0, 500),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          lightGreenFinder,
          150,
          scrollable: listScrollable,
        );
        await tester.tap(lightGreenFinder);
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const Key('studio-customize-list')),
          const Offset(0, 1400),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('studio-contrast-warning')), findsOneWidget);

        // Open JSON Import modal: reject invalid JSON first, then import valid JSON.
        await tester.tap(find.byKey(const Key('studio-import-json-btn')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('studio-json-import-field')),
          '{"palettePreset":"pinoECarta","unknownEvilKey":1}',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('studio-json-import-error')), findsOneWidget);

        final importPayload = jsonEncode({
          'palettePreset': 'terraERame',
          'minTouchTarget': 58,
          'copy': {
            'radarTitle': 'Sentiero Importato',
            'radarCaption': 'Tentativo modifica protetta',
          },
        });
        await tester.enterText(
          find.byKey(const Key('studio-json-import-field')),
          importPayload,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('studio-json-import-valid')), findsOneWidget);
        await tester.tap(find.byKey(const Key('studio-json-import-submit')));
        await tester.pumpAndSettle();

        // Switch to Copy category: verify synced controller and read-only protected radarCaption.
        final copyChip = find.byKey(const Key('custom-cat-copy'));
        await tester.ensureVisible(copyChip);
        await tester.pumpAndSettle();
        await tester.tap(copyChip);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('copy-field-radarCaption')), findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const Key('copy-protected-radarCaption')),
          180,
          scrollable: listScrollable,
        );
        expect(
          find.byKey(const Key('copy-protected-radarCaption')),
          findsOneWidget,
        );
        expect(find.text('Sentiero Importato'), findsWidgets);

        // Apply and verify controller state + protected caption.
        await tester.tap(find.byKey(const Key('studio-apply-btn')));
        await tester.pumpAndSettle();
        expect(controller.config.palettePreset, OutdoorPalettePreset.terraERame);
        expect(controller.config.minTouchTarget, 58);
        expect(controller.config.copy.radarTitle, 'Sentiero Importato');
        expect(
          controller.config.copy.radarCaption,
          OutdoorCopyTokens.defaultRadarCaption,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PopScope prompts before discarding unsaved Studio changes and pops cleanly on Apply',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final controller = DesignDirectionController.forTest(
          DesignDirection.outdoorPremium,
        );

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => FrontendDesignStudioPage(
                            controller: controller,
                            initialCustomizeTab: true,
                          ),
                        ),
                      ),
                      child: const Text('Apri Studio'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Apri Studio'));
        await tester.pumpAndSettle();
        expect(find.byType(FrontendDesignStudioPage), findsOneWidget);

        // Make a dirty change (switch preset to Cresta Alba).
        await tester.tap(find.byKey(const Key('preset-crestaAlba')));
        await tester.pumpAndSettle();

        // Attempt back navigation -> blocked by PopScope confirmation dialog.
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Scartare le modifiche?'), findsOneWidget);

        // Cancel discard -> stay on Studio.
        await tester.tap(find.text('Resta'));
        await tester.pumpAndSettle();
        expect(find.byType(FrontendDesignStudioPage), findsOneWidget);

        // Attempt back again and confirm discard -> pops without mutating controller.
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('studio-discard-confirm-btn')));
        await tester.pumpAndSettle();
        expect(find.byType(FrontendDesignStudioPage), findsNothing);
        expect(controller.config.palettePreset, OutdoorPalettePreset.pinoECarta);

        // Re-open, make a change, and tap Applica -> pops immediately without discard dialog.
        await tester.tap(find.text('Apri Studio'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('preset-crestaAlba')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('studio-apply-btn')));
        await tester.pumpAndSettle();
        expect(find.text('Scartare le modifiche?'), findsNothing);
        expect(find.byType(FrontendDesignStudioPage), findsNothing);
        expect(controller.config.palettePreset, OutdoorPalettePreset.crestaAlba);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Outdoor Studio renders all 6 customize categories without overflow at 360x780 @ 1.3x scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        SharedPreferences.setMockInitialValues({});
        final controller = DesignDirectionController.forTest(
          DesignDirection.outdoorPremium,
        );

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              textScaler: TextScaler.linear(1.3),
              disableAnimations: true,
            ),
            child: MaterialApp(
              home: FrontendDesignStudioPage(
                controller: controller,
                initialCustomizeTab: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final cat in CustomizerCategory.values) {
          final chip = find.byKey(Key('custom-cat-${cat.name}'));
          await tester.ensureVisible(chip);
          await tester.pumpAndSettle();
          await tester.tap(chip);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Category ${cat.name} overflowed at 360x780 @ 1.3x',
          );
        }
      },
    );
  });
}
