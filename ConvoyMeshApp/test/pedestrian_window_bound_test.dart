import 'package:convoy_mesh/location/pedestrian_position_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('100 Hz for a minute retains time support with at most 26 bins', () {
    final estimator = PedestrianPositionEstimator();
    final start = DateTime.utc(2026, 1, 1);
    DateTime? first;
    for (var milliseconds = 0; milliseconds <= 60000; milliseconds += 10) {
      final at = start.add(Duration(milliseconds: milliseconds));
      final result = estimator.add(
        GpsObservation(0, 0, 3, at),
        receivedAt: at,
        moving: false,
        motionReliable: false,
      );
      if (result.lat != null) first ??= at;
      expect(estimator.retainedObservationCount, lessThanOrEqualTo(26));
    }
    expect(first, isNotNull);
    expect(
      first!.difference(start),
      lessThanOrEqualTo(const Duration(seconds: 10)),
    );
  });
}
