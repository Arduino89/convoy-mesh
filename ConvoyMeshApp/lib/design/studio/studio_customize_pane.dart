import 'package:flutter/material.dart';

import '../design_presets.dart';
import '../design_tokens.dart';
import '../outdoor_components.dart';
import '../outdoor_config.dart';
import '../outdoor_copy.dart';
import 'studio_controls.dart';

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

/// 6-axis Outdoor Premium live customiser workspace with real-time WCAG
/// contrast diagnostics across all 12 active surface pairs, all 8 color role
/// pickers, bounded visual copy editors, and protected technical notices.
class StudioCustomizeWorkspace extends StatelessWidget {
  const StudioCustomizeWorkspace({
    super.key,
    required this.tokens,
    required this.draft,
    required this.category,
    required this.copyControllers,
    required this.onSelectCategory,
    required this.onUpdateDraft,
    required this.onResetCopy,
    required this.onResetAll,
    required this.onOpenPreview,
  });

  final ConvoyDesignTokens tokens;
  final OutdoorCustomConfig draft;
  final CustomizerCategory category;
  final Map<String, TextEditingController> copyControllers;
  final ValueChanged<CustomizerCategory> onSelectCategory;
  final ValueChanged<OutdoorCustomConfig> onUpdateDraft;
  final VoidCallback onResetCopy;
  final VoidCallback onResetAll;
  final VoidCallback onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final report = DesignPresets.evaluateContrast(t);
    final bodyCr = DesignPresets.contrastRatio(t.ink, t.surface);
    final worst = report.failures.isEmpty
        ? null
        : report.failures.reduce((a, b) => a.ratio <= b.ratio ? a : b);

