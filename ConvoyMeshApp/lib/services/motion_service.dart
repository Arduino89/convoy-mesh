import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

enum MotionState { unknown, stationary, moving }

class MotionService {
  MotionService({
    this.stationaryThreshold = 0.35,
    this.movingThreshold = 0.75,
    this.window = const Duration(seconds: 2),
    this.minHold = const Duration(milliseconds: 1200),
  });

  final double stationaryThreshold;
  final double movingThreshold;
  final Duration window;
  final Duration minHold;

  final StreamController<MotionState> _ctrl = StreamController<MotionState>.broadcast();
  Stream<MotionState> get stream => _ctrl.stream;

  StreamSubscription<UserAccelerometerEvent>? _sub;
  final List<_Sample> _samples = <_Sample>[];

  MotionState _state = MotionState.unknown;
  MotionState get state => _state;

  DateTime _lastFlipAt = DateTime.fromMillisecondsSinceEpoch(0);

  void start() {
    if (_sub != null) return;

    _sub = userAccelerometerEventStream().listen(
      _onSample,
      onError: (_) => _emit(MotionState.unknown),
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _samples.clear();
    await _ctrl.close();
  }

  void _onSample(UserAccelerometerEvent e) {
    final now = DateTime.now();
    final magnitude = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);

    _samples.add(_Sample(now, magnitude));
    _samples.removeWhere((s) => now.difference(s.ts) > window);

    final avg = _samples.isEmpty
        ? magnitude
        : _samples.map((s) => s.magnitude).reduce((a, b) => a + b) / _samples.length;

    if (now.difference(_lastFlipAt) < minHold) return;

    if (_state == MotionState.moving) {
      if (avg <= stationaryThreshold) _emit(MotionState.stationary);
      return;
    }

    if (avg >= movingThreshold) {
      _emit(MotionState.moving);
    } else if (_state == MotionState.unknown && avg <= stationaryThreshold) {
      _emit(MotionState.stationary);
    }
  }

  void _emit(MotionState next) {
    if (_state == next) return;
    _state = next;
    _lastFlipAt = DateTime.now();
    if (!_ctrl.isClosed) _ctrl.add(next);
  }
}

class _Sample {
  final DateTime ts;
  final double magnitude;

  const _Sample(this.ts, this.magnitude);
}
