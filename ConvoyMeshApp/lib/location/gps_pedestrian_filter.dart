import 'dart:math';

enum PedestrianGpsDecision {
  accepted,
  anchored,
  rejectedJump,
  rejectedPoorAccuracy,
  waitingForFirstGoodFix,
}

class PedestrianGpsResult {
  const PedestrianGpsResult({
    required this.displayLat,
    required this.displayLon,
    required this.rawLat,
    required this.rawLon,
    required this.accuracyM,
    required this.quality,
    required this.bars,
    required this.decision,
    required this.reason,
    required this.acceptedForTrack,
    required this.distanceFromPreviousM,
    required this.speedKmh,
  });

  final double? displayLat;
  final double? displayLon;
  final double rawLat;
  final double rawLon;
  final double accuracyM;
  final int quality;
  final int bars;
  final PedestrianGpsDecision decision;
  final String reason;
  final bool acceptedForTrack;
  final double distanceFromPreviousM;
  final double speedKmh;

  String get decisionLabel {
    switch (decision) {
      case PedestrianGpsDecision.accepted:
        return 'accepted';
      case PedestrianGpsDecision.anchored:
        return 'anchored';
      case PedestrianGpsDecision.rejectedJump:
        return 'rejected_jump';
      case PedestrianGpsDecision.rejectedPoorAccuracy:
        return 'rejected_poor_accuracy';
      case PedestrianGpsDecision.waitingForFirstGoodFix:
        return 'waiting_first_good_fix';
    }
  }
}

/// Pedestrian-first GPS filter for Convoy Mesh.
///
/// Scope: walking groups in low-connectivity outdoor areas. It intentionally
/// avoids vehicle assumptions and road/map matching.
class PedestrianGpsFilter {
  static const double maxWalkingSpeedKmh = 12.0;
  static const double maxUsableAccuracyM = 120.0;
  static const double maxTrackAccuracyM = 80.0;
  static const double goodAccuracyM = 25.0;
  static const double stationaryUnlockMinM = 12.0;
  static const double stationaryAccuracyFactor = 1.2;

