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
  bool _centeredOnce = false;

  @override
  Widget build(BuildContext context) {
    final mesh = ConvoyMeshService.instance;
    final loc = LocationFusionService.instance;

    return AnimatedBuilder(
      animation: Listenable.merge([mesh, loc]),
      builder: (context, _) {
        final me = mesh.myLast ?? loc.last;
        final meLat = me?.lat;
        final meLon = me?.lon;

        final mePos = (meLat != null && meLon != null) ? LatLng(meLat, meLon) : const LatLng(45.4642, 9.1900);

        if (!_centeredOnce && meLat != null && meLon != null) {
          _centeredOnce = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _map.move(mePos, 16);
          });
        }

        final myTrail = mesh.myTrail;

        final polylines = <Polyline>[];

        // mia traccia
        if (myTrail.length >= 2) {
          polylines.add(
            Polyline(
              points: myTrail.map((p) => LatLng(p.lat, p.lon)).toList(),
              strokeWidth: 4,
              color: Colors.blue.withOpacity(0.65),
            ),
          );
        }

        // tracce peers
        for (final p in mesh.peers.values) {
          if (p.trail.length < 2) continue;
          final c = Color(ConvoyMeshService.colorForUser(p.userId)).withOpacity(0.35);
          polylines.add(
            Polyline(
              points: p.trail.map((t) => LatLng(t.lat, t.lon)).toList(),
              strokeWidth: 4,
              color: c,
            ),
          );
        }

        final markers = <Marker>[];

        // marker io
        if (meLat != null && meLon != null) {
          markers.add(
            Marker(
              width: 46,
              height: 46,
              point: mePos,
              child: _meMarker(),
            ),
          );
        }

        // marker peers
        for (final p in mesh.peers.values) {
          if (p.lat == null || p.lon == null) continue;
          final c = Color(ConvoyMeshService.colorForUser(p.userId));
          final label = (p.name != null && p.name!.trim().isNotEmpty) ? p.name! : "User ${p.userId}";
          markers.add(
            Marker(
              width: 90,
              height: 60,
              point: LatLng(p.lat!, p.lon!),
              child: _peerMarker(c, label),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text("Mappa"),
            actions: [
              IconButton(
                onPressed: () {
                  if (meLat != null && meLon != null) _map.move(mePos, _map.camera.zoom);
                },
                icon: const Icon(Icons.my_location),
              ),
              IconButton(
                onPressed: () => mesh.clearMyTrail(),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: mePos,
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.convoy_mesh',
              ),
              if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
              if (markers.isNotEmpty) MarkerLayer(markers: markers),
            ],
          ),
        );
      },
    );
  }

  Widget _meMarker() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: const Icon(Icons.person_pin_circle, color: Colors.white),
    );
  }

  Widget _peerMarker(Color c, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Icon(Icons.person, color: Colors.white, size: 18),
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ),
      ],
    );
  }
}
