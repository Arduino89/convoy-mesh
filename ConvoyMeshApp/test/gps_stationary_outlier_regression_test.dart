import 'package:convoy_mesh/location/gps_pedestrian_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stationary good-accuracy outlier does not move the displayed position', () {
    final previousTs = DateTime(2026, 8, 30, 12);

    final result = PedestrianGpsFilter.evaluate(
      rawLat: 45.00027,
      rawLon: 10.00000,
      accuracyM: 5,
      ts: previousTs.add(const Duration(seconds: 5)),
      isMoving: false,
      motionScore: 0.04,
      motionReliable: true,
      previousLat: 45.00000,
      previousLon: 10.00000,
      previousTs: previousTs,
      previousAccuracyM: 5,
    );

    expect(result.distanceFromPreviousM, greaterThan(25));
    expect(result.speedKmh, greaterThan(PedestrianGpsFilter.maxWalkingSpeedKmh));
    expect(result.decision, PedestrianGpsDecision.anchored);
    expect(result.displayLat, 45.00000);
    expect(result.displayLon, 10.00000);
    expect(result.acceptedForTrack, isFalse);
  });
}
