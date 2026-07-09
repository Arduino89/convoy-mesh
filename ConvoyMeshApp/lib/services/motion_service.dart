import 'dart:async';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'motion_service.dart';

enum GpsUiState { off, searching, ok }

class FusedLocation {
  FusedLocation({
    required this.display,
    required this.filtered,
    required this.raw,
    required this.accuracyM,
    required this.gpsBars,
    required this.gpsState,
    required this.statusText,
    required this.permissionGranted,
    required this.serviceEnabled,
    required this.motion,
    required this.fixAt,
  });

  final LatLng? display; // posizione “da mostrare” (bloccata se fermo)
  final LatLng? filtered; // EMA
  final LatLng? raw; // GPS grezzo
  final double accuracyM;

  final int gpsBars; // 0..4
  final GpsUiState gpsState;
  final String statusText;

  final bool permissionGranted;
  final bool serviceEnabled;

  final MotionState motion;
  final DateTime? fixAt;

  bool get isMoving => motion == MotionState.moving;
}

class LocationFusionService {
  LocationFusionService._();

  static final LocationFusionService instance = LocationFusionService._();

  // ====== TUNING (anti micro-scie) ======
  static const double emaAlpha = 0.22;
  static const double deadbandMinM = 6.0;
  static const double deadbandAccuracyFactor = 1.2;
  static const double unlockAnchorMinM = 15.0;

  // update piedi: 8–10s come dicevi
  static const Duration interval = Duration(seconds: 10);

  final _controller = StreamController<FusedLocation>.broadcast();
  Stream<FusedLocation> get stream => _controller.stream;

  FusedLocation? _current;
  FusedLocation? get current => _current;

  bool _started = false;

  StreamSubscription<ServiceStatus>? _serviceSub;
  StreamSubscription<Position>? _posSub;
  StreamSubscription<MotionState>? _motionSub;

  final MotionService _motion = MotionService(
    stationaryThreshold: 0.35,
    window: const Duration(seconds: 2),
    minHold: const Duration(milliseconds: 1200),
  );
  MotionState _motionState = MotionState.unknown;

  bool _hasPermission = false;
  bool _serviceEnabled = false;

  Position? _lastRawPos;
  DateTime? _lastFixAt;

  LatLng? _filtered;
  LatLng? _anchorWhenStationary;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _motion.start();
    _motionSub = _motion.stream.listen((s) {
      _motionState = s;
      if (_motionState == MotionState.moving) {
        _anchorWhenStationary = null;
      }
      _emitCurrent(); // aggiorna UI anche senza nuovo fix GPS
    });

    await _ensurePermission();

    _serviceEnabled = await Geolocator.isLocationServiceEnabled();

    _serviceSub?.cancel();
    _serviceSub = Geolocator.getServiceStatusStream().listen((status) {
      _serviceEnabled = (status == ServiceStatus.enabled);

      if (_serviceEnabled) {
        _startPositionStream();
      } else {
        _posSub?.cancel();
        _posSub = null;
      }

      _emitCurrent();
    });

