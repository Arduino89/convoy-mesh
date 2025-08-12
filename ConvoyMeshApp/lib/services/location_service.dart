import 'dart:async';
import 'package:geolocator/geolocator.dart';

class LocationService {
  final _controller = StreamController<Position>.broadcast();
  Stream<Position> get stream => _controller.stream;

  Future<bool> ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  StreamSubscription<Position>? _sub;

  Future<void> start({int seconds=5}) async {
    await stop();
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3),
    ).listen((pos) {
      _controller.add(pos);
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    _controller.close();
  }
}
