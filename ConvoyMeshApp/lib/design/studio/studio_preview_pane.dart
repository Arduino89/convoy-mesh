import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/convoy_mesh_service.dart';
import '../design_presets.dart';
import '../design_theme.dart';
import '../design_tokens.dart';
import '../diagnostic/designed_diagnostic_header.dart';
import '../map/designed_map_chrome.dart';
import '../outdoor_components.dart';
import '../radar/designed_radar_view.dart';
import '../radar/radar_actions.dart';
import '../radar/radar_view_data.dart';
import '../shell/designed_app_shell.dart';
import 'original_radar_preview.dart';
import 'synthetic_radar_fixtures.dart';

enum StudioPreviewPage { radar, map, diagnostic }

/// Synthetic interactive preview workspace comparing **Outdoor Premium** and
/// **Originale (LAB +15)** across Radar BLE, Map and Diagnostic screens.
class StudioPreviewWorkspace extends StatelessWidget {
  const StudioPreviewWorkspace({
    super.key,
    required this.outdoorTokens,
    required this.selectedDirection,
    required this.previewPage,
    required this.scenario,
    required this.onlineBasemap,
    required this.diagActive,
    required this.onSelectDirection,
    required this.onSelectScenario,
    required this.onSelectPreviewPage,
    required this.onToggleOnlineBasemap,
    required this.onToggleDiagActive,
    required this.onToggleOutingScenario,
    required this.onOpenCustomize,
    required this.onPreviewAction,
  });

  final ConvoyDesignTokens outdoorTokens;
  final DesignDirection selectedDirection;
  final StudioPreviewPage previewPage;
  final SyntheticScenario scenario;
  final bool onlineBasemap;
  final bool diagActive;
  final ValueChanged<DesignDirection> onSelectDirection;
  final ValueChanged<SyntheticScenario> onSelectScenario;
  final ValueChanged<StudioPreviewPage> onSelectPreviewPage;
  final ValueChanged<bool> onToggleOnlineBasemap;
  final VoidCallback onToggleDiagActive;
  final VoidCallback onToggleOutingScenario;
  final VoidCallback onOpenCustomize;
  final ValueChanged<String> onPreviewAction;

