import 'package:latlong2/latlong.dart';

class TrackPoint {
  final LatLng latLng;
  final DateTime ts;
  final double accuracyM;

  TrackPoint({
    required this.latLng,
    required this.ts,
    required this.accuracyM,
  });
}

class SelfTrack {
  final List<TrackPoint> points = [];

  void clear() => points.clear();

  void add(TrackPoint p) => points.add(p);
}
