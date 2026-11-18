import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'radar_view_data.dart';

/// Reusable Outdoor Premium building blocks driven strictly by [ConvoyDesignTokens].

/// Tappable Bluetooth status pill. Same states/labels as the original banner.
class DesignBleStatusPill extends StatelessWidget {
  const DesignBleStatusPill({
    super.key,
    required this.tokens,
    required this.label,
    required this.ready,
    required this.onTap,
    this.onHero = false,
  });

  final ConvoyDesignTokens tokens;
  final String label;
  final bool ready;
  final VoidCallback onTap;
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final tone = ready ? t.positive : t.critical;
    final dark = t.brightness == Brightness.dark;
    final Color bg;
    final Color fg;
    if (onHero) {
      bg = t.heroInk.withValues(alpha: 0.12);
      fg = t.heroInk;
    } else {
      bg = dark
          ? tone.withValues(alpha: 0.14)
          : Color.alphaBlend(tone.withValues(alpha: 0.10), t.surface);
      fg = tone;
    }
    return Semantics(
      button: true,
      label: label,
      hint: ready
          ? 'Tocca per conferma dello stato'
          : 'Tocca per capire come risolvere',
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radiusLarge),
          side: BorderSide(
            color: onHero
                ? t.heroInk.withValues(alpha: 0.24)
                : tone.withValues(alpha: 0.35),
            width: t.borderWidth,
          ),
        ),
        child: InkWell(
          key: const Key('design-ble-status-tap'),
          borderRadius: BorderRadius.circular(t.radiusLarge),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: (t.minTouchTarget - 8).clamp(40, 60)),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: t.space(3.5)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: onHero
                        ? (ready
                            ? const Color(0xFF9BE2B4)
                            : const Color(0xFFFF9C8F))
                        : tone,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: t.space(2)),
                Icon(
                  ready ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  size: t.iconSize(18),
                  color: fg,
                ),
                SizedBox(width: t.space(1.5)),
                Flexible(
                  child: Text(
                    t.label(label),
                    overflow: TextOverflow.ellipsis,
                    style: t.body(14, color: fg, weight: FontWeight.w700)
                        .copyWith(letterSpacing: t.uppercaseLabels ? 0.9 : 0),
                  ),
                ),
                SizedBox(width: t.space(1.5)),
                Icon(Icons.chevron_right,
                    size: t.iconSize(18), color: fg.withValues(alpha: 0.82)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Live/idle indicator: softly breathing dot while [active] and [pulseEnabled].
class LiveDot extends StatefulWidget {
  const LiveDot({
    super.key,
    required this.active,
    required this.color,
    this.size = 10,
    this.pulseEnabled = true,
  });

  final bool active;
  final Color color;
  final double size;
  final bool pulseEnabled;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant LiveDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.active && widget.pulseEnabled && !reduce) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final showRing = widget.active && widget.pulseEnabled;
    return SizedBox(
      width: s * 2.2,
      height: s * 2.2,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(alignment: Alignment.center, children: [
          if (showRing)
            Container(
              width: s + s * 1.2 * _c.value,
              height: s + s * 1.2 * _c.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.45 * (1 - _c.value)),
              ),
            ),
          Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.active ? widget.color : Colors.transparent,
              border: Border.all(color: widget.color, width: 1.6),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Four-bar signal meter mapped from existing RSSI quality buckets.
class SignalBars extends StatelessWidget {
  const SignalBars({
    super.key,
    required this.level,
    required this.color,
    required this.track,
    this.height = 16,
  });

  final int level;
  final Color color;
  final Color track;
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Qualità segnale $level su 4',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 1; i <= 4; i++)
              Container(
                margin: const EdgeInsets.only(left: 2),
                width: height / 4,
                height: height * (0.35 + 0.65 * i / 4),
                decoration: BoxDecoration(
                  color: i <= level ? color : track,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
          ],
        ),
      );
}

/// Initials avatar using the participant colour assigned by ConvoyMeshService.
class PeerAvatar extends StatelessWidget {
  const PeerAvatar({
    super.key,
    required this.tokens,
    required this.peer,
    double? size,
  }) : _size = size;

  final ConvoyDesignTokens tokens;
  final RadarPeerView peer;
  final double? _size;

  @override
  Widget build(BuildContext context) {
    final s = _size ?? tokens.avatarSize;
    final color = Color(peer.color);
    return Stack(clipBehavior: Clip.none, children: [
      AnimatedContainer(
        duration: tokens.effectiveMotionMedium,
        curve: tokens.motionCurve,
        width: s,
        height: s,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: peer.online ? color : tokens.surfaceRaised,
          shape: BoxShape.circle,
          border: Border.all(
            color: peer.online ? color : tokens.outline,
            width: peer.online ? 0 : tokens.borderWidth + 0.4,
          ),
        ),
        child: Text(
          peer.initials,
          style: TextStyle(
            fontFamily: tokens.bodyFamily,
            fontWeight: FontWeight.w800,
            fontSize: s * 0.36,
            color: peer.online ? Colors.white : tokens.inkMuted,
          ),
        ),
      ),
      Positioned(
        right: -2,
        bottom: -2,
        child: Container(
          width: s * 0.32,
          height: s * 0.32,
          decoration: BoxDecoration(
            color: peer.online ? tokens.positive : tokens.inkMuted,
            shape: BoxShape.circle,
            border: Border.all(color: tokens.surface, width: 2.5),
          ),
        ),
      ),
    ]);
  }
}

