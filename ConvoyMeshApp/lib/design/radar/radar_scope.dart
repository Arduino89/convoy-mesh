import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'radar_view_data.dart';

/// Decorative radar hero.
///
/// Placement contract (truthful by design):
/// * the ring of a peer encodes its **BLE signal-quality bucket** (the same
///   four buckets as `ConvoyMeshService.rssiQuality`), never metres;
/// * the angle is a stable hash of the user id so dots do not jump around;
///   it is NOT a bearing;
/// * peers whose signal is not currently received sit hollow on the outer ring.
/// Motion runs only while [scanning] is true and respects the platform
/// "remove animations" accessibility setting.
class RadarScope extends StatefulWidget {
  const RadarScope({
    super.key,
    required this.tokens,
    required this.peers,
    required this.scanning,
    this.showLabels = false,
    this.selectedPeerId,
    this.onPeerTap,
  });

  final ConvoyDesignTokens tokens;
  final List<RadarPeerView> peers;
  final bool scanning;
  final bool showLabels;
  final int? selectedPeerId;
  final ValueChanged<RadarPeerView>? onPeerTap;

  /// Fraction of the radius for each signal level (index = level 0..4).
  static const ringForLevel = <double>[0.94, 0.82, 0.65, 0.48, 0.30];

  static double angleFor(int userId) =>
      ((userId * 137.50776) % 360.0) * math.pi / 180.0 - math.pi / 2;

  static double radiusFractionFor(RadarPeerView peer) =>
      peer.online ? ringForLevel[peer.signalLevel] : ringForLevel[0];

  @override
  State<RadarScope> createState() => _RadarScopeState();
}

