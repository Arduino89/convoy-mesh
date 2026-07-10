import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:sensors_plus/sensors_plus.dart';

import '../location/fused_location.dart';
import '../location/gps_pedestrian_filter.dart';
import 'diagnostic_recorder.dart';

class TrackPoint {
  final double lat;
  final double lon;
  final DateTime ts;
  final double accuracyM;

  TrackPoint({
    required this.lat,
    required this.lon,
    required this.ts,
    required this.accuracyM,
  });
}

class LocationFusionService extends ChangeNotifier {
  LocationFusionService._();

  static final LocationFusionService instance = LocationFusionService._();

  final StreamController<FusedLocation> _ctrl = StreamController<FusedLocation>.broadcast();
  Stream<FusedLocation> get stream => _ctrl.stream;

  FusedLocation? _last;
  FusedLocation? get last => _last;

  final List<TrackPoint> _track = <TrackPoint>[];
  List<TrackPoint> get trackPoints => List<TrackPoint>.unmodifiable(_track);

  StreamSubscription<ServiceStatus>? _serviceSub;
  StreamSubscription<Position>? _posSub;
  StreamSubscription<UserAccelerometerEvent>? _uaSub;

  bool _hasPerm = false;
  bool _serviceEnabled = false;

  double? _acceptedLat;
  double? _acceptedLon;
  double? _acceptedAccuracyM;
  DateTime? _acceptedAt;

  double _motionEma = 0.0;
  bool _isMoving = false;
  DateTime _lastMotionFlip = DateTime.fromMillisecondsSinceEpoch(0);
  int _motionSamples = 0;
  bool _motionSensorFailed = false;

  bool get _motionReliable => !_motionSensorFailed && _motionSamples >= 5;

  static const double stillEnter = 0.20;
  static const double moveEnter = 0.55;
  static const Duration motionHold = Duration(seconds: 2);

  static const int updateSeconds = 5;
  static const int trackRetentionMinutes = 90;

