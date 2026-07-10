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

  /// True solo se i sensori disponibili indicano movimento reale.
  final bool isMoving;

  /// False durante il bootstrap dei sensori o se l'accelerometro non è disponibile.
  /// In quel caso il filtro passa in GPS-only senza fingere uno stato di movimento.
  final bool motionReliable;

  /// Indicatore “energia movimento” (0.. circa 2+), utile debug.
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
    required this.motionReliable,
    required this.motionScore,
    required this.gpsDecision,
    required this.gpsReason,
  });
}