class _RadarScopeState extends State<RadarScope> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.tokens.radarPeriod);

  bool get _reduceMotion => MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant RadarScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tokens.radarPeriod != widget.tokens.radarPeriod) {
      _ctrl.duration = widget.tokens.radarPeriod;
    }
    _sync();
  }

  void _sync() {
    if (widget.scanning && !_reduceMotion) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final online = widget.peers.where((p) => p.online).length;
    return Semantics(
      label: 'Radar dei partecipanti: $online presenti, '
          '${widget.peers.length - online} non ricevuti. '
          'Gli anelli indicano la qualità del segnale, non la distanza.',
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(builder: (context, box) {
          final size = box.biggest.shortestSide;
          // Reserve inset so outer-ring blips and labels stay comfortably inside.
          final radius = math.max(24.0, size / 2 - 20.0);
          return RepaintBoundary(
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) => CustomPaint(
                    painter: _ScopePainter(
                      tokens: t,
                      peers: widget.peers,
                      progress: _ctrl.value,
                      active: widget.scanning,
                      radiusInset: 20.0,
                    ),
                  ),
                ),
              ),
              if (widget.peers.isEmpty) _emptyHint(t, size),
              _centerMarker(t, size),
              for (final p in widget.peers) _blip(t, p, size, radius),
            ]),
          );
        }),
      ),
    );
  }

  Widget _emptyHint(ConvoyDesignTokens t, double size) {
    final darkHero = t.radarStyle == RadarScopeStyle.contour || t.radarStyle == RadarScopeStyle.sweep;
    final fg = darkHero ? t.heroInk.withValues(alpha: 0.72) : t.inkMuted;
    return Positioned(
      left: 16,
      right: 16,
      bottom: size * 0.14,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: darkHero
                  ? Colors.black.withValues(alpha: 0.25)
                  : t.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(t.radiusLarge),
              border: Border.all(
                color: darkHero ? t.heroInk.withValues(alpha: 0.18) : t.outline,
              ),
            ),
            child: Text(
              t.label(widget.scanning ? 'In ascolto nel raggio BLE…' : 'Scansione ferma'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.caption(color: fg).copyWith(fontSize: 11),
            ),
          ),
        ),
      ),
    );
  }

  Widget _centerMarker(ConvoyDesignTokens t, double size) {
    final d = t.radarStyle == RadarScopeStyle.sweep ? 14.0 : 22.0;
    final color = switch (t.radarStyle) {
      RadarScopeStyle.contour => t.heroInk,
      RadarScopeStyle.sweep => t.radarSweep,
      RadarScopeStyle.pulse => t.highlight,
    };
    return Positioned(
      left: size / 2 - d / 2,
      top: size / 2 - d / 2,
      child: Container(
        width: d,
        height: d,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: t.radarStyle == RadarScopeStyle.sweep ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: t.radarStyle == RadarScopeStyle.sweep ? BorderRadius.circular(3) : null,
          border: Border.all(
            color: t.radarStyle == RadarScopeStyle.pulse ? Colors.white : color.withValues(alpha: 0.35),
            width: t.radarStyle == RadarScopeStyle.pulse ? 3 : 1.5,
          ),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 14)],
        ),
        child: t.radarStyle == RadarScopeStyle.sweep
            ? null
            : Text(
                'IO',
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 7.5,
                  fontWeight: FontWeight.w800,
                  color: t.radarStyle == RadarScopeStyle.contour ? t.accent : Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _blip(ConvoyDesignTokens t, RadarPeerView p, double size, double radius) {
    final r = RadarScope.radiusFractionFor(p) * radius;
    final a = RadarScope.angleFor(p.userId);
    final cx = size / 2 + r * math.cos(a);
    final cy = size / 2 + r * math.sin(a);
    final sweep = t.radarStyle == RadarScopeStyle.sweep;
    final selected = widget.selectedPeerId == p.userId;
    final d = sweep ? (selected ? 16.0 : 12.0) : (size < 220 ? 26.0 : (selected ? 36.0 : 31.0));
    final userColor = Color(p.color);

    final Widget dot;
    if (sweep) {
      dot = AnimatedContainer(
        duration: t.motionFast,
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.online ? t.radarSweep : Colors.transparent,
          border: Border.all(
            color: selected ? Colors.white : (p.online ? t.radarSweep : t.warning),
            width: selected ? 2.2 : 1.6,
          ),
          boxShadow: p.online
              ? [BoxShadow(color: t.radarSweep.withValues(alpha: 0.75), blurRadius: selected ? 14 : 10)]
              : const [],
        ),
      );
    } else {
      final fill = switch (t.radarStyle) {
        RadarScopeStyle.contour => userColor,
        _ => t.ink,
      };
      final ring = switch (t.radarStyle) {
        RadarScopeStyle.contour => selected ? t.radarSweep : t.heroInk,
        _ => selected ? t.highlight : userColor,
      };
      dot = AnimatedContainer(
        duration: t.motionFast,
        width: d,
        height: d,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.online ? fill : Colors.transparent,
          border: Border.all(
            color: p.online
                ? ring
                : (t.radarStyle == RadarScopeStyle.contour ? t.heroInk : t.inkMuted)
                    .withValues(alpha: 0.72),
            width: selected ? 3.0 : (p.online ? 2.4 : 1.6),
          ),
          boxShadow: p.online && t.radarStyle == RadarScopeStyle.contour
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : const [],
        ),
        child: Text(
          p.initials,
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: d * 0.36,
            fontWeight: FontWeight.w800,
            color: p.online
                ? Colors.white
                : (t.radarStyle == RadarScopeStyle.contour ? t.heroInk : t.inkMuted),
          ),
        ),
      );
    }

    final showLabel = widget.showLabels || sweep || selected;
    const labelWidth = 84.0;
    final toLeft = cx > size * 0.56;
    final rawLeft = showLabel && toLeft ? cx - d / 2 - labelWidth - 4 : cx - d / 2;
    final totalWidth = showLabel ? d + 4 + labelWidth : d;
    final clampedLeft = rawLeft.clamp(2.0, math.max(2.0, size - totalWidth - 2.0)).toDouble();
    final clampedTop = (cy - d / 2).clamp(2.0, math.max(2.0, size - d - 2.0)).toDouble();

    return Positioned(
      left: clampedLeft,
      top: clampedTop,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPeerTap != null ? () => widget.onPeerTap!(p) : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showLabel && toLeft) _blipLabel(t, p, labelWidth, TextAlign.right),
            if (showLabel && toLeft) const SizedBox(width: 4),
            AnimatedOpacity(
              duration: t.motionMedium,
              opacity: p.online ? 1 : 0.78,
              child: dot,
            ),
            if (showLabel && !toLeft) const SizedBox(width: 4),
            if (showLabel && !toLeft) _blipLabel(t, p, labelWidth, TextAlign.left),
          ],
        ),
      ),
    );
  }

  Widget _blipLabel(ConvoyDesignTokens t, RadarPeerView p, double width, TextAlign align) {
    final darkHero = t.radarStyle == RadarScopeStyle.contour || t.radarStyle == RadarScopeStyle.sweep;
    final textColor = darkHero
        ? (p.online ? t.radarSweep : t.warning)
        : (p.online ? t.ink : t.inkMuted);
    return SizedBox(
      width: width,
      child: Text(
        t.label(p.name),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: t.data(10.5, color: textColor, weight: FontWeight.w700),
      ),
    );
  }
}

class _ScopePainter extends CustomPainter {
  _ScopePainter({
    required this.tokens,
    required this.peers,
    required this.progress,
    required this.active,
    required this.radiusInset,
  });

