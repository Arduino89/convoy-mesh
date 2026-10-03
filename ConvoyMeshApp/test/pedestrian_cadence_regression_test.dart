import 'dart:math';

import 'package:convoy_mesh/location/pedestrian_position_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/pedestrian_candidate_probe.dart' as probe;

// These deadlines are experimental app-level acceptance budgets, not Android
// provider timing guarantees. The synthetic provider supplies every listed fix.
// Slow walking, drift and sharp corners are measured by the companion probe;
// passing these tests must not be described as validating their field accuracy.
void main() {
  test('unequal intervals do not turn a constant speed into a singleton jump', () {
    final estimator = PedestrianPositionEstimator();
    PositionEstimate? result;
    for (final t in [0.0, 1.0, 10.0]) {
      result = probe.SyntheticFix(t, 1.4 * t, 0, accuracy: 3).apply(estimator);
    }
    expect(result!.lat, isNotNull);
    expect(result.lat! * probe.metresPerDegree, closeTo(14, 0.01));
    expect(result.addToTrack, isFalse);
  });

  test('selected minority cannot confirm motion against contradictory time bins', () {
    final estimator = PedestrianPositionEstimator();
    PositionEstimate? result;
    final metres = [0.0, 100.0, 100.0, 100.0, 5.6, 100.0, 100.0, 100.0, 11.2];
    for (var i = 0; i < metres.length; i++) {
      result = probe.SyntheticFix(i.toDouble(), metres[i], 0, accuracy: 3).apply(estimator);
    }
    expect(result!.lat, isNull);
    expect(result.addToTrack, isFalse);
  });

  test('one initial outlier does not block a subsequent supported moving path', () {
    final estimator = PedestrianPositionEstimator();
    const probe.SyntheticFix(0, 300, 0, accuracy: 1).apply(estimator);
    PositionEstimate? result;
    for (final t in [5.0, 10.0, 15.0]) {
      result = probe.SyntheticFix(t, 1.4 * t, 0, accuracy: 3).apply(estimator);
    }
    expect(result!.lat, isNotNull);
    expect(result.lat! * probe.metresPerDegree, closeTo(21, 0.01));
    expect(result.addToTrack, isFalse);
  });

  for (final entry in probe.cadencePatterns.entries) {
    test('stationary startup acquires by 15 s at ${entry.key}', () {
      final result = probe.stationaryStart(entry.key, entry.value);
      expect(result.firstConfirmationSeconds, isNotNull);
      expect(result.firstConfirmationSeconds, lessThanOrEqualTo(15));
      expect(result.points.last.error, lessThan(0.01));
      expect(result.points.every((p) => !p.estimate.addToTrack), isTrue);
    });

    test(
      'precise 1.4 m/s moving startup acquires at ${entry.key} without IMU',
      () {
        final result = probe.movingStart(entry.key, entry.value);
        expect(result.firstConfirmationSeconds, isNotNull);
        expect(result.firstConfirmationSeconds, lessThanOrEqualTo(15));
        final confirmed = result.points
            .where((point) => point.confirmed)
            .toList();
        expect(
          confirmed.first.estimate.addToTrack,
          isFalse,
          reason: 'Acquisition establishes a point, not a traversed segment.',
        );
        for (final point in confirmed) {
          expect(point.estimate.isFreshAt(point.fix.at), isTrue);
          expect(point.error, lessThan(10), reason: 't=${point.fix.seconds} s');
        }
        expect(result.points.last.estimate.addToTrack, isTrue);
      },
    );

    test(
      'GPS-only walking after rest is not cadence-locked at ${entry.key}',
      () {
        final result = probe.walkingAfterRest(entry.key, entry.value);
        expect(result.firstTrackAfterMotionSeconds, isNotNull);
        expect(result.firstTrackAfterMotionSeconds, lessThanOrEqualTo(35));
        expect(result.points.last.error, lessThan(8));
        expect(result.points.last.estimate.addToTrack, isTrue);
      },
    );
    test('moving startup also works at accuracy 5 m and ${entry.key}', () {
      final result = probe.movingStart(entry.key, entry.value, accuracy: 5);
      expect(result.firstConfirmationSeconds, isNotNull);
      expect(result.firstConfirmationSeconds, lessThanOrEqualTo(15));
      expect(result.points.last.error, lessThan(10));
      // A finite acquisition/lag budget, not a statistically calibrated radius.
      for (final point in result.points.where((point) => point.confirmed)) {
        expect(point.error, lessThan(15), reason: 't=${point.fix.seconds} s');
      }
    });
  }

  test(
    'original precise moving-start counterexample also acquires with IMU',
    () {
      final result = probe.movingStart('5s', [5], reliable: true);
      expect(result.firstConfirmationSeconds, isNotNull);
      expect(result.firstConfirmationSeconds, lessThanOrEqualTo(15));
      expect(result.points.last.error, lessThan(10));
    },
  );

  test('20 Hz burst does not erase the time span needed for acquisition', () {
    final result = probe.stationaryStart('20Hz', [0.05]);
    expect(result.firstConfirmationSeconds, isNotNull);
    expect(result.firstConfirmationSeconds, lessThanOrEqualTo(15));
    expect(result.points.last.error, lessThan(0.01));
  });

  test(
    'single initially precise 300 m outlier cannot establish the origin',
    () {
      final result = probe.initialOutlier();
      expect(result.points.first.confirmed, isFalse);
      expect(result.firstConfirmationSeconds, isNotNull);
      expect(result.firstConfirmationSeconds, lessThanOrEqualTo(20));
      for (final point in result.points.where((point) => point.confirmed)) {
        expect(point.error, lessThan(2));
        expect(point.estimate.addToTrack, isFalse);
      }
    },
  );

  for (final walking in [false, true]) {
    test(
      'long dropout reacquires ${walking ? "moving" : "stationary"} without a bridge',
      () {
        final result = probe.dropout(walking: walking);
        final afterGap = result.points
            .where((point) => point.fix.seconds >= 100)
            .toList();
        expect(
          afterGap.first.estimate.isFreshAt(afterGap.first.fix.at),
          isFalse,
        );
        expect(afterGap.first.estimate.addToTrack, isFalse);
        final recovered = afterGap
            .where((point) => point.estimate.decision == 'reacquired')
            .toList();
        expect(recovered, hasLength(1));
        expect(recovered.single.fix.seconds, lessThanOrEqualTo(115));
        expect(recovered.single.error, lessThan(10));
        expect(recovered.single.estimate.addToTrack, isFalse);
        expect(
          recovered.single.estimate.isFreshAt(recovered.single.fix.at),
          isTrue,
        );
      },
    );
  }

  test('phone motion does not corroborate one isolated 20 m GNSS innovation', () {
    final result = probe.phoneHandling();
    final spike = result.points.singleWhere((point) => point.fix.seconds == 15);
    expect(
      spike.fix.moving,
      isTrue,
      reason:
          'The production IMU classifier treats this handling signal as motion.',
    );
    expect(spike.fix.reliable, isTrue);
    expect(spike.error, lessThan(2));
    expect(spike.estimate.addToTrack, isFalse);
    expect(
      spike.estimate.supportedAt,
      probe.syntheticEpoch.add(const Duration(seconds: 10)),
      reason:
          'An unsupported distant observation must not renew the held point.',
    );
  });

  for (final gap in [10.0, 20.0]) {
    test(
      'walking resumes after a ${gap}s sample gap without permanent freeze',
      () {
        final result = probe.shortDropout(gap);
        expect(result.metrics()['first_fresh_after_resume_s'], isNotNull);
        expect(
          result.metrics()['first_fresh_after_resume_s'],
          lessThanOrEqualTo(25),
        );
        expect(result.points.last.error, lessThan(8));
        expect(result.points.last.estimate.addToTrack, isTrue);
        expect(
          result.points.any((point) => point.estimate.decision == 'reacquired'),
          isFalse,
          reason:
              'These brief gaps do not satisfy the long-gap reacquisition contract.',
        );
      },
    );
  }

  test(
    'identical GNSS and IMU inputs cannot distinguish coherent bias from walking',
    () {
      final drift = probe.coherentDrift();
      final walk = probe.coherentDrift(stationaryTruth: false);
      for (var i = 0; i < drift.points.length; i++) {
        final a = drift.points[i].estimate;
        final b = walk.points[i].estimate;
        expect(a.lat, b.lat);
        expect(a.lon, b.lon);
        expect(a.decision, b.decision);
        expect(a.addToTrack, b.addToTrack);
      }
      // Two truths 35 m apart: the sum of errors must be at least 35 m.
      // This explicitly records a limit of the evidence, not successful tracking.
      expect(
        drift.points.last.error! + walk.points.last.error!,
        greaterThanOrEqualTo(35 - 1e-6),
      );
    },
  );

  test(
    'slow GPS-only and corners keep support tied to observations, not a timer',
    () {
      final cases = [
        probe.walkingAfterRest('5s', [5], speed: 0.3, accuracy: 10),
        probe.cornersWithoutImu(),
        probe.hairpinWithoutImu(),
      ];
      for (final result in cases) {
        final sourceTimes = result.points.map((point) => point.fix.at).toSet();
        for (final point in result.points.where((point) => point.confirmed)) {
          expect(sourceTimes, contains(point.estimate.supportedAt));
          expect(point.estimate.supportedAt!.isAfter(point.fix.at), isFalse);
          expect(point.estimate.coordinateAt!.isAfter(point.fix.at), isFalse);
          expect(point.north!.isFinite && point.east!.isFinite, isTrue);
        }
        // Snapshot calls cannot manufacture fresh support when sampling stops.
        final estimator = PedestrianPositionEstimator();
        for (final point in result.points) {
          point.fix.apply(estimator);
        }
        final old = estimator.snapshot('before');
        final later = result.points.last.fix.at.add(
          const Duration(seconds: 16),
        );
        final held = estimator.snapshot('display_only');
        expect(held.supportedAt, old.supportedAt);
        expect(held.coordinateAt, old.coordinateAt);
        expect(held.isFreshAt(later), isFalse);
        expect(held.addToTrack, isFalse);
        expect(result.metrics()['max_confirmed_error_m'], isA<double>());
      }
    },
  );

  test(
    'reported radius for a supported held point includes the current fix offset',
    () {
      final estimator = PedestrianPositionEstimator();
      for (final time in [0.0, 5.0, 10.0]) {
        probe.SyntheticFix(time, 0, 0, accuracy: 15).apply(estimator);
      }
      final held = const probe.SyntheticFix(
        15,
        8,
        0,
        accuracy: 1,
      ).apply(estimator);
      final offset = sqrt(
        pow(held.lat! * probe.metresPerDegree - 8, 2) +
            pow(held.lon! * probe.metresPerDegree, 2),
      );
      expect(held.accuracyM!, greaterThanOrEqualTo(offset + 1 - 1e-6));
    },
  );
}
