import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/convoy_mesh_service.dart';
import '../design_controller.dart';
import '../design_presets.dart';
import '../design_theme.dart';
import '../design_tokens.dart';
import '../diagnostic/designed_diagnostic_header.dart';
import '../map/designed_map_chrome.dart';
import '../radar/designed_radar_view.dart';
import '../radar/radar_actions.dart';
import '../shell/designed_app_shell.dart';
import 'original_radar_preview.dart';
import 'synthetic_radar_fixtures.dart';

enum StudioPreviewPage { radar, map, diagnostic }

/// Interactive, 100% synthetic Design Studio embedded inside Convoy Mesh.
///
/// Lets reviewers and testers compare the original UI against all three
/// aesthetic directions across Radar, Map, and Diagnostics before applying
/// one to the live application.
class FrontendDesignStudioPage extends StatefulWidget {
  const FrontendDesignStudioPage({
    super.key,
    this.controller,
    this.initialDirection,
  });

  final DesignDirectionController? controller;
  final DesignDirection? initialDirection;

  @override
  State<FrontendDesignStudioPage> createState() => _FrontendDesignStudioPageState();
}

class _FrontendDesignStudioPageState extends State<FrontendDesignStudioPage> {
  late DesignDirection _selected;
  StudioPreviewPage _previewPage = StudioPreviewPage.radar;
  SyntheticScenario _scenario = SyntheticScenario.groupHike;
  bool _showSpecs = false;
  bool _syntheticOnlineBasemap = true;
  bool _syntheticDiagActive = true;

  DesignDirectionController get _ctrl => widget.controller ?? DesignDirectionController.instance;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDirection ?? _ctrl.direction;
  }

  Future<void> _apply() async {
    await _ctrl.select(_selected);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Stile applicato: ${_selected.label}')),
    );
    Navigator.of(context).maybePop();
  }

  void _onPreviewAction(String name) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Anteprima sintetica: azione «$name»'),
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = SyntheticRadarFixtures.of(_scenario);
    final tokens = DesignPresets.of(_selected);
    final applied = _ctrl.direction == _selected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Design Studio'),
        actions: [
          IconButton(
            tooltip: _showSpecs ? 'Mostra anteprima schermo' : 'Mostra token e palette',
            icon: Icon(_showSpecs ? Icons.smartphone_outlined : Icons.tune),
            onPressed: () => setState(() => _showSpecs = !_showSpecs),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: applied ? null : _apply,
              child: Text(applied ? 'Attivo' : 'Applica'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _controlsStrip(),
          const Divider(height: 1),
          Expanded(
            child: _showSpecs
                ? _TokensSpecSheet(direction: _selected, tokens: tokens)
                : _previewShell(tokens, data),
          ),
        ],
      ),
    );
  }

  Widget _controlsStrip() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final d in DesignDirection.values) ...[
                  ChoiceChip(
                    key: Key('studio-dir-${d.storageId}'),
                    label: Text(d.label),
                    selected: _selected == d,
                    onSelected: (_) => setState(() => _selected = d),
                  ),
                  const SizedBox(width: 6),
                ],
              ]),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final s in SyntheticScenario.values) ...[
                      FilterChip(
                        label: Text(s.label, style: const TextStyle(fontSize: 12)),
                        selected: _scenario == s,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _scenario = s),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ]),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _previewShell(ConvoyDesignTokens tokens, data) {
    final actions = RadarActions.recording(_onPreviewAction);
    final Widget body;
    if (_selected == DesignDirection.classic) {
      body = switch (_previewPage) {
        StudioPreviewPage.radar => OriginalRadarPreview(data: data, actions: actions),
        StudioPreviewPage.map => _OriginalMapPreview(scenario: _scenario),
        StudioPreviewPage.diagnostic => _OriginalDiagnosticPreview(
            active: _syntheticDiagActive,
            onToggle: () => setState(() => _syntheticDiagActive = !_syntheticDiagActive),
          ),
      };
    } else {
      body = Theme(
        data: buildConvoyTheme(tokens),
        child: switch (_previewPage) {
          StudioPreviewPage.radar => DesignedRadarView(
              tokens: tokens,
              data: data,
              actions: actions,
            ),
          StudioPreviewPage.map => DesignedMapScaffold(
              tokens: tokens,
              gpsVisual: SyntheticRadarFixtures.gpsVisualOf(_scenario),
              gpsStatusText: SyntheticRadarFixtures.gpsTextOf(_scenario),
              onlineBasemap: _syntheticOnlineBasemap,
              peerCountWithFix: _scenario == SyntheticScenario.activeOuting ||
                      _scenario == SyntheticScenario.groupHike
                  ? 2
                  : 0,
              hasOwnTrail: _scenario == SyntheticScenario.activeOuting,
              mapChild: _SyntheticMapCanvas(
                tokens: tokens,
                scenario: _scenario,
                onlineBasemap: _syntheticOnlineBasemap,
              ),
              onLocate: () => _onPreviewAction('locate'),
              onToggleBasemap: (v) => setState(() => _syntheticOnlineBasemap = v),
              onClearTrail: () => _onPreviewAction('clearTrail'),
              onChooseDesign: () => setState(() => _showSpecs = true),
            ),
          StudioPreviewPage.diagnostic => _DesignedDiagnosticPreview(
              tokens: tokens,
              active: _syntheticDiagActive,
              onToggle: () => setState(() => _syntheticDiagActive = !_syntheticDiagActive),
            ),
        },
      );
    }

    final Widget dock = _selected == DesignDirection.classic
        ? _OriginalBottomPreview(
            selectedIndex: _previewPage.index,
            outingActive: _scenario == SyntheticScenario.activeOuting,
            onSelectIndex: (i) => setState(() => _previewPage = StudioPreviewPage.values[i]),
          )
        : Theme(
            data: buildConvoyTheme(tokens),
            child: DesignedBottomDock(
              tokens: tokens,
              selectedIndex: _previewPage.index,
              outingActive: _scenario == SyntheticScenario.activeOuting,
              busy: false,
              error: null,
              onToggleOuting: () => setState(() {
                _scenario = _scenario == SyntheticScenario.activeOuting
                    ? SyntheticScenario.groupHike
                    : SyntheticScenario.activeOuting;
              }),
              onSelectIndex: (i) => setState(() => _previewPage = StudioPreviewPage.values[i]),
            ),
          );

    return Column(children: [
      Expanded(child: body),
      dock,
    ]);
  }
}