/// Location glyph keeping the same three semantics as the original UI.
class LocationGlyph extends StatelessWidget {
  const LocationGlyph({
    super.key,
    required this.tokens,
    required this.state,
    this.size = 20,
  });

  final ConvoyDesignTokens tokens;
  final PeerLocationState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String label) = switch (state) {
      PeerLocationState.fresh => (
          Icons.location_on,
          tokens.positive,
          'Posizione recente e precisa'
        ),
      PeerLocationState.searching => (
          Icons.location_searching,
          tokens.warning,
          'Posizione non recente o imprecisa'
        ),
      PeerLocationState.off => (
          Icons.location_off,
          tokens.warning,
          'Posizione non disponibile'
        ),
    };
    return Semantics(
      label: label,
      child: Icon(icon, color: color, size: tokens.iconSize(size)),
    );
  }
}

/// Outdoor Premium section header with optional trailing count.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.tokens,
    required this.title,
    this.trailing,
  });

  final ConvoyDesignTokens tokens;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Padding(
      padding: EdgeInsets.only(top: t.sectionTop, bottom: t.space(2.5)),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: t.space(2),
          runSpacing: t.space(1),
          children: [
            Text(t.label(title), style: t.display(22)),
            if (trailing != null)
              Text(trailing!,
                  style: t.caption(color: t.inkMuted, size: 12.5)),
          ],
        ),
      ),
    );
  }
}

/// Big, gloved-hand friendly tool button.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.tokens,
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasis = false,
  });

  final ConvoyDesignTokens tokens;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final bg = emphasis ? t.accent : t.surfaceRaised;
    final fg = emphasis ? t.onAccent : t.ink;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusMedium),
        side: BorderSide(color: emphasis ? bg : t.outline, width: t.borderWidth),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.radiusMedium),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: t.minTouchTarget),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: t.space(3.5), vertical: t.space(2.5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: t.iconSize(20), color: emphasis ? fg : t.accent),
              SizedBox(width: t.space(2.5)),
              Flexible(
                child: Text(
                  t.label(label),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.body(14, color: fg, weight: FontWeight.w700).copyWith(
                      letterSpacing: t.uppercaseLabels ? 0.8 : 0),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Collapsible Outdoor Premium panel (`Diagnostica BLE` / `Avanzate`).
class DesignPanel extends StatelessWidget {
  const DesignPanel({
    super.key,
    required this.tokens,
    required this.title,
    required this.icon,
    required this.children,
  });

  final ConvoyDesignTokens tokens;
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final radius = BorderRadius.circular(t.radiusMedium);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(3)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: t.elevated ? t.shadow : const [],
        ),
        child: Material(
          color: t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: t.outline, width: t.borderWidth),
          ),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: Icon(icon, color: t.accent, size: t.iconSize(21)),
              title: Text(
                t.label(title),
                style: t.body(15, weight: FontWeight.w700).copyWith(
                    letterSpacing: t.uppercaseLabels ? 1.0 : 0),
              ),
              childrenPadding:
                  EdgeInsets.fromLTRB(t.cardPad, 0, t.cardPad, t.cardPad),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}