  @override
  Widget build(BuildContext context) {
    final data = SyntheticRadarFixtures.of(scenario);
    final tokens = selectedDirection == DesignDirection.classic
        ? DesignPresets.classicReference
        : outdoorTokens;

    return Column(
      children: [
        Material(
          color: outdoorTokens.canvas,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    ChoiceChip(
                      key: const Key('studio-dir-outdoorPremium'),
                      label: Text(DesignDirection.outdoorPremium.label),
                      selected:
                          selectedDirection == DesignDirection.outdoorPremium,
                      onSelected: (_) =>
                          onSelectDirection(DesignDirection.outdoorPremium),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      key: const Key('studio-dir-classic'),
                      label: Text(DesignDirection.classic.label),
                      selected: selectedDirection == DesignDirection.classic,
                      onSelected: (_) =>
                          onSelectDirection(DesignDirection.classic),
                    ),
                  ]),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final s in SyntheticScenario.values) ...[
                      FilterChip(
                        label:
                            Text(s.label, style: const TextStyle(fontSize: 12)),
                        selected: scenario == s,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => onSelectScenario(s),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ]),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _previewShell(tokens, data)),
      ],
    );
  }

  Widget _previewShell(ConvoyDesignTokens tokens, RadarViewData data) {
    final actions = RadarActions.recording(onPreviewAction);
    final Widget body;
    if (selectedDirection == DesignDirection.classic) {
      body = switch (previewPage) {
        StudioPreviewPage.radar =>
          OriginalRadarPreview(data: data, actions: actions),
        StudioPreviewPage.map => OriginalMapPreview(scenario: scenario),
        StudioPreviewPage.diagnostic => OriginalDiagnosticPreview(
            active: diagActive,
            onToggle: onToggleDiagActive,
          ),
      };
    } else {
      body = Theme(
        data: buildConvoyTheme(tokens),
        child: switch (previewPage) {
          StudioPreviewPage.radar => DesignedRadarView(
              tokens: tokens,
              data: data,
              actions: actions,
            ),
          StudioPreviewPage.map => DesignedMapScaffold(
              tokens: tokens,
              gpsVisual: SyntheticRadarFixtures.gpsVisualOf(scenario),
              gpsStatusText: SyntheticRadarFixtures.gpsTextOf(scenario),
              onlineBasemap: onlineBasemap,
              peerCountWithFix:
                  scenario == SyntheticScenario.activeOuting ||
                          scenario == SyntheticScenario.groupHike
                      ? 2
                      : 0,
              hasOwnTrail: scenario == SyntheticScenario.activeOuting,
              mapChild: SyntheticMapCanvas(
                tokens: tokens,
                scenario: scenario,
                onlineBasemap: onlineBasemap,
              ),
              onLocate: () => onPreviewAction('locate'),
              onToggleBasemap: onToggleOnlineBasemap,
              onClearTrail: () => onPreviewAction('clearTrail'),
              onChooseDesign: onOpenCustomize,
            ),
          StudioPreviewPage.diagnostic => DesignedDiagnosticPreview(
              tokens: tokens,
              active: diagActive,
              onToggle: onToggleDiagActive,
            ),
        },
      );
    }

    final Widget dock = selectedDirection == DesignDirection.classic
        ? OriginalBottomPreview(
            selectedIndex: previewPage.index,
            outingActive: scenario == SyntheticScenario.activeOuting,
            onSelectIndex: (i) =>
                onSelectPreviewPage(StudioPreviewPage.values[i]),
          )
        : Theme(
            data: buildConvoyTheme(tokens),
            child: DesignedBottomDock(
              tokens: tokens,
              selectedIndex: previewPage.index,
              outingActive: scenario == SyntheticScenario.activeOuting,
              busy: false,
              error: null,
              onToggleOuting: onToggleOutingScenario,
              onSelectIndex: (i) =>
                  onSelectPreviewPage(StudioPreviewPage.values[i]),
            ),
          );

    return Column(children: [
      Expanded(child: body),
      dock,
    ]);
  }
}

class OriginalBottomPreview extends StatelessWidget {
  const OriginalBottomPreview({
    super.key,
    required this.selectedIndex,
    required this.outingActive,
    required this.onSelectIndex,
  });

  final int selectedIndex;
  final bool outingActive;
  final ValueChanged<int> onSelectIndex;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: Icon(outingActive
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline),
              label: Text(
                  outingActive ? 'Uscita attiva • Termina uscita' : 'Avvia uscita'),
            ),
          ),
        ),
        NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelectIndex,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.radar), label: 'Radar BLE'),
            NavigationDestination(icon: Icon(Icons.map), label: 'Mappa'),
            NavigationDestination(
                icon: Icon(Icons.bug_report_outlined), label: 'Test log'),
          ],
        ),
      ]),
    );
  }
}

class OriginalMapPreview extends StatelessWidget {
  const OriginalMapPreview({super.key, required this.scenario});
  final SyntheticScenario scenario;

  @override
  Widget build(BuildContext context) {
    final gpsVisual = SyntheticRadarFixtures.gpsVisualOf(scenario);
    final gpsText = SyntheticRadarFixtures.gpsTextOf(scenario);
    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mappa'),
          actions: [
            IconButton(
              onPressed: () {},
              icon: Icon(Icons.my_location,
                  color: gpsVisual.isGreen ? Colors.green : Colors.red),
            ),
            IconButton(onPressed: () {}, icon: const Icon(Icons.delete_outline)),
          ],
        ),
        body: Column(children: [
          SwitchListTile(
            dense: true,
            title: const Text('Sfondo cartografico online'),
            subtitle: const Text(
              'Senza rete restano coordinate, marker e tracce; non sono mappe offline scaricate.',
            ),
            value: true,
            onChanged: (_) {},
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '$gpsText Cerchi = incertezza stimata. Tratteggio = percorso recuperato dopo una riconnessione.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: SyntheticMapCanvas(
              tokens: DesignPresets.classicReference,
              scenario: scenario,
              onlineBasemap: false,
            ),
          ),
        ]),
      ),
    );
  }
}