  Future<void> start() async {
    final perm = await ph.Permission.locationWhenInUse.request();
    _hasPerm = perm.isGranted;

    _startMotionSensors();
    _serviceEnabled = await Geolocator.isLocationServiceEnabled();

    DiagnosticRecorder.instance.record(
      'gps',
      'service_start',
      data: <String, Object?>{
        'permission': _hasPerm,
        'service_enabled': _serviceEnabled,
      },
    );

    _pushState(
      lat: null,
      lon: null,
      acc: null,
      forcedState: _serviceEnabled && _hasPerm ? GpsUiState.searching : GpsUiState.off,
      gpsDecision: _hasPerm ? 'startup' : 'permission_denied',
      gpsReason: !_hasPerm
          ? 'Permesso posizione non concesso.'
          : _serviceEnabled
              ? 'GPS attivo: aggancio in corso.'
              : 'Posizione Android disattivata.',
    );

    await _serviceSub?.cancel();
    _serviceSub = Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
      _serviceEnabled = status == ServiceStatus.enabled;

      DiagnosticRecorder.instance.record(
        'gps',
        'service_status',
        data: <String, Object?>{
          'enabled': _serviceEnabled,
          'permission': _hasPerm,
        },
      );

      if (!_serviceEnabled || !_hasPerm) {
        _posSub?.cancel();
        _posSub = null;
        _pushState(
          lat: null,
          lon: null,
          acc: null,
          forcedState: GpsUiState.off,
          gpsDecision: !_hasPerm ? 'permission_denied' : 'location_off',
          gpsReason: !_hasPerm ? 'Permesso posizione non concesso.' : 'Posizione Android disattivata.',
        );
      } else {
        _startPosStream();
      }
    });

    if (_serviceEnabled && _hasPerm) {
      _startPosStream();
    }
  }

  void _startMotionSensors() {
    _uaSub?.cancel();
    _motionSamples = 0;
    _motionSensorFailed = false;

    _uaSub = userAccelerometerEventStream().listen(
      (UserAccelerometerEvent event) {
        final magnitude = sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        );

        _motionEma = _motionEma * 0.85 + magnitude * 0.15;
        _motionSamples = min(_motionSamples + 1, 1000000);

        final now = DateTime.now();
        if (_isMoving) {
          if (_motionEma < stillEnter && now.difference(_lastMotionFlip) > motionHold) {
            _isMoving = false;
            _lastMotionFlip = now;
            DiagnosticRecorder.instance.record(
              'motion',
              'state_change',
              data: <String, Object?>{
                'moving': false,
                'score': _motionEma,
                'reliable': _motionReliable,
              },
            );
            notifyListeners();
          }
        } else if (_motionEma > moveEnter && now.difference(_lastMotionFlip) > motionHold) {
          _isMoving = true;
          _lastMotionFlip = now;
          DiagnosticRecorder.instance.record(
            'motion',
            'state_change',
            data: <String, Object?>{
              'moving': true,
              'score': _motionEma,
              'reliable': _motionReliable,
            },
          );
          notifyListeners();
        }
      },
      onError: (Object error) {
        _motionSensorFailed = true;
        _motionSamples = 0;
        DiagnosticRecorder.instance.record(
          'motion',
          'sensor_error',
          data: <String, Object?>{'error': error.toString()},
        );
        notifyListeners();
      },
    );
  }

  void _startPosStream() {
    if (!_hasPerm || !_serviceEnabled) return;

    _posSub?.cancel();

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      intervalDuration: const Duration(seconds: updateSeconds),
      distanceFilter: 0,
    );

    DiagnosticRecorder.instance.record(
      'gps',
      'stream_start',
      data: <String, Object?>{
        'interval_seconds': updateSeconds,
        'accuracy_mode': 'best',
      },
    );

    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (Position position) {
        final rawLat = position.latitude;
        final rawLon = position.longitude;
        final accuracyM = max(0.0, position.accuracy.toDouble());
        final now = DateTime.now();
        final lastTrack = _track.isEmpty ? null : _track.last;

        final result = PedestrianGpsFilter.evaluate(
          rawLat: rawLat,
          rawLon: rawLon,
          accuracyM: accuracyM,
          ts: now,
          isMoving: _isMoving,
          motionScore: _motionEma,
          motionReliable: _motionReliable,
          previousLat: _acceptedLat,
          previousLon: _acceptedLon,
          previousTs: _acceptedAt,
          previousAccuracyM: _acceptedAccuracyM,
          lastTrackLat: lastTrack?.lat,
          lastTrackLon: lastTrack?.lon,
        );

        if (result.decision == PedestrianGpsDecision.accepted &&
            result.displayLat != null &&
            result.displayLon != null) {
          _acceptedLat = result.displayLat;
          _acceptedLon = result.displayLon;
          _acceptedAccuracyM = result.accuracyM;
          _acceptedAt = now;
        }

        final gpsState = _stateForResult(result);
        final fused = FusedLocation(
          lat: result.displayLat,
          lon: result.displayLon,
          accuracyM: result.accuracyM,
          rawLat: result.rawLat,
          rawLon: result.rawLon,
          hasPermission: _hasPerm,
          serviceEnabled: _serviceEnabled,
          gpsState: gpsState,
          gpsBars: gpsState == GpsUiState.off ? 0 : result.bars,
          gpsQuality: gpsState == GpsUiState.off ? 0 : result.quality,
          ts: now,
          isMoving: _isMoving,
          motionReliable: _motionReliable,
          motionScore: _motionEma,
          gpsDecision: result.decisionLabel,
          gpsReason: result.reason,
        );

        DiagnosticRecorder.instance.record(
          'gps',
          'fix',
          data: <String, Object?>{
            'raw_lat': rawLat,
            'raw_lon': rawLon,
            'display_lat': result.displayLat,
            'display_lon': result.displayLon,
            'accuracy_m': result.accuracyM,
            'quality': result.quality,
            'bars': result.bars,
            'decision': result.decisionLabel,
            'reason': result.reason,
            'track_added': result.acceptedForTrack,
            'distance_from_previous_m': result.distanceFromPreviousM,
            'speed_kmh': result.speedKmh,
            'moving': _isMoving,
            'motion_reliable': _motionReliable,
            'motion_score': _motionEma,
          },
        );

        _last = fused;
        _ctrl.add(fused);
        notifyListeners();

        if (result.acceptedForTrack && result.displayLat != null && result.displayLon != null) {
          _track.add(
            TrackPoint(
              lat: result.displayLat!,
              lon: result.displayLon!,
              ts: now,
              accuracyM: result.accuracyM,
            ),
          );
          _trimTrack(minutes: trackRetentionMinutes);
        }
      },
      onError: (Object error) {
        DiagnosticRecorder.instance.record(
          'gps',
          'stream_error',
          data: <String, Object?>{'error': error.toString()},
        );
        _pushState(
          lat: _acceptedLat,
          lon: _acceptedLon,
          acc: _acceptedAccuracyM,
          forcedState: GpsUiState.searching,
          gpsDecision: 'gps_error',
          gpsReason: 'Errore nello stream GPS: mantengo ultima posizione valida.',
          rawLat: _last?.rawLat,
          rawLon: _last?.rawLon,
        );
      },
    );

    _pushState(
      lat: _acceptedLat,
      lon: _acceptedLon,
      acc: _acceptedAccuracyM,
      forcedState: GpsUiState.searching,
      gpsDecision: 'searching',
      gpsReason: 'GPS attivo: aggancio in corso.',
      rawLat: _last?.rawLat,
      rawLon: _last?.rawLon,
    );
  }

  void clearTrack() {
    _track.clear();
    DiagnosticRecorder.instance.record('gps', 'track_cleared');
    notifyListeners();
  }

  void disposeService() {
    _serviceSub?.cancel();
    _posSub?.cancel();
    _uaSub?.cancel();
  }

  void _trimTrack({required int minutes}) {
    final cutoff = DateTime.now().subtract(Duration(minutes: minutes));
    while (_track.isNotEmpty && _track.first.ts.isBefore(cutoff)) {
      _track.removeAt(0);
    }
  }

  void _pushState({
    required double? lat,
    required double? lon,
    required double? acc,
    required GpsUiState forcedState,
    String gpsDecision = 'state',
    String gpsReason = '-',
    double? rawLat,
    double? rawLon,
  }) {
    final bars = PedestrianGpsFilter.barsForAccuracy(acc);
    final state = (!_hasPerm || !_serviceEnabled) ? GpsUiState.off : forcedState;
    final quality = acc == null
        ? 0
        : PedestrianGpsFilter.qualityScore(
            accuracyM: max(0.0, acc),
            isMoving: _isMoving,
            motionScore: _motionEma,
            motionReliable: _motionReliable,
          );

    final fused = FusedLocation(
      lat: lat,
      lon: lon,
      accuracyM: acc,
      rawLat: rawLat,
      rawLon: rawLon,
      hasPermission: _hasPerm,
      serviceEnabled: _serviceEnabled,
      gpsState: state,
      gpsBars: state == GpsUiState.off ? 0 : bars,
      gpsQuality: state == GpsUiState.off ? 0 : quality,
      ts: DateTime.now(),
      isMoving: _isMoving,
      motionReliable: _motionReliable,
      motionScore: _motionEma,
      gpsDecision: gpsDecision,
      gpsReason: gpsReason,
    );

    _last = fused;
    _ctrl.add(fused);
    notifyListeners();
  }

  static GpsUiState _stateForResult(PedestrianGpsResult result) {
    switch (result.decision) {
      case PedestrianGpsDecision.accepted:
      case PedestrianGpsDecision.anchored:
        return result.bars >= 2 && result.quality >= 35 ? GpsUiState.ok : GpsUiState.searching;
      case PedestrianGpsDecision.rejectedJump:
      case PedestrianGpsDecision.rejectedPoorAccuracy:
      case PedestrianGpsDecision.waitingForFirstGoodFix:
        return GpsUiState.searching;
    }
  }

  static double minStepForTrack(double accuracyM) {
    return PedestrianGpsFilter.minStepForTrack(accuracyM);
  }
}
