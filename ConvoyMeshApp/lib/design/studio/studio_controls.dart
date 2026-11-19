import 'package:flutter/material.dart';

import '../design_presets.dart';
import '../design_tokens.dart';
import '../outdoor_components.dart';
import '../outdoor_config.dart';

/// Reusable mode tab button for Outdoor Studio workspace switching.
class StudioModeTabButton extends StatelessWidget {
  const StudioModeTabButton({
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
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
      ),
    );
  }
}

/// Curated Outdoor palette preset selector tile with 4-swatch strip.
class StudioPresetOptionTile extends StatelessWidget {
  const StudioPresetOptionTile({
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
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
                    Text(
                      preset.label,
                      style: t.body(14.5, weight: FontWeight.w800),
                    ),
                    Text(
                      preset.subtitle,
                      style: t.body(12, color: t.inkMuted),
                    ),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: t.accent, size: 22),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Accessible 48x48dp color swatch selector row for a single Outdoor color role.
class StudioSwatchRow extends StatelessWidget {
  const StudioSwatchRow({
    super.key,
    required this.tokens,
    required this.group,
    required this.label,
    required this.swatches,
    required this.selected,
    required this.onPick,
  });

  final ConvoyDesignTokens tokens;
  final String group;
  final String label;
  final List<Color> swatches;
  final Color selected;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(2.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.body(13.5, weight: FontWeight.w700)),
          SizedBox(height: t.space(1)),
          Wrap(
            spacing: t.space(1),
            runSpacing: t.space(1),
            children: [
              for (final c in swatches) _swatchButton(t, c),
            ],
          ),
        ],
      ),
    );
  }

  Widget _swatchButton(ConvoyDesignTokens t, Color c) {
    final hex = c.toARGB32().toRadixString(16).padLeft(8, '0');
    final rgbHex = '#${hex.substring(2).toUpperCase()}';
    final isSelected = selected.toARGB32() == c.toARGB32();
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label $rgbHex',
      child: Tooltip(
        message: rgbHex,
        child: GestureDetector(
          key: Key('swatch-$group-$hex'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onPick(c),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? t.highlight : t.outline,
                    width: isSelected ? 3.0 : 1.2,
                  ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 18,
                        color: DesignPresets.contrastingInkOn(c),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Font family picker chip group for a single typography role.
class StudioFontPicker extends StatelessWidget {
  const StudioFontPicker({
    super.key,
    required this.tokens,
    required this.role,
    required this.title,
    required this.selected,
    required this.labelFor,
    required this.onPick,
  });

  final ConvoyDesignTokens tokens;
  final String role;
  final String title;
  final String? selected;
  final String Function(String?) labelFor;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
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
                key: Key(
                  'font-$role-${f ?? OutdoorCustomConfig.systemFontSentinel}',
                ),
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
}

/// Labelled numeric slider with tabular current value readout.
class StudioSliderRow extends StatelessWidget {
  const StudioSliderRow({
    super.key,
    required this.tokens,
    required this.sliderKey,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final ConvoyDesignTokens tokens;
  final Key sliderKey;
  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
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

/// Live WCAG 2.1 contrast diagnostics card across all active UI surface pairs.
class StudioContrastDiagnosticsCard extends StatelessWidget {
  const StudioContrastDiagnosticsCard({
    super.key,
    required this.tokens,
    required this.report,
  });

  final ConvoyDesignTokens tokens;
  final OutdoorContrastReport report;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final passedCount = report.checks.length - report.failures.length;
    final total = report.checks.length;
    final summaryTone = report.allPassAa
        ? (report.bodyIsAaa ? OutdoorTone.positive : OutdoorTone.highlight)
        : OutdoorTone.warning;
    final summaryLabel = '$passedCount/$total AA';

    return OutdoorCard(
      key: const Key('studio-contrast-diagnostics'),
      tokens: t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutdoorCardHeader(
            tokens: t,
            icon: report.allPassAa
                ? Icons.verified_outlined
                : Icons.contrast_outlined,
            title: 'Diagnostica contrasto WCAG',
            subtitle:
                'Verifica live su $total coppie testo/sfondo (min ${report.minRatio.toStringAsFixed(1)}:1).',
            tone: summaryTone,
            trailing: OutdoorStatusBadge(
              tokens: t,
              label: summaryLabel,
              tone: summaryTone,
            ),
          ),
          SizedBox(height: t.space(2)),
          for (var i = 0; i < report.checks.length; i++)
            _checkRow(
              t,
              report.checks[i],
              showDivider: i < report.checks.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _checkRow(
    ConvoyDesignTokens t,
    OutdoorContrastCheck check, {
    required bool showDivider,
  }) {
    final grade = check.passesAaa
        ? 'AAA'
        : check.passesAa
            ? 'AA'
            : 'Basso';
    final tone = check.passesAaa
        ? OutdoorTone.positive
        : check.passesAa
            ? OutdoorTone.highlight
            : OutdoorTone.warning;

    return Container(
      padding: EdgeInsets.symmetric(vertical: t.space(1.4)),
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: t.outline.withValues(alpha: 0.45),
                  width: t.borderWidth * 0.75,
                ),
              ),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              check.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.body(12.5, color: t.inkMuted),
            ),
          ),
          SizedBox(width: t.space(2)),
          Text(
            '${check.ratio.toStringAsFixed(1)}:1',
            style: t.data(
              12.5,
              color: check.passesAa ? t.ink : t.warning,
              weight: FontWeight.w700,
            ),
          ),
          SizedBox(width: t.space(1.5)),
          OutdoorStatusBadge(tokens: t, label: grade, tone: tone),
        ],
      ),
    );
  }
}
