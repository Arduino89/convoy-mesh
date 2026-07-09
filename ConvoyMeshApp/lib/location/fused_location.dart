enum GpsUiState { off, searching, ok }

class FusedLocation {
  final double? lat;
  final double? lon;
  final double? accuracyM;

  final double? rawLat;
  final double? rawLon;

  final bool hasPermission;
  final bool serviceEnabled;

  final GpsUiState gpsState;
  final int gpsBars;
  final int gpsQuality;

  final DateTime ts;

  /// True se i sensori indicano movimento reale (non drift GPS)
  final bool isMoving;

  /// Indicatore “energia movimento” (0.. circa 2+), utile debug
  final double motionScore;

  /// Decisione sintetica del filtro pedonale, utile per debug e test campo.
  final String gpsDecision;

  /// Motivo leggibile dell'ultimo fix accettato/scartato/ancorato.
  final String gpsReason;

  const FusedLocation({
    required this.lat,
    required this.lon,
    required this.accuracyM,
    required this.rawLat,
    required this.rawLon,
    required this.hasPermission,
    required this.serviceEnabled,
    required this.gpsState,
    required this.gpsBars,
    required this.gpsQuality,
    required this.ts,
    required this.isMoving,
    required this.motionScore,
    required this.gpsDecision,
    required this.gpsReason,
  });
}
