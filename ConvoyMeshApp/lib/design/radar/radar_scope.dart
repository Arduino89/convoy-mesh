import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'radar_view_data.dart';

/// Decorative Outdoor Premium topographic radar hero.
///
/// Placement contract (truthful by design):
/// * the ring of a peer encodes its **BLE signal-quality bucket** (the same
///   four buckets as `ConvoyMeshService.rssiQuality`), never metres;
/// * the angle is a stable hash of the user id so dots do not jump around;
///   it is NOT a bearing;
/// * peers whose signal is not currently received sit hollow on the outer ring.
/// Motion runs only when [scanning], [tokens.shouldRotateRadar], and platform
/// accessibility animations allow it.
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

class _RadarScopeState extends State<RadarScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.tokens.radarPeriod);

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

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
    if (widget.scanning &&
        widget.tokens.shouldRotateRadar &&
        !_reduceMotion) {
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
      child: FractionallySizedBox(
        widthFactor: t.radarScopeScale.clamp(0.75, 1.0),
        child: AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(builder: (context, box) {
            final size = box.biggest.shortestSide;
            final radius = math.max(24.0, size / 2 - 20.0);
            return RepaintBoundary(
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, _) => CustomPaint(
                      painter: _ContourScopePainter(
                        tokens: t,
                        progress: _ctrl.value,
                        rotateLight:
                            widget.scanning && t.shouldRotateRadar && !_reduceMotion,
                        showContours: t.showTopoContours,
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
      ),
    );
  }

  Widget _emptyHint(ConvoyDesignTokens t, double size) {
    final fg = t.heroInk.withValues(alpha: 0.78);
    return Positioned(
      left: 16,
      right: 16,
      bottom: size * 0.14,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(t.radiusLarge),
              border: Border.all(
                color: t.heroInk.withValues(alpha: 0.20),
                width: t.borderWidth,
              ),
            ),
            child: Text(
              t.label(widget.scanning
                  ? 'In ascolto nel raggio BLE…'
                  : 'Scansione ferma'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.caption(color: fg, size: 11),
            ),
          ),
        ),
      ),
    );
  }

  Widget _centerMarker(ConvoyDesignTokens t, double size) {
    const d = 22.0;
    return Positioned(
      left: size / 2 - d / 2,
      top: size / 2 - d / 2,
      child: Container(
        width: d,
        height: d,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.heroInk,
          shape: BoxShape.circle,
          border: Border.all(
            color: t.heroInk.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(color: t.heroInk.withValues(alpha: 0.40), blurRadius: 14)
          ],
        ),
        child: Text(
          'IO',
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 7.5,
            fontWeight: FontWeight.w800,
            color: t.accent,
          ),
        ),
      ),
    );
  }

  Widget _blip(
    ConvoyDesignTokens t,
    RadarPeerView p,
    double size,
    double radius,
  ) {
    final r = RadarScope.radiusFractionFor(p) * radius;
    final a = RadarScope.angleFor(p.userId);
    final cx = size / 2 + r * math.cos(a);
    final cy = size / 2 + r * math.sin(a);
    final selected = widget.selectedPeerId == p.userId;
    final d = size < 220 ? 26.0 : (selected ? 36.0 : 31.0);
    final userColor = Color(p.color);

    final dot = AnimatedContainer(
      duration: t.effectiveMotionFast,
      curve: t.motionCurve,
      width: d,
      height: d,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.online ? userColor : Colors.transparent,
        border: Border.all(
          color: p.online
              ? (selected ? t.radarSweep : t.heroInk)
              : t.heroInk.withValues(alpha: 0.72),
          width: selected ? 3.0 : (p.online ? 2.4 : 1.6),
        ),
        boxShadow: p.online
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
          color: p.online ? Colors.white : t.heroInk,
        ),
      ),
    );

    final showLabel = widget.showLabels || selected;
    const labelWidth = 84.0;
    final toLeft = cx > size * 0.56;
    final rawLeft =
        showLabel && toLeft ? cx - d / 2 - labelWidth - 4 : cx - d / 2;
    final totalWidth = showLabel ? d + 4 + labelWidth : d;
    final clampedLeft =
        rawLeft.clamp(2.0, math.max(2.0, size - totalWidth - 2.0)).toDouble();
    final clampedTop =
        (cy - d / 2).clamp(2.0, math.max(2.0, size - d - 2.0)).toDouble();

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
              duration: t.effectiveMotionMedium,
              opacity: p.online ? 1 : 0.78,
              child: dot,
            ),
            if (showLabel && !toLeft) const SizedBox(width: 4),
            if (showLabel && !toLeft)
              _blipLabel(t, p, labelWidth, TextAlign.left),
          ],
        ),
      ),
    );
  }

  Widget _blipLabel(
    ConvoyDesignTokens t,
    RadarPeerView p,
    double width,
    TextAlign align,
  ) {
    final textColor = p.online ? t.radarSweep : t.warning;
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

class _ContourScopePainter extends CustomPainter {
  _ContourScopePainter({
    required this.tokens,
    required this.progress,
    required this.rotateLight,
    required this.showContours,
    required this.radiusInset,
  });

  final ConvoyDesignTokens tokens;
  final double progress;
  final bool rotateLight;
  final bool showContours;
  final double radiusInset;

  @override
  void paint(Canvas canvas, Size size) {
    final t = tokens;
    final c = size.center(Offset.zero);
    final r = math.max(24.0, size.shortestSide / 2 - radiusInset);

    if (rotateLight) {
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

    if (showContours) {
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
            ..color = t.radarGrid
                .withValues(alpha: k == 6 ? 0.55 : (k.isEven ? 0.45 : 0.28)),
        );
      }
    } else {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = t.radarGrid.withValues(alpha: 0.55),
      );
    }

    // Dotted guides for the four BLE RSSI quality buckets.
    for (final f in RadarScope.ringForLevel.skip(1)) {
      _dotted(canvas, c, r * f, t.heroInk.withValues(alpha: 0.22), 2.2, 64);
    }
  }

  void _dotted(
    Canvas canvas,
    Offset c,
    double radius,
    Color color,
    double dot,
    int count,
  ) {
    final p = Paint()..color = color;
    for (var i = 0; i < count; i++) {
      final a = i / count * 2 * math.pi;
      canvas.drawCircle(
          c + Offset(math.cos(a), math.sin(a)) * radius, dot / 2, p);
    }
  }

  @override
  bool shouldRepaint(covariant _ContourScopePainter old) =>
      old.progress != progress ||
      old.rotateLight != rotateLight ||
      old.showContours != showContours ||
      old.tokens != tokens ||
      old.radiusInset != radiusInset;
}