  static PedestrianGpsResult evaluate({
    required double rawLat,
    required double rawLon,
    required double accuracyM,
    required DateTime ts,
    required bool isMoving,
    required double motionScore,
    double? previousLat,
    double? previousLon,
    DateTime? previousTs,
    double? previousAccuracyM,
    double? lastTrackLat,
    double? lastTrackLon,
  }) {
    final acc = max(0.0, accuracyM);
    final bars = barsForAccuracy(acc);
    final quality = qualityScore(accuracyM: acc, isMoving: isMoving, motionScore: motionScore);

    final hasPrevious = previousLat != null && previousLon != null && previousTs != null;

    if (acc > maxUsableAccuracyM) {
      if (hasPrevious) {
        final prevLat = previousLat!;
        final prevLon = previousLon!;
        final distanceFromPrevious = distanceMeters(prevLat, prevLon, rawLat, rawLon);
        return PedestrianGpsResult(
          displayLat: prevLat,
          displayLon: prevLon,
          rawLat: rawLat,
          rawLon: rawLon,
          accuracyM: acc,
          quality: quality,
          bars: bars,
          decision: PedestrianGpsDecision.rejectedPoorAccuracy,
          reason: 'Accuracy troppo debole: mantengo ultima posizione buona.',
          acceptedForTrack: false,
          distanceFromPreviousM: distanceFromPrevious,
          speedKmh: 0,
        );
      }

      return PedestrianGpsResult(
        displayLat: null,
        displayLon: null,
        rawLat: rawLat,
        rawLon: rawLon,
        accuracyM: acc,
        quality: quality,
        bars: bars,
        decision: PedestrianGpsDecision.waitingForFirstGoodFix,
        reason: 'Aspetto un primo fix GPS piu affidabile.',
        acceptedForTrack: false,
        distanceFromPreviousM: 0,
        speedKmh: 0,
      );
    }

    if (!hasPrevious) {
      final acceptedForTrack = isMoving && bars >= 2 && acc <= maxTrackAccuracyM;
      return PedestrianGpsResult(
        displayLat: rawLat,
        displayLon: rawLon,
        rawLat: rawLat,
        rawLon: rawLon,
        accuracyM: acc,
        quality: quality,
        bars: bars,
        decision: PedestrianGpsDecision.accepted,
        reason: 'Primo fix GPS accettato.',
        acceptedForTrack: acceptedForTrack,
        distanceFromPreviousM: 0,
        speedKmh: 0,
      );
    }

    final prevLat = previousLat!;
    final prevLon = previousLon!;
    final prevTs = previousTs!;

    final dtSeconds = max(1, ts.difference(prevTs).inSeconds);
    final distanceFromPrevious = distanceMeters(prevLat, prevLon, rawLat, rawLon);
    final speedKmh = (distanceFromPrevious / dtSeconds) * 3.6;

    final allowedByWalking = (maxWalkingSpeedKmh / 3.6) * dtSeconds;
    final uncertaintyBuffer = max(acc, previousAccuracyM ?? acc) * 1.2;
    final maxPlausibleDistance = max(25.0, allowedByWalking + uncertaintyBuffer);

    if (distanceFromPrevious > maxPlausibleDistance && acc > goodAccuracyM) {
      return PedestrianGpsResult(
        displayLat: prevLat,
        displayLon: prevLon,
        rawLat: rawLat,
        rawLon: rawLon,
        accuracyM: acc,
        quality: min(quality, 35),
        bars: bars,
        decision: PedestrianGpsDecision.rejectedJump,
        reason: 'Salto GPS implausibile per camminata: mantengo ultima posizione buona.',
        acceptedForTrack: false,
        distanceFromPreviousM: distanceFromPrevious,
        speedKmh: speedKmh,
      );
    }

    if (!isMoving) {
      final unlockDistance = max(
        stationaryUnlockMinM,
        max(acc, previousAccuracyM ?? acc) * stationaryAccuracyFactor,
      );

      if (distanceFromPrevious < unlockDistance) {
        return PedestrianGpsResult(
          displayLat: prevLat,
          displayLon: prevLon,
          rawLat: rawLat,
          rawLon: rawLon,
          accuracyM: acc,
          quality: quality,
          bars: bars,
          decision: PedestrianGpsDecision.anchored,
          reason: 'Fermo: jitter GPS ignorato.',
          acceptedForTrack: false,
          distanceFromPreviousM: distanceFromPrevious,
          speedKmh: speedKmh,
        );
      }
    }

    var acceptedForTrack = false;
    if (isMoving && bars >= 2 && acc <= maxTrackAccuracyM) {
      if (lastTrackLat == null || lastTrackLon == null) {
        acceptedForTrack = true;
      } else {
        final trackDistance = distanceMeters(lastTrackLat, lastTrackLon, rawLat, rawLon);
        acceptedForTrack = trackDistance >= minStepForTrack(acc);
      }
    }

    return PedestrianGpsResult(
      displayLat: rawLat,
      displayLon: rawLon,
      rawLat: rawLat,
      rawLon: rawLon,
      accuracyM: acc,
      quality: quality,
      bars: bars,
      decision: PedestrianGpsDecision.accepted,
      reason: acceptedForTrack ? 'Camminata: fix accettato e aggiunto alla traccia.' : 'Fix accettato.',
      acceptedForTrack: acceptedForTrack,
      distanceFromPreviousM: distanceFromPrevious,
      speedKmh: speedKmh,
    );
  }

  static int barsForAccuracy(double? accuracyM) {
    if (accuracyM == null) return 0;
    if (accuracyM <= 5) return 4;
    if (accuracyM <= 15) return 3;
    if (accuracyM <= 50) return 2;
    if (accuracyM <= 100) return 1;
    return 0;
  }

  static int qualityScore({
    required double accuracyM,
    required bool isMoving,
    required double motionScore,
  }) {
    final base = accuracyM <= 5
        ? 100
        : accuracyM <= 10
            ? 92
            : accuracyM <= 15
                ? 84
                : accuracyM <= 25
                    ? 72
                    : accuracyM <= 50
                        ? 55
                        : accuracyM <= 80
                            ? 35
                            : accuracyM <= 120
                                ? 20
                                : 5;

    final motionBonus = !isMoving && motionScore < 0.25 ? 5 : 0;
    return (base + motionBonus).clamp(0, 100).toInt();
  }

  static double minStepForTrack(double accuracyM) {
    return max(4.0, accuracyM * 0.40);
  }

  static double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static double _deg2rad(double d) => d * (pi / 180.0);
}
