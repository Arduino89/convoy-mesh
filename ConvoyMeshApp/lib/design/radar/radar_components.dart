import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'radar_view_data.dart';

/// Small reusable building blocks shared by the three Radar layouts.
/// Every visual value comes from [ConvoyDesignTokens].

/// Tappable Bluetooth status. Same states/labels as the original banner.
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
      bg = dark ? tone.withValues(alpha: 0.12) : Color.alphaBlend(tone.withValues(alpha: 0.10), t.surface);
      fg = tone;
    }
    return Semantics(
      button: true,
      label: label,
      hint: ready ? 'Tocca per conferma dello stato' : 'Tocca per capire come risolvere',
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radiusLarge),
          side: BorderSide(
            color: onHero ? t.heroInk.withValues(alpha: 0.22) : tone.withValues(alpha: 0.35),
            width: t.borderWidth,
          ),
        ),
        child: InkWell(
          key: const Key('design-ble-status-tap'),
          borderRadius: BorderRadius.circular(t.radiusLarge),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: t.minTouchTarget - 8),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: t.space(3.5)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: onHero ? (ready ? const Color(0xFF9BE2B4) : const Color(0xFFFF9C8F)) : tone,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: t.space(2)),
                Icon(ready ? Icons.bluetooth_connected : Icons.bluetooth_disabled, size: 18, color: fg),
                SizedBox(width: t.space(1.5)),
                Flexible(
                  child: Text(
                    t.label(label),
                    overflow: TextOverflow.ellipsis,
                    style: t.body(14, color: fg, weight: FontWeight.w700)
                        .copyWith(letterSpacing: t.uppercaseLabels ? 1.1 : 0),
                  ),
                ),
                SizedBox(width: t.space(1.5)),
                Icon(Icons.chevron_right, size: 18, color: fg.withValues(alpha: 0.8)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Live/idle indicator: a softly breathing dot only while scanning.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, required this.active, required this.color, this.size = 10});
  final bool active;
  final Color color;
  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

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
    if (widget.active && !reduce) {
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
    return SizedBox(
      width: s * 2.2,
      height: s * 2.2,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(alignment: Alignment.center, children: [
          if (widget.active)
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

/// Four-bar signal meter mapped from the existing RSSI quality buckets.
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

/// Initials avatar using the participant colour already shown on the map.
class PeerAvatar extends StatelessWidget {
  const PeerAvatar({
    super.key,
    required this.tokens,
    required this.peer,
    this.size = 48,
    this.square = false,
  });

  final ConvoyDesignTokens tokens;
  final RadarPeerView peer;
  final double size;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final color = Color(peer.color);
    final radius = square ? BorderRadius.circular(tokens.radiusSmall) : BorderRadius.circular(size);
    return Stack(clipBehavior: Clip.none, children: [
      AnimatedContainer(
        duration: tokens.motionMedium,
        curve: tokens.motionCurve,
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: peer.online ? color : tokens.surfaceRaised,
          borderRadius: radius,
          border: Border.all(
            color: peer.online ? color : tokens.outline,
            width: peer.online ? 0 : 1.5,
          ),
        ),
        child: Text(
          peer.initials,
          style: TextStyle(
            fontFamily: tokens.bodyFamily,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.36,
            color: peer.online ? Colors.white : tokens.inkMuted,
          ),
        ),
      ),
      Positioned(
        right: -2,
        bottom: -2,
        child: Container(
          width: size * 0.32,
          height: size * 0.32,
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

/// Location glyph with the same three semantics as the original trailing icon.
class LocationGlyph extends StatelessWidget {
  const LocationGlyph({super.key, required this.tokens, required this.state, this.size = 20});
  final ConvoyDesignTokens tokens;
  final PeerLocationState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String label) = switch (state) {
      PeerLocationState.fresh => (Icons.location_on, tokens.positive, 'Posizione recente e precisa'),
      PeerLocationState.searching => (Icons.location_searching, tokens.warning, 'Posizione non recente o imprecisa'),
      PeerLocationState.off => (Icons.location_off, tokens.warning, 'Posizione non disponibile'),
    };
    return Semantics(label: label, child: Icon(icon, color: color, size: size));
  }
}

/// Section title with optional trailing count.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.tokens, required this.title, this.trailing});
  final ConvoyDesignTokens tokens;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final style = switch (t.layoutStyle) {
      RadarLayoutStyle.hud => t.caption(color: t.inkMuted).copyWith(fontSize: 12),
      RadarLayoutStyle.heroCard => t.display(22),
      RadarLayoutStyle.editorial => t.display(22).copyWith(letterSpacing: -0.4),
    };
    return Padding(
      padding: EdgeInsets.only(top: t.space(6), bottom: t.space(2.5)),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: t.space(2),
          runSpacing: t.space(1),
          children: [
            Text(t.label(title), style: style),
            if (trailing != null)
              Text(trailing!, style: t.caption(color: t.inkMuted).copyWith(fontSize: 12.5)),
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
    final dark = t.brightness == Brightness.dark;
    final bg = emphasis
        ? t.accent
        : (t.layoutStyle == RadarLayoutStyle.hud ? t.surface : t.surfaceRaised);
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
            padding: EdgeInsets.symmetric(horizontal: t.space(3.5), vertical: t.space(2.5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20, color: emphasis ? fg : (dark ? t.accent : t.accent)),
              SizedBox(width: t.space(2.5)),
              Flexible(
                child: Text(
                  t.label(label),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.body(14, color: fg, weight: FontWeight.w700)
                      .copyWith(letterSpacing: t.uppercaseLabels ? 0.9 : 0),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Collapsible panel (Diagnostica BLE / Avanzate) styled from tokens.
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
    return Container(
      margin: EdgeInsets.only(bottom: t.space(3)),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.radiusMedium),
        border: Border.all(color: t.outline, width: t.borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(icon, color: t.inkMuted),
          title: Text(t.label(title), style: t.body(15, weight: FontWeight.w700)
              .copyWith(letterSpacing: t.uppercaseLabels ? 1.2 : 0)),
          childrenPadding: EdgeInsets.fromLTRB(t.space(4), 0, t.space(4), t.space(4)),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
