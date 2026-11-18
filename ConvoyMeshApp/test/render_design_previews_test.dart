import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:convoy_mesh/design/design_controller.dart';
import 'package:convoy_mesh/design/design_presets.dart';
import 'package:convoy_mesh/design/design_theme.dart';
import 'package:convoy_mesh/design/design_tokens.dart';
import 'package:convoy_mesh/design/map/designed_map_chrome.dart';
import 'package:convoy_mesh/design/outdoor_components.dart';
import 'package:convoy_mesh/design/outdoor_config.dart';
import 'package:convoy_mesh/design/radar/designed_radar_view.dart';
import 'package:convoy_mesh/design/radar/radar_actions.dart';
import 'package:convoy_mesh/design/shell/designed_app_shell.dart';
import 'package:convoy_mesh/design/studio/frontend_design_studio_page.dart';
import 'package:convoy_mesh/design/studio/original_radar_preview.dart';
import 'package:convoy_mesh/design/studio/synthetic_radar_fixtures.dart';
import 'package:convoy_mesh/pages/detailed_diagnostic_upload_card.dart';
import 'package:convoy_mesh/pages/diagnostic_page.dart';
import 'package:convoy_mesh/pages/manual_ping_card.dart';
import 'package:convoy_mesh/services/convoy_mesh_service.dart';
import 'package:convoy_mesh/services/diagnostic_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const bool _renderPreviews = bool.fromEnvironment('RENDER_PREVIEWS');
const String _previewOutDir = String.fromEnvironment(
  'PREVIEW_DIR',
  defaultValue: '../docs/design-previews',
);
const String _flutterSdkRoot = String.fromEnvironment(
  'FLUTTER_SDK_ROOT',
  defaultValue: '',
);

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var loadedAny = false;
  for (final path in paths) {
    final f = File(path);
    if (await f.exists()) {
      final bytes = await f.readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
      loadedAny = true;
    }
  }
  if (loadedAny) await loader.load();
}

Future<void> _loadAllFonts() async {
  await _loadFont('Fraunces', [
    'assets/fonts/Fraunces-500.ttf',
    'assets/fonts/Fraunces-700.ttf',
  ]);
  await _loadFont('Manrope', [
    'assets/fonts/Manrope-400.ttf',
    'assets/fonts/Manrope-600.ttf',
    'assets/fonts/Manrope-800.ttf',
  ]);
  await _loadFont('JetBrainsMono', [
    'assets/fonts/JetBrainsMono-500.ttf',
    'assets/fonts/JetBrainsMono-700.ttf',
  ]);
  if (_flutterSdkRoot.isNotEmpty) {
    final mat = '$_flutterSdkRoot/bin/cache/artifacts/material_fonts';
    await _loadFont('Roboto', [
      '$mat/Roboto-Regular.ttf',
      '$mat/Roboto-Medium.ttf',
      '$mat/Roboto-Bold.ttf',
    ]);
    await _loadFont('MaterialIcons', [
      '$mat/MaterialIcons-Regular.otf',
    ]);
  }
}

Future<void> _captureBoundary(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String fileName,
) async {
  final bytes = await tester.runAsync<Uint8List>(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  final outDir = Directory(_previewOutDir);
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  File('${outDir.path}/$fileName').writeAsBytesSync(bytes!);
}

Widget _phoneFrame({
  required GlobalKey boundaryKey,
  required ThemeData theme,
  required Widget child,
}) {
  return MediaQuery(
    data: const MediaQueryData(
      size: Size(390, 844),
      padding: EdgeInsets.only(top: 44, bottom: 20),
    ),
    child: RepaintBoundary(
      key: boundaryKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: child,
      ),
    ),
  );
}

String _synthJsonlLine(
  int i,
  String category,
  String event,
  Map<String, Object?> data,
) =>
    jsonEncode({
      'ts_utc': '2026-11-18T08:00:00.000Z',
      'elapsed_ms': i * 1000,
      'session_id': 'CM-outdoor-preview',
      'device_id': 4096,
      'device_name': 'Chiara M.',
      'event_index': i,
      'category': category,
      'event': event,
      'data': data,
    });

