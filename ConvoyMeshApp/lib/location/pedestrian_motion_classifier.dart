class PedestrianMotionUpdate {
  const PedestrianMotionUpdate({
    required this.moving,
    required this.score,
    required this.changed,
    required this.reason,
  });

  final bool moving;
  final double score;
  final bool changed;
  final String reason;
}

/// Stateful pedestrian IMU classifier tuned for a phone carried while walking.
///
/// The old single-threshold hysteresis could repeatedly flip still/moving when
/// the EMA crossed its limits for only an instant. This classifier has three
/// independent evidences:
/// - strong motion: short confirmation;
/// - weak but sustained motion: catches slow walking;
/// - sustained quiet: the only way to return to still.
///
/// It deliberately does not integrate acceleration into distance.
class PedestrianMotionClassifier {
  static const double strongMoveThreshold = 0.50;
  static const double slowMoveThreshold = 0.30;
  static const double quietThreshold = 0.18;
  static const strongMoveHold = Duration(milliseconds: 800);
  static const slowMoveHold = Duration(milliseconds: 3500);
  static const quietHold = Duration(seconds: 5);
  static const reliableMaxAge = Duration(seconds: 3);

  bool _moving = false;
  bool _hasScore = false;
  double _score = 0;
  int _samples = 0;
  Duration? _lastSampleAt;
  Duration? _strongSince;
  Duration? _slowSince;
  Duration? _quietSince;

  bool get moving => _moving;
  double get score => _score;
  int get samples => _samples;
  Duration? get lastSampleAt => _lastSampleAt;

  bool isReliableAt(Duration now) =>
      _samples >= 5 &&
      _lastSampleAt != null &&
      now >= _lastSampleAt! &&
      now - _lastSampleAt! <= reliableMaxAge;

  PedestrianMotionUpdate addSample(double magnitude, Duration now) {
    if (!magnitude.isFinite || magnitude < 0) {
      return PedestrianMotionUpdate(
        moving: _moving,
        score: _score,
        changed: false,
        reason: 'invalid_sample',
      );
    }

    _lastSampleAt = now;
    _samples = (_samples + 1).clamp(0, 1000000);
    _score = _hasScore ? _score * 0.85 + magnitude * 0.15 : magnitude;
    _hasScore = true;

    final before = _moving;
    var reason = 'steady';

    if (!_moving) {
      _quietSince = null;
      if (_score >= strongMoveThreshold) {
        _strongSince ??= now;
        _slowSince ??= now;
        if (now - _strongSince! >= strongMoveHold) {
          _moving = true;
          reason = 'strong_motion_sustained';
        }
      } else {
        _strongSince = null;
        if (_score >= slowMoveThreshold) {
          _slowSince ??= now;
        } else {
          _slowSince = null;
        }
      }

      if (!_moving &&
          _slowSince != null &&
          now - _slowSince! >= slowMoveHold) {
        _moving = true;
        reason = 'slow_motion_sustained';
      }
    } else {
      _strongSince = null;
      _slowSince = null;
      if (_score <= quietThreshold) {
        _quietSince ??= now;
        if (now - _quietSince! >= quietHold) {
          _moving = false;
          reason = 'quiet_sustained';
        }
      } else {
        _quietSince = null;
      }
    }

    if (_moving != before) {
      // Do not carry partially satisfied evidence across a state transition.
      _strongSince = null;
      _slowSince = null;
      _quietSince = null;
    }

    return PedestrianMotionUpdate(
      moving: _moving,
      score: _score,
      changed: _moving != before,
      reason: reason,
    );
  }

  void reset() {
    _moving = false;
    _hasScore = false;
    _score = 0;
    _samples = 0;
    _lastSampleAt = null;
    _strongSince = null;
    _slowSince = null;
    _quietSince = null;
  }
}
