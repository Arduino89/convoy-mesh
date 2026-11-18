import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/convoy_mesh_service.dart';
import '../design_controller.dart';
import '../design_presets.dart';
import '../design_theme.dart';
import '../design_tokens.dart';
import '../diagnostic/designed_diagnostic_header.dart';
import '../map/designed_map_chrome.dart';
import '../outdoor_components.dart';
import '../outdoor_config.dart';
import '../outdoor_copy.dart';
import '../radar/designed_radar_view.dart';
import '../radar/radar_actions.dart';
import '../shell/designed_app_shell.dart';
import 'original_radar_preview.dart';
import 'synthetic_radar_fixtures.dart';

enum StudioMode { preview, customize }

enum StudioPreviewPage { radar, map, diagnostic }

enum CustomizerCategory {
  colors('Colori', Icons.palette_outlined),
  fonts('Caratteri', Icons.font_download_outlined),
  dimensions('Dimensioni', Icons.straighten),
  spacing('Spaziature', Icons.space_bar),
  motion('Animazioni', Icons.motion_photos_on_outlined),
  copy('Testi', Icons.edit_note);

  const CustomizerCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

double _contrastRatio(Color fg, Color bg) {
  final opaqueFg = Color.alphaBlend(fg, bg);
  final l1 = opaqueFg.computeLuminance();
  final l2 = bg.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

/// Interactive **Outdoor Studio** for Convoy Mesh (100% synthetic data).
///
/// Offers two workspaces:
/// * **Anteprima UI**: side-by-side synthetic preview across Radar BLE, Map and
///   Diagnostic screens switching between **Outdoor Premium** and
///   **Originale (LAB +15)** for easy visual regression checks & rollback.
/// * **Personalizza**: live 6-axis customiser for Outdoor Premium (Colors,
///   Typography, Dimensions, Spacing, Animations, Visual Copy) with real-time
///   WCAG contrast readout and JSON config export.
class FrontendDesignStudioPage extends StatefulWidget {
  const FrontendDesignStudioPage({
    super.key,
    this.controller,
    this.initialDirection,
    this.initialCustomizeTab = false,
  });

  final DesignDirectionController? controller;
  final DesignDirection? initialDirection;
  final bool initialCustomizeTab;

  @override
  State<FrontendDesignStudioPage> createState() =>
      _FrontendDesignStudioPageState();
}

class _FrontendDesignStudioPageState extends State<FrontendDesignStudioPage> {
  late DesignDirection _selected;
  late OutdoorCustomConfig _draft;
  late StudioMode _mode;
  CustomizerCategory _category = CustomizerCategory.colors;
  StudioPreviewPage _previewPage = StudioPreviewPage.radar;
  SyntheticScenario _scenario = SyntheticScenario.groupHike;
  bool _syntheticOnlineBasemap = true;
  bool _syntheticDiagActive = true;

  final Map<String, TextEditingController> _copyControllers = {};

  DesignDirectionController get _ctrl =>
      widget.controller ?? DesignDirectionController.instance;

  @override
  void initState() {
    super.initState();
    _draft = _ctrl.config;
    _mode = widget.initialCustomizeTab ? StudioMode.customize : StudioMode.preview;
    _selected = _mode == StudioMode.customize
        ? DesignDirection.outdoorPremium
        : (widget.initialDirection ?? _ctrl.direction);
    _initCopyControllers(_draft.copy);
  }

  void _initCopyControllers(OutdoorCopyTokens copy) {
    final map = copy.toJson();
    for (final e in map.entries) {
      _copyControllers[e.key] = TextEditingController(text: e.value);
    }
  }

  void _syncCopyControllers(OutdoorCopyTokens copy) {
    final map = copy.toJson();
    for (final e in map.entries) {
      final c = _copyControllers[e.key];
      if (c != null && c.text != e.value) c.text = e.value;
    }
  }

  @override
  void dispose() {
    for (final c in _copyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _dirty => _selected != _ctrl.direction || _draft != _ctrl.config;

  void _updateDraft(OutdoorCustomConfig next) {
    setState(() {
      _draft = next;
      _selected = DesignDirection.outdoorPremium;
    });
  }

  Future<void> _apply() async {
    await _ctrl.updateConfig(_draft);
    await _ctrl.select(_selected);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Stile applicato: ${_selected.label}')),
    );
    Navigator.of(context).maybePop();
  }

  void _resetAll() {
    setState(() {
      _draft = OutdoorCustomConfig.defaults;
      _selected = DesignDirection.outdoorPremium;
      _syncCopyControllers(_draft.copy);
    });
  }

  Future<void> _exportJson() async {
    final formatted = const JsonEncoder.withIndent('  ').convert(_draft.toJson());
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configurazione Outdoor JSON'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              formatted,
              style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: formatted));
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Configurazione JSON copiata negli appunti.'),
                  ),
                );
              }
            },
            child: const Text('Copia'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  void _onPreviewAction(String name) {
    if (!mounted) return;
    if (name == 'chooseDesign') {
      setState(() {
        _mode = StudioMode.customize;
        _selected = DesignDirection.outdoorPremium;
      });
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Anteprima sintetica: azione «$name»'),
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outdoorTokens = DesignPresets.buildOutdoor(_draft);
    final outerTheme = buildConvoyTheme(outdoorTokens);
    final dirty = _dirty;

    return Theme(
      data: outerTheme,
      child: Scaffold(
        backgroundColor: outdoorTokens.canvas,
        appBar: AppBar(
          title: Text('Outdoor Studio', style: outdoorTokens.display(21)),
          actions: [
            IconButton(
              key: const Key('studio-export-json-btn'),
              tooltip: 'Esporta configurazione JSON',
              icon: const Icon(Icons.data_object),
              onPressed: _exportJson,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                key: const Key('studio-apply-btn'),
                onPressed: dirty ? _apply : null,
                child: Text(dirty ? 'Applica' : 'Attivo'),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            _modeBar(outdoorTokens),
            Divider(height: 1, color: outdoorTokens.outline),
            Expanded(
              child: _mode == StudioMode.preview
                  ? _previewWorkspace(outdoorTokens)
                  : _customizeWorkspace(outdoorTokens),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeBar(ConvoyDesignTokens t) {
    return Container(
      color: t.surface,
      padding: EdgeInsets.fromLTRB(t.hPad * 0.75, 8, t.hPad * 0.75, 10),
      child: Row(children: [
        Expanded(
          child: _ModeTabButton(
            key: const Key('studio-mode-preview'),
            tokens: t,
            icon: Icons.smartphone_outlined,
            label: 'Anteprima UI',
            selected: _mode == StudioMode.preview,
            onTap: () => setState(() => _mode = StudioMode.preview),
          ),
        ),
        SizedBox(width: t.space(2)),
        Expanded(
          child: _ModeTabButton(
            key: const Key('studio-mode-customize'),
            tokens: t,
            icon: Icons.tune,
            label: 'Personalizza',
            selected: _mode == StudioMode.customize,
            onTap: () => setState(() {
              _mode = StudioMode.customize;
              _selected = DesignDirection.outdoorPremium;
            }),
          ),
        ),
      ]),
    );
  }

  Widget _previewWorkspace(ConvoyDesignTokens outdoorTokens) {
    final data = SyntheticRadarFixtures.of(_scenario);
    final tokens = _selected == DesignDirection.classic
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
                      selected: _selected == DesignDirection.outdoorPremium,
                      onSelected: (_) => setState(
                          () => _selected = DesignDirection.outdoorPremium),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      key: const Key('studio-dir-classic'),
                      label: Text(DesignDirection.classic.label),
                      selected: _selected == DesignDirection.classic,
                      onSelected: (_) =>
                          setState(() => _selected = DesignDirection.classic),
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
                        selected: _scenario == s,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _scenario = s),
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

  Widget _previewShell(ConvoyDesignTokens tokens, dynamic data) {
    final actions = RadarActions.recording(_onPreviewAction);
    final Widget body;
    if (_selected == DesignDirection.classic) {
      body = switch (_previewPage) {
        StudioPreviewPage.radar =>
          OriginalRadarPreview(data: data, actions: actions),
        StudioPreviewPage.map => _OriginalMapPreview(scenario: _scenario),
        StudioPreviewPage.diagnostic => _OriginalDiagnosticPreview(
            active: _syntheticDiagActive,
            onToggle: () =>
                setState(() => _syntheticDiagActive = !_syntheticDiagActive),
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
              peerCountWithFix:
                  _scenario == SyntheticScenario.activeOuting ||
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
              onToggleBasemap: (v) =>
                  setState(() => _syntheticOnlineBasemap = v),
              onClearTrail: () => _onPreviewAction('clearTrail'),
              onChooseDesign: () => setState(() => _mode = StudioMode.customize),
            ),
          StudioPreviewPage.diagnostic => _DesignedDiagnosticPreview(
              tokens: tokens,
              active: _syntheticDiagActive,
              onToggle: () =>
                  setState(() => _syntheticDiagActive = !_syntheticDiagActive),
            ),
        },
      );
    }

    final Widget dock = _selected == DesignDirection.classic
        ? _OriginalBottomPreview(
            selectedIndex: _previewPage.index,
            outingActive: _scenario == SyntheticScenario.activeOuting,
            onSelectIndex: (i) =>
                setState(() => _previewPage = StudioPreviewPage.values[i]),
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
              onSelectIndex: (i) =>
                  setState(() => _previewPage = StudioPreviewPage.values[i]),
            ),
          );

    return Column(children: [
      Expanded(child: body),
      dock,
    ]);
  }

  Widget _customizeWorkspace(ConvoyDesignTokens t) {
    final bodyCr = _contrastRatio(t.ink, t.surface);
    final accentCr = _contrastRatio(t.onAccent, t.accent);
    final heroCr = _contrastRatio(t.heroInk, t.heroBackground.colors.first);
    final minCr = [bodyCr, accentCr, heroCr].reduce(math.min);

    return Column(
      children: [
        _liveSwatchPreviewBar(t, bodyCr: bodyCr, minCr: minCr),
        Container(
          color: t.canvas,
          padding: EdgeInsets.fromLTRB(t.hPad * 0.6, 6, t.hPad * 0.6, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final cat in CustomizerCategory.values) ...[
                ChoiceChip(
                  key: Key('custom-cat-${cat.name}'),
                  avatar: Icon(cat.icon, size: 16),
                  label: Text(cat.label),
                  selected: _category == cat,
                  onSelected: (_) => setState(() => _category = cat),
                ),
                const SizedBox(width: 6),
              ],
            ]),
          ),
        ),
        Divider(height: 1, color: t.outline),
        Expanded(
          child: ListView(
            key: const Key('studio-customize-list'),
            padding: EdgeInsets.fromLTRB(
              t.hPad * 0.85,
              t.space(3),
              t.hPad * 0.85,
              t.space(6),
            ),
            children: [
              if (minCr < 4.5) ...[
                OutdoorCallout(
                  tokens: t,
                  icon: Icons.warning_amber_rounded,
                  tone: OutdoorTone.warning,
                  text:
                      'Contrasto sotto 4.5:1 (min ${minCr.toStringAsFixed(1)}:1). Aumenta il contrasto o usa uno dei preset Outdoor verificati.',
                ),
                SizedBox(height: t.space(3)),
              ],
              ...switch (_category) {
                CustomizerCategory.colors => _buildColorControls(t),
                CustomizerCategory.fonts => _buildFontControls(t),
                CustomizerCategory.dimensions => _buildDimensionControls(t),
                CustomizerCategory.spacing => _buildSpacingControls(t),
                CustomizerCategory.motion => _buildMotionControls(t),
                CustomizerCategory.copy => _buildCopyControls(t),
              },
              SizedBox(height: t.space(3)),
              OutlinedButton.icon(
                key: const Key('studio-reset-btn'),
                onPressed: _resetAll,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Ripristina predefiniti Outdoor Premium'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _liveSwatchPreviewBar(
    ConvoyDesignTokens t, {
    required double bodyCr,
    required double minCr,
  }) {
    final wcagLabel = minCr >= 7.0
        ? 'AAA ${bodyCr.toStringAsFixed(1)}:1'
        : minCr >= 4.5
            ? 'AA ${bodyCr.toStringAsFixed(1)}:1'
            : '<4.5:1';
    final wcagTone = minCr >= 7.0
        ? OutdoorTone.positive
        : minCr >= 4.5
            ? OutdoorTone.highlight
            : OutdoorTone.warning;

    return Container(
      color: t.surface,
      padding: EdgeInsets.symmetric(horizontal: t.hPad * 0.75, vertical: 8),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: t.heroBackground,
            borderRadius: BorderRadius.circular(t.radiusSmall),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.radar, color: t.heroInk, size: 22),
        ),
        SizedBox(width: t.space(2.5)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.copy.radarTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.display(16.5),
              ),
              Text(
                '${t.displayFamily ?? 'Sistema'} · ${t.bodyFamily ?? 'Sistema'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.body(11.5, color: t.inkMuted),
              ),
            ],
          ),
        ),
        SizedBox(width: t.space(1.5)),
        OutdoorStatusBadge(tokens: t, label: wcagLabel, tone: wcagTone),
        SizedBox(width: t.space(1.5)),
        IconButton(
          key: const Key('studio-live-to-preview-btn'),
          tooltip: 'Apri anteprima schermo completo',
          icon: Icon(Icons.open_in_full, size: 19, color: t.accent),
          onPressed: () => setState(() => _mode = StudioMode.preview),
        ),
      ]),
    );
  }

  // ── Category 1: Colors ─────────────────────────────────────────────────

  List<Widget> _buildColorControls(ConvoyDesignTokens t) {
    const surfaceSwatches = <Color>[
      Color(0xFFFFFCF5),
      Color(0xFFFFFFFF),
      Color(0xFFF6F1E6),
      Color(0xFF14201A),
      Color(0xFF1B201D),
    ];

    return [
      OutdoorCard(
        tokens: t,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutdoorCardHeader(
              tokens: t,
              icon: Icons.landscape_outlined,
              title: 'Palette Outdoor curate',
              subtitle:
                  'Combinazioni verificate WCAG AAA per sole diretto o crepuscolo.',
            ),
            SizedBox(height: t.space(3)),
            for (final preset in OutdoorPalettePreset.values) ...[
              _PresetOptionTile(
                key: Key('preset-${preset.name}'),
                tokens: t,
                preset: preset,
                previewTokens: DesignPresets.paletteOf(preset),
                selected: _draft.palettePreset == preset &&
                    _draft.canvasArgb == null &&
                    _draft.surfaceArgb == null &&
                    _draft.accentArgb == null &&
                    _draft.highlightArgb == null &&
                    _draft.heroBaseArgb == null,
                onTap: () => _updateDraft(_draft.withPalettePreset(preset)),
              ),
              SizedBox(height: t.space(2)),
            ],
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
              icon: Icons.color_lens_outlined,
              title: 'Personalizza singoli colori',
              subtitle:
                  'Sovrascrive solo il ruolo selezionato mantenendo il resto.',
            ),
            SizedBox(height: t.space(3)),
            _swatchRow(
              t,
              group: 'canvas',
              label: 'Sfondo app (Canvas)',
              swatches: DesignPresets.customCanvasSwatches,
              selected: t.canvas,
              onPick: (c) => _updateDraft(_draft.copyWith(canvasArgb: c.toARGB32())),
            ),
            _swatchRow(
              t,
              group: 'surface',
              label: 'Sfondo schede (Surface)',
              swatches: surfaceSwatches,
              selected: t.surface,
              onPick: (c) =>
                  _updateDraft(_draft.copyWith(surfaceArgb: c.toARGB32())),
            ),
            _swatchRow(
              t,
              group: 'accent',
              label: 'Accento primario (Pulsanti e icone)',
              swatches: DesignPresets.customAccentSwatches,
              selected: t.accent,
              onPick: (c) => _updateDraft(_draft.copyWith(accentArgb: c.toARGB32())),
            ),
            _swatchRow(
              t,
              group: 'highlight',
              label: 'Evidenziazione secondaria (Ambra/Rame)',
              swatches: DesignPresets.customHighlightSwatches,
              selected: t.highlight,
              onPick: (c) =>
                  _updateDraft(_draft.copyWith(highlightArgb: c.toARGB32())),
            ),
            _swatchRow(
              t,
              group: 'hero',
              label: 'Sfondo Hero Radar BLE',
              swatches: DesignPresets.customHeroSwatches,
              selected: t.heroBackground.colors.first,
              onPick: (c) =>
                  _updateDraft(_draft.copyWith(heroBaseArgb: c.toARGB32())),
            ),
            SizedBox(height: t.space(1)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    _updateDraft(_draft.withPalettePreset(_draft.palettePreset)),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Ripristina solo colori del preset'),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _swatchRow(
    ConvoyDesignTokens t, {
    required String group,
    required String label,
    required List<Color> swatches,
    required Color selected,
    required ValueChanged<Color> onPick,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.body(13.5, weight: FontWeight.w700)),
          SizedBox(height: t.space(1.5)),
          Wrap(
            spacing: t.space(2),
            runSpacing: t.space(2),
            children: [
              for (final c in swatches)
                GestureDetector(
                  key: Key(
                    'swatch-$group-${c.toARGB32().toRadixString(16).padLeft(8, '0')}',
                  ),
                  onTap: () => onPick(c),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected.toARGB32() == c.toARGB32()
                            ? t.highlight
                            : t.outline,
                        width:
                            selected.toARGB32() == c.toARGB32() ? 3.0 : 1.2,
                      ),
                    ),
                    child: selected.toARGB32() == c.toARGB32()
                        ? Icon(
                            Icons.check,
                            size: 18,
                            color: DesignPresets.contrastingInkOn(c),
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Category 2: Typography ─────────────────────────────────────────────

  List<Widget> _buildFontControls(ConvoyDesignTokens t) {
    String fontLabel(String? f) => switch (f) {
          'Fraunces' => 'Fraunces (Editoriale)',
          'Manrope' => 'Manrope (Outdoor Sans)',
          'JetBrainsMono' => 'JetBrains Mono (Tecnico)',
          _ => 'Sistema Android',
        };

    return [
      OutdoorCard(
        tokens: t,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutdoorCardHeader(
              tokens: t,
              icon: Icons.text_fields,
              title: 'Famiglie tipografiche',
              subtitle:
                  'Scegli font distinti per titoli, corpo testo e cifre tabulari.',
            ),
            SizedBox(height: t.space(3)),
            _fontPicker(
              t,
              role: 'display',
              title: 'Titoli e intestazioni (Display)',
              selected: _draft.displayFamily,
              labelFor: fontLabel,
              onPick: (f) => _updateDraft(_draft.copyWith(displayFamily: f)),
            ),
            SizedBox(height: t.space(2.5)),
            _fontPicker(
              t,
              role: 'body',
              title: 'Testi principali e pulsanti (Body)',
              selected: _draft.bodyFamily,
              labelFor: fontLabel,
              onPick: (f) => _updateDraft(_draft.copyWith(bodyFamily: f)),
            ),
            SizedBox(height: t.space(2.5)),
            _fontPicker(
              t,
              role: 'data',
              title: 'Valori numerici, dBm e timer (Data)',
              selected: _draft.dataFamily,
              labelFor: fontLabel,
              onPick: (f) => _updateDraft(_draft.copyWith(dataFamily: f)),
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
              icon: Icons.format_size,
              title: 'Scala e peso tipografico',
            ),
            SizedBox(height: t.space(2)),
            _sliderRow(
              t,
              sliderKey: const Key('slider-font-scale'),
              label: 'Scala testo app',
              valueText: '${(_draft.fontScale * 100).round()}%',
              value: _draft.fontScale,
              min: 0.88,
              max: 1.24,
              divisions: 18,
              onChanged: (v) => _updateDraft(_draft.copyWith(fontScale: v)),
            ),
            SwitchListTile.adaptive(
              key: const Key('switch-display-bold'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Titoli in grassetto marcato'),
              subtitle:
                  const Text('Rafforza Fraunces/Manrope su titoli e intestazioni.'),
              value: _draft.displayBold,
              onChanged: (v) => _updateDraft(_draft.copyWith(displayBold: v)),
            ),
            SwitchListTile.adaptive(
              key: const Key('switch-uppercase-labels'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Etichette e badge in maiuscolo'),
              subtitle: const Text(
                  'Stile cartografico su pulsanti ed etichette (accessibility invariata).'),
              value: _draft.uppercaseLabels,
              onChanged: (v) =>
                  _updateDraft(_draft.copyWith(uppercaseLabels: v)),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _fontPicker(
    ConvoyDesignTokens t, {
    required String role,
    required String title,
    required String? selected,
    required String Function(String?) labelFor,
    required ValueChanged<String?> onPick,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: t.body(13.5, weight: FontWeight.w700)),
        SizedBox(height: t.space(1.5)),
        Wrap(
          spacing: t.space(2),
          runSpacing: t.space(1.5),
          children: [
            for (final f in OutdoorCustomConfig.availableFonts)
              ChoiceChip(
                key: Key('font-$role-${f ?? OutdoorCustomConfig.systemFontSentinel}'),
                label: Text(
                  labelFor(f),
                  style: TextStyle(fontFamily: f),
                ),
                selected: selected == f,
                onSelected: (_) => onPick(f),
              ),
          ],
        ),
      ],
    );
  }

  // ── Category 3: Dimensions ─────────────────────────────────────────────

  List<Widget> _buildDimensionControls(ConvoyDesignTokens t) {
    return [
      OutdoorCard(
        tokens: t,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutdoorCardHeader(
              tokens: t,
              icon: Icons.touch_app_outlined,
              title: 'Ergonomia outdoor & forme',
              subtitle: 'Regola target touch per i guanti, bordi, raggi e radar.',
            ),
            SizedBox(height: t.space(2.5)),
            _sliderRow(
              t,
              sliderKey: const Key('slider-touch-target'),
              label: 'Altezza minima bottoni (guanti)',
              valueText: '${_draft.minTouchTarget.round()} dp',
              value: _draft.minTouchTarget,
              min: 48,
              max: 64,
              divisions: 16,
              onChanged: (v) => _updateDraft(_draft.copyWith(minTouchTarget: v)),
            ),
            _sliderRow(
              t,
              sliderKey: const Key('slider-radius-small'),
              label: 'Raggio piccolo (badge e campi)',
              valueText: '${_draft.radiusSmall.round()} dp',
              value: _draft.radiusSmall,
              min: 4,
              max: 20,
              divisions: 16,
              onChanged: (v) => _updateDraft(_draft.copyWith(radiusSmall: v)),
            ),
            _sliderRow(
              t,
              sliderKey: const Key('slider-radius-medium'),
              label: 'Raggio schede e bottoni',
              valueText: '${_draft.radiusMedium.round()} dp',
              value: _draft.radiusMedium,
              min: 8,
              max: 30,
              divisions: 22,
              onChanged: (v) => _updateDraft(_draft.copyWith(radiusMedium: v)),
            ),
            _sliderRow(
              t,
              sliderKey: const Key('slider-radius-large'),
              label: 'Raggio hero radar e modali',
              valueText: '${_draft.radiusLarge.round()} dp',
              value: _draft.radiusLarge,
              min: 12,
              max: 38,
              divisions: 26,
              onChanged: (v) => _updateDraft(_draft.copyWith(radiusLarge: v)),
            ),
            _sliderRow(
              t,
              sliderKey: const Key('slider-border-width'),
              label: 'Spessore bordi',
              valueText: '${_draft.borderWidth.toStringAsFixed(1)} dp',
              value: _draft.borderWidth,
              min: 0.8,
              max: 2.5,
              divisions: 17,
              onChanged: (v) => _updateDraft(_draft.copyWith(borderWidth: v)),
            ),
            _sliderRow(
              t,
              sliderKey: const Key('slider-avatar-size'),
              label: 'Dimensione avatar partecipanti',
              valueText: '${_draft.avatarSize.round()} dp',
              value: _draft.avatarSize,
              min: 38,
              max: 60,
              divisions: 22,
              onChanged: (v) => _updateDraft(_draft.copyWith(avatarSize: v)),
            ),
            _sliderRow(
              t,
              sliderKey: const Key('slider-icon-scale'),
              label: 'Scala icone',
              valueText: '${(_draft.iconScale * 100).round()}%',
              value: _draft.iconScale,
              min: 0.85,
              max: 1.25,
              divisions: 8,
              onChanged: (v) => _updateDraft(_draft.copyWith(iconScale: v)),
            ),
            _sliderRow(
              t,
              sliderKey: const Key('slider-radar-scale'),
              label: 'Ampiezza cerchio Radar BLE',
              valueText: '${(_draft.radarScopeScale * 100).round()}%',
              value: _draft.radarScopeScale,
              min: 0.75,
              max: 1.0,
              divisions: 10,
              onChanged: (v) =>
                  _updateDraft(_draft.copyWith(radarScopeScale: v)),
            ),
            SwitchListTile.adaptive(
              key: const Key('switch-elevated'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Ombre ed elevazione schede'),
              subtitle:
                  const Text('Disattiva per una resa piatta ad alto contrasto.'),
              value: _draft.elevated,
              onChanged: (v) => _updateDraft(_draft.copyWith(elevated: v)),
            ),
          ],
        ),
      ),
    ];
  }

  // ── Category 4: Spacing ────────────────────────────────────────────────

  List<Widget> _buildSpacingControls(ConvoyDesignTokens t) {
    return [
      OutdoorCard(
        tokens: t,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutdoorCardHeader(
              tokens: t,
              icon: Icons.grid_view_outlined,
              title: 'Ritmo e spaziature',
              subtitle:
                  'Modula densità delle informazioni e respiro visivo sui sentieri.',
            ),
            SizedBox(height: t.space(2.5)),
            _sliderRow(
              t,
              sliderKey: const Key('slider-space-unit'),
              label: 'Unità griglia base',
              valueText: '${_draft.spaceUnit.toStringAsFixed(1)} dp',
              value: _draft.spaceUnit,
              min: 3.0,
              max: 5.5,
              divisions: 10,
              onChanged: (v) => _updateDraft(_draft.copyWith(spaceUnit: v)),
            ),
            _sliderRow(
              t,
              sliderKey: const Key('slider-screen-padding'),
              label: 'Margini laterali schermate',
              valueText: '${(_draft.screenPaddingScale * 100).round()}%',
              value: _draft.screenPaddingScale,
              min: 0.80,
              max: 1.35,
              divisions: 11,
              onChanged: (v) =>
                  _updateDraft(_draft.copyWith(screenPaddingScale: v)),
            ),
            _sliderRow(
              t,
              sliderKey: const Key('slider-card-padding'),
              label: 'Padding interno schede',
              valueText: '${(_draft.cardPaddingScale * 100).round()}%',
              value: _draft.cardPaddingScale,
              min: 0.80,
              max: 1.35,
              divisions: 11,
              onChanged: (v) =>
                  _updateDraft(_draft.copyWith(cardPaddingScale: v)),
            ),
            _sliderRow(
              t,
              sliderKey: const Key('slider-section-gap'),
              label: 'Distanza tra sezioni',
              valueText: '${(_draft.sectionGapScale * 100).round()}%',
              value: _draft.sectionGapScale,
              min: 0.80,
              max: 1.40,
              divisions: 12,
              onChanged: (v) =>
                  _updateDraft(_draft.copyWith(sectionGapScale: v)),
            ),
          ],
        ),
      ),
    ];
  }

  // ── Category 5: Motion & Animations ────────────────────────────────────

  List<Widget> _buildMotionControls(ConvoyDesignTokens t) {
    final enabled = _draft.animationsEnabled;
    return [
      OutdoorCard(
        tokens: t,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutdoorCardHeader(
              tokens: t,
              icon: Icons.animation,
              title: 'Animazioni e sensibilità batteria',
              subtitle:
                  'Puoi ridurre o fermare fascio radar e impulsi senza influire sul BLE.',
            ),
            SizedBox(height: t.space(1.5)),
            SwitchListTile.adaptive(
              key: const Key('switch-animations-enabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Animazioni interfaccia attive'),
              subtitle: const Text('Interruttore generale (risparmio o moto ridotto).'),
              value: enabled,
              onChanged: (v) =>
                  _updateDraft(_draft.copyWith(animationsEnabled: v)),
            ),
            SwitchListTile.adaptive(
              key: const Key('switch-radar-rotation'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Fascio rotante sul Radar BLE'),
              value: _draft.radarRotationEnabled,
              onChanged: enabled
                  ? (v) =>
                      _updateDraft(_draft.copyWith(radarRotationEnabled: v))
                  : null,
            ),
            SwitchListTile.adaptive(
              key: const Key('switch-live-pulse'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Impulso sui badge live'),
              value: _draft.livePulseEnabled,
              onChanged: enabled
                  ? (v) => _updateDraft(_draft.copyWith(livePulseEnabled: v))
                  : null,
            ),
            SwitchListTile.adaptive(
              key: const Key('switch-topo-contours'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Curve topografiche decorative'),
              subtitle:
                  const Text('Isoipse sottili su Radar Hero e reticolo offline Mappa.'),
              value: _draft.showTopoContours,
              onChanged: (v) =>
                  _updateDraft(_draft.copyWith(showTopoContours: v)),
            ),
            SizedBox(height: t.space(2)),
            _sliderRow(
              t,
              sliderKey: const Key('slider-radar-period'),
              label: 'Periodo rotazione radar',
              valueText: '${(_draft.radarPeriodMs / 1000).toStringAsFixed(1)} s',
              value: _draft.radarPeriodMs.toDouble(),
              min: 2400,
              max: 9500,
              divisions: 71,
              onChanged: enabled
                  ? (v) =>
                      _updateDraft(_draft.copyWith(radarPeriodMs: v.round()))
                  : null,
            ),
            _sliderRow(
              t,
              sliderKey: const Key('slider-motion-fast'),
              label: 'Transizioni rapide',
              valueText: '${_draft.motionFastMs} ms',
              value: _draft.motionFastMs.toDouble(),
              min: 80,
              max: 450,
              divisions: 37,
              onChanged: enabled
                  ? (v) =>
                      _updateDraft(_draft.copyWith(motionFastMs: v.round()))
                  : null,
            ),
            _sliderRow(
              t,
              sliderKey: const Key('slider-motion-medium'),
              label: 'Transizioni medie',
              valueText: '${_draft.motionMediumMs} ms',
              value: _draft.motionMediumMs.toDouble(),
              min: 140,
              max: 750,
              divisions: 61,
              onChanged: enabled
                  ? (v) =>
                      _updateDraft(_draft.copyWith(motionMediumMs: v.round()))
                  : null,
            ),
          ],
        ),
      ),
    ];
  }

  // ── Category 6: Copy ───────────────────────────────────────────────────

  List<Widget> _buildCopyControls(ConvoyDesignTokens t) {
    void updateCopy(String key, String raw) {
      final value = raw.trim();
      final c = _draft.copy;
      final next = switch (key) {
        'appKicker' => c.copyWith(
            appKicker: value.isEmpty ? OutdoorCopyTokens.defaultAppKicker : value),
        'radarTitle' => c.copyWith(
            radarTitle: value.isEmpty ? OutdoorCopyTokens.defaultRadarTitle : value),
        'radarSubtitle' => c.copyWith(
            radarSubtitle:
                value.isEmpty ? OutdoorCopyTokens.defaultRadarSubtitle : value),
        'radarCaption' => c.copyWith(
            radarCaption:
                value.isEmpty ? OutdoorCopyTokens.defaultRadarCaption : value),
        'peersSectionTitle' => c.copyWith(
            peersSectionTitle: value.isEmpty
                ? OutdoorCopyTokens.defaultPeersSectionTitle
                : value),
        'emptyPeersMessage' => c.copyWith(
            emptyPeersMessage: value.isEmpty
                ? OutdoorCopyTokens.defaultEmptyPeersMessage
                : value),
        'toolsSectionTitle' => c.copyWith(
            toolsSectionTitle: value.isEmpty
                ? OutdoorCopyTokens.defaultToolsSectionTitle
                : value),
        'bleDiagSectionTitle' => c.copyWith(
            bleDiagSectionTitle: value.isEmpty
                ? OutdoorCopyTokens.defaultBleDiagSectionTitle
                : value),
        'advancedSectionTitle' => c.copyWith(
            advancedSectionTitle: value.isEmpty
                ? OutdoorCopyTokens.defaultAdvancedSectionTitle
                : value),
        'mapSearchCta' => c.copyWith(
            mapSearchCta:
                value.isEmpty ? OutdoorCopyTokens.defaultMapSearchCta : value),
        'mapRecenterCta' => c.copyWith(
            mapRecenterCta: value.isEmpty
                ? OutdoorCopyTokens.defaultMapRecenterCta
                : value),
        'diagnosticTitle' => c.copyWith(
            diagnosticTitle: value.isEmpty
                ? OutdoorCopyTokens.defaultDiagnosticTitle
                : value),
        'diagnosticStartTitle' => c.copyWith(
            diagnosticStartTitle: value.isEmpty
                ? OutdoorCopyTokens.defaultDiagnosticStartTitle
                : value),
        'diagnosticActiveTitle' => c.copyWith(
            diagnosticActiveTitle: value.isEmpty
                ? OutdoorCopyTokens.defaultDiagnosticActiveTitle
                : value),
        'diagnosticContextTitle' => c.copyWith(
            diagnosticContextTitle: value.isEmpty
                ? OutdoorCopyTokens.defaultDiagnosticContextTitle
                : value),
        'diagnosticRuntimeTitle' => c.copyWith(
            diagnosticRuntimeTitle: value.isEmpty
                ? OutdoorCopyTokens.defaultDiagnosticRuntimeTitle
                : value),
        'diagnosticGuideTitle' => c.copyWith(
            diagnosticGuideTitle: value.isEmpty
                ? OutdoorCopyTokens.defaultDiagnosticGuideTitle
                : value),
        _ => c,
      };
      _updateDraft(_draft.copyWith(copy: next));
    }

    Widget copyField(String key, String label, {int maxLines = 1}) {
      return Padding(
        padding: EdgeInsets.only(bottom: t.space(2.5)),
        child: TextFormField(
          key: Key('copy-field-$key'),
          controller: _copyControllers[key],
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label),
          onChanged: (v) => updateCopy(key, v),
        ),
      );
    }

    return [
      OutdoorCallout(
        tokens: t,
        icon: Icons.shield_outlined,
        tone: OutdoorTone.accent,
        text:
            'Puoi personalizzare titoli, didascalie e sottotitoli visivi. I comandi funzionali e di collaudo («Avvia uscita», «Radar BLE», «Mappa», «Test log», «Avvia registrazione diagnostica • max 4 min») restano invariati per sicurezza.',
      ),
      SizedBox(height: t.space(3)),
      OutdoorCard(
        tokens: t,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutdoorCardHeader(
              tokens: t,
              icon: Icons.radar,
              title: 'Testi Radar BLE',
            ),
            SizedBox(height: t.space(2.5)),
            copyField('appKicker', 'Kicker intestazione app'),
            copyField('radarTitle', 'Titolo principale Radar'),
            copyField('radarSubtitle', 'Sottotitolo Radar', maxLines: 2),
            copyField('radarCaption', 'Didascalia anelli Radar', maxLines: 2),
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
              icon: Icons.groups_outlined,
              title: 'Partecipanti & Strumenti',
            ),
            SizedBox(height: t.space(2.5)),
            copyField('peersSectionTitle', 'Titolo sezione partecipanti'),
            copyField('emptyPeersMessage', 'Messaggio nessun partecipante',
                maxLines: 2),
            copyField('toolsSectionTitle', 'Titolo sezione strumenti'),
            copyField('bleDiagSectionTitle', 'Titolo pannello diagnostica BLE'),
            copyField('advancedSectionTitle', 'Titolo pannello avanzate'),
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
              icon: Icons.map_outlined,
              title: 'Mappa',
            ),
            SizedBox(height: t.space(2.5)),
            copyField('mapSearchCta', 'Pulsante mappa senza GPS'),
            copyField('mapRecenterCta', 'Pulsante centra con GPS attivo'),
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
              icon: Icons.bug_report_outlined,
              title: 'Schermata Test log',
            ),
            SizedBox(height: t.space(2.5)),
            copyField('diagnosticTitle', 'Titolo AppBar Test log'),
            copyField('diagnosticStartTitle', 'Titolo scheda pronta'),
            copyField('diagnosticActiveTitle', 'Titolo scheda in registrazione'),
            copyField('diagnosticContextTitle', 'Titolo scheda condizioni reali'),
            copyField('diagnosticRuntimeTitle', 'Titolo scheda runtime hardware'),
            copyField('diagnosticGuideTitle', 'Titolo pannello lettura log'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  _updateDraft(_draft.copyWith(copy: OutdoorCopyTokens.defaults));
                  _syncCopyControllers(OutdoorCopyTokens.defaults);
                },
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Ripristina solo testi predefiniti'),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _sliderRow(
    ConvoyDesignTokens t, {
    required Key sliderKey,
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double>? onChanged,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(1.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(label, style: t.body(13.5, weight: FontWeight.w600)),
            ),
            Text(valueText, style: t.data(13, color: t.accent)),
          ]),
          Slider(
            key: sliderKey,
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ModeTabButton extends StatelessWidget {
  const _ModeTabButton({
    super.key,
    required this.tokens,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ConvoyDesignTokens tokens;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Material(
      color: selected ? t.accent : t.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusSmall),
        side: BorderSide(
          color: selected ? t.accent : t.outline,
          width: t.borderWidth,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.radiusSmall),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: t.space(2.5),
            vertical: t.space(2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? t.onAccent : t.ink,
              ),
              SizedBox(width: t.space(1.5)),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.body(
                    13.5,
                    color: selected ? t.onAccent : t.ink,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetOptionTile extends StatelessWidget {
  const _PresetOptionTile({
    super.key,
    required this.tokens,
    required this.preset,
    required this.previewTokens,
    required this.selected,
    required this.onTap,
  });

  final ConvoyDesignTokens tokens;
  final OutdoorPalettePreset preset;
  final ConvoyDesignTokens previewTokens;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final p = previewTokens;
    final swatches = [
      p.canvas,
      p.heroBackground.colors.first,
      p.accent,
      p.highlight,
    ];
    return Material(
      color: selected
          ? Color.alphaBlend(t.accent.withValues(alpha: 0.12), t.surface)
          : t.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusSmall),
        side: BorderSide(
          color: selected ? t.accent : t.outline,
          width: selected ? t.borderWidth + 0.8 : t.borderWidth,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.radiusSmall),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(t.space(3)),
          child: Row(children: [
            Row(children: [
              for (final c in swatches)
                Container(
                  width: 18,
                  height: 30,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.black26, width: 0.8),
                  ),
                ),
            ]),
            SizedBox(width: t.space(2.5)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(preset.label, style: t.body(14.5, weight: FontWeight.w800)),
                  Text(preset.subtitle,
                      style: t.body(12, color: t.inkMuted)),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: t.accent, size: 22),
          ]),
        ),
      ),
    );
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
  const _OriginalDiagnosticPreview(
      {required this.active, required this.onToggle});
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
                      foregroundColor: Colors.white,
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
                  icon: Icons.cloud_upload_outlined,
                  title: 'Invio diagnostico PostHog EU — beta chiusa',
                  subtitle:
                      'Anteprima sintetica: consenso esplicito per ogni partecipante.',
                  tone: OutdoorTone.highlight,
                  trailing: OutdoorStatusBadge(
                    tokens: t,
                    label: 'Anteprima',
                    tone: OutdoorTone.highlight,
                  ),
                ),
                SizedBox(height: t.space(2.5)),
                OutdoorCallout(
                  tokens: t,
                  icon: Icons.verified_user_outlined,
                  tone: OutdoorTone.accent,
                  text:
                      'In anteprima nessun dato lascia il telefono: l’invio reale richiede i consensi espliciti nella scheda Test log.',
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
              showContours: onlineBasemap && tokens.showTopoContours,
              showGroup: showGroup,
              selfColor: classic ? Colors.blue : tokens.accent,
              marcoColor: marcoColor,
              lucaColor: lucaColor,
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
                (dark ? t.accent : const Color(0xFF8C826F)).withValues(alpha: 0.22),
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
          ..color = (dark ? t.inkMuted : const Color(0xFF9A7B56))
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
      old.tokens != tokens ||
      old.showContours != showContours ||
      old.showGroup != showGroup;
}
