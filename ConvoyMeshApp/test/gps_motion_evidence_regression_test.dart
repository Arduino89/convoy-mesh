import 'dart:math';

import 'package:convoy_mesh/location/pedestrian_position_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 1, 1);

  PositionEstimate feed(
    PedestrianPositionEstimator estimator,
    double metres,
    int seconds, {
    bool reliable = true,
    double bearing = 0,
  }) {
    final time = start.add(Duration(seconds: seconds));
    final angle = bearing * pi / 180;
    return estimator.add(
      GpsObservation(
        45 + metres * cos(angle) / 111195,
        10 + metres * sin(angle) / (111195 * cos(pi / 4)),
        5,
        time,
      ),
      receivedAt: time,
      moving: false,
      motionReliable: reliable,
    );
  }

  PedestrianPositionEstimator acquired() {
    final estimator = PedestrianPositionEstimator();
    for (final time in [0, 5, 10]) {
      feed(estimator, 0, time);
    }
    return estimator;
  }

  double offsetMetres(PositionEstimate point) {
    final north = (point.lat! - 45) * 111195;
    final east = (point.lon! - 10) * 111195 * cos(pi / 4);
    return sqrt(north * north + east * east);
  }

  for (final reliable in [true, false]) {
    group(reliable ? 'stationary IMU' : 'GPS-only fallback', () {
      test('a final outlier cannot turn several small jitters into a walk', () {
        for (final bearing in [0.0, 45.0, 90.0, 180.0, 270.0]) {
          final estimator = acquired();
          final samples = [0.6, 1.3, 2.0, 30.0];
          for (var i = 0; i < samples.length; i++) {
            final point = feed(estimator, samples[i], 15 + i * 5,
                reliable: reliable, bearing: bearing);
            expect(offsetMetres(point), lessThan(0.01),
                reason: 'bearing=$bearing sample=$i');
            expect(point.addToTrack, isFalse);
            expect(point.decision, isNot('gps_motion'));
          }
          expect(estimator.snapshot('check').supportedAt,
              start.add(const Duration(seconds: 25)));
        }
      });

      test('an earlier rejected outlier cannot masquerade as the start of a walk', () {
        for (final bearing in [0.0, 45.0, 90.0, 180.0, 270.0]) {
          final estimator = acquired();
          // Once the 30 m point reaches the FIRST slot of the motion window,
          // net/path alone mistakes this return to the stationary cluster for
          // directed movement. Small jitter supplies the other nonzero steps.
          final samples = [30.0, -0.5, 0.1, 0.7, 1.3, -0.5, 0.1];
          for (var i = 0; i < samples.length; i++) {
            final point = feed(estimator, samples[i], 15 + i * 5,
                reliable: reliable, bearing: bearing);
            expect(offsetMetres(point), lessThan(0.01),
                reason: 'bearing=$bearing sample=$i');
            expect(point.addToTrack, isFalse);
            expect(point.decision, isNot('gps_motion'));
          }
        }
      });

      test('a single outlier in any window slot cannot unlock the anchor', () {
        for (var slot = 0; slot < 8; slot++) {
          for (final sign in [-1.0, 1.0]) {
            final estimator = acquired();
            for (var i = 0; i < 18; i++) {
              final metres = i == slot ? sign * 30 : (i % 4) * 0.7 - 1.0;
              final point = feed(estimator, metres, 15 + i * 5, reliable: reliable);
              expect(offsetMetres(point), lessThan(0.01),
                  reason: 'slot=$slot sign=$sign sample=$i');
              expect(point.addToTrack, isFalse);
            }
          }
        }
      });

      test('distributed real movement still overrides an absent or stuck IMU', () {
        for (final bearing in [0.0, 90.0, 180.0, 270.0]) {
          final estimator = acquired();
          PositionEstimate? point;
          for (var seconds = 15; seconds <= 80; seconds += 5) {
            point = feed(estimator, (seconds - 10).toDouble(), seconds,
                reliable: reliable, bearing: bearing);
          }
          expect(point!.decision, 'gps_motion');
          expect(point.addToTrack, isTrue);
          expect(offsetMetres(point), inInclusiveRange(65, 71));
        }
      });

      test('ordinary uneven sample spacing still establishes GPS motion', () {
        final estimator = acquired();
        PositionEstimate? point;
        for (final seconds in [15, 19, 25, 30, 35, 39, 45, 50]) {
          point = feed(estimator, (seconds - 10).toDouble(), seconds,
              reliable: reliable);
        }
        expect(point!.decision, 'gps_motion');
        expect(point.addToTrack, isTrue);
        expect(offsetMetres(point), inInclusiveRange(35, 41));
      });
    });
  }
}
