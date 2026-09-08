import 'dart:math';
import 'gps_pedestrian_filter.dart';

class GpsObservation {
  const GpsObservation(this.lat, this.lon, this.accuracyM, this.at);
  final double lat, lon, accuracyM;
  final DateTime at;
}

/// Accuracy describes the displayed estimate, never a different rejected fix.
class PositionEstimate {
  const PositionEstimate({
    required this.lat, required this.lon, required this.accuracyM,
    required this.coordinateAt, required this.supportedAt,
    required this.decision, required this.addToTrack,
  });
  final double? lat, lon, accuracyM;
  final DateTime? coordinateAt, supportedAt;
  final String decision;
  final bool addToTrack;
  bool isFreshAt(DateTime now) {
    final t = supportedAt;
    if (lat == null || lon == null || t == null) return false;
    final age = now.difference(t);
    return !age.isNegative && age <= PedestrianPositionEstimator.maxAge;
  }
}

/// Small bounded estimator, not a claim of survey-grade accuracy.
/// Reuses the existing geodesic helper; no GNSS/IMU double integration.
class PedestrianPositionEstimator {
  static const maxAge = Duration(seconds: 15);
  static const windowAge = Duration(seconds: 25);
  static const reacquireAfter = Duration(seconds: 45);
  final List<GpsObservation> _window = [];
  GpsObservation? _anchor;
  DateTime? _supportedAt, _lastInputAt;
  double? _displayAccuracy;

  PositionEstimate snapshot(String decision) => PositionEstimate(
    lat: _anchor?.lat, lon: _anchor?.lon,
    accuracyM: _displayAccuracy,
    coordinateAt: _anchor?.at, supportedAt: _supportedAt,
    decision: decision, addToTrack: false,
  );

  PositionEstimate add(GpsObservation sample, {
    required DateTime receivedAt,
    required bool moving,
    required bool motionReliable,
  }) {
    if (!sample.lat.isFinite || !sample.lon.isFinite ||
        sample.lat.abs() > 90 || sample.lon.abs() > 180 ||
        !sample.accuracyM.isFinite || sample.accuracyM <= 0) {
      return snapshot('invalid_fix');
    }
    final age = receivedAt.difference(sample.at);
    if (age > maxAge || age < const Duration(seconds: -2)) {
      return snapshot('stale_or_future_fix');
    }
    if (_lastInputAt != null && !sample.at.isAfter(_lastInputAt!)) {
      return snapshot('out_of_order_fix');
    }
    _lastInputAt = sample.at;
    if (sample.accuracyM > 120) return snapshot('poor_accuracy');

    final anchor = _anchor;
    final gap = _supportedAt == null ? null : sample.at.difference(_supportedAt!);
    final reacquiring = anchor != null && gap != null && gap > reacquireAfter;
    _window.removeWhere((s) => sample.at.difference(s.at) > windowAge);
    if (anchor != null && !reacquiring) {
      final dt = max(0.1, sample.at.difference(_supportedAt ?? anchor.at).inMilliseconds / 1000);
      final excess = max(0.0, _distance(anchor, sample) -
          max(anchor.accuracyM, _displayAccuracy ?? 0) - sample.accuracyM);
      if (excess > max(20.0, 4.2 * dt + 10)) {
        return snapshot('rejected_jump');
      }
    }
    _window.add(sample);
    if (_window.length > 7) _window.removeAt(0);

    if (anchor == null || reacquiring) {
      final consensus = _consensus();
      if (consensus == null) return snapshot(anchor == null ? 'acquiring' : 'reacquiring');
      return _accept(consensus, sample.at,
          anchor == null ? 'acquired' : 'reacquired', false);
    }

    final gpsWalking = _hasWalkingEvidence();
    if ((!motionReliable || !moving) && !gpsWalking) {
      final consensus = _consensus();
      // One allegedly accurate outlier never moves a stationary anchor.
      if (consensus != null &&
          consensus.accuracyM <= anchor.accuracyM * 0.70 &&
          _distance(anchor, consensus) >= 2) {
        return _accept(consensus, sample.at, 'reanchored_better_cluster', false);
      }
      final d = _distance(anchor, sample);
      if (d > max(12.0, anchor.accuracyM + sample.accuracyM)) {
        return snapshot('stationary_outlier');
      }
      // A recent observation supports the held point, but its uncertainty must
      // cover the displacement; we do NOT assign the raw accuracy to the anchor.
      _displayAccuracy = max(anchor.accuracyM, sample.accuracyM + d);
      _supportedAt = sample.at;
      return snapshot(motionReliable ? 'anchored' : 'anchored_gps_only');
    }

    // Moving, or IMU not currently trustworthy: GPS-only, with outlier gating.
    // A light accuracy-dependent blend limits jitter without long walking lag.
    final gain = sample.accuracyM <= 10 ? 0.85 : sample.accuracyM <= 25 ? 0.65 : 0.45;
    final lat = anchor.lat + gain * (sample.lat - anchor.lat);
    // Shortest longitude delta also handles crossing the dateline.
    final deltaLon = ((sample.lon - anchor.lon + 540) % 360) - 180;
    final lon = ((anchor.lon + gain * deltaLon + 540) % 360) - 180;
    final displayed = GpsObservation(lat, lon,
        max(sample.accuracyM, sample.accuracyM + _distance(
          GpsObservation(lat, lon, sample.accuracyM, sample.at), sample)), sample.at);
    return _accept(displayed, sample.at, motionReliable && moving ? 'walking' : 'gps_motion', true);
  }

