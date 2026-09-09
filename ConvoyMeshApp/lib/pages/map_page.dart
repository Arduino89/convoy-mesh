import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/convoy_mesh_service.dart';
import '../services/location_fusion_service.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _map = MapController();
  bool _centered = false, _onlineBasemap = true;

  @override
  Widget build(BuildContext context) {
    final mesh = ConvoyMeshService.instance;
    final loc = LocationFusionService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([mesh, loc]),
      builder: (context, _) {
        final me = mesh.myLast;
        final mePos = me?.lat != null && me?.lon != null ? LatLng(me!.lat!, me.lon!) : null;
        final myFresh = me?.hasFreshFixAt(DateTime.now()) ?? false;
        final centre = mePos ?? const LatLng(45.25, 10.75);
        if (!_centered && mePos != null) {
          _centered = true;
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

        void addPeerTrail(List<PeerPoint> source, Color colour) {
          if (source.length < 2) return;
          final points = [...source]..sort((a, b) => a.ts.compareTo(b.ts));
          for (var i = 1; i < points.length; i++) {
            final a = points[i - 1];
            final b = points[i];
            // Sender-side GPS reacquisition intentionally starts a new segment.
            if (a.segment != b.segment && !a.recovered && !b.recovered) continue;
            final pair = [LatLng(a.lat, a.lon), LatLng(b.lat, b.lon)];
            final recovered = a.recovered || b.recovered;
            if (recovered) {
              lines.add(Polyline(
                points: pair,
                strokeWidth: 3,
                color: colour.withOpacity(0.65),
                pattern: StrokePattern.dashed(segments: const [10, 7]),
              ));
            } else {
              lines.add(Polyline(
                points: pair,
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

        return Scaffold(
          appBar: AppBar(
            title: const Text('Mappa'),
            actions: [
              IconButton(
                tooltip: 'Centra sulla mia posizione',
                onPressed: mePos == null ? null : () => _map.move(mePos, _map.camera.zoom),
                icon: const Icon(Icons.my_location),
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
                  mePos == null
                      ? 'Aggancio GPS in corso. Nessuna posizione affidabile da mostrare.'
                      : 'Cerchi = incertezza stimata. ${myFresh ? 'Mia misura recente.' : 'Mia misura non aggiornata: ${ConvoyMeshService.ageLabel(me?.measurementAt)}.'} Tratteggio = percorso recuperato dopo una riconnessione.',
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
