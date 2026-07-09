import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class SelfMapPage extends StatefulWidget {
  const SelfMapPage({super.key});

  @override
  State<SelfMapPage> createState() => _SelfMapPageState();
}

class _SelfMapPageState extends State<SelfMapPage> {
  Position? _position;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() {
          _error = "GPS disattivato";
          _loading = false;
        });
        return;
      }

      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _position = pos;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Mappa")),
        body: Center(child: Text(_error!)),
      );
    }

    final center = LatLng(
      _position!.latitude,
      _position!.longitude,
    );

    return Scaffold(
      appBar: AppBar(title: const Text("La mia posizione")),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: 16,
        ),
        children: [
          TileLayer(
            urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            userAgentPackageName: "convoy_mesh",
          ),
          MarkerLayer(
            markers: [
              Marker(
                width: 50,
                height: 50,
                point: center,
                child: const Icon(
                  Icons.person_pin_circle,
                  size: 40,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