  bool _hasWalkingEvidence() {
    if (_window.length < 5) return false;
    final points = _window.sublist(_window.length - 5);
    if (points.last.at.difference(points.first.at) < const Duration(seconds: 15)) return false;
    final accs = points.map((p) => p.accuracyM).toList()..sort();
    final net = _distance(points.first, points.last);
    if (net < max(10.0, accs[2] * 1.5)) return false;

    // Net/path alone accepts a stationary cluster plus ONE distant endpoint:
    // the jump (or the return from it as the window slides) dominates the path.
    // Keep those observations available for consensus/reacquisition, but do not
    // let an isolated jump override a still/unknown IMU and create a false trail.
    // GPS-only motion needs material forward progress in at least 3 of the 4
    // intervals, with no interval accounting for most of the travelled path.
    final minProgress = max(0.5, net * 0.10);
    var path = 0.0;
    var largestStep = 0.0;
    var progressingSteps = 0;
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final step = _distance(previous, current);
      path += step;
      largestStep = max(largestStep, step);
      final progress = _distance(previous, points.last) -
          _distance(current, points.last);
      if (progress >= minProgress) progressingSteps++;
    }
    return progressingSteps >= 3 && path > 0 &&
        largestStep <= path * 0.50 && net / path >= 0.85;
  }

  PositionEstimate _accept(GpsObservation point, DateTime support, String decision, bool track) {
    _anchor = point;
    _displayAccuracy = point.accuracyM;
    _supportedAt = support;
    return PositionEstimate(lat: point.lat, lon: point.lon,
      accuracyM: point.accuracyM, coordinateAt: point.at, supportedAt: support,
      decision: decision, addToTrack: track && point.accuracyM <= 50);
  }

  GpsObservation? _consensus() {
    if (_window.length < 3 || _window.last.at.difference(_window.first.at) < const Duration(seconds: 8)) {
      return null;
    }
    // Spatial medoid first: a singleton claiming 1 m cannot dominate the centre.
    final sorted = [..._window]..sort((a, b) =>
        _window.fold<double>(0, (s, p) => s + _distance(a, p)).compareTo(
        _window.fold<double>(0, (s, p) => s + _distance(b, p))));
    final medoid = sorted.first;
    final accs = _window.map((p) => p.accuracyM).toList()..sort();
    final radius = max(6.0, min(35.0, accs[accs.length ~/ 2] * 1.5));
    final inliers = _window.where((p) => _distance(p, medoid) <= radius).toList();
    if (inliers.length < 3 || inliers.length * 2 <= _window.length ||
        !inliers.contains(_window.last)) return null;
    double weights = 0, lat = 0, lonDelta = 0;
    for (final p in inliers) {
      final weight = 1 / pow(p.accuracyM.clamp(3.0, 30.0), 2);
      weights += weight;
      lat += weight * p.lat;
      lonDelta += weight * (((p.lon - medoid.lon + 540) % 360) - 180);
    }
    final centre = GpsObservation(lat / weights,
        ((medoid.lon + lonDelta / weights + 540) % 360) - 180,
        medoid.accuracyM, _window.last.at);
    final radii = inliers.map((p) => p.accuracyM + _distance(p, centre)).toList()..sort();
    // No sqrt(n) optimism: phone fixes are correlated and may share a bias.
    return GpsObservation(centre.lat, centre.lon, radii[radii.length ~/ 2], centre.at);
  }

  static double _distance(GpsObservation a, GpsObservation b) =>
      PedestrianGpsFilter.distanceMeters(a.lat, a.lon, b.lat, b.lon);
}