class _OriginalBottomPreview extends StatelessWidget {
  const _OriginalBottomPreview({
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
              icon: Icon(outingActive ? Icons.stop_circle_outlined : Icons.play_circle_outline),
              label: Text(outingActive ? 'Uscita attiva • Termina uscita' : 'Avvia uscita'),
            ),
          ),
        ),
        NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelectIndex,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.radar), label: 'Radar BLE'),
            NavigationDestination(icon: Icon(Icons.map), label: 'Mappa'),
            NavigationDestination(icon: Icon(Icons.bug_report_outlined), label: 'Test log'),
          ],
        ),
      ]),
    );
  }
}

class _OriginalMapPreview extends StatelessWidget {
  const _OriginalMapPreview({required this.scenario});
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
              icon: Icon(Icons.my_location, color: gpsVisual.isGreen ? Colors.green : Colors.red),
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
            child: _SyntheticMapCanvas(
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

class _OriginalDiagnosticPreview extends StatelessWidget {
  const _OriginalDiagnosticPreview({required this.active, required this.onToggle});
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Builder(
                  builder: (ctx) => Text(
                    active ? 'Registrazione locale in corso' : 'Registrazione diagnostica locale',
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
                    label: const Text('Avvia registrazione diagnostica • max 4 min'),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _DesignedDiagnosticPreview extends StatelessWidget {
  const _DesignedDiagnosticPreview({
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
      appBar: AppBar(title: Text(t.label('Test diagnostico'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                active ? 'Registrazione locale in corso' : 'Registrazione diagnostica locale',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('Telefono: Chiara M. • ID 4096', style: t.body(14, color: t.inkMuted)),
              Text('Registrazione diagnostica: massimo 4 minuti', style: t.body(14, color: t.inkMuted)),
              const SizedBox(height: 12),
              if (active) ...[
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Segna qui un problema'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: onToggle,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Termina registrazione diagnostica'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: onToggle,
                  icon: const Icon(Icons.fiber_manual_record),
                  label: const Text('Avvia registrazione diagnostica • max 4 min'),
                ),
              const SizedBox(height: 10),
              Text(
                'Registrazione indipendente dall’uscita; non attiva GPS o servizi extra.',
                style: t.body(12.5, color: t.inkMuted),
              ),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.label('Runtime e capacità hardware'),
                  style: t.body(15, weight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Servizio foreground: NON ATTIVO', style: t.data(13, color: t.inkMuted)),
              Text('UWB: non rilevato • Wi-Fi RTT: non rilevato',
                  style: t.data(13, color: t.inkMuted)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Offline synthetic vector map showing uncertainty circles, own trail,
/// recovered HISTORY dashed segment, and themed markers without network tiles.
class _SyntheticMapCanvas extends StatelessWidget {
  const _SyntheticMapCanvas({
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
          child: CustomPaint(
            painter: _SyntheticVectorMapPainter(
              tokens: tokens,
              showContours: onlineBasemap,
              showGroup: showGroup,
              selfColor: classic ? Colors.blue : tokens.accent,
              marcoColor: marcoColor,
              lucaColor: lucaColor,
            ),
          ),
        ),
        // Self marker
        Positioned(
          left: selfPos.dx - 65,
          top: selfPos.dy - 24,
          width: 130,
          child: DesignedMapMarker(
            tokens: tokens,
            colour: classic ? Colors.blue : tokens.accent,
            label: scenario == SyntheticScenario.activeOuting ? 'Io' : 'Io • ultima nota',
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
    required this.tokens,
    required this.showContours,
    required this.showGroup,
    required this.selfColor,
    required this.marcoColor,
    required this.lucaColor,
  });

  final ConvoyDesignTokens tokens;
  final bool showContours;
  final bool showGroup;
  final Color selfColor;
  final Color marcoColor;
  final Color lucaColor;

  @override
  void paint(Canvas canvas, Size size) {
    final t = tokens;
    final dark = t.brightness == Brightness.dark;
    if (showContours) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = dark ? const Color(0xFF0E1513) : const Color(0xFFEBE7DC),
      );
      // Synthetic trail/contour background lines (not real map data)
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
            ..color = (dark ? t.accent : const Color(0xFF8C826F)).withValues(alpha: 0.22),
        );
      }
      // Synthetic footpath curve
      final trail = Path()
        ..moveTo(size.width * 0.08, size.height * 0.78)
        ..quadraticBezierTo(size.width * 0.35, size.height * 0.56, size.width * 0.52, size.height * 0.48)
        ..quadraticBezierTo(size.width * 0.74, size.height * 0.35, size.width * 0.92, size.height * 0.22);
      canvas.drawPath(
        trail,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = (dark ? t.inkMuted : const Color(0xFF9A7B56)).withValues(alpha: 0.5),
      );
    }

    final selfPos = Offset(size.width * 0.48, size.height * 0.48);
    // Uncertainty circle + own trail
    canvas.drawCircle(selfPos, 38, Paint()..color = selfColor.withValues(alpha: 0.14));
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

      canvas.drawCircle(marcoPos, 28, Paint()..color = marcoColor.withValues(alpha: 0.14));
      canvas.drawCircle(
        marcoPos,
        28,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = marcoColor.withValues(alpha: 0.5),
      );
      canvas.drawCircle(lucaPos, 54, Paint()..color = lucaColor.withValues(alpha: 0.07));
      canvas.drawCircle(
        lucaPos,
        54,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = lucaColor.withValues(alpha: 0.4),
      );

      // Dashed HISTORY recovered trail segment for Luca
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
      old.tokens != tokens || old.showContours != showContours || old.showGroup != showGroup;
}

class _TokensSpecSheet extends StatelessWidget {
  const _TokensSpecSheet({required this.direction, required this.tokens});
  final DesignDirection direction;
  final ConvoyDesignTokens tokens;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final palette = <(String, Color)>[
      ('Canvas', t.canvas),
      ('Surface', t.surface),
      ('Ink', t.ink),
      ('Accent', t.accent),
      ('Highlight', t.highlight),
      ('Positive', t.positive),
      ('Warning', t.warning),
      ('Critical', t.critical),
    ];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(direction.label, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      Text(direction.tagline),
      const SizedBox(height: 16),
      Text('Palette e identità', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (name, color) in palette)
          Container(
            width: 155,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.black26),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  Text('#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                      style: const TextStyle(fontSize: 11)),
                ]),
              ),
            ]),
          ),
      ]),
      const SizedBox(height: 16),
      Text('Tipografia, forme ed ergonomia', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      _specRow('Display font', t.displayFamily ?? 'Sistema (Roboto)'),
      _specRow('Body font', t.bodyFamily ?? 'Sistema (Roboto)'),
      _specRow('Data font', t.dataFamily ?? 'Sistema (Roboto)'),
      _specRow('Raggio card / bottoni', '${t.radiusMedium.round()} dp / ${t.radiusLarge.round()} dp'),
      _specRow('Target touch minimo', '${t.minTouchTarget.round()} dp'),
      _specRow('Radar scope', t.radarStyle.name),
      _specRow('Layout', t.layoutStyle.name),
    ]);
  }

  Widget _specRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(color: Colors.black54))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}