class OriginalDiagnosticPreview extends StatelessWidget {
  const OriginalDiagnosticPreview({
    super.key,
    required this.active,
    required this.onToggle,
  });

  final bool active;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('Test diagnostico')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Builder(
                    builder: (ctx) => Text(
                      active
                          ? 'Registrazione locale in corso'
                          : 'Registrazione diagnostica locale',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Telefono: Chiara M. • ID 4096'),
                  const Text('Registrazione diagnostica: massimo 4 minuti'),
                  const Text('App: 0.7.7-diaglab+15 • sintetica'),
                  const SizedBox(height: 8),
                  if (active) ...[
                    const Text('Durata 01:24 • restante 02:36'),
                    const Text('Eventi 48 • scartati per limite 0'),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Segna qui un problema'),
                    ),
                    FilledButton.icon(
                      onPressed: onToggle,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Termina registrazione diagnostica'),
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed: onToggle,
                      icon: const Icon(Icons.fiber_manual_record),
                      label: const Text(
                          'Avvia registrazione diagnostica • max 4 min'),
                    ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class DesignedDiagnosticPreview extends StatelessWidget {
  const DesignedDiagnosticPreview({
    super.key,
    required this.tokens,
    required this.active,
    required this.onToggle,
  });

  final ConvoyDesignTokens tokens;
  final bool active;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Scaffold(
      backgroundColor: t.canvas,
      appBar: AppBar(title: Text(t.copy.diagnosticTitle)),
      body: ListView(
        padding: EdgeInsets.all(t.hPad),
        children: [
          OutdoorCard(
            tokens: t,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DesignedDiagnosticStatusStrip(
                  tokens: t,
                  active: active,
                  ready: true,
                  persistent: true,
                  elapsed: const Duration(seconds: 84),
                  remaining: const Duration(seconds: 156),
                  eventCount: 48,
                  droppedEvents: 0,
                ),
                Text(
                  active
                      ? t.copy.diagnosticActiveTitle
                      : t.copy.diagnosticStartTitle,
                  style: t.display(18.5),
                ),
                SizedBox(height: t.space(1.5)),
                Text(
                  'Telefono: Chiara M. • ID 4096',
                  style: t.body(13.5, weight: FontWeight.w700),
                ),
                Text(
                  'Registrazione diagnostica: massimo 4 minuti',
                  style: t.body(12.5, color: t.inkMuted),
                ),
                SizedBox(height: t.space(2)),
                if (active) ...[
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Segna qui un problema'),
                  ),
                  SizedBox(height: t.space(1.75)),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: t.critical,
                      foregroundColor: t.onCritical,
                    ),
                    onPressed: onToggle,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Termina registrazione diagnostica'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: onToggle,
                    icon: const Icon(Icons.fiber_manual_record),
                    label: const Text(
                        'Avvia registrazione diagnostica • max 4 min'),
                  ),
                SizedBox(height: t.space(2)),
                OutdoorCallout(
                  tokens: t,
                  icon: Icons.lock_outline,
                  text:
                      'Registrazione indipendente dall’uscita; nessun invio automatico.',
                ),
              ],
            ),
          ),
          OutdoorCard(
            tokens: t,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutdoorCardHeader(
                  tokens: t,
                  icon: Icons.summarize_outlined,
                  title: 'Riepilogo tecnico locale',
                  subtitle: 'Sessione sintetica di anteprima • 01:24',
                  tone: OutdoorTone.positive,
                ),
                SizedBox(height: t.space(2.5)),
                OutdoorSpecRow(tokens: t, label: 'Durata', value: '1m 24s'),
                OutdoorSpecRow(
                  tokens: t,
                  label: 'Fix GPS validi',
                  value: '18 (ottimi 16)',
                  valueColor: t.positive,
                ),
                OutdoorSpecRow(
                    tokens: t, label: 'Punti traccia locale', value: '14'),
                OutdoorSpecRow(
                  tokens: t,
                  label: 'Peer BLE osservati',
                  value: '2',
                  showDivider: false,
                ),
              ],
            ),
          ),
          OutdoorCard(
            tokens: t,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutdoorCardHeader(
                  tokens: t,
                  icon: Icons.cloud_off_outlined,
                  title: 'Invio diagnostico PostHog EU',
                  subtitle:
                      'In pausa sulle build Outdoor; l’invio richiede consenso esplicito.',
                  tone: OutdoorTone.neutral,
                  trailing: OutdoorStatusBadge(
                    tokens: t,
                    label: 'Anteprima',
                    tone: OutdoorTone.neutral,
                  ),
                ),
                SizedBox(height: t.space(2.5)),
                OutdoorCallout(
                  tokens: t,
                  icon: Icons.info_outline,
                  tone: OutdoorTone.accent,
                  text:
                      'In anteprima nessun dato lascia il telefono: la registrazione e la condivisione locale dei log restano sempre disponibili.',
                ),
              ],
            ),
          ),
          OutdoorCard(
            tokens: t,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutdoorCardHeader(
                  tokens: t,
                  icon: Icons.memory_outlined,
                  title: t.copy.diagnosticRuntimeTitle,
                ),
                SizedBox(height: t.space(2)),
                OutdoorSpecRow(
                  tokens: t,
                  label: 'Servizio foreground',
                  value: 'Non attivo',
                ),
                OutdoorSpecRow(
                  tokens: t,
                  label: 'UWB / Wi-Fi RTT',
                  value: 'Non rilevato',
                  showDivider: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Offline synthetic vector map showing uncertainty circles, own trail,
/// recovered HISTORY dashed segment, and themed markers without network tiles.
class SyntheticMapCanvas extends StatelessWidget {
  const SyntheticMapCanvas({
    super.key,
    required this.tokens,
    required this.scenario,
    required this.onlineBasemap,
  });

  final ConvoyDesignTokens tokens;
  final SyntheticScenario scenario;
  final bool onlineBasemap;

  @override
  Widget build(BuildContext context) {
    final showGroup = scenario == SyntheticScenario.groupHike ||
        scenario == SyntheticScenario.activeOuting;
    final classic = tokens.direction == DesignDirection.classic;
    final marcoColor = Color(ConvoyMeshService.colorForUser(1042));
    final lucaColor = Color(ConvoyMeshService.colorForUser(3317));

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;
      final selfPos = Offset(w * 0.48, h * 0.48);
      final marcoPos = Offset(w * 0.68, h * 0.36);
      final lucaPos = Offset(w * 0.30, h * 0.62);

      return Stack(children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _SyntheticVectorMapPainter(
                brightness: tokens.brightness,
                accent: tokens.accent,
                inkMuted: tokens.inkMuted,
                showContours: onlineBasemap && tokens.showTopoContours,
                showGroup: showGroup,
                selfColor: classic ? Colors.blue : tokens.accent,
                marcoColor: marcoColor,
                lucaColor: lucaColor,
              ),
            ),
          ),
        ),
        Positioned(
          left: selfPos.dx - 65,
          top: selfPos.dy - 24,
          width: 130,
          child: DesignedMapMarker(
            tokens: tokens,
            colour: classic ? Colors.blue : tokens.accent,
            label: scenario == SyntheticScenario.activeOuting
                ? 'Io'
                : 'Io • ultima nota',
            fresh: scenario == SyntheticScenario.activeOuting,
            isSelf: true,
          ),
        ),
        if (showGroup) ...[
          Positioned(
            left: marcoPos.dx - 55,
            top: marcoPos.dy - 24,
            width: 110,
            child: DesignedMapMarker(
              tokens: tokens,
              colour: marcoColor,
              label: 'Marco R.',
              fresh: true,
            ),
          ),
          Positioned(
            left: lucaPos.dx - 75,
            top: lucaPos.dy - 24,
            width: 150,
            child: DesignedMapMarker(
              tokens: tokens,
              colour: lucaColor,
              label: 'Luca B. • 1m fa',
              fresh: false,
            ),
          ),
        ],
      ]);
    });
  }
}

