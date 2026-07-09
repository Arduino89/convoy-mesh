import 'package:convoy_mesh/location/gps_pedestrian_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PedestrianGpsFilter', () {
    test('accepts the first usable outdoor fix', () {
      final now = DateTime(2026, 7, 9, 12, 0);

      final result = PedestrianGpsFilter.evaluate(
        rawLat: 45.0,
        rawLon: 10.0,
        accuracyM: 8,
        ts: now,
        isMoving: false,
        motionScore: 0.05,
      );

      expect(result.decision, PedestrianGpsDecision.accepted);
      expect(result.displayLat, 45.0);
      expect(result.displayLon, 10.0);
      expect(result.bars, 3);
      expect(result.quality, greaterThanOrEqualTo(90));
      expect(result.acceptedForTrack, isFalse);
    });

    test('waits for a better fix when the first fix has very poor accuracy', () {
      final result = PedestrianGpsFilter.evaluate(
        rawLat: 45.0,
        rawLon: 10.0,
        accuracyM: 160,
        ts: DateTime(2026, 7, 9, 12, 0),
        isMoving: false,
        motionScore: 0.05,
      );

      expect(result.decision, PedestrianGpsDecision.waitingForFirstGoodFix);
      expect(result.displayLat, isNull);
      expect(result.displayLon, isNull);
      expect(result.acceptedForTrack, isFalse);
    });

    test('anchors stationary jitter around the previous good position', () {
      final prevTs = DateTime(2026, 7, 9, 12, 0);
      final result = PedestrianGpsFilter.evaluate(
        rawLat: 45.00002,
        rawLon: 10.00000,
        accuracyM: 12,
        ts: prevTs.add(const Duration(seconds: 5)),
        isMoving: false,
        motionScore: 0.04,
        previousLat: 45.00000,
        previousLon: 10.00000,
        previousTs: prevTs,
        previousAccuracyM: 8,
      );

      expect(result.decision, PedestrianGpsDecision.anchored);
      expect(result.displayLat, 45.00000);
      expect(result.displayLon, 10.00000);
      expect(result.acceptedForTrack, isFalse);
      expect(result.distanceFromPreviousM, lessThan(5));
    });

    test('accepts real walking movement and adds it to trail when step is meaningful', () {
      final prevTs = DateTime(2026, 7, 9, 12, 0);
      final result = PedestrianGpsFilter.evaluate(
        rawLat: 45.00012,
        rawLon: 10.00000,
        accuracyM: 8,
        ts: prevTs.add(const Duration(seconds: 12)),
        isMoving: true,
        motionScore: 0.9,
        previousLat: 45.00000,
        previousLon: 10.00000,
        previousTs: prevTs,
        previousAccuracyM: 8,
        lastTrackLat: 45.00000,
        lastTrackLon: 10.00000,
      );

      expect(result.decision, PedestrianGpsDecision.accepted);
      expect(result.displayLat, 45.00012);
      expect(result.acceptedForTrack, isTrue);
      expect(result.speedKmh, lessThan(PedestrianGpsFilter.maxWalkingSpeedKmh));
    });

    test('does not add tiny walking movement to trail', () {
      final prevTs = DateTime(2026, 7, 9, 12, 0);
      final result = PedestrianGpsFilter.evaluate(
        rawLat: 45.00001,
        rawLon: 10.00000,
        accuracyM: 10,
        ts: prevTs.add(const Duration(seconds: 5)),
        isMoving: true,
        motionScore: 0.8,
        previousLat: 45.00000,
        previousLon: 10.00000,
        previousTs: prevTs,
        previousAccuracyM: 10,
        lastTrackLat: 45.00000,
        lastTrackLon: 10.00000,
      );

      expect(result.decision, PedestrianGpsDecision.accepted);
      expect(result.acceptedForTrack, isFalse);
    });

    test('rejects a poor-accuracy jump that is implausible for walking', () {
      final prevTs = DateTime(2026, 7, 9, 12, 0);
      final result = PedestrianGpsFilter.evaluate(
        rawLat: 45.01000,
        rawLon: 10.00000,
        accuracyM: 45,
        ts: prevTs.add(const Duration(seconds: 5)),
        isMoving: true,
        motionScore: 0.8,
        previousLat: 45.00000,
        previousLon: 10.00000,
        previousTs: prevTs,
        previousAccuracyM: 8,
      );

      expect(result.decision, PedestrianGpsDecision.rejectedJump);
      expect(result.displayLat, 45.00000);
      expect(result.displayLon, 10.00000);
      expect(result.acceptedForTrack, isFalse);
      expect(result.speedKmh, greaterThan(PedestrianGpsFilter.maxWalkingSpeedKmh));
    });

    test('keeps previous good position when accuracy becomes unusable', () {
      final prevTs = DateTime(2026, 7, 9, 12, 0);
      final result = PedestrianGpsFilter.evaluate(
        rawLat: 45.001,
        rawLon: 10.001,
        accuracyM: 180,
        ts: prevTs.add(const Duration(seconds: 10)),
        isMoving: false,
        motionScore: 0.05,
        previousLat: 45.00000,
        previousLon: 10.00000,
        previousTs: prevTs,
        previousAccuracyM: 8,
      );

      expect(result.decision, PedestrianGpsDecision.rejectedPoorAccuracy);
      expect(result.displayLat, 45.00000);
      expect(result.displayLon, 10.00000);
      expect(result.bars, 0);
      expect(result.acceptedForTrack, isFalse);
    });
  });
}
