import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

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
  bool _centered = false, _onlineBasemap = true, _centerOnNextFresh = false;

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
      await loc.start();
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
      animation: Listenable.merge([mesh, loc]),
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
            color: colour.withOpacity(fresh ? 0.12 : 0.04),
            borderColor: colour.withOpacity(0.45),
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
                color: colour.withOpacity(0.5),
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
              color: colour.withOpacity(0.65),
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
                color: colour.withOpacity(0.5),
              ));
            }
          }
        }

        addOwnTrail(mesh.myTrail, Colors.blue);
        if (mePos != null) {
          circle(mePos, me!.accuracyM, Colors.blue, myFresh);
          markers.add(Marker(
            point: mePos,
            width: 110,
            height: 60,
            child: _marker(Colors.blue, myFresh ? 'Io' : 'Io • ultima nota', myFresh),
          ));
        }

        for (final p in mesh.peers.values) {
          final colour = Color(ConvoyMeshService.colorForUser(p.userId));
          addPeerTrail(p.trail, colour);
          if (!p.hasFix) continue;
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
            child: _marker(colour, fresh ? name : '$name • $age', fresh),
          ));
        }

        final gpsText = switch (gpsVisual.mode) {
          GpsVisualMode.off => 'GPS non agganciato. Tocca il mirino per cercare la posizione.',
          GpsVisualMode.searching => 'Ricerca GPS in corso…',
          GpsVisualMode.stable => '${gpsVisual.label}. Incertezza ±${(me?.accuracyM ?? 0).toStringAsFixed(0)} m.',
          GpsVisualMode.unstable => '${gpsVisual.label}. Incertezza ±${(me?.accuracyM ?? 0).toStringAsFixed(0)} m.',
        };

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
              Expanded(
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(initialCenter: centre, initialZoom: 15),
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
                      const Align(
                        alignment: Alignment.bottomRight,
                        child: ColoredBox(
                          color: Colors.white,
                          child: Padding(
                            padding: EdgeInsets.all(3),
                            child: Text(
                              '© OpenStreetMap contributors',
                              style: TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _marker(Color colour, String label, bool fresh) => Opacity(
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
  void initState() {
    super.initState();
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
    final period = widget.state.blinkPeriod;
    if (period == null) {
      _controller.stop();
      _controller.value = 1;
      return;
    }
    _controller.duration = period;
    _controller.repeat(reverse: true);
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