class _SyntheticVectorMapPainter extends CustomPainter {
  _SyntheticVectorMapPainter({
    required this.brightness,
    required this.accent,
    required this.inkMuted,
    required this.showContours,
    required this.showGroup,
    required this.selfColor,
    required this.marcoColor,
    required this.lucaColor,
  });

  final Brightness brightness;
  final Color accent;
  final Color inkMuted;
  final bool showContours;
  final bool showGroup;
  final Color selfColor;
  final Color marcoColor;
  final Color lucaColor;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = brightness == Brightness.dark;
    if (showContours) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = dark ? const Color(0xFF0E1713) : const Color(0xFFEBE7DC),
      );
      for (var k = 1; k <= 6; k++) {
        final r = k * 54.0;
        final c = Offset(size.width * 0.62, size.height * 0.42);
        final path = Path();
        for (var i = 0; i <= 72; i++) {
          final a = i / 72 * 2 * math.pi;
          final rr = r * (1 + 0.08 * math.sin(3 * a + k));
          final p = c + Offset(rr * math.cos(a), rr * 0.78 * math.sin(a));
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        path.close();
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color =
                (dark ? accent : const Color(0xFF8C826F)).withValues(alpha: 0.22),
        );
      }
      final trail = Path()
        ..moveTo(size.width * 0.08, size.height * 0.78)
        ..quadraticBezierTo(size.width * 0.35, size.height * 0.56,
            size.width * 0.52, size.height * 0.48)
        ..quadraticBezierTo(size.width * 0.74, size.height * 0.35,
            size.width * 0.92, size.height * 0.22);
      canvas.drawPath(
        trail,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = (dark ? inkMuted : const Color(0xFF9A7B56))
              .withValues(alpha: 0.5),
      );
    }

    final selfPos = Offset(size.width * 0.48, size.height * 0.48);
    canvas.drawCircle(
        selfPos, 38, Paint()..color = selfColor.withValues(alpha: 0.14));
    canvas.drawCircle(
      selfPos,
      38,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = selfColor.withValues(alpha: 0.5),
    );
    final ownPath = Path()
      ..moveTo(size.width * 0.28, size.height * 0.70)
      ..lineTo(size.width * 0.36, size.height * 0.62)
      ..lineTo(size.width * 0.41, size.height * 0.54)
      ..lineTo(selfPos.dx, selfPos.dy);
    canvas.drawPath(
      ownPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..color = selfColor.withValues(alpha: 0.65),
    );

    if (showGroup) {
      final marcoPos = Offset(size.width * 0.68, size.height * 0.36);
      final lucaPos = Offset(size.width * 0.30, size.height * 0.62);

      canvas.drawCircle(
          marcoPos, 28, Paint()..color = marcoColor.withValues(alpha: 0.14));
      canvas.drawCircle(
        marcoPos,
        28,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = marcoColor.withValues(alpha: 0.5),
      );
      canvas.drawCircle(
          lucaPos, 54, Paint()..color = lucaColor.withValues(alpha: 0.07));
      canvas.drawCircle(
        lucaPos,
        54,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = lucaColor.withValues(alpha: 0.4),
      );

      final a = Offset(size.width * 0.14, size.height * 0.69);
      const dashes = 8;
      for (var i = 0; i < dashes; i += 2) {
        final t0 = i / dashes;
        final t1 = (i + 1) / dashes;
        canvas.drawLine(
          Offset.lerp(a, lucaPos, t0)!,
          Offset.lerp(a, lucaPos, t1)!,
          Paint()
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = lucaColor.withValues(alpha: 0.68),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SyntheticVectorMapPainter old) =>
      old.brightness != brightness ||
      old.accent != accent ||
      old.inkMuted != inkMuted ||
      old.showContours != showContours ||
      old.showGroup != showGroup ||
      old.selfColor != selfColor ||
      old.marcoColor != marcoColor ||
      old.lucaColor != lucaColor;
}