    if (_serviceEnabled) {
      _startPositionStream();
    } else {
      _emitCurrent();
    }
  }

  Future<void> stop() async {
    _started = false;
    await _serviceSub?.cancel();
    await _posSub?.cancel();
    await _motionSub?.cancel();
    _motion.dispose();
  }

  Future<void> _ensurePermission() async {
    final locStatus = await ph.Permission.locationWhenInUse.request();
    _hasPermission = locStatus.isGranted;
  }

  void _startPositionStream() {
    _posSub?.cancel();

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      intervalDuration: interval,
      distanceFilter: 0,
    );

    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(
          (pos) {
        _lastRawPos = pos;
        _lastFixAt = DateTime.now();

        final acc = max(0.0, pos.accuracy.toDouble());
        final raw = LatLng(pos.latitude, pos.longitude);

        _filtered = (_filtered == null) ? raw : _ema(_filtered!, raw, emaAlpha);

        // “ancora” quando fermo
        final display = _computeDisplayPos(_filtered!, acc);

        final bars = _accuracyToBars(acc);
        final gpsState = _barsToState(bars);
        final text = _buildStatusText(pos, acc, gpsState);

        _current = FusedLocation(
          display: display,
          filtered: _filtered,
          raw: raw,
          accuracyM: acc,
          gpsBars: bars,
          gpsState: gpsState,
          statusText: text,
          permissionGranted: _hasPermission,
          serviceEnabled: _serviceEnabled,
          motion: _motionState,
          fixAt: _lastFixAt,
        );

        _controller.add(_current!);
      },
      onError: (e) {
        _emitCurrent(error: "Errore GPS: $e");
      },
    );

    _emitCurrent();
  }

  void _emitCurrent({String? error}) {
    final pos = _lastRawPos;
    final acc = pos == null ? 9999.0 : max(0.0, pos.accuracy.toDouble());
    final bars = _accuracyToBars(acc);
    final gpsState = _barsToState(bars);

    final text = error ??
        (pos == null
            ? (_serviceEnabled ? "GPS attivo: aggancio in corso…" : "Location disattivata (GPS OFF).")
            : _buildStatusText(pos, acc, gpsState));

    _current ??= FusedLocation(
      display: _filtered,
      filtered: _filtered,
      raw: pos == null ? null : LatLng(pos.latitude, pos.longitude),
      accuracyM: acc,
      gpsBars: bars,
      gpsState: gpsState,
      statusText: text,
      permissionGranted: _hasPermission,
      serviceEnabled: _serviceEnabled,
      motion: _motionState,
      fixAt: _lastFixAt,
    );

    _current = FusedLocation(
      display: _current!.display,
      filtered: _current!.filtered,
      raw: _current!.raw,
      accuracyM: _current!.accuracyM,
      gpsBars: bars,
      gpsState: gpsState,
      statusText: text,
      permissionGranted: _hasPermission,
      serviceEnabled: _serviceEnabled,
      motion: _motionState,
      fixAt: _lastFixAt,
    );

    _controller.add(_current!);
  }

  LatLng _ema(LatLng prev, LatLng next, double alpha) {
    return LatLng(
      prev.latitude + alpha * (next.latitude - prev.latitude),
      prev.longitude + alpha * (next.longitude - prev.longitude),
    );
  }

  LatLng _computeDisplayPos(LatLng filtered, double acc) {
    if (!_serviceEnabled || !_hasPermission) return filtered;

    if (_motionState == MotionState.stationary) {
      _anchorWhenStationary ??= filtered;

      final dist = Geolocator.distanceBetween(
        _anchorWhenStationary!.latitude,
        _anchorWhenStationary!.longitude,
        filtered.latitude,
        filtered.longitude,
      );

      final unlock = max(unlockAnchorMinM, acc * 1.5);
      if (dist > unlock) {
        _anchorWhenStationary = filtered;
      }
      return _anchorWhenStationary!;
    }

    return filtered;
  }

  int _accuracyToBars(double accM) {
    if (accM <= 5) return 4;
    if (accM <= 15) return 3;
    if (accM <= 50) return 2;
    if (accM <= 100) return 1;
    return 0;
  }

  GpsUiState _barsToState(int bars) {
    if (!_serviceEnabled || !_hasPermission) return GpsUiState.off;
    if (_lastRawPos == null) return GpsUiState.searching;

    final age = _lastFixAt == null ? 9999 : DateTime.now().difference(_lastFixAt!).inSeconds;
    if (age > 20) return GpsUiState.searching;

    if (bars >= 2) return GpsUiState.ok;
    return GpsUiState.searching;
  }

  String _buildStatusText(Position p, double acc, GpsUiState state) {
    final lat = p.latitude.toStringAsFixed(5);
    final lon = p.longitude.toStringAsFixed(5);

    if (!_serviceEnabled) return "Location disattivata (GPS OFF).";
    if (state == GpsUiState.searching) return "GPS attivo: aggancio in corso…";

    final motionTxt = switch (_motionState) {
      MotionState.stationary => "fermo",
      MotionState.moving => "in movimento",
      _ => "?"
    };

    return "GPS OK: $lat, $lon (±${acc.toStringAsFixed(0)}m) • $motionTxt";
  }

  /// Exposed helper (utile al track della mappa)
  static double minStepForTrack(double accuracyM) {
    return max(deadbandMinM, accuracyM * deadbandAccuracyFactor);
  }
}