  final ConvoyDesignTokens tokens;
  final List<RadarPeerView> peers;
  final double progress;
  final bool active;
  final double radiusInset;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.max(24.0, size.shortestSide / 2 - radiusInset);
    switch (tokens.radarStyle) {
      case RadarScopeStyle.contour:
        _contour(canvas, c, r);
      case RadarScopeStyle.sweep:
        _sweep(canvas, c, r);
      case RadarScopeStyle.pulse:
        _pulse(canvas, c, r);
    }
  }

  // ── A · topographic contour lines with a warm rotating light ────────────
  void _contour(Canvas canvas, Offset c, double r) {
    final t = tokens;
    if (active) {
      final rot = progress * 2 * math.pi;
      final light = Paint()
        ..shader = SweepGradient(
          colors: [
            t.radarSweep.withValues(alpha: 0.0),
            t.radarSweep.withValues(alpha: 0.0),
            t.radarSweep.withValues(alpha: 0.30),
            t.radarSweep.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.70, 0.97, 1.0],
          transform: GradientRotation(rot),
        ).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, light);
    }
    for (var k = 1; k <= 6; k++) {
      final base = r * (k / 6.0);
      final path = Path();
      const steps = 120;
      for (var i = 0; i <= steps; i++) {
        final th = i / steps * 2 * math.pi;
        final wobble = 1 +
            0.050 * math.sin(3 * th + k * 0.9) +
            0.030 * math.sin(5 * th + k * 1.7) +
            0.018 * math.sin(8 * th + k);
        final rr = base * (k == 6 ? 1.0 : wobble);
        final p = c + Offset(rr * math.cos(th), rr * math.sin(th));
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
          ..strokeWidth = k == 6 ? 1.6 : (k.isEven ? 1.1 : 0.7)
          ..color = t.radarGrid.withValues(alpha: k == 6 ? 0.55 : (k.isEven ? 0.45 : 0.28)),
      );
    }
    // Ring guides for the four signal buckets (dotted).
    for (final f in RadarScope.ringForLevel.skip(1)) {
      _dotted(canvas, c, r * f, t.heroInk.withValues(alpha: 0.18), 2.2, 64);
    }
  }

  // ── B · HUD sweep with bezel ticks and afterglow ────────────────────────
  void _sweep(Canvas canvas, Offset c, double r) {
    final t = tokens;
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = t.radarGrid;
    for (final f in RadarScope.ringForLevel.skip(1)) {
      canvas.drawCircle(c, r * f, grid..color = t.radarGrid.withValues(alpha: 0.35));
    }
    canvas.drawCircle(c, r, grid..color = t.radarGrid.withValues(alpha: 0.9));
    final cross = Paint()
      ..strokeWidth = 1
      ..color = t.radarGrid.withValues(alpha: 0.25);
    canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), cross);
    canvas.drawLine(c - Offset(0, r), c + Offset(0, r), cross);
    for (var i = 0; i < 72; i++) {
      final a = i / 72 * 2 * math.pi;
      final long = i % 6 == 0;
      final p1 = c + Offset(math.cos(a), math.sin(a)) * r;
      final p2 = c + Offset(math.cos(a), math.sin(a)) * (r - (long ? 9 : 4));
      canvas.drawLine(
          p1, p2, Paint()..strokeWidth = long ? 1.4 : 0.8..color = t.radarGrid.withValues(alpha: long ? 0.9 : 0.5));
    }
    if (!active) return;
    final rot = progress * 2 * math.pi - math.pi / 2;
    final wedge = Paint()
      ..shader = SweepGradient(
        colors: [
          t.radarSweep.withValues(alpha: 0.0),
          t.radarSweep.withValues(alpha: 0.0),
          t.radarSweep.withValues(alpha: 0.38),
        ],
        stops: const [0.0, 0.78, 1.0],
        transform: GradientRotation(rot),
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r - 1, wedge);
    final lead = c + Offset(math.cos(rot), math.sin(rot)) * r;
    canvas.drawLine(
      c,
      lead,
      Paint()
        ..strokeWidth = 2
        ..color = t.radarSweep
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2),
    );
    // Afterglow halo on online blips the sweep has just passed.
    for (final p in peers.where((p) => p.online)) {
      final pa = RadarScope.angleFor(p.userId);
      var behind = (rot - pa) % (2 * math.pi);
      if (behind < 0) behind += 2 * math.pi;
      final glow = math.pow(1 - behind / (2 * math.pi), 3).toDouble();
      if (glow < 0.05) continue;
      final pr = RadarScope.radiusFractionFor(p) * r;
      canvas.drawCircle(
        c + Offset(math.cos(pa), math.sin(pa)) * pr,
        10 + 10 * glow,
        Paint()
          ..color = t.radarSweep.withValues(alpha: 0.35 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  // ── C · minimal rings with outward pulse waves (#4 motif, scaled up) ───
  void _pulse(Canvas canvas, Offset c, double r) {
    final t = tokens;
    for (final f in RadarScope.ringForLevel) {
      canvas.drawCircle(
        c,
        r * f,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = f == RadarScope.ringForLevel.first ? 1.4 : 1
          ..color = t.radarGrid,
      );
    }
    if (!active) return;
    for (var i = 0; i < 3; i++) {
      final phase = (progress + i / 3) % 1.0;
      final eased = Curves.easeOutCubic.transform(phase);
      canvas.drawCircle(
        c,
        14 + eased * (r - 14),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * (1 - phase) + 0.6
          ..color = t.radarSweep.withValues(alpha: (1 - phase) * 0.55),
      );
    }
  }

  void _dotted(Canvas canvas, Offset c, double radius, Color color, double dot, int count) {
    final p = Paint()..color = color;
    for (var i = 0; i < count; i++) {
      final a = i / count * 2 * math.pi;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * radius, dot / 2, p);
    }
  }

  @override
  bool shouldRepaint(covariant _ScopePainter old) =>
      old.progress != progress ||
      old.active != active ||
      old.tokens != tokens ||
      old.peers != peers ||
      old.radiusInset != radiusInset;
}
