import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../location/gps_visual_state.dart';
import '../design_tokens.dart';

/// Purely visual wrapper and controls for the Map screen when one of the
/// redesigned directions is active. All map data, trails, circles and markers
/// stay owned by `MapPage`.
class DesignedMapScaffold extends StatelessWidget {
  const DesignedMapScaffold({
    super.key,
    required this.tokens,
    required this.gpsVisual,
    required this.gpsStatusText,
    required this.onlineBasemap,
    required this.peerCountWithFix,
    required this.hasOwnTrail,
    required this.mapChild,
    required this.onLocate,
    required this.onToggleBasemap,
    required this.onClearTrail,
    required this.onChooseDesign,
  });

  final ConvoyDesignTokens tokens;
  final GpsVisualState gpsVisual;
  final String gpsStatusText;
  final bool onlineBasemap;
  final int peerCountWithFix;
  final bool hasOwnTrail;
  final Widget mapChild;
  final VoidCallback onLocate;
  final ValueChanged<bool> onToggleBasemap;
  final VoidCallback onClearTrail;
  final VoidCallback onChooseDesign;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final dark = t.brightness == Brightness.dark;
    final hud = t.layoutStyle == RadarLayoutStyle.hud;

    return Scaffold(
      backgroundColor: t.canvas,
      body: Stack(children: [
        // Offline vector/grid cartographic surface sits beneath FlutterMap so
        // offline sessions look intentional and legible even without tiles.
        Positioned.fill(
          child: CustomPaint(
            painter: _OfflineCartoPainter(tokens: t),
          ),
        ),
        Positioned.fill(child: mapChild),
        // Top floating status bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(t.space(3.5), t.space(2.5), t.space(3.5), 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _GpsStatusPill(
                      tokens: t,
                      gpsVisual: gpsVisual,
                      gpsStatusText: gpsStatusText,
                      peerCountWithFix: peerCountWithFix,
                      onTap: onLocate,
                    ),
                  ),
                  SizedBox(width: t.space(2)),
                  _FloatingCircleButton(
                    key: const Key('map-open-design-btn'),
                    tokens: t,
                    icon: Icons.palette_outlined,
                    tooltip: 'Stili UI e Design Studio',
                    onTap: onChooseDesign,
                  ),
                ],
              ),
            ),
          ),
        ),
        // Bottom one-handed thumb dock
        Positioned(
          left: t.space(3.5),
          right: t.space(3.5),
          bottom: t.space(3.5),
          child: Container(
            padding: EdgeInsets.all(t.space(2.5)),
            decoration: BoxDecoration(
              color: t.surface.withValues(alpha: dark ? 0.94 : 0.96),
              borderRadius: BorderRadius.circular(hud ? t.radiusMedium : t.radiusLarge),
              border: Border.all(color: t.outline, width: t.borderWidth),
              boxShadow: t.elevated ? t.shadow : const [],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Expanded(
                    child: _PrimaryLocateButton(
                      tokens: t,
                      gpsVisual: gpsVisual,
                      onTap: onLocate,
                    ),
                  ),
                  SizedBox(width: t.space(2)),
                  _DockIconButton(
                    tokens: t,
                    icon: Icons.info_outline,
                    tooltip: 'Legenda mappa e mappe offline',
                    onTap: () => _showLegend(context),
                  ),
                  SizedBox(width: t.space(1.5)),
                  _DockIconButton(
                    tokens: t,
                    icon: Icons.delete_outline,
                    tooltip: 'Cancella la mia traccia',
                    destructive: true,
                    enabled: hasOwnTrail,
                    onTap: () => _confirmClearTrail(context),
                  ),
                ]),
                SizedBox(height: t.space(2)),
                Row(children: [
                  Icon(
                    onlineBasemap ? Icons.public : Icons.layers_clear_outlined,
                    size: 16,
                    color: onlineBasemap ? t.accent : t.inkMuted,
                  ),
                  SizedBox(width: t.space(2)),
                  Expanded(
                    child: Text(
                      onlineBasemap
                          ? 'Sfondo OpenStreetMap online'
                          : 'Solo reticolo locale (offline)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body(13, color: t.ink, weight: FontWeight.w600),
                    ),
                  ),
                  Switch.adaptive(
                    value: onlineBasemap,
                    onChanged: onToggleBasemap,
                  ),
                ]),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _showLegend(BuildContext context) {
    final t = tokens;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(t.space(5), 0, t.space(5), t.space(5)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Legenda mappa', style: t.display(22)),
              SizedBox(height: t.space(3)),
              _legendRow(
                icon: Icons.radio_button_unchecked,
                color: t.accent,
                title: 'Cerchi = incertezza GPS stimata',
                subtitle: 'La sovrapposizione dei cerchi non dimostra posizione identica.',
              ),
              SizedBox(height: t.space(2.5)),
              _legendRow(
                icon: Icons.more_horiz,
                color: t.highlight,
                title: 'Tratteggio = percorso recuperato',
                subtitle: 'Punti di traccia ricevuti via HISTORY dopo una riconnessione BLE.',
              ),
              SizedBox(height: t.space(2.5)),
              _legendRow(
                icon: Icons.cloud_off_outlined,
                color: t.inkMuted,
                title: 'Sfondo cartografico online',
                subtitle: 'Senza rete restano coordinate, marker e tracce; non sono mappe offline scaricate.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legendRow({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    final t = tokens;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 22),
      SizedBox(width: t.space(3)),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: t.body(14.5, weight: FontWeight.w700)),
          SizedBox(height: t.space(0.5)),
          Text(subtitle, style: t.body(13, color: t.inkMuted)),
        ]),
      ),
    ]);
  }

  Future<void> _confirmClearTrail(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancellare la tua traccia?'),
        content: const Text(
          'Verranno rimossi i punti della tua traccia visibili in mappa e invalidati eventuali pacchetti HISTORY in coda.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancella traccia'),
          ),
        ],
      ),
    );
    if (confirmed == true) onClearTrail();
  }
}

