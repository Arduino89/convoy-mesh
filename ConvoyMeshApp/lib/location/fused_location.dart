enum GpsUiState { off, searching, ok }

class FusedLocation {
  final double? lat;
  final double? lon;
  final double? accuracyM;

  final bool hasPermission;
  final bool serviceEnabled;

  final GpsUiState gpsState;
  final int gpsBars;

  final DateTime ts;

  /// True se i sensori indicano movimento reale (non drift GPS)
  final bool isMoving;

  /// Indicatore “energia movimento” (0.. circa 2+), utile debug
  final double motionScore;

  const FusedLocation({
    required this.lat,
    required this.lon,
    required this.accuracyM,
    required this.hasPermission,
    required this.serviceEnabled,
    required this.gpsState,
    required this.gpsBars,
    required this.ts,
    required this.isMoving,
    required this.motionScore,
  });
}
