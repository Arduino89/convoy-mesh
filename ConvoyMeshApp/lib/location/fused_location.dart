enum GpsUiState { off, searching, ok }

class FusedLocation {
  final double? lat, lon, accuracyM, rawLat, rawLon, rawAccuracyM;
  final bool hasPermission, serviceEnabled, isMoving, motionReliable;
  final GpsUiState gpsState;
  final int gpsBars, gpsQuality;
  final double motionScore;
  final String gpsDecision, gpsReason;
  /// Emission of a UI/state event, not a new position measurement.
  final DateTime ts;
  /// Latest observation supporting the displayed estimate.
  final DateTime? measurementAt;
  /// Last change of displayed coordinates (can precede measurementAt when held).
  final DateTime? coordinateAt;

  const FusedLocation({required this.lat, required this.lon, required this.accuracyM,
    required this.rawLat, required this.rawLon, required this.hasPermission,
    required this.serviceEnabled, required this.gpsState, required this.gpsBars,
    required this.gpsQuality, required this.ts, required this.isMoving,
    required this.motionReliable, required this.motionScore,
    required this.gpsDecision, required this.gpsReason,
    this.measurementAt, this.coordinateAt, this.rawAccuracyM});

  bool hasFreshFixAt(DateTime now) {
    final measured = measurementAt;
    if (!hasPermission || !serviceEnabled || lat == null || lon == null ||
        measured == null || accuracyM == null || !accuracyM!.isFinite) return false;
    final age = now.difference(measured);
    return !age.isNegative && age <= const Duration(seconds: 15);
  }
}
