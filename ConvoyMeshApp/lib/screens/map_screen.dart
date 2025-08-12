import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/location_service.dart';
import '../services/ble_service.dart';

class MapScreen extends StatefulWidget {
  final String roomCode;
  final bool isLeader;
  const MapScreen({super.key, required this.roomCode, required this.isLeader});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  late final LocationService _loc;
  late final BleMeshService _ble;
  bool _trekMode = false;
  LatLng? _myPos;
  StreamSubscription<Position>? _locSub;
  StreamSubscription<List<PeerPosition>>? _peerSub;
  List<PeerPosition> _peers = [];

  @override
  void initState() {
    super.initState();
    _loc = LocationService();
    _ble = BleMeshService();
    _init();
  }

  Future<void> _init() async {
    await _askPerms();
    await _loc.ensurePermission();
    await _loc.start(seconds: 5);
    _locSub = _loc.stream.listen((p) {
      setState(() {
        _myPos = LatLng(p.latitude, p.longitude);
      });
      _ble.broadcastSelf(p.latitude, p.longitude);
    });
    await _ble.joinRoom(widget.roomCode);
    _peerSub = _ble.peersStream.listen((list) {
      setState(() {
        _peers = list;
      });
    });
  }

  Future<void> _askPerms() async {
    await Permission.location.request();
    await Permission.bluetooth.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothAdvertise.request();
    await Permission.bluetoothConnect.request();
  }

  @override
  void dispose() {
    _locSub?.cancel();
    _peerSub?.cancel();
    _loc.dispose();
    _ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];
    if (_myPos != null) {
      markers.add(Marker(
        width: 40, height: 40, point: _myPos!,
        child: const Icon(Icons.my_location, size: 36),
      ));
    }
    for (final p in _peers) {
      markers.add(Marker(
        width: 40, height: 40, point: LatLng(p.lat, p.lon),
        child: Tooltip(
          message: 'Nodo ${p.nodeId} • hop ${p.hops}',
          child: const Icon(Icons.location_on, size: 36),
        ),
      ));
    }

    final center = _myPos ?? (_peers.isNotEmpty ? LatLng(_peers.first.lat, _peers.first.lon) : const LatLng(45.156, 10.792));
    return Scaffold(
      appBar: AppBar(
        title: Text('Stanza ${widget.roomCode}${widget.isLeader ? " • Capofila" : ""}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 14,
                onTap: (_, __){},
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.example.convoy_mesh_app',
                ),
                MarkerLayer(markers: markers),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.directions_walk),
                      label: Text(_trekMode ? 'Trekking (attivo)' : 'Trekking (attiva)'),
                      onPressed: () => setState(()=> _trekMode = !_trekMode),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.pause_circle),
                      label: const Text('Pausa condivisione'),
                      onPressed: () {
                        _loc.stop();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
