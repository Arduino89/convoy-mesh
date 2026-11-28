import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../design/design_direction_picker.dart';
import '../design/design_tokens.dart';
import '../design/map/designed_map_chrome.dart';
import '../location/gps_visual_state.dart';
import '../services/convoy_mesh_service.dart';
import '../services/location_fusion_service.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _map = MapController();
  // Both styles host the same live map, even though their chrome differs.
  // Reparent its state in the same frame instead of remounting the camera.
  final _mapKey = GlobalKey();
  late final Listenable _mergedListenable;
  bool _centered = false, _onlineBasemap = true, _centerOnNextFresh = false;

  @override
  void initState() {
    super.initState();
    _mergedListenable = Listenable.merge([
      ConvoyMeshService.instance,
      LocationFusionService.instance,
    ]);
  }

  Future<void> _locate(ConvoyMeshService mesh, LocationFusionService loc) async {
    _centerOnNextFresh = true;
    if (!mesh.isOutingActive) {
      final permission = await ph.Permission.locationWhenInUse.request();
      if (!permission.isGranted) {
        _centerOnNextFresh = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Concedi il permesso Posizione per cercare il GPS.')),
          );
        }
        return;
      }
      if (!mounted) return;
      await loc.startPreview();
    }

    if (!mounted) return;
    final fix = loc.last;
    if (fix?.serviceEnabled == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attiva la Posizione del telefono per cercare il GPS.')),
      );
      return;
    }
    if (fix?.hasFreshFixAt(DateTime.now()) == true && fix?.lat != null && fix?.lon != null) {
      _centerOnNextFresh = false;
      _map.move(LatLng(fix!.lat!, fix.lon!), _map.camera.zoom);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final mesh = ConvoyMeshService.instance;
    final loc = LocationFusionService.instance;
    return AnimatedBuilder(
      animation: _mergedListenable,
      builder: (context, _) {
        final me = mesh.myLast;
        final now = DateTime.now();
        final mePos = me?.lat != null && me?.lon != null ? LatLng(me!.lat!, me.lon!) : null;
        final myFresh = me?.hasFreshFixAt(now) ?? false;
        final gpsVisual = GpsVisualState.from(loc.last, now);
        final centre = mePos ?? const LatLng(45.25, 10.75);
        if ((!_centered || _centerOnNextFresh) && myFresh && mePos != null) {
          _centered = true;
          _centerOnNextFresh = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _map.move(mePos, 16);
          });
        }

        final markers = <Marker>[];
        final circles = <CircleMarker>[];
        final lines = <Polyline>[];

        void circle(LatLng position, double? accuracy, Color colour, bool fresh) {
          if (accuracy == null || !accuracy.isFinite || accuracy <= 0 || accuracy > 500) return;
          circles.add(CircleMarker(
            point: position,
            radius: accuracy,
            useRadiusInMeter: true,
            color: colour.withValues(alpha: fresh ? 0.12 : 0.04),
            borderColor: colour.withValues(alpha: 0.45),
            borderStrokeWidth: 1,
          ));
        }

        void addOwnTrail(List<PeerPoint> points, Color colour) {
          final segments = <int, List<LatLng>>{};
          for (final p in points) {
            segments.putIfAbsent(p.segment, () => []).add(LatLng(p.lat, p.lon));
          }
          for (final segment in segments.values) {
            if (segment.length >= 2) {
              lines.add(Polyline(
                points: segment,
                strokeWidth: 3,
                color: colour.withValues(alpha: 0.5),
              ));
            }
          }
        }

        void addDashedPair(LatLng a, LatLng b, Color colour) {
          // flutter_map 6.2.1 has no StrokePattern API. Split each recovered
          // link into short physical polyline pieces instead of upgrading the
          // mapping dependency during a reliability pass.
          const pieces = 12;
          for (var i = 0; i < pieces; i += 2) {
            final t0 = i / pieces;
            final t1 = (i + 1) / pieces;
            final p0 = LatLng(
              a.latitude + (b.latitude - a.latitude) * t0,
              a.longitude + (b.longitude - a.longitude) * t0,
            );
            final p1 = LatLng(
              a.latitude + (b.latitude - a.latitude) * t1,
              a.longitude + (b.longitude - a.longitude) * t1,
            );
            lines.add(Polyline(
              points: [p0, p1],
              strokeWidth: 3,
              color: colour.withValues(alpha: 0.65),
            ));
          }
        }

        void addPeerTrail(List<PeerPoint> source, Color colour) {
          if (source.length < 2) return;
          final points = [...source]..sort((a, b) => a.ts.compareTo(b.ts));
          for (var i = 1; i < points.length; i++) {
            final a = points[i - 1];
            final b = points[i];
            final timeGap = b.ts.difference(a.ts);
            // Missing HISTORY packets must remain a visible gap, not a made-up
            // straight line spanning a long period with no observations.
            if (timeGap.isNegative || timeGap > const Duration(seconds: 30)) continue;
            if (a.segment != b.segment && !a.recovered && !b.recovered) continue;
            final start = LatLng(a.lat, a.lon);
            final end = LatLng(b.lat, b.lon);
            final recovered = a.recovered || b.recovered;
            if (recovered) {
              addDashedPair(start, end, colour);
            } else {
              lines.add(Polyline(
                points: [start, end],
                strokeWidth: 3,
                color: colour.withValues(alpha: 0.5),
              ));
            }
          }
        }

        final tokens = ConvoyDesignTokens.maybeOf(context);
        final selfColor = tokens != null ? tokens.accent : Colors.blue;
        addOwnTrail(mesh.myTrail, selfColor);
        if (mePos != null) {
          circle(mePos, me!.accuracyM, selfColor, myFresh);
          markers.add(Marker(
            point: mePos,
            width: 132,
            height: 60,
            child: _marker(
              tokens,
              selfColor,
              myFresh ? 'Io' : 'Io • ultima nota',
              myFresh,
              isSelf: true,
            ),
          ));
        }

        var peerWithFixCount = 0;
        for (final p in mesh.peers.values) {
          final colour = Color(ConvoyMeshService.colorForUser(p.userId));
          addPeerTrail(p.trail, colour);
          if (!p.hasFix) continue;
          peerWithFixCount++;
          final position = LatLng(p.lat!, p.lon!);
          final fresh = p.hasFreshFix && p.lastFixMeasuredAt != null;
          circle(position, p.accuracyM, colour, fresh);
          final name = p.name?.trim().isNotEmpty == true ? p.name! : 'User ${p.userId}';
          final age = p.lastFixMeasuredAt == null
              ? 'età GPS ignota'
              : ConvoyMeshService.ageLabel(p.lastFixMeasuredAt);
          markers.add(Marker(
            point: position,
            width: 150,
            height: 60,
            child: _marker(
              tokens,
              colour,
              fresh ? name : '$name • $age',
              fresh,
            ),
          ));
        }

        final gpsText = switch (gpsVisual.mode) {
          GpsVisualMode.off => 'GPS non agganciato. Tocca il mirino per cercare la posizione.',
          GpsVisualMode.searching => 'Ricerca GPS in corso…',
          GpsVisualMode.stable => '${gpsVisual.label}. Incertezza ±${(me?.accuracyM ?? 0).toStringAsFixed(0)} m.',
          GpsVisualMode.unstable => '${gpsVisual.label}. Incertezza ±${(me?.accuracyM ?? 0).toStringAsFixed(0)} m.',
        };

        final flutterMap = FlutterMap(
          key: _mapKey,
          mapController: _map,
          options: MapOptions(
            initialCenter: centre,
            initialZoom: 15,
            backgroundColor: tokens != null ? Colors.transparent : const Color(0xFFE0E0E0),
          ),
          children: [
            if (_onlineBasemap)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.convoy_mesh',
              ),
            if (circles.isNotEmpty) CircleLayer(circles: circles),
            if (lines.isNotEmpty) PolylineLayer(polylines: lines),
            if (markers.isNotEmpty) MarkerLayer(markers: markers),
            if (_onlineBasemap)
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: tokens != null
                        ? math.max(138.0, tokens.minTouchTarget + 94.0)
                        : 0,
                    right: tokens != null ? tokens.hPad * 0.78 : 0,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    decoration: BoxDecoration(
                      color: tokens != null
                          ? tokens.surface.withValues(alpha: 0.92)
                          : Colors.white,
                      borderRadius: tokens != null
                          ? BorderRadius.circular((tokens.radiusSmall * 0.5).clamp(4, 8))
                          : BorderRadius.zero,
                      border: tokens != null
                          ? Border.all(color: tokens.outline, width: 0.8)
                          : null,
                    ),
                    child: Text(
                      '© OpenStreetMap contributors',
                      style: TextStyle(
                        fontSize: 10,
                        color: tokens != null ? tokens.inkMuted : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );

        if (tokens != null) {
          return DesignedMapScaffold(
            tokens: tokens,
            gpsVisual: gpsVisual,
            gpsStatusText: gpsText,
            onlineBasemap: _onlineBasemap,
            peerCountWithFix: peerWithFixCount,
            hasOwnTrail: mesh.myTrail.isNotEmpty,
            mapChild: flutterMap,
            onLocate: () => _locate(mesh, loc),
            onToggleBasemap: (v) => setState(() => _onlineBasemap = v),
            onClearTrail: mesh.clearMyTrail,
            onChooseDesign: () => showDesignDirectionPicker(context),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Mappa'),
            actions: [
              IconButton(
                tooltip: '${gpsVisual.label} • tocca per localizzarti',
                onPressed: () => _locate(mesh, loc),
                icon: _GpsStatusIcon(state: gpsVisual),
              ),
              IconButton(
                tooltip: 'Cancella la mia traccia',
                onPressed: mesh.clearMyTrail,
                icon: const Icon(Icons.delete_outline),
              ),
              IconButton(
                key: const Key('map-open-design-btn'),
                tooltip: 'Personalizza Outdoor Premium o torna a Originale',
                onPressed: () => showDesignDirectionPicker(context),
                icon: const Icon(Icons.palette_outlined),
              ),
            ],
          ),
          body: Column(
            children: [
              SwitchListTile(
                dense: true,
                title: const Text('Sfondo cartografico online'),
                subtitle: const Text(
                  'Senza rete restano coordinate, marker e tracce; non sono mappe offline scaricate.',
                ),
                value: _onlineBasemap,
                onChanged: (v) => setState(() => _onlineBasemap = v),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '$gpsText Cerchi = incertezza stimata. Tratteggio = percorso recuperato dopo una riconnessione.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Expanded(child: flutterMap),
            ],
          ),
        );
      },
    );
  }

  Widget _marker(
    ConvoyDesignTokens? tokens,
    Color colour,
    String label,
    bool fresh, {
    bool isSelf = false,
  }) {
    if (tokens != null) {
      return DesignedMapMarker(
        tokens: tokens,
        colour: colour,
        label: label,
        fresh: fresh,
        isSelf: isSelf,
      );
    }
    return Opacity(
      opacity: fresh ? 1 : 0.55,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colour,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsStatusIcon extends StatefulWidget {
  const _GpsStatusIcon({required this.state});

  final GpsVisualState state;

  @override
  State<_GpsStatusIcon> createState() => _GpsStatusIconState();
}

class _GpsStatusIconState extends State<_GpsStatusIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  late final Animation<double> _opacity = Tween<double>(begin: 0.35, end: 1).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(covariant _GpsStatusIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.mode != widget.state.mode ||
        oldWidget.state.blinkPeriod != widget.state.blinkPeriod) {
      _configure();
    }
  }

  void _configure() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final period = widget.state.blinkPeriod;
    if (period == null || reduceMotion) {
      _controller.stop();
      _controller.value = 1;
      return;
    }
    _controller.duration = period;
    if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colour = widget.state.isGreen ? Colors.green : Colors.red;
    return FadeTransition(
      opacity: _opacity,
      child: Icon(Icons.my_location, color: colour),
    );
  }
}