/// Marker widget adapted to the active aesthetic direction.
class DesignedMapMarker extends StatelessWidget {
  const DesignedMapMarker({
    super.key,
    required this.tokens,
    required this.colour,
    required this.label,
    required this.fresh,
    this.isSelf = false,
  });

  final ConvoyDesignTokens tokens;
  final Color colour;
  final String label;
  final bool fresh;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final hud = t.layoutStyle == RadarLayoutStyle.hud;
    final dark = t.brightness == Brightness.dark;
    return Opacity(
      opacity: fresh ? 1 : 0.62,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colour,
              shape: hud ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: hud ? BorderRadius.circular(6) : null,
              border: Border.all(
                color: dark ? t.canvas : Colors.white,
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              isSelf ? Icons.navigation_rounded : Icons.person,
              color: Colors.white,
              size: 17,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: dark ? t.surface.withValues(alpha: 0.92) : const Color(0xE6141816),
              borderRadius: BorderRadius.circular(hud ? 4 : 10),
              border: Border.all(
                color: dark ? colour.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: t.dataFamily ?? t.bodyFamily,
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsStatusPill extends StatelessWidget {
  const _GpsStatusPill({
    required this.tokens,
    required this.gpsVisual,
    required this.gpsStatusText,
    required this.peerCountWithFix,
    required this.onTap,
  });

  final ConvoyDesignTokens tokens;
  final GpsVisualState gpsVisual;
  final String gpsStatusText;
  final int peerCountWithFix;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final dark = t.brightness == Brightness.dark;
    final tone = gpsVisual.isGreen ? t.positive : t.critical;
    return Material(
      color: t.surface.withValues(alpha: dark ? 0.94 : 0.96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusMedium),
        side: BorderSide(color: t.outline, width: t.borderWidth),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.radiusMedium),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space(3.5), vertical: t.space(2.5)),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(t.radiusSmall),
              ),
              child: Icon(
                gpsVisual.mode == GpsVisualMode.off
                    ? Icons.gps_off
                    : gpsVisual.mode == GpsVisualMode.searching
                        ? Icons.gps_not_fixed
                        : Icons.gps_fixed,
                color: tone,
                size: 19,
              ),
            ),
            SizedBox(width: t.space(2.5)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.label(gpsVisual.label),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.body(13.5, color: tone, weight: FontWeight.w800),
                  ),
                  Text(
                    gpsStatusText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.body(12, color: t.inkMuted),
                  ),
                ],
              ),
            ),
            if (peerCountWithFix > 0) ...[
              SizedBox(width: t.space(2)),
              Container(
                padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1)),
                decoration: BoxDecoration(
                  color: t.surfaceRaised,
                  borderRadius: BorderRadius.circular(t.radiusSmall),
                  border: Border.all(color: t.outline),
                ),
                child: Text(
                  '$peerCountWithFix peer',
                  style: t.data(11.5, color: t.ink, weight: FontWeight.w700),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _PrimaryLocateButton extends StatelessWidget {
  const _PrimaryLocateButton({
    required this.tokens,
    required this.gpsVisual,
    required this.onTap,
  });

  final ConvoyDesignTokens tokens;
  final GpsVisualState gpsVisual;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final hud = t.layoutStyle == RadarLayoutStyle.hud;
    final tone = gpsVisual.isGreen ? t.accent : (hud ? t.accent : t.ink);
    final fg = t.brightness == Brightness.dark ? t.onAccent : Colors.white;
    return Semantics(
      button: true,
      label: '${gpsVisual.label} • tocca per localizzarti',
      child: Material(
        color: tone,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radiusMedium),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.radiusMedium),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: t.minTouchTarget - 4),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: t.space(3.5)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.my_location, color: fg, size: 19),
                SizedBox(width: t.space(2)),
                Flexible(
                  child: Text(
                    t.label(
                      gpsVisual.mode == GpsVisualMode.off ? 'Cerca GPS' : 'Centra su di me',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body(14, color: fg, weight: FontWeight.w800),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockIconButton extends StatelessWidget {
  const _DockIconButton({
    required this.tokens,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.destructive = false,
    this.enabled = true,
  });

  final ConvoyDesignTokens tokens;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool destructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final s = t.minTouchTarget - 4;
    final fg = !enabled
        ? t.inkMuted.withValues(alpha: 0.4)
        : destructive
            ? t.critical
            : t.ink;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: t.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radiusMedium),
          side: BorderSide(color: t.outline, width: t.borderWidth),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.radiusMedium),
          onTap: enabled ? onTap : null,
          child: SizedBox(width: s, height: s, child: Icon(icon, color: fg, size: 21)),
        ),
      ),
    );
  }
}

