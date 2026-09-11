import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:sensors_plus/sensors_plus.dart';
import '../location/fused_location.dart';
import '../location/gps_pedestrian_filter.dart';
import '../location/pedestrian_motion_classifier.dart';
import '../location/pedestrian_position_estimator.dart';
import 'diagnostic_recorder.dart';

class TrackPoint {
  final double lat, lon, accuracyM;
  final DateTime ts;
  final int segment;
  TrackPoint({required this.lat, required this.lon, required this.ts,
    required this.accuracyM, this.segment = 0});
}

class LocationFusionService extends ChangeNotifier {
  LocationFusionService._();
  static final instance = LocationFusionService._();
  final _ctrl = StreamController<FusedLocation>.broadcast();
  Stream<FusedLocation> get stream => _ctrl.stream;
  FusedLocation? _last;
  FusedLocation? get last => _last;
  final List<TrackPoint> _track = [];
  List<TrackPoint> get trackPoints => List.unmodifiable(_track);
  PedestrianPositionEstimator _estimator = PedestrianPositionEstimator();
  final PedestrianMotionClassifier _motion = PedestrianMotionClassifier();
  GpsObservation? _raw;
  Future<void>? _startFuture;
  Future<void> _positionOp = Future.value();
  StreamSubscription<ServiceStatus>? _serviceSub;
  StreamSubscription<Position>? _posSub;
  StreamSubscription<UserAccelerometerEvent>? _motionSub;
  Timer? _ageTimer;
  bool _running = false, _hasPerm = false, _serviceEnabled = false;
  int _generation = 0, _positionGeneration = 0, _segment = 0;
  final Stopwatch _clock = Stopwatch()..start();
  static const int updateSeconds = 5;
  static const int trackRetentionMinutes = 90;
  bool get _motionReliable => _motion.isReliableAt(_clock.elapsed);