void main() {
  if (!_renderPreviews) {
    test('preview renderer skips when RENDER_PREVIEWS is not enabled', () {
      expect(_renderPreviews, isFalse);
    });
    return;
  }

  testWidgets(
      'render real Flutter PNG previews across Original and full Outdoor Premium',
      (tester) async {
    await tester.runAsync(_loadAllFonts);
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final data = SyntheticRadarFixtures.of(SyntheticScenario.groupHike);
    final actions = RadarActions.recording((_) {});

    // 1. Original (LAB +15) Radar comparison baseline
    {
      final key = GlobalKey();
      await tester.pumpWidget(
        _phoneFrame(
          boundaryKey: key,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
            useMaterial3: true,
          ),
          child: Scaffold(
            body: OriginalRadarPreview(data: data, actions: actions),
            bottomNavigationBar: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Avvia uscita'),
                    ),
                  ),
                ),
                NavigationBar(
                  selectedIndex: 0,
                  onDestinationSelected: (_) {},
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.radar), label: 'Radar BLE'),
                    NavigationDestination(icon: Icon(Icons.map), label: 'Mappa'),
                    NavigationDestination(
                        icon: Icon(Icons.bug_report_outlined), label: 'Test log'),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await _captureBoundary(tester, key, '01_original_radar.png');
    }

    // 2 & 3. Outdoor Premium (Pino & Carta) Radar Hero + Scrolled Peers
    {
      final key = GlobalKey();
      const tokens = DesignPresets.outdoorPremium;
      await tester.pumpWidget(
        _phoneFrame(
          boundaryKey: key,
          theme: buildConvoyTheme(tokens),
          child: Scaffold(
            body: DesignedRadarView(tokens: tokens, data: data, actions: actions),
            bottomNavigationBar: DesignedBottomDock(
              tokens: tokens,
              selectedIndex: 0,
              onSelectIndex: (_) {},
              outingActive: false,
              busy: false,
              error: null,
              onToggleOuting: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 520));
      await _captureBoundary(tester, key, '02_outdoor_radar.png');

      await tester.drag(
          find.byKey(const Key('designed-radar-list')), const Offset(0, -470));
      await tester.pump(const Duration(milliseconds: 520));
      await _captureBoundary(tester, key, '03_outdoor_peers.png');
    }

    // 4 & 5. Outdoor Premium Maps: Cresta Alba (daylight) & Abete Notturno (dark)
    for (final entry in [
      (
        DesignPresets.paletteOf(OutdoorPalettePreset.crestaAlba),
        '04_outdoor_map_cresta.png',
        SyntheticScenario.activeOuting,
        true,
      ),
      (
        DesignPresets.paletteOf(OutdoorPalettePreset.abeteNotturno),
        '05_outdoor_map_abete_notturno.png',
        SyntheticScenario.groupHike,
        false,
      ),
    ]) {
      final key = GlobalKey();
      final tokens = entry.$1;
      final file = entry.$2;
      final scenario = entry.$3;
      final outing = entry.$4;
      await tester.pumpWidget(
        _phoneFrame(
          boundaryKey: key,
          theme: buildConvoyTheme(tokens),
          child: Scaffold(
            body: DesignedMapScaffold(
              tokens: tokens,
              gpsVisual: SyntheticRadarFixtures.gpsVisualOf(scenario),
              gpsStatusText: SyntheticRadarFixtures.gpsTextOf(scenario),
              onlineBasemap: false,
              peerCountWithFix: 2,
              hasOwnTrail: true,
              mapChild: _PreviewMapCanvas(tokens: tokens),
              onLocate: () {},
              onToggleBasemap: (_) {},
              onClearTrail: () {},
              onChooseDesign: () {},
            ),
            bottomNavigationBar: DesignedBottomDock(
              tokens: tokens,
              selectedIndex: 1,
              onSelectIndex: (_) {},
              outingActive: outing,
              busy: false,
              error: null,
              onToggleOuting: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await _captureBoundary(tester, key, file);
    }

    // 6. Real DiagnosticPage recording active in Outdoor Premium
    {
      final recorder = DiagnosticRecorder.instance;
      if (recorder.isActive) recorder.stop(reason: 'preview_reset');
      recorder.start(deviceId: 4096, deviceName: 'Chiara M.');
      recorder.record('gps', 'fix', data: {'fresh': true, 'accuracy_m': 8.2});
      recorder.record('runtime', 'snapshot', data: {
        'outing_active': true,
        'foreground_service': true,
      });

      final design = DesignDirectionController.instance;
      await design.select(DesignDirection.outdoorPremium);
      final tokens = design.outdoorTokens;
      final key = GlobalKey();

      await tester.pumpWidget(
        _phoneFrame(
          boundaryKey: key,
          theme: buildConvoyTheme(tokens),
          child: Scaffold(
            body: DiagnosticPage(
              deviceIdOverride: 4096,
              deviceNameOverride: 'Chiara M.',
              captureNowOverride: () {},
            ),
            bottomNavigationBar: DesignedBottomDock(
              tokens: tokens,
              selectedIndex: 2,
              onSelectIndex: (_) {},
              outingActive: true,
              busy: false,
              error: null,
              onToggleOuting: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await _captureBoundary(tester, key, '06_outdoor_diagnostic_top.png');
      recorder.stop(reason: 'manual_stop');
    }

    // 7. Outdoor Premium Diagnostic Summary + PostHog Upload Opt-In + Ping Card
    {
      final key = GlobalKey();
      const tokens = DesignPresets.outdoorPremium;
      final synthSession = [
        _synthJsonlLine(0, 'session', 'start', {}),
        _synthJsonlLine(1, 'runtime', 'snapshot', {
          'peers': [
            {'id': 1042, 'name': 'Marco R.', 'lat': 45.81, 'lon': 11.21},
          ],
        }),
        _synthJsonlLine(2, 'gps', 'fix', {'raw_lat': 45.81, 'raw_lon': 11.21}),
        _synthJsonlLine(3, 'session', 'stop', {}),
      ].join('\n');

      await tester.pumpWidget(
        _phoneFrame(
          boundaryKey: key,
          theme: buildConvoyTheme(tokens),
          child: Scaffold(
            backgroundColor: tokens.canvas,
            appBar: AppBar(title: const Text('Test diagnostico')),
            body: ListView(
              padding: EdgeInsets.all(tokens.hPad),
              children: [
                OutdoorCard(
                  tokens: tokens,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutdoorCardHeader(
                        tokens: tokens,
                        icon: Icons.summarize_outlined,
                        title: 'Riepilogo tecnico locale',
                        subtitle: 'Chiusura: manual_stop',
                        tone: OutdoorTone.positive,
                      ),
                      SizedBox(height: tokens.space(2)),
                      OutdoorSpecRow(
                          tokens: tokens, label: 'Durata', value: '01m 24s'),
                      OutdoorSpecRow(
                        tokens: tokens,
                        label: 'Fix GPS validi',
                        value: '18 (ottimi 16)',
                        valueColor: tokens.positive,
                      ),
                      OutdoorSpecRow(
                        tokens: tokens,
                        label: 'Punti traccia locale',
                        value: '14',
                        showDivider: false,
                      ),
                    ],
                  ),
                ),
                DetailedDiagnosticUploadCard(
                  jsonl: synthSession,
                  configuredOverride: true,
                  senderOverride: (_) async => 200,
                ),
                const ManualPingCard(configuredOverride: true),
              ],
            ),
            bottomNavigationBar: DesignedBottomDock(
              tokens: tokens,
              selectedIndex: 2,
              onSelectIndex: (_) {},
              outingActive: false,
              busy: false,
              error: null,
              onToggleOuting: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await _captureBoundary(tester, key, '07_outdoor_diagnostic_summary_cloud.png');
    }

    // 8. Interactive Outdoor Studio Customizer
    {
      final key = GlobalKey();
      final ctrl = DesignDirectionController.forTest(
        DesignDirection.outdoorPremium,
      );
      await tester.pumpWidget(
        _phoneFrame(
          boundaryKey: key,
          theme: buildConvoyTheme(ctrl.outdoorTokens),
          child: FrontendDesignStudioPage(
            controller: ctrl,
            initialCustomizeTab: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 450));
      await _captureBoundary(tester, key, '08_outdoor_studio_customizer.png');
    }
  });
}

class _PreviewMapCanvas extends StatelessWidget {
  const _PreviewMapCanvas({required this.tokens});
  final ConvoyDesignTokens tokens;

  @override
  Widget build(BuildContext context) {
    final marcoColor = Color(ConvoyMeshService.colorForUser(1042));
    final lucaColor = Color(ConvoyMeshService.colorForUser(3317));
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;
      return Stack(children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _MiniVectorPainter(
              selfColor: tokens.accent,
              marcoColor: marcoColor,
              lucaColor: lucaColor,
            ),
          ),
        ),
        Positioned(
          left: w * 0.48 - 65,
          top: h * 0.46 - 24,
          width: 130,
          child: DesignedMapMarker(
            tokens: tokens,
            colour: tokens.accent,
            label: 'Io',
            fresh: true,
            isSelf: true,
          ),
        ),
        Positioned(
          left: w * 0.68 - 55,
          top: h * 0.34 - 24,
          width: 110,
          child: DesignedMapMarker(
            tokens: tokens,
            colour: marcoColor,
            label: 'Marco R.',
            fresh: true,
          ),
        ),
        Positioned(
          left: w * 0.30 - 75,
          top: h * 0.56 - 24,
          width: 150,
          child: DesignedMapMarker(
            tokens: tokens,
            colour: lucaColor,
            label: 'Luca B. • 1m fa',
            fresh: false,
          ),
        ),
      ]);
    });
  }
}

class _MiniVectorPainter extends CustomPainter {
  _MiniVectorPainter({
    required this.selfColor,
    required this.marcoColor,
    required this.lucaColor,
  });

  final Color selfColor;
  final Color marcoColor;
  final Color lucaColor;

  @override
  void paint(Canvas canvas, Size size) {
    final self = Offset(size.width * 0.48, size.height * 0.46);
    final marco = Offset(size.width * 0.68, size.height * 0.34);
    final luca = Offset(size.width * 0.30, size.height * 0.56);

    canvas.drawCircle(self, 36, Paint()..color = selfColor.withValues(alpha: 0.14));
    canvas.drawCircle(
      self,
      36,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = selfColor.withValues(alpha: 0.55),
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.26, size.height * 0.66)
        ..lineTo(size.width * 0.36, size.height * 0.58)
        ..lineTo(self.dx, self.dy),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..color = selfColor.withValues(alpha: 0.7),
    );

    canvas.drawCircle(marco, 26, Paint()..color = marcoColor.withValues(alpha: 0.14));
    canvas.drawCircle(
      marco,
      26,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = marcoColor.withValues(alpha: 0.5),
    );

    canvas.drawCircle(luca, 46, Paint()..color = lucaColor.withValues(alpha: 0.08));
    const dashes = 8;
    final lucaStart = Offset(size.width * 0.11, size.height * 0.63);
    for (var i = 0; i < dashes; i += 2) {
      canvas.drawLine(
        Offset.lerp(lucaStart, luca, i / dashes)!,
        Offset.lerp(lucaStart, luca, (i + 1) / dashes)!,
        Paint()
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = lucaColor.withValues(alpha: 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