class _FloatingCircleButton extends StatelessWidget {
  const _FloatingCircleButton({
    super.key,
    required this.tokens,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final ConvoyDesignTokens tokens;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final s = t.minTouchTarget - 6;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: t.surface.withValues(alpha: 0.95),
        shape: CircleBorder(side: BorderSide(color: t.outline, width: t.borderWidth)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: s, height: s, child: Icon(icon, color: t.ink, size: 20)),
        ),
      ),
    );
  }
}

/// Topographic / tactical / minimal offline backdrop grid drawn behind the map.
class _OfflineCartoPainter extends CustomPainter {
  _OfflineCartoPainter({required this.tokens});
  final ConvoyDesignTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final t = tokens;
    canvas.drawRect(Offset.zero & size, Paint()..color = t.canvas);

    final gridColor = t.outline.withValues(alpha: t.brightness == Brightness.dark ? 0.45 : 0.65);
    final minorPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.45)
      ..strokeWidth = 0.8;
    final majorPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.2;

    const step = 36.0;
    for (var x = 0.0, i = 0; x <= size.width; x += step, i++) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), i % 4 == 0 ? majorPaint : minorPaint);
    }
    for (var y = 0.0, j = 0; y <= size.height; y += step, j++) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), j % 4 == 0 ? majorPaint : minorPaint);
    }

    if (t.radarStyle == RadarScopeStyle.contour) {
      // Soft topographic contour bands for offline Outdoor Premium feel.
      final center = Offset(size.width * 0.56, size.height * 0.44);
      for (var k = 1; k <= 5; k++) {
        final r = 55.0 * k;
        final path = Path();
        for (var i = 0; i <= 90; i++) {
          final a = i / 90 * 2 * math.pi;
          final rr = r * (1 + 0.09 * math.sin(2 * a + k) + 0.04 * math.cos(3 * a - k));
          final p = center + Offset(rr * math.cos(a), rr * 0.72 * math.sin(a));
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
            ..strokeWidth = 1.1
            ..color = t.accent.withValues(alpha: 0.14),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OfflineCartoPainter old) => old.tokens != tokens;
}
