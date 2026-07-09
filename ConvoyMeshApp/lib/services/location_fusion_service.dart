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

  final _ctrl = StreamController<FusedLocation>.broadcast();
  Stream<FusedLocation> get stream => _ctrl.stream;

  FusedLocation? _last;
  FusedLocation? get last => _last;

  final List<TrackPoint> _track = [];
  List<TrackPoint> get trackPoints => List.unmodifiable(_track);

  StreamSubscription<ServiceStatus>? _serviceSub;
  StreamSubscription<Position>? _posSub;
  StreamSubscription<UserAccelerometerEvent>? _uaSub;

  bool _hasPerm = false;
  bool _serviceEnabled = false;

  // -------- MOVIMENTO (sensori) --------
  // userAccelerometerEvents (m/s^2) => da fermo tende vicino a 0
  double _motionEma = 0.0; // smoothing
  bool _isMoving = false;
  DateTime _lastMotionFlip = DateTime.fromMillisecondsSinceEpoch(0);

  // Soglie tarate per camminata/trekking, non per veicoli.
  // Isteresi + hold time evitano flip continui fermo/in movimento.
  static const double STILL_ENTER = 0.20;
  static const double MOVE_ENTER = 0.55;
  static const Duration MOTION_HOLD = Duration(seconds: 2);

  // -------- Tuning “a piedi” --------
  static const int updateSeconds = 5; // reattivo ma non troppo energivoro

  // Trail retention
  static const int trackRetentionMinutes = 90;

  Future<void> start() async {
    // 1) permesso location
    final perm = await ph.Permission.locationWhenInUse.request();
    _hasPerm = perm.isGranted;

    // 2) sensori movimento (no permessi extra)
    _startMotionSensors();

    // 3) stato servizi GPS
    _serviceEnabled = await Geolocator.isLocationServiceEnabled();

    _pushState(
      lat: null,
      lon: null,
      acc: null,
      forcedState: _serviceEnabled ? GpsUiState.searching : GpsUiState.off,
      gpsDecision: 'startup',
      gpsReason: _serviceEnabled ? 'GPS attivo: aggancio in corso.' : 'Posizione Android disattivata.',
    );

    _serviceSub?.cancel();
    _serviceSub = Geolocator.getServiceStatusStream().listen((s) {
      _serviceEnabled = (s == ServiceStatus.enabled);

      if (!_serviceEnabled) {
        _posSub?.cancel();
        _posSub = null;
        _pushState(
          lat: null,
          lon: null,
          acc: null,
          forcedState: GpsUiState.off,
          gpsDecision: 'location_off',
          gpsReason: 'Posizione Android disattivata.',
        );
      } else {
        _startPosStream();
      }
    });

    if (_serviceEnabled) {
      _startPosStream();
    }
  }

  void _startMotionSensors() {
    _uaSub?.cancel();

    _uaSub = userAccelerometerEvents.listen((e) {
      // magnitudine (senza gravità)
      final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);

      // EMA (filtro passa-basso)
      _motionEma = _motionEma * 0.85 + mag * 0.15;

      final now = DateTime.now();

      if (_isMoving) {
        if (_motionEma < STILL_ENTER && now.difference(_lastMotionFlip) > MOTION_HOLD) {
          _isMoving = false;
          _lastMotionFlip = now;
          notifyListeners();
        }
      } else {
        if (_motionEma > MOVE_ENTER && now.difference(_lastMotionFlip) > MOTION_HOLD) {
          _isMoving = true;
          _lastMotionFlip = now;
          notifyListeners();
        }
      }
    }, onError: (_) {
      // Se i sensori falliscono, restiamo in modalità GPS-only (non crashiamo).
    });
  }

  void _startPosStream() {
    _posSub?.cancel();

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      intervalDuration: const Duration(seconds: updateSeconds),
      distanceFilter: 0,
    );

    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        final rawLat = pos.latitude;
        final rawLon = pos.longitude;
        final acc = max(0.0, pos.accuracy.toDouble());
        final now = DateTime.now();

        final prev = _last;
        final lastTrack = _track.isEmpty ? null : _track.last;

        final result = PedestrianGpsFilter.evaluate(
          rawLat: rawLat,
          rawLon: rawLon,
          accuracyM: acc,
          ts: now,
          isMoving: _isMoving,
          motionScore: _motionEma,
          previousLat: prev?.lat,
          previousLon: prev?.lon,
          previousTs: prev?.ts,
          previousAccuracyM: prev?.accuracyM,
          lastTrackLat: lastTrack?.lat,
          lastTrackLon: lastTrack?.lon,
        );

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
          lat: _last?.lat,
          lon: _last?.lon,
          acc: _last?.accuracyM,
          forcedState: GpsUiState.searching,
          gpsDecision: 'gps_error',
          gpsReason: 'Errore nello stream GPS: mantengo ultima posizione nota.',
          rawLat: _last?.rawLat,
          rawLon: _last?.rawLon,
        );
      },
    );

    _pushState(
      lat: _last?.lat,
      lon: _last?.lon,
      acc: _last?.accuracyM,
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
    final st = (!_hasPerm || !_serviceEnabled) ? GpsUiState.off : forcedState;
    final quality = acc == null
        ? 0
        : PedestrianGpsFilter.qualityScore(
            accuracyM: max(0.0, acc),
            isMoving: _isMoving,
            motionScore: _motionEma,
          );

    final f = FusedLocation(
      lat: lat,
      lon: lon,
      accuracyM: acc,
      rawLat: rawLat,
      rawLon: rawLon,
      hasPermission: _hasPerm,
      serviceEnabled: _serviceEnabled,
      gpsState: st,
      gpsBars: st == GpsUiState.off ? 0 : bars,
      gpsQuality: st == GpsUiState.off ? 0 : quality,
      ts: DateTime.now(),
      isMoving: _isMoving,
      motionScore: _motionEma,
      gpsDecision: gpsDecision,
      gpsReason: gpsReason,
    );

    _last = f;
    _ctrl.add(f);
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

  static int _accuracyToBars(double accM) {
    return PedestrianGpsFilter.barsForAccuracy(accM);
  }

  static GpsUiState _computeGpsState(int bars) {
    if (bars >= 2) return GpsUiState.ok;
    return GpsUiState.searching;
  }

  static double minStepForTrack(double accuracyM) {
    return PedestrianGpsFilter.minStepForTrack(accuracyM);
  }
}
