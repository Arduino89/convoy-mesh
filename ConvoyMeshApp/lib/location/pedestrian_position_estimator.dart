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
    required this.lat,
    required this.lon,
    required this.accuracyM,
    required this.coordinateAt,
    required this.supportedAt,
    required this.decision,
    required this.addToTrack,
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
  GpsObservation? _origin;
  DateTime? _supportedAt, _lastInputAt;
  double? _displayAccuracy;

  // Loop-closure evidence is intentionally tiny and bounded. It is only used
  // after real accepted movement away from the outing origin.
  double _maxAcceptedExcursionFromOriginM = 0;
  double? _previousRawDistanceToOriginM;
  int _originReturnEvidence = 0;

  PositionEstimate snapshot(String decision) => PositionEstimate(
        lat: _anchor?.lat,
        lon: _anchor?.lon,
        accuracyM: _displayAccuracy,
        coordinateAt: _anchor?.at,
        supportedAt: _supportedAt,
        decision: decision,
        addToTrack: false,
      );

  PositionEstimate add(
    GpsObservation sample, {
    required DateTime receivedAt,
    required bool moving,
    required bool motionReliable,
  }) {
    if (!sample.lat.isFinite ||
        !sample.lon.isFinite ||
        sample.lat.abs() > 90 ||
        sample.lon.abs() > 180 ||
        !sample.accuracyM.isFinite ||
        sample.accuracyM <= 0) {
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
      final dt = max(
        0.1,
        sample.at.difference(_supportedAt ?? anchor.at).inMilliseconds / 1000,
      );
      final excess = max(
        0.0,
        _distance(anchor, sample) -
            max(anchor.accuracyM, _displayAccuracy ?? 0) -
            sample.accuracyM,
      );
      if (excess > max(20.0, 4.2 * dt + 10)) {
        return snapshot('rejected_jump');
      }
    }

    _window.add(sample);
    if (_window.length > 7) _window.removeAt(0);

    if (anchor == null || reacquiring) {
      final consensus = _consensus();
      if (consensus == null) {
        return snapshot(anchor == null ? 'acquiring' : 'reacquiring');
      }
      final result = _accept(
        consensus,
        sample.at,
        anchor == null ? 'acquired' : 'reacquired',
        false,
      );
      if (_origin == null) {
        _origin = GpsObservation(
          consensus.lat,
          consensus.lon,
          consensus.accuracyM,
          consensus.at,
        );
      }
      return result;
    }

    final gpsWalking = _hasWalkingEvidence();

    // Before applying the normal moving/stationary update, check whether a
    // completed excursion is coherently returning inside the uncertainty region
    // of the outing origin. This is NOT an arbitrary snap-to-start: it requires
    // accepted movement away from origin, uncertainty overlap and at least two
    // consecutive approaching raw fixes. It addresses the common phone-GNSS
    // behaviour where the same physical point is reported 10-20 m apart before
    // and after a short loop.
    final closed = _maybeCloseOrigin(sample);
    if (closed != null) return closed;

    if ((!motionReliable || !moving) && !gpsWalking) {
      final consensus = _consensus();
      // One allegedly accurate outlier never moves a stationary anchor.
      if (consensus != null &&
          consensus.accuracyM <= anchor.accuracyM * 0.70 &&
          _distance(anchor, consensus) >= 2) {
        return _accept(
          consensus,
          sample.at,
          'reanchored_better_cluster',
          false,
        );
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
    final gain = sample.accuracyM <= 10
        ? 0.85
        : sample.accuracyM <= 25
            ? 0.65
            : 0.45;
    final lat = anchor.lat + gain * (sample.lat - anchor.lat);
    // Shortest longitude delta also handles crossing the dateline.
    final deltaLon = ((sample.lon - anchor.lon + 540) % 360) - 180;
    final lon = ((anchor.lon + gain * deltaLon + 540) % 360) - 180;
    final displayed = GpsObservation(
      lat,
      lon,
      max(
        sample.accuracyM,
        sample.accuracyM +
            _distance(
              GpsObservation(lat, lon, sample.accuracyM, sample.at),
              sample,
            ),
      ),
      sample.at,
    );
    return _accept(
      displayed,
      sample.at,
      motionReliable && moving ? 'walking' : 'gps_motion',
      true,
    );
  }

  PositionEstimate? _maybeCloseOrigin(GpsObservation sample) {
    final origin = _origin;
    final anchor = _anchor;
    if (origin == null || anchor == null) return null;

    final distanceToOrigin = _distance(origin, sample);
    final previousDistance = _previousRawDistanceToOriginM;
    _previousRawDistanceToOriginM = distanceToOrigin;

    // RSS/GNSS "accuracy" values are radii/uncertainty estimates, not truth.
    // Use root-sum-square to test whether the start and current measurement
    // regions plausibly overlap, then cap the gate to avoid huge poor-GPS snaps.
    final combinedUncertainty = sqrt(
      origin.accuracyM * origin.accuracyM +
          sample.accuracyM * sample.accuracyM,
    );
    final closureGateM = max(8.0, min(25.0, combinedUncertainty * 1.15));
    final excursionRequiredM = max(15.0, closureGateM * 1.15);

    if (_maxAcceptedExcursionFromOriginM < excursionRequiredM) {
      _originReturnEvidence = 0;
      return null;
    }

    final approaching = previousDistance == null ||
        distanceToOrigin <= previousDistance + 2.0;
    final insideGate = distanceToOrigin <= closureGateM;

    if (insideGate && approaching) {
      _originReturnEvidence++;
    } else if (distanceToOrigin > closureGateM * 1.5) {
      _originReturnEvidence = 0;
    } else if (!approaching && _originReturnEvidence > 0) {
      _originReturnEvidence--;
    }

    if (_originReturnEvidence < 2) return null;

    // Require that the recent raw window also contains at least two samples
    // compatible with the origin. This prevents one low-accuracy endpoint from
    // closing the loop by itself.
    final recentNearOrigin = _window
        .where((p) {
          final combined = sqrt(
            origin.accuracyM * origin.accuracyM +
                p.accuracyM * p.accuracyM,
          );
          final gate = max(8.0, min(25.0, combined * 1.15));
          return _distance(origin, p) <= gate;
        })
        .length;
    if (recentNearOrigin < 2) return null;

    final inferredAccuracy = max(
      origin.accuracyM,
      max(sample.accuracyM, distanceToOrigin),
    );
    final reconciled = GpsObservation(
      origin.lat,
      origin.lon,
      inferredAccuracy,
      sample.at,
    );

    _originReturnEvidence = 0;
    _maxAcceptedExcursionFromOriginM = 0;
    _previousRawDistanceToOriginM = 0;

    return _accept(
      reconciled,
      sample.at,
      'loop_closed_origin',
      true,
    );
  }

  bool _hasWalkingEvidence() {
    if (_window.length < 5) return false;
    final points = _window.sublist(_window.length - 5);
    if (points.last.at.difference(points.first.at) < const Duration(seconds: 15)) {
      return false;
    }
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
    return progressingSteps >= 3 &&
        path > 0 &&
        largestStep <= path * 0.50 &&
        net / path >= 0.85;
  }

  PositionEstimate _accept(
    GpsObservation point,
    DateTime support,
    String decision,
    bool track,
  ) {
    _anchor = point;
    _displayAccuracy = point.accuracyM;
    _supportedAt = support;

    final origin = _origin;
    if (origin != null && track && decision != 'loop_closed_origin') {
      _maxAcceptedExcursionFromOriginM = max(
        _maxAcceptedExcursionFromOriginM,
        _distance(origin, point),
      );
    }

    return PositionEstimate(
      lat: point.lat,
      lon: point.lon,
      accuracyM: point.accuracyM,
      coordinateAt: point.at,
      supportedAt: support,
      decision: decision,
      addToTrack: track && point.accuracyM <= 50,
    );
  }

  GpsObservation? _consensus() {
    if (_window.length < 3 ||
        _window.last.at.difference(_window.first.at) <
            const Duration(seconds: 8)) {
      return null;
    }

    // Spatial medoid first: a singleton claiming 1 m cannot dominate the centre.
    final sorted = [..._window]
      ..sort(
        (a, b) => _window
            .fold<double>(0, (s, p) => s + _distance(a, p))
            .compareTo(
              _window.fold<double>(0, (s, p) => s + _distance(b, p)),
            ),
      );
    final medoid = sorted.first;
    final accs = _window.map((p) => p.accuracyM).toList()..sort();
    final radius = max(6.0, min(35.0, accs[accs.length ~/ 2] * 1.5));
    final inliers = _window.where((p) => _distance(p, medoid) <= radius).toList();
    if (inliers.length < 3 ||
        inliers.length * 2 <= _window.length ||
        !inliers.contains(_window.last)) {
      return null;
    }

    double weights = 0, lat = 0, lonDelta = 0;
    for (final p in inliers) {
      final weight = 1 / pow(p.accuracyM.clamp(3.0, 30.0), 2);
      weights += weight;
      lat += weight * p.lat;
      lonDelta += weight * (((p.lon - medoid.lon + 540) % 360) - 180);
    }

    final centre = GpsObservation(
      lat / weights,
      ((medoid.lon + lonDelta / weights + 540) % 360) - 180,
      medoid.accuracyM,
      _window.last.at,
    );
    final radii = inliers
        .map((p) => p.accuracyM + _distance(p, centre))
        .toList()
      ..sort();

    // No sqrt(n) optimism: phone fixes are correlated and may share a bias.
    return GpsObservation(
      centre.lat,
      centre.lon,
      radii[radii.length ~/ 2],
      centre.at,
    );
  }

  static double _distance(GpsObservation a, GpsObservation b) =>
      PedestrianGpsFilter.distanceMeters(a.lat, a.lon, b.lat, b.lon);
}