    return Column(
      children: [
        _liveSwatchPreviewBar(t, bodyCr: bodyCr, report: report),
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
                  selected: category == cat,
                  onSelected: (_) => onSelectCategory(cat),
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
              if (worst != null) ...[
                OutdoorCallout(
                  key: const Key('studio-contrast-warning'),
                  tokens: t,
                  icon: Icons.warning_amber_rounded,
                  tone: OutdoorTone.warning,
                  text:
                      'Contrasto sotto ${worst.minAa.toStringAsFixed(1)}:1 su «${worst.label}» (${worst.ratio.toStringAsFixed(1)}:1, ${report.failures.length} avvisi). Scegli un colore più contrastato o un preset Outdoor verificato.',
                ),
                SizedBox(height: t.space(3)),
              ],
              ...switch (category) {
                CustomizerCategory.colors => _buildColorControls(t, report),
                CustomizerCategory.fonts => _buildFontControls(t),
                CustomizerCategory.dimensions => _buildDimensionControls(t),
                CustomizerCategory.spacing => _buildSpacingControls(t),
                CustomizerCategory.motion => _buildMotionControls(t),
                CustomizerCategory.copy => _buildCopyControls(t),
              },
              SizedBox(height: t.space(3)),
              OutlinedButton.icon(
                key: const Key('studio-reset-btn'),
                onPressed: onResetAll,
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
    required OutdoorContrastReport report,
  }) {
    final minCr = report.minRatio;
    final wcagLabel = !report.allPassAa
        ? '<4.5:1 (${minCr.toStringAsFixed(1)})'
        : (report.bodyIsAaa && minCr >= 4.5)
            ? 'AAA ${bodyCr.toStringAsFixed(1)}:1'
            : 'AA ${minCr.toStringAsFixed(1)}:1';
    final wcagTone = !report.allPassAa
        ? OutdoorTone.warning
        : report.bodyIsAaa
            ? OutdoorTone.positive
            : OutdoorTone.highlight;

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
          onPressed: onOpenPreview,
        ),
      ]),
    );
  }

  // ── Category 1: Colors ─────────────────────────────────────────────────

  List<Widget> _buildColorControls(
    ConvoyDesignTokens t,
    OutdoorContrastReport report,
  ) {
    final noColorOverrides = draft.canvasArgb == null &&
        draft.surfaceArgb == null &&
        draft.accentArgb == null &&
        draft.highlightArgb == null &&
        draft.heroBaseArgb == null &&
        draft.positiveArgb == null &&
        draft.warningArgb == null &&
        draft.criticalArgb == null;

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
                  'Combinazioni verificate WCAG AAA/AA per sole diretto o crepuscolo.',
            ),
            SizedBox(height: t.space(3)),
            for (final preset in OutdoorPalettePreset.values) ...[
              StudioPresetOptionTile(
                key: Key('preset-${preset.name}'),
                tokens: t,
                preset: preset,
                previewTokens: DesignPresets.paletteOf(preset),
                selected: draft.palettePreset == preset && noColorOverrides,
                onTap: () => onUpdateDraft(draft.withPalettePreset(preset)),
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
                  'Tutti gli 8 ruoli cromatici; il contrasto si aggiorna in tempo reale.',
            ),
            SizedBox(height: t.space(3)),
            StudioSwatchRow(
              tokens: t,
              group: 'canvas',
              label: 'Sfondo app (Canvas)',
              swatches: DesignPresets.customCanvasSwatches,
              selected: t.canvas,
              onPick: (c) =>
                  onUpdateDraft(draft.copyWith(canvasArgb: c.toARGB32())),
            ),
            StudioSwatchRow(
              tokens: t,
              group: 'surface',
              label: 'Sfondo schede (Surface)',
              swatches: DesignPresets.customSurfaceSwatches,
              selected: t.surface,
              onPick: (c) =>
                  onUpdateDraft(draft.copyWith(surfaceArgb: c.toARGB32())),
            ),
            StudioSwatchRow(
              tokens: t,
              group: 'accent',
              label: 'Accento primario (Pulsanti e icone)',
              swatches: DesignPresets.customAccentSwatches,
              selected: t.accent,
              onPick: (c) =>
                  onUpdateDraft(draft.copyWith(accentArgb: c.toARGB32())),
            ),
            StudioSwatchRow(
              tokens: t,
              group: 'highlight',
              label: 'Evidenziazione secondaria (Ambra/Rame)',
              swatches: DesignPresets.customHighlightSwatches,
              selected: t.highlight,
              onPick: (c) =>
                  onUpdateDraft(draft.copyWith(highlightArgb: c.toARGB32())),
            ),
            StudioSwatchRow(
              tokens: t,
              group: 'hero',
              label: 'Sfondo Hero Radar BLE',
              swatches: DesignPresets.customHeroSwatches,
              selected: t.heroBackground.colors.first,
              onPick: (c) =>
                  onUpdateDraft(draft.copyWith(heroBaseArgb: c.toARGB32())),
            ),
            StudioSwatchRow(
              tokens: t,
              group: 'positive',
              label: 'Stato positivo (BLE pronto / GPS attivo)',
              swatches: DesignPresets.customPositiveSwatches,
              selected: t.positive,
              onPick: (c) =>
                  onUpdateDraft(draft.copyWith(positiveArgb: c.toARGB32())),
            ),
            StudioSwatchRow(
              tokens: t,
              group: 'warning',
              label: 'Avviso / stato intermedio (Warning)',
              swatches: DesignPresets.customWarningSwatches,
              selected: t.warning,
              onPick: (c) =>
                  onUpdateDraft(draft.copyWith(warningArgb: c.toARGB32())),
            ),
            StudioSwatchRow(
              tokens: t,
              group: 'critical',
              label: 'Azione critica / stop / blocco (Critical)',
              swatches: DesignPresets.customCriticalSwatches,
              selected: t.critical,
              onPick: (c) =>
                  onUpdateDraft(draft.copyWith(criticalArgb: c.toARGB32())),
            ),
            SizedBox(height: t.space(1)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    onUpdateDraft(draft.withPalettePreset(draft.palettePreset)),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Ripristina solo colori del preset'),
              ),
            ),
          ],
        ),
      ),
      StudioContrastDiagnosticsCard(tokens: t, report: report),
    ];
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
            StudioFontPicker(
              tokens: t,
              role: 'display',
              title: 'Titoli e intestazioni (Display)',
              selected: draft.displayFamily,
              labelFor: fontLabel,
              onPick: (f) => onUpdateDraft(draft.copyWith(displayFamily: f)),
            ),
            SizedBox(height: t.space(2.5)),
            StudioFontPicker(
              tokens: t,
              role: 'body',
              title: 'Testi principali e pulsanti (Body)',
              selected: draft.bodyFamily,
              labelFor: fontLabel,
              onPick: (f) => onUpdateDraft(draft.copyWith(bodyFamily: f)),
            ),
            SizedBox(height: t.space(2.5)),
            StudioFontPicker(
              tokens: t,
              role: 'data',
              title: 'Valori numerici, dBm e timer (Data)',
              selected: draft.dataFamily,
              labelFor: fontLabel,
              onPick: (f) => onUpdateDraft(draft.copyWith(dataFamily: f)),
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
            StudioSliderRow(
              tokens: t,
              sliderKey: const Key('slider-font-scale'),
              label: 'Scala testo app',
              valueText: '${(draft.fontScale * 100).round()}%',
              value: draft.fontScale,
              min: 0.88,
              max: 1.24,
              divisions: 18,
              onChanged: (v) => onUpdateDraft(draft.copyWith(fontScale: v)),
            ),
            SwitchListTile.adaptive(
              key: const Key('switch-display-bold'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Titoli in grassetto marcato'),
              subtitle: const Text(
                  'Rafforza Fraunces/Manrope su titoli e intestazioni.'),
              value: draft.displayBold,
              onChanged: (v) => onUpdateDraft(draft.copyWith(displayBold: v)),
            ),
            SwitchListTile.adaptive(
              key: const Key('switch-uppercase-labels'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Etichette e badge in maiuscolo'),
              subtitle: const Text(
                  'Stile cartografico su pulsanti ed etichette (accessibility invariata).'),
              value: draft.uppercaseLabels,
              onChanged: (v) =>
                  onUpdateDraft(draft.copyWith(uppercaseLabels: v)),
            ),
          ],
        ),
      ),
    ];
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
              subtitle:
                  'Regola target touch per i guanti, bordi, raggi e radar.',
            ),
            SizedBox(height: t.space(2.5)),
            StudioSliderRow(
              tokens: t,
              sliderKey: const Key('slider-touch-target'),
              label: 'Altezza minima bottoni (guanti)',
              valueText: '${draft.minTouchTarget.round()} dp',
              value: draft.minTouchTarget,
              min: 48,
              max: 64,
              divisions: 16,
              onChanged: (v) =>
                  onUpdateDraft(draft.copyWith(minTouchTarget: v)),
            ),
            StudioSliderRow(
              tokens: t,
              sliderKey: const Key('slider-radius-small'),
              label: 'Raggio piccolo (badge e campi)',
              valueText: '${draft.radiusSmall.round()} dp',
              value: draft.radiusSmall,
              min: 4,
              max: 20,
              divisions: 16,
              onChanged: (v) => onUpdateDraft(draft.copyWith(radiusSmall: v)),
            ),
            StudioSliderRow(
              tokens: t,
              sliderKey: const Key('slider-radius-medium'),
              label: 'Raggio schede e bottoni',
              valueText: '${draft.radiusMedium.round()} dp',
              value: draft.radiusMedium,
              min: 8,
              max: 30,
              divisions: 22,
              onChanged: (v) => onUpdateDraft(draft.copyWith(radiusMedium: v)),
            ),
            StudioSliderRow(
              tokens: t,
              sliderKey: const Key('slider-radius-large'),
              label: 'Raggio hero radar e modali',
              valueText: '${draft.radiusLarge.round()} dp',
              value: draft.radiusLarge,
              min: 12,
              max: 38,
              divisions: 26,
              onChanged: (v) => onUpdateDraft(draft.copyWith(radiusLarge: v)),
            ),
            StudioSliderRow(
              tokens: t,
              sliderKey: const Key('slider-border-width'),
              label: 'Spessore bordi',
              valueText: '${draft.effectiveBorderWidth.toStringAsFixed(1)} dp',
              value: draft.effectiveBorderWidth,
              min: 0.8,
              max: 2.5,
              divisions: 17,
              onChanged: (v) => onUpdateDraft(draft.copyWith(borderWidth: v)),
            ),
            StudioSliderRow(
              tokens: t,
              sliderKey: const Key('slider-avatar-size'),
              label: 'Dimensione avatar partecipanti',
              valueText: '${draft.avatarSize.round()} dp',
              value: draft.avatarSize,
              min: 38,
              max: 60,
              divisions: 22,
              onChanged: (v) => onUpdateDraft(draft.copyWith(avatarSize: v)),
            ),
            StudioSliderRow(
              tokens: t,
              sliderKey: const Key('slider-icon-scale'),
              label: 'Scala icone',
              valueText: '${(draft.iconScale * 100).round()}%',
              value: draft.iconScale,
              min: 0.85,
              max: 1.25,
              divisions: 8,
              onChanged: (v) => onUpdateDraft(draft.copyWith(iconScale: v)),
            ),
            StudioSliderRow(
              tokens: t,
              sliderKey: const Key('slider-radar-scale'),
              label: 'Ampiezza cerchio Radar BLE',
              valueText: '${(draft.radarScopeScale * 100).round()}%',
              value: draft.radarScopeScale,
              min: 0.75,
              max: 1.0,
              divisions: 10,
              onChanged: (v) =>
                  onUpdateDraft(draft.copyWith(radarScopeScale: v)),
            ),
            SwitchListTile.adaptive(
              key: const Key('switch-elevated'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Ombre ed elevazione schede'),
              subtitle: const Text(
                  'Disattiva per una resa piatta ad alto contrasto.'),
              value: draft.effectiveElevated,
              onChanged: (v) => onUpdateDraft(draft.copyWith(elevated: v)),
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
            StudioSliderRow(
              tokens: t,
              sliderKey: const Key('slider-space-unit'),
              label: 'Unità griglia base',
              valueText: '${draft.spaceUnit.toStringAsFixed(1)} dp',
              value: draft.spaceUnit,
              min: 3.0,
              max: 5.5,
              divisions: 10,
              onChanged: (v) => onUpdateDraft(draft.copyWith(spaceUnit: v)),
            ),
            StudioSliderRow(
              tokens: t,
              sliderKey: const Key('slider-screen-padding'),
              label: 'Margini laterali schermate',
              valueText: '${(draft.screenPaddingScale * 100).round()}%',
              value: draft.screenPaddingScale,
              min: 0.80,
              max: 1.35,
              divisions: 11,
              onChanged: (v) =>
                  onUpdateDraft(draft.copyWith(screenPaddingScale: v)),
            ),
            StudioSliderRow(
              tokens: t,
              sliderKey: const Key('slider-card-padding'),
              label: 'Padding interno schede',
              valueText: '${(draft.cardPaddingScale * 100).round()}%',
              value: draft.cardPaddingScale,
              min: 0.80,
              max: 1.35,
              divisions: 11,
              onChanged: (v) =>
                  onUpdateDraft(draft.copyWith(cardPaddingScale: v)),
            ),
            StudioSliderRow(
              tokens: t,
              sliderKey: const Key('slider-section-gap'),
              label: 'Distanza tra sezioni',
              valueText: '${(draft.sectionGapScale * 100).round()}%',
              value: draft.sectionGapScale,
              min: 0.80,
              max: 1.40,
              divisions: 12,
              onChanged: (v) =>
                  onUpdateDraft(draft.copyWith(sectionGapScale: v)),
            ),
          ],
        ),
      ),
    ];
  }

  // ── Category 5: Motion & Animations ────────────────────────────────────

  List<Widget> _buildMotionControls(ConvoyDesignTokens t) {
    final enabled = draft.animationsEnabled;
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
              subtitle:
                  const Text('Interruttore generale (risparmio o moto ridotto).'),
              value: enabled,
              onChanged: (v) =>
                  onUpdateDraft(draft.copyWith(animationsEnabled: v)),
            ),
            SwitchListTile.adaptive(
              key: const Key('switch-radar-rotation'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Fascio rotante sul Radar BLE'),
              value: draft.radarRotationEnabled,
              onChanged: enabled
                  ? (v) =>
                      onUpdateDraft(draft.copyWith(radarRotationEnabled: v))
                  : null,
            ),
            SwitchListTile.adaptive(
              key: const Key('switch-live-pulse'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Impulso sui badge live'),
              value: draft.livePulseEnabled,
              onChanged: enabled
                  ? (v) => onUpdateDraft(draft.copyWith(livePulseEnabled: v))
                  : null,
            ),
            SwitchListTile.adaptive(
              key: const Key('switch-topo-contours'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Curve topografiche decorative'),
              subtitle: const Text(
                  'Isoipse sottili su Radar Hero e reticolo offline Mappa.'),
              value: draft.showTopoContours,
              onChanged: (v) =>
                  onUpdateDraft(draft.copyWith(showTopoContours: v)),
            ),
            SizedBox(height: t.space(2)),
            StudioSliderRow(
              tokens: t,
              sliderKey: const Key('slider-radar-period'),
              label: 'Periodo rotazione radar',
              valueText: '${(draft.radarPeriodMs / 1000).toStringAsFixed(1)} s',
              value: draft.radarPeriodMs.toDouble(),
              min: 2400,
              max: 9500,
              divisions: 71,
              onChanged: enabled
                  ? (v) =>
                      onUpdateDraft(draft.copyWith(radarPeriodMs: v.round()))
                  : null,
            ),
            StudioSliderRow(
              tokens: t,
              sliderKey: const Key('slider-motion-fast'),
              label: 'Transizioni rapide',
              valueText: '${draft.motionFastMs} ms',
              value: draft.motionFastMs.toDouble(),
              min: 80,
              max: 450,
              divisions: 37,
              onChanged: enabled
                  ? (v) =>
                      onUpdateDraft(draft.copyWith(motionFastMs: v.round()))
                  : null,
            ),
            StudioSliderRow(
              tokens: t,
              sliderKey: const Key('slider-motion-medium'),
              label: 'Transizioni medie',
              valueText: '${draft.motionMediumMs} ms',
              value: draft.motionMediumMs.toDouble(),
              min: 140,
              max: 750,
              divisions: 61,
              onChanged: enabled
                  ? (v) =>
                      onUpdateDraft(draft.copyWith(motionMediumMs: v.round()))
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
      final maxLen = OutdoorCopyTokens.maxLengthFor(key);
      final c = draft.copy;
      final next = switch (key) {
        'appKicker' => c.copyWith(
            appKicker: OutdoorCopyTokens.sanitize(
              raw,
              fallback: OutdoorCopyTokens.defaultAppKicker,
              maxLength: maxLen,
            ),
          ),
        'radarTitle' => c.copyWith(
            radarTitle: OutdoorCopyTokens.sanitize(
              raw,
              fallback: OutdoorCopyTokens.defaultRadarTitle,
              maxLength: maxLen,
            ),
          ),
        'radarSubtitle' => c.copyWith(
            radarSubtitle: OutdoorCopyTokens.sanitize(
              raw,
              fallback: OutdoorCopyTokens.defaultRadarSubtitle,
              maxLength: maxLen,
            ),
          ),
        'peersSectionTitle' => c.copyWith(
            peersSectionTitle: OutdoorCopyTokens.sanitize(
              raw,
              fallback: OutdoorCopyTokens.defaultPeersSectionTitle,
              maxLength: maxLen,
            ),
          ),
        'emptyPeersMessage' => c.copyWith(
            emptyPeersMessage: OutdoorCopyTokens.sanitize(
              raw,
              fallback: OutdoorCopyTokens.defaultEmptyPeersMessage,
              maxLength: maxLen,
            ),
          ),
        'toolsSectionTitle' => c.copyWith(
            toolsSectionTitle: OutdoorCopyTokens.sanitize(
              raw,
              fallback: OutdoorCopyTokens.defaultToolsSectionTitle,
              maxLength: maxLen,
            ),
          ),
        'bleDiagSectionTitle' => c.copyWith(
            bleDiagSectionTitle: OutdoorCopyTokens.sanitize(
              raw,
              fallback: OutdoorCopyTokens.defaultBleDiagSectionTitle,
              maxLength: maxLen,
            ),
          ),
        'advancedSectionTitle' => c.copyWith(
            advancedSectionTitle: OutdoorCopyTokens.sanitize(
              raw,
              fallback: OutdoorCopyTokens.defaultAdvancedSectionTitle,
              maxLength: maxLen,
            ),
          ),
        'mapSearchCta' => c.copyWith(
            mapSearchCta: OutdoorCopyTokens.sanitize(
              raw,
              fallback: OutdoorCopyTokens.defaultMapSearchCta,
              maxLength: maxLen,
            ),
          ),
        'mapRecenterCta' => c.copyWith(
            mapRecenterCta: OutdoorCopyTokens.sanitize(
              raw,
              fallback: OutdoorCopyTokens.defaultMapRecenterCta,
              maxLength: maxLen,
            ),
          ),
        'diagnosticTitle' => c.copyWith(
            diagnosticTitle: OutdoorCopyTokens.sanitize(
              raw,
              fallback: OutdoorCopyTokens.defaultDiagnosticTitle,
              maxLength: maxLen,
            ),
          ),
        'diagnosticStartTitle' => c.copyWith(
            diagnosticStartTitle: OutdoorCopyTokens.sanitize(
              raw,
              fallback: OutdoorCopyTokens.defaultDiagnosticStartTitle,
              maxLength: maxLen,
            ),
          ),
        'diagnosticActiveTitle' => c.copyWith(
            diagnosticActiveTitle: OutdoorCopyTokens.sanitize(
              raw,
              fallback: OutdoorCopyTokens.defaultDiagnosticActiveTitle,
              maxLength: maxLen,
            ),
          ),
        'diagnosticContextTitle' => c.copyWith(
            diagnosticContextTitle: OutdoorCopyTokens.sanitize(
              raw,
              fallback: OutdoorCopyTokens.defaultDiagnosticContextTitle,
              maxLength: maxLen,
            ),
          ),
        'diagnosticRuntimeTitle' => c.copyWith(
            diagnosticRuntimeTitle: OutdoorCopyTokens.sanitize(
              raw,
              fallback: OutdoorCopyTokens.defaultDiagnosticRuntimeTitle,
              maxLength: maxLen,
            ),
          ),
        'diagnosticGuideTitle' => c.copyWith(
            diagnosticGuideTitle: OutdoorCopyTokens.sanitize(
              raw,
              fallback: OutdoorCopyTokens.defaultDiagnosticGuideTitle,
              maxLength: maxLen,
            ),
          ),
        _ => c,
      };
      onUpdateDraft(draft.copyWith(copy: next));
    }

    Widget copyField(String key, String label, {int maxLines = 1}) {
      return Padding(
        padding: EdgeInsets.only(bottom: t.space(2.5)),
        child: TextFormField(
          key: Key('copy-field-$key'),
          controller: copyControllers[key],
          maxLines: maxLines,
          maxLength: OutdoorCopyTokens.maxLengthFor(key),
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
            'Puoi personalizzare titoli e sottotitoli visivi. I comandi funzionali («Avvia uscita», «Radar BLE», «Mappa», «Test log», «Avvia registrazione diagnostica • max 4 min») e le note tecniche di sicurezza restano invariati.',
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
            OutdoorCallout(
              key: const Key('copy-protected-radarCaption'),
              tokens: t,
              icon: Icons.lock_outline,
              tone: OutdoorTone.neutral,
              text:
                  'Didascalia anelli Radar (protetta): «${OutdoorCopyTokens.defaultRadarCaption}» — bloccata per mantenere accurata la lettura del segnale BLE.',
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
                onPressed: onResetCopy,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Ripristina solo testi predefiniti'),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}
