import 'dart:io';
import 'dart:ui' as ui;

import 'package:convoy_mesh/design/design_controller.dart';
import 'package:convoy_mesh/design/design_presets.dart';
import 'package:convoy_mesh/design/design_theme.dart';
import 'package:convoy_mesh/design/design_tokens.dart';
import 'package:convoy_mesh/design/diagnostic/designed_diagnostic_header.dart';
import 'package:convoy_mesh/design/map/designed_map_chrome.dart';
import 'package:convoy_mesh/design/radar/designed_radar_view.dart';
import 'package:convoy_mesh/design/radar/radar_actions.dart';
import 'package:convoy_mesh/design/shell/designed_app_shell.dart';
import 'package:convoy_mesh/design/studio/frontend_design_studio_page.dart';
import 'package:convoy_mesh/design/studio/original_radar_preview.dart';
import 'package:convoy_mesh/design/studio/synthetic_radar_fixtures.dart';
import 'package:convoy_mesh/services/convoy_mesh_service.dart';
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
  await _loadFont('SpaceGrotesk', [
    'assets/fonts/SpaceGrotesk-500.ttf',
    'assets/fonts/SpaceGrotesk-700.ttf',
  ]);
  await _loadFont('JetBrainsMono', [
    'assets/fonts/JetBrainsMono-500.ttf',
    'assets/fonts/JetBrainsMono-700.ttf',
  ]);
  await _loadFont('PlusJakartaSans', [
    'assets/fonts/PlusJakartaSans-400.ttf',
    'assets/fonts/PlusJakartaSans-600.ttf',
    'assets/fonts/PlusJakartaSans-800.ttf',
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

void main() {
  if (!_renderPreviews) {
    test('preview renderer skips when RENDER_PREVIEWS is not enabled', () {
      expect(_renderPreviews, isFalse);
    });
    return;
  }

  testWidgets('render real Flutter PNG previews across original and 3 directions',
      (tester) async {
    await tester.runAsync(_loadAllFonts);
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final data = SyntheticRadarFixtures.of(SyntheticScenario.groupHike);
    final outingData = SyntheticRadarFixtures.of(SyntheticScenario.activeOuting);
    final actions = RadarActions.recording((_) {});

    // 1. Original (LAB +15) Radar
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
                    NavigationDestination(icon: Icon(Icons.bug_report_outlined), label: 'Test log'),
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

    // 2. Outdoor Premium (Radar Hero) + scrolled peers view
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
      await _captureBoundary(tester, key, '02_outdoor_premium_radar.png');

      await tester.drag(find.byKey(const Key('designed-radar-list')), const Offset(0, -470));
      await tester.pump(const Duration(milliseconds: 520));
      await _captureBoundary(tester, key, '03_outdoor_premium_peers.png');
    }

    // 3. Tactical Explorer (HUD + Sweep)
    {
      final key = GlobalKey();
      const tokens = DesignPresets.tacticalExplorer;
      await tester.pumpWidget(
        _phoneFrame(
          boundaryKey: key,
          theme: buildConvoyTheme(tokens),
          child: Scaffold(
            body: DesignedRadarView(tokens: tokens, data: outingData, actions: actions),
            bottomNavigationBar: DesignedBottomDock(
              tokens: tokens,
              selectedIndex: 0,
              onSelectIndex: (_) {},
              outingActive: true,
              busy: false,
              error: null,
              onToggleOuting: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await _captureBoundary(tester, key, '04_tactical_explorer_radar.png');
    }

    // 4. Minimal Adventure (Editorial + Pulse)
    {
      final key = GlobalKey();
      const tokens = DesignPresets.minimalAdventure;
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
      await tester.pump(const Duration(milliseconds: 620));
      await _captureBoundary(tester, key, '05_minimal_adventure_radar.png');
    }

    // 5. Redesigned Map views (Outdoor Premium & Tactical Explorer)
    for (final entry in [
      (DesignPresets.outdoorPremium, '06_map_outdoor_premium.png', true),
      (DesignPresets.tacticalExplorer, '07_map_tactical_explorer.png', false),
    ]) {
      final key = GlobalKey();
      final tokens = entry.$1;
      final file = entry.$2;
      final outing = entry.$3;
      final scenario =
          outing ? SyntheticScenario.activeOuting : SyntheticScenario.groupHike;
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
      await tester.pump(const Duration(milliseconds: 300));
      await _captureBoundary(tester, key, file);
    }

    // 6. Redesigned Diagnostic view (Outdoor Premium)
    {
      final key = GlobalKey();
      const tokens = DesignPresets.outdoorPremium;
      await tester.pumpWidget(
        _phoneFrame(
          boundaryKey: key,
          theme: buildConvoyTheme(tokens),
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Test diagnostico'),
              actions: const [
                Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(Icons.palette_outlined),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DesignedDiagnosticStatusStrip(
                          tokens: tokens,
                          active: true,
                          ready: true,
                          persistent: true,
                          elapsed: const Duration(minutes: 1, seconds: 24),
                          remaining: const Duration(minutes: 2, seconds: 36),
                          eventCount: 48,
                          droppedEvents: 0,
                        ),
                        Builder(
                          builder: (ctx) => Text(
                            'Registrazione locale in corso',
                            style: Theme.of(ctx).textTheme.titleLarge,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('Telefono: Chiara M. • ID 4096'),
                        const Text('Registrazione diagnostica: massimo 4 minuti'),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.flag_outlined),
                          label: const Text('Segna qui un problema'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('Termina registrazione diagnostica'),
                        ),
                      ],
                    ),
                  ),
                ),
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
      await tester.pump(const Duration(milliseconds: 300));
      await _captureBoundary(tester, key, '08_diagnostic_outdoor_premium.png');
    }

    // 7. Interactive Design Studio screen
    {
      final key = GlobalKey();
      final ctrl = DesignDirectionController.forTest(DesignDirection.minimalAdventure);
      await tester.pumpWidget(
        _phoneFrame(
          boundaryKey: key,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
            useMaterial3: true,
          ),
          child: FrontendDesignStudioPage(
            controller: ctrl,
            initialDirection: DesignDirection.minimalAdventure,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 620));
      await _captureBoundary(tester, key, '09_design_studio.png');
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
