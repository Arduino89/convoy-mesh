import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:sensors_plus/sensors_plus.dart';

import '../location/fused_location.dart';

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

  // Soglie: tarate “a mano” per uso normale.
  // Se vuoi più aggressivo contro drift: alza unlockDistance o alza STILL_ENTER.
  static const double STILL_ENTER = 0.20; // sotto => consideriamo "fermo" (con stabilizzazione)
  static const double MOVE_ENTER  = 0.55; // sopra => consideriamo "in movimento"
  static const Duration MOTION_HOLD = Duration(seconds: 2);

  // -------- Tuning “a piedi” --------
  static const double maxSpeedKmh = 20.0;
  static const int updateSeconds = 5; // un pelo più reattivo, ma non eccessivo

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
    );

    _serviceSub?.cancel();
    _serviceSub = Geolocator.getServiceStatusStream().listen((s) {
      _serviceEnabled = (s == ServiceStatus.enabled);

      if (!_serviceEnabled) {
        _posSub?.cancel();
        _posSub = null;
        _pushState(lat: null, lon: null, acc: null, forcedState: GpsUiState.off);
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

      // isteresi + hold time per evitare flip continui
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
      // Se sensori falliscono, restiamo in modalità GPS-only (non crashiamo)
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

        // --- filtro “teletrasporti” (camminata) ---
        if (prev?.lat != null && prev?.lon != null) {
          final dt = max(1, now.difference(prev!.ts).inSeconds);
          final distM = Geolocator.distanceBetween(prev.lat!, prev.lon!, rawLat, rawLon);
          final maxM = (maxSpeedKmh / 3.6) * dt;

          if (distM > maxM * 1.6 && acc > 25) {
            // scarta fix brutto
            _pushState(
              lat: prev.lat,
              lon: prev.lon,
              acc: prev.accuracyM,
              forcedState: GpsUiState.searching,
              keepTs: true,
            );
            return;
          }
        }

        // --- BLOCCO ANTI-DRIFT: se sensori dicono "fermo", congela la posizione ---
        // Sblocco solo se lo spostamento supera una soglia “plausibile”.
        if (!_isMoving && prev?.lat != null && prev?.lon != null) {
          final distM = Geolocator.distanceBetween(prev!.lat!, prev.lon!, rawLat, rawLon);

          // Soglia di sblocco: più l’accuracy è brutta, più richiediamo spostamento reale
          final unlockDistance = max(12.0, acc * 1.2); // 12m minimo

          if (distM < unlockDistance) {
            // mantieni coordinate precedenti (marker fermo), ma aggiorna stato/accuratezza
            final bars = _accuracyToBars(acc);
            final gpsState = _computeGpsState(bars);

            final fused = FusedLocation(
              lat: prev.lat,
              lon: prev.lon,
              accuracyM: acc,
              hasPermission: _hasPerm,
              serviceEnabled: _serviceEnabled,
              gpsState: gpsState,
              gpsBars: bars,
              ts: now,
              isMoving: _isMoving,
              motionScore: _motionEma,
            );

            _last = fused;
            _ctrl.add(fused);
            notifyListeners();
            return;
          }
        }

        // --- track: aggiungi solo sopra minStep e con fix decente ---
        final minStep = minStepForTrack(acc);

        bool acceptForTrack = true;
        if (_track.isNotEmpty) {
          final lastPt = _track.last;
          final d = Geolocator.distanceBetween(lastPt.lat, lastPt.lon, rawLat, rawLon);
          if (d < minStep) acceptForTrack = false;
        }

        // Se sensori dicono “fermo”, NON tracciamo mai
        if (!_isMoving) acceptForTrack = false;

        final bars = _accuracyToBars(acc);
        final gpsState = _computeGpsState(bars);

        final fused = FusedLocation(
          lat: rawLat,
          lon: rawLon,
          accuracyM: acc,
          hasPermission: _hasPerm,
          serviceEnabled: _serviceEnabled,
          gpsState: gpsState,
          gpsBars: bars,
          ts: now,
          isMoving: _isMoving,
          motionScore: _motionEma,
        );

        _last = fused;
        _ctrl.add(fused);
        notifyListeners();

        if (acceptForTrack && gpsState != GpsUiState.off && bars >= 2) {
          _track.add(TrackPoint(lat: rawLat, lon: rawLon, ts: now, accuracyM: acc));
          _trimTrack(minutes: trackRetentionMinutes);
        }
      },
      onError: (_) {
        _pushState(
          lat: _last?.lat,
          lon: _last?.lon,
          acc: _last?.accuracyM,
          forcedState: GpsUiState.searching,
        );
      },
    );

    _pushState(lat: _last?.lat, lon: _last?.lon, acc: _last?.accuracyM, forcedState: GpsUiState.searching);
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
    bool keepTs = false,
  }) {
    final bars = acc == null ? 0 : _accuracyToBars(acc);
    final st = (!_hasPerm || !_serviceEnabled) ? GpsUiState.off : forcedState;

    final ts = keepTs ? (_last?.ts ?? DateTime.now()) : DateTime.now();

    final f = FusedLocation(
      lat: lat,
      lon: lon,
      accuracyM: acc,
      hasPermission: _hasPerm,
      serviceEnabled: _serviceEnabled,
      gpsState: st,
      gpsBars: st == GpsUiState.off ? 0 : bars,
      ts: ts,
      isMoving: _isMoving,
      motionScore: _motionEma,
    );

    _last = f;
    _ctrl.add(f);
    notifyListeners();
  }

  static int _accuracyToBars(double accM) {
    if (accM <= 5) return 4;
    if (accM <= 15) return 3;
    if (accM <= 50) return 2;
    if (accM <= 100) return 1;
    return 0;
  }

  static GpsUiState _computeGpsState(int bars) {
    if (bars >= 2) return GpsUiState.ok;
    return GpsUiState.searching;
  }

  static double minStepForTrack(double accuracyM) {
    return max(4.0, accuracyM * 0.40);
  }
}
