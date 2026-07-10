import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:sensors_plus/sensors_plus.dart';

import '../location/fused_location.dart';
import '../location/gps_pedestrian_filter.dart';

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

  // Ultima posizione realmente accettata dal filtro. Non viene aggiornata da
  // jitter ancorato, fix scartati o errori: serve come riferimento stabile per
  // distanza e velocità del fix successivo.
  double? _acceptedLat;
  double? _acceptedLon;
  double? _acceptedAccuracyM;
  DateTime? _acceptedAt;

  // -------- MOVIMENTO (sensori) --------
  double _motionEma = 0.0;
  bool _isMoving = false;
  DateTime _lastMotionFlip = DateTime.fromMillisecondsSinceEpoch(0);
  int _motionSamples = 0;
  bool _motionSensorFailed = false;

  bool get _motionReliable => !_motionSensorFailed && _motionSamples >= 5;

  // Soglie tarate per camminata/trekking, non per veicoli.
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
            notifyListeners();
          }
        } else if (_motionEma > moveEnter && now.difference(_lastMotionFlip) > motionHold) {
          _isMoving = true;
          _lastMotionFlip = now;
          notifyListeners();
        }
      },
      onError: (_) {
        // Senza accelerometro il filtro passa automaticamente in GPS-only:
        // niente freeze permanente e trail ancora utilizzabile.
        _motionSensorFailed = true;
        _motionSamples = 0;
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
          isMoving: _motionReliable ? _isMoving : true,
          motionScore: _motionEma,
          gpsDecision: result.decisionLabel,
          gpsReason: result.reason,
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
      onError: (_) {
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
            isMoving: _motionReliable ? _isMoving : true,
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
      isMoving: _motionReliable ? _isMoving : true,
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