  Future<void> start() => _startFuture ??= _startInternal();
  Future<void> _startInternal() async {
    _running = true;
    final epoch = ++_generation;
    _segment++;
    _estimator = PedestrianPositionEstimator();
    _raw = null;
    _hasPerm = (await ph.Permission.locationWhenInUse.status).isGranted;
    _serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!_running || epoch != _generation) return;
    _startMotion();
    await _serviceSub?.cancel();
    _serviceSub = Geolocator.getServiceStatusStream().listen((status) {
      if (!_running || epoch != _generation) return;
      _serviceEnabled = status == ServiceStatus.enabled;
      DiagnosticRecorder.instance.record('gps', 'service_status',
          data: {'enabled': _serviceEnabled, 'permission': _hasPerm});
      unawaited(_reconcilePositionStream());
    }, onError: (Object e) {
      DiagnosticRecorder.instance.record('gps', 'service_status_error', data: {'error': e.toString()});
    });
    await _reconcilePositionStream();
    _ageTimer?.cancel();
    _ageTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_running && _last != null && !_last!.hasFreshFixAt(DateTime.now())) {
        _emit(_estimator.snapshot('waiting_for_fresh_fix'));
      }
    });
  }

  void _startMotion() {
    _motion.reset();
    _motionSub = userAccelerometerEventStream().listen((event) {
      if (!_running) return;
      final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      final update = _motion.addSample(magnitude, _clock.elapsed);
      if (update.changed) {
        DiagnosticRecorder.instance.record('motion', 'state_change', data: {
          'moving': update.moving,
          'score': update.score,
          'reliable': _motionReliable,
          'reason': update.reason,
        });
      }
    }, onError: (Object e) {
      _motion.reset();
      DiagnosticRecorder.instance.record('motion', 'sensor_error', data: {'error': e.toString()});
    });
  }

  Future<void> _reconcilePositionStream() {
    final epoch = _generation;
    _positionOp = _positionOp.then((_) async {
      if (!_running || epoch != _generation) return;
      final streamEpoch = ++_positionGeneration;
      await _posSub?.cancel();
      _posSub = null;
      if (!_running || epoch != _generation) return;
      if (!_hasPerm || !_serviceEnabled) {
        _emit(_estimator.snapshot(!_hasPerm ? 'permission_denied' : 'location_off'));
        return;
      }
      final settings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        intervalDuration: const Duration(seconds: updateSeconds),
        distanceFilter: 0,
      );
      _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((position) {
        if (_running && epoch == _generation && streamEpoch == _positionGeneration) {
          _onPosition(position);
        }
      }, onError: (Object e) {
        DiagnosticRecorder.instance.record('gps', 'stream_error', data: {'error': e.toString()});
        _emit(_estimator.snapshot('gps_error'));
      });
      _emit(_estimator.snapshot('acquiring'));
    }).catchError((Object e) {
      DiagnosticRecorder.instance.record('gps', 'stream_start_error', data: {'error': e.toString()});
      _emit(_estimator.snapshot('gps_error'));
    });
    return _positionOp;
  }

  void _onPosition(Position position) {
    final received = DateTime.now().toUtc();
    final observation = GpsObservation(
      position.latitude,
      position.longitude,
      position.accuracy,
      position.timestamp.toUtc(),
    );
    _raw = observation;
    final result = _estimator.add(
      observation,
      receivedAt: received,
      moving: _motion.moving,
      motionReliable: _motionReliable,
    );
    if (result.decision == 'reacquired') _segment++;
    var added = false;
    if (result.addToTrack && result.isFreshAt(received) && result.lat != null &&
        result.lon != null && result.accuracyM != null) {
      final previous = _track.isEmpty ? null : _track.last;
      final distance = previous == null || previous.segment != _segment
          ? double.infinity
          : PedestrianGpsFilter.distanceMeters(
              previous.lat,
              previous.lon,
              result.lat!,
              result.lon!,
            );
      if (distance >= minStepForTrack(result.accuracyM!)) {
        _track.add(TrackPoint(
          lat: result.lat!,
          lon: result.lon!,
          ts: result.supportedAt!,
          accuracyM: result.accuracyM!,
          segment: _segment,
        ));
        added = true;
      }
    }
    _track.removeWhere((p) =>
        received.difference(p.ts) > const Duration(minutes: trackRetentionMinutes));
    DiagnosticRecorder.instance.record('gps', 'fix', data: {
      'source_ts_utc': observation.at.toIso8601String(),
      'received_ts_utc': received.toIso8601String(),
      'coordinate_ts_utc': result.coordinateAt?.toUtc().toIso8601String(),
      'supported_ts_utc': result.supportedAt?.toUtc().toIso8601String(),
      'raw_lat': observation.lat,
      'raw_lon': observation.lon,
      'raw_accuracy_m': observation.accuracyM,
      'display_lat': result.lat,
      'display_lon': result.lon,
      'accuracy_m': result.accuracyM,
      'decision': result.decision,
      'fresh': result.isFreshAt(received),
      'track_added': added,
      'track_points_total': _track.length,
      'moving': _motion.moving,
      'motion_reliable': _motionReliable,
      'motion_score': _motion.score,
    });
    _emit(result);
  }

  void _emit(PositionEstimate result) {
    final now = DateTime.now();
    final fresh = _running && _hasPerm && _serviceEnabled && result.isFreshAt(now);
    final acc = result.accuracyM;
    final bars = fresh ? PedestrianGpsFilter.barsForAccuracy(acc) : 0;
    final quality = !fresh || acc == null
        ? 0
        : PedestrianGpsFilter.qualityScore(
            accuracyM: acc,
            isMoving: _motion.moving,
            motionScore: _motion.score,
            motionReliable: _motionReliable,
          );
    _last = FusedLocation(
      lat: result.lat,
      lon: result.lon,
      accuracyM: acc,
      rawLat: _raw?.lat,
      rawLon: _raw?.lon,
      rawAccuracyM: _raw?.accuracyM,
      hasPermission: _hasPerm,
      serviceEnabled: _serviceEnabled && _running,
      gpsState: !_running || !_hasPerm || !_serviceEnabled
          ? GpsUiState.off
          : fresh && bars >= 2
              ? GpsUiState.ok
              : GpsUiState.searching,
      gpsBars: bars,
      gpsQuality: quality,
      ts: now,
      measurementAt: result.supportedAt,
      coordinateAt: result.coordinateAt,
      isMoving: _motion.moving,
      motionReliable: _motionReliable,
      motionScore: _motion.score,
      gpsDecision: result.decision,
      gpsReason: result.decision,
    );
    _ctrl.add(_last!);
    notifyListeners();
  }

  void clearTrack() {
    _track.clear();
    notifyListeners();
  }

  Future<void> disposeService() async {
    _running = false;
    _generation++;
    _positionGeneration++;
    _ageTimer?.cancel();
    _ageTimer = null;
    await _serviceSub?.cancel();
    _serviceSub = null;
    await _motionSub?.cancel();
    _motionSub = null;
    await _positionOp;
    await _posSub?.cancel();
    _posSub = null;
    _motion.reset();
    _startFuture = null;
    _emit(_estimator.snapshot('stopped'));
  }

  static double minStepForTrack(double accuracyM) =>
      PedestrianGpsFilter.minStepForTrack(accuracyM);
}
