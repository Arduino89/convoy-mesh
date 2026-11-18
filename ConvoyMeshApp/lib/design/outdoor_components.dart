import 'package:flutter/material.dart';

import 'design_tokens.dart';

enum OutdoorTone { accent, highlight, positive, warning, critical, neutral }

extension OutdoorToneColor on OutdoorTone {
  Color resolve(ConvoyDesignTokens t) => switch (this) {
        OutdoorTone.accent => t.accent,
        OutdoorTone.highlight => t.highlight,
        OutdoorTone.positive => t.positive,
        OutdoorTone.warning => t.warning,
        OutdoorTone.critical => t.critical,
        OutdoorTone.neutral => t.inkMuted,
      };
}

/// Bordered and optionally shadowed container matching the Outdoor Premium surface language.
class OutdoorCard extends StatelessWidget {
  const OutdoorCard({
    super.key,
    required this.tokens,
    required this.child,
    this.padding,
    this.margin,
    this.borderColor,
    this.backgroundColor,
    this.elevated,
  });

  final ConvoyDesignTokens tokens;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? borderColor;
  final Color? backgroundColor;
  final bool? elevated;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final useShadow = elevated ?? t.elevated;
    final radius = BorderRadius.circular(t.radiusMedium);
    return Padding(
      padding: margin ?? EdgeInsets.only(bottom: t.space(3.5)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: useShadow ? t.shadow : const [],
        ),
        child: Material(
          color: backgroundColor ?? t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: borderColor ?? t.outline,
              width: t.borderWidth,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: padding ?? EdgeInsets.all(t.cardPad),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Consistent section header inside cards, bottom sheets and dialogs.
class OutdoorCardHeader extends StatelessWidget {
  const OutdoorCardHeader({
    super.key,
    required this.tokens,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tone = OutdoorTone.accent,
    this.trailing,
  });

  final ConvoyDesignTokens tokens;
  final IconData icon;
  final String title;
  final String? subtitle;
  final OutdoorTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final accent = tone.resolve(t);
    final boxSize = (36 * t.iconScale).clamp(32.0, 48.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: boxSize,
          height: boxSize,
          decoration: BoxDecoration(
            color: accent.withValues(
                alpha: t.brightness == Brightness.dark ? 0.18 : 0.11),
            borderRadius: BorderRadius.circular(t.radiusSmall),
          ),
          child: Icon(icon, color: accent, size: t.iconSize(19)),
        ),
        SizedBox(width: t.space(3)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.display(18)),
              if (subtitle != null) ...[
                SizedBox(height: t.space(0.5)),
                Text(subtitle!, style: t.body(12.5, color: t.inkMuted)),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          SizedBox(width: t.space(2)),
          trailing!,
        ],
      ],
    );
  }
}

/// High-contrast tinted callout banner replacing bare unstyled warning/error lines.
class OutdoorCallout extends StatelessWidget {
  const OutdoorCallout({
    super.key,
    required this.tokens,
    required this.icon,
    required this.text,
    this.tone = OutdoorTone.neutral,
    this.padding,
  });

  final ConvoyDesignTokens tokens;
  final IconData icon;
  final String text;
  final OutdoorTone tone;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final color = tone.resolve(t);
    final bg = Color.alphaBlend(
      color.withValues(alpha: t.brightness == Brightness.dark ? 0.16 : 0.08),
      t.surfaceRaised,
    );
    return Container(
      padding: padding ??
          EdgeInsets.symmetric(
              horizontal: t.space(3), vertical: t.space(2.25)),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(t.radiusSmall),
        border: Border.all(
          color: color.withValues(alpha: 0.34),
          width: t.borderWidth,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, color: color, size: t.iconSize(17)),
          ),
          SizedBox(width: t.space(2)),
          Expanded(
            child: Text(
              text,
              style: t.body(
                13,
                color: tone == OutdoorTone.neutral ? t.inkMuted : color,
                weight: tone == OutdoorTone.neutral
                    ? FontWeight.w500
                    : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact pill badge with semantic border & tint.
class OutdoorStatusBadge extends StatelessWidget {
  const OutdoorStatusBadge({
    super.key,
    required this.tokens,
    required this.label,
    this.tone = OutdoorTone.neutral,
    this.icon,
  });

  final ConvoyDesignTokens tokens;
  final String label;
  final OutdoorTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final color = tone.resolve(t);
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: t.space(2.2), vertical: t.space(1)),
      decoration: BoxDecoration(
        color: color.withValues(
            alpha: t.brightness == Brightness.dark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(t.radiusSmall),
        border: Border.all(
          color: color.withValues(alpha: 0.28),
          width: t.borderWidth,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: t.iconSize(13), color: color),
            SizedBox(width: t.space(1)),
          ],
          Flexible(
            child: Text(
              t.label(label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.caption(color: color, size: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// Key-value technical readout row with tabular figures.
class OutdoorSpecRow extends StatelessWidget {
  const OutdoorSpecRow({
    super.key,
    required this.tokens,
    required this.label,
    required this.value,
    this.valueColor,
    this.showDivider = true,
  });

  final ConvoyDesignTokens tokens;
  final String label;
  final String value;
  final Color? valueColor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Container(
      padding: EdgeInsets.symmetric(vertical: t.space(1.75)),
      decoration: showDivider
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: t.outline.withValues(alpha: 0.55),
                  width: t.borderWidth * 0.75,
                ),
              ),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: t.body(13, color: t.inkMuted)),
          ),
          SizedBox(width: t.space(2)),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: t.data(13.5, color: valueColor ?? t.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// AlertDialog title bar with subtle Outdoor icon badge.
class OutdoorDialogTitle extends StatelessWidget {
  const OutdoorDialogTitle({
    super.key,
    required this.tokens,
    required this.icon,
    required this.title,
    this.tone = OutdoorTone.accent,
  });

  final ConvoyDesignTokens tokens;
  final IconData icon;
  final String title;
  final OutdoorTone tone;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final color = tone.resolve(t);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(t.radiusSmall),
          ),
          child: Icon(icon, color: color, size: t.iconSize(19)),
        ),
        SizedBox(width: t.space(2.5)),
        Expanded(child: Text(title, style: t.display(20))),
      ],
    );
  }
}
