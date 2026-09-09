import 'package:convoy_mesh/location/pedestrian_position_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const metresPerDegree = 111195.0;
  final start = DateTime.utc(2026, 9, 9, 8);

  PositionEstimate feed(
    PedestrianPositionEstimator estimator,
    double metres,
    int seconds, {
    double accuracy = 9,
    bool moving = true,
  }) {
    final at = start.add(Duration(seconds: seconds));
    return estimator.add(
      GpsObservation(45 + metres / metresPerDegree, 10, accuracy, at),
      receivedAt: at,
      moving: moving,
      motionReliable: true,
    );
  }

  PedestrianPositionEstimator acquired({double accuracy = 14}) {
    final estimator = PedestrianPositionEstimator();
    feed(estimator, 0, 0, accuracy: accuracy, moving: false);
    feed(estimator, 0.5, 5, accuracy: accuracy, moving: false);
    feed(estimator, -0.5, 10, accuracy: accuracy, moving: false);
    return estimator;
  }

  double metres(PositionEstimate position) =>
      (position.lat! - 45) * metresPerDegree;

  test('short real excursion can close at origin despite a biased GNSS return', () {
    final estimator = acquired();

    // Synthetic analogue of the 2026-09-09 phone trace: accepted movement
    // reaches ~20-25 m, then the user physically returns but GNSS still reports
    // points ~14-16 m from its own starting estimate. The two uncertainty
    // regions overlap, and two consecutive approaching fixes support closure.
    feed(estimator, 10, 15);
    feed(estimator, 20, 20);
    feed(estimator, 25, 25);
    feed(estimator, 24, 30);
    feed(estimator, 21, 35);
    final near = feed(estimator, 16, 40);
    expect(near.decision, isNot('loop_closed_origin'));

    final closed = feed(estimator, 14, 45);
    expect(closed.decision, 'loop_closed_origin');
    expect(metres(closed).abs(), lessThan(0.5));
    expect(closed.addToTrack, isTrue);
    // Reconciliation must not pretend to be more accurate than the evidence.
    expect(closed.accuracyM, greaterThanOrEqualTo(14));
  });

  test('high-quality GNSS passing near origin is not snapped outside uncertainty', () {
    final estimator = acquired(accuracy: 3);
    for (var i = 1; i <= 5; i++) {
      feed(estimator, i * 8.0, 10 + i * 5, accuracy: 3);
    }

    // 12 m is clearly outside the overlap of two ~3 m fixes. Even after a real
    // excursion, this is a nearby path, not evidence of returning to origin.
    PositionEstimate? last;
    for (final pair in <(double, int)>[(20, 40), (15, 45), (12, 50)]) {
      last = feed(estimator, pair.$1, pair.$2, accuracy: 3);
      expect(last.decision, isNot('loop_closed_origin'));
    }
    expect(metres(last!).abs(), greaterThan(5));
  });

  test('stationary drift alone cannot manufacture a loop excursion', () {
    final estimator = acquired(accuracy: 15);
    PositionEstimate? last;
    for (var t = 15; t <= 180; t += 5) {
      final wobble = t % 20 == 0 ? 12.0 : -8.0;
      last = feed(estimator, wobble, t, accuracy: 15, moving: false);
      expect(last.decision, isNot('loop_closed_origin'));
      expect(last.addToTrack, isFalse);
    }
  });
}
