// Synthetic comparison only: these metres and coordinates are generated, not
// recordings from a person. Run with `dart run tool/pedestrian_candidate_probe.dart`.
// Imports the estimator used by LocationFusionService, not a replica of it.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:convoy_mesh/location/pedestrian_motion_classifier.dart';
import 'package:convoy_mesh/location/pedestrian_position_estimator.dart';

const metresPerDegree = 111194.92664455874;
final syntheticEpoch = DateTime.utc(2026, 1, 1);

class SyntheticFix {
  const SyntheticFix(
    this.seconds,
    this.north,
    this.east, {
    this.accuracy = 5,
    this.moving = false,
    this.reliable = false,
    double? truthNorth,
    double? truthEast,
  }) : truthNorth = truthNorth ?? north,
       truthEast = truthEast ?? east;

  final double seconds, north, east, accuracy, truthNorth, truthEast;
  final bool moving, reliable;

  DateTime get at => syntheticEpoch.add(
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round()),
  );

  PositionEstimate apply(PedestrianPositionEstimator estimator) =>
      estimator.add(
        GpsObservation(
          north / metresPerDegree,
          east / metresPerDegree,
          accuracy,
          at,
        ),
        receivedAt: at,
        moving: moving,
        motionReliable: reliable,
      );
}

class ProbePoint {
  const ProbePoint(this.fix, this.estimate);
  final SyntheticFix fix;
  final PositionEstimate estimate;

  bool get confirmed => estimate.lat != null && estimate.lon != null;
  double? get north =>
      estimate.lat == null ? null : estimate.lat! * metresPerDegree;
  double? get east =>
      estimate.lon == null ? null : estimate.lon! * metresPerDegree;
  double? get error => confirmed
      ? sqrt(pow(north! - fix.truthNorth, 2) + pow(east! - fix.truthEast, 2))
      : null;
}

class ProbeResult {
  ProbeResult(
    this.name,
    Iterable<SyntheticFix> fixes, {
    this.motionStartsAt = 0,
    this.recoveryStartsAt,
  }) {
    final estimator = PedestrianPositionEstimator();
    for (final fix in fixes) {
      points.add(ProbePoint(fix, fix.apply(estimator)));
    }
  }

  final String name;
  final double motionStartsAt;
  final double? recoveryStartsAt;
  final List<ProbePoint> points = [];

  double? get firstConfirmationSeconds {
    for (final point in points) {
      if (point.confirmed) return point.fix.seconds;
    }
    return null;
  }

  double? get firstTrackAfterMotionSeconds {
    for (final point in points) {
      if (point.fix.seconds >= motionStartsAt && point.estimate.addToTrack) {
        return point.fix.seconds - motionStartsAt;
      }
    }
    return null;
  }

  Map<String, Object?> metrics() {
    final decisions = <String, int>{};
    double? largestError;
    double? largestFreshError;
    double? recoveryDelay;
    var staleDisplays = 0;
    var trackCandidates = 0;
    var candidatePath = 0.0;
    ProbePoint? previousTrack;
    for (final point in points) {
      decisions.update(
        point.estimate.decision,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      final error = point.error;
      if (error != null) largestError = max(largestError ?? error, error);
      final fresh = point.estimate.isFreshAt(point.fix.at);
      if (error != null && fresh) {
        largestFreshError = max(largestFreshError ?? error, error);
      }
      if (point.confirmed && !fresh) staleDisplays++;
      if (recoveryStartsAt != null &&
          point.fix.seconds >= recoveryStartsAt! &&
          fresh) {
        recoveryDelay ??= point.fix.seconds - recoveryStartsAt!;
      }
      if (point.estimate.addToTrack) {
        trackCandidates++;
        if (previousTrack != null) {
          candidatePath += sqrt(
            pow(point.north! - previousTrack.north!, 2) +
                pow(point.east! - previousTrack.east!, 2),
          );
        }
        previousTrack = point;
      }
    }
    return {
      'case': name,
      'samples': points.length,
      'first_confirmation_s': firstConfirmationSeconds,
      'first_track_after_motion_s': firstTrackAfterMotionSeconds,
      'final_error_m': points.last.error,
      'max_confirmed_error_m': largestError,
      'max_fresh_error_m': largestFreshError,
      'stale_display_observations': staleDisplays,
      if (recoveryStartsAt != null) 'first_fresh_after_resume_s': recoveryDelay,
      'final_north_m': points.last.north,
      'final_east_m': points.last.east,
      'track_candidates': trackCandidates,
      // Estimator candidates, before the service's spacing/segment gates.
      'candidate_path_m': candidatePath,
      'final_accuracy_m': points.last.estimate.accuracyM,
      'final_decision': points.last.estimate.decision,
      'decisions': decisions,
    };
  }
}

const cadencePatterns = <String, List<double>>{
  '1s': [1],
  '2s': [2],
  '2.5s': [2.5],
  '5s': [5],
  'irregular': [1, 4, 2.5, 7.5, 5],
};

Iterable<double> sampleTimes(
  List<double> cadence,
  double end, {
  double start = 0,
}) sync* {
  var time = start;
  var index = 0;
  yield time;
  while (time < end) {
    time = min(end, time + cadence[index++ % cadence.length]);
    yield time;
  }
}

ProbeResult stationaryStart(String cadence, List<double> pattern) =>
    ProbeResult(
      'stationary_start_$cadence',
      sampleTimes(
        pattern,
        30,
      ).map((t) => SyntheticFix(t, 0, 0, reliable: true)),
    );

ProbeResult movingStart(
  String cadence,
  List<double> pattern, {
  bool reliable = false,
  double accuracy = 3,
}) => ProbeResult(
  'moving_start_1.4m_s_acc${accuracy}_${cadence}_${reliable ? "imu" : "gps_only"}',
  sampleTimes(pattern, 120).map(
    (t) => SyntheticFix(
      t,
      1.4 * t,
      0,
      accuracy: accuracy,
      moving: reliable,
      reliable: reliable,
    ),
  ),
);

ProbeResult walkingAfterRest(
  String cadence,
  List<double> pattern, {
  double speed = 1.2,
  double accuracy = 5,
}) => ProbeResult('gps_only_${speed}m_s_acc${accuracy}_$cadence', [
  for (final t in [0.0, 5.0, 10.0]) SyntheticFix(t, 0, 0, accuracy: accuracy),
  for (final t in sampleTimes(pattern, 130, start: 10).skip(1))
    SyntheticFix(t, (t - 10) * speed, 0, accuracy: accuracy),
], motionStartsAt: 10);

ProbeResult cornersWithoutImu() =>
    ProbeResult('gps_only_four_right_angle_corners', [
      for (final t in [0.0, 5.0, 10.0]) SyntheticFix(t, 0, 0),
      for (var t = 5.0; t <= 120; t += 5)
        SyntheticFix(
          t + 10,
          t <= 30
              ? 1.2 * t
              : t <= 60
              ? 36
              : t <= 90
              ? 36 - 1.2 * (t - 60)
              : 0,
          t <= 30
              ? 0
              : t <= 60
              ? 1.2 * (t - 30)
              : t <= 90
              ? 36
              : 36 - 1.2 * (t - 90),
        ),
    ], motionStartsAt: 10);

ProbeResult hairpinWithoutImu() => ProbeResult('gps_only_hairpin_return', [
  for (final t in [0.0, 5.0, 10.0]) SyntheticFix(t, 0, 0),
  for (var t = 5.0; t <= 100; t += 5)
    SyntheticFix(t + 10, t <= 50 ? 1.2 * t : 60 - 1.2 * (t - 50), 0),
], motionStartsAt: 10);

ProbeResult shortDropout(double gap) => ProbeResult(
  'moving_dropout_${gap}s',
  [
    for (final t in [0.0, 5.0, 10.0]) SyntheticFix(t, 0, 0),
    for (var t = 15.0; t <= 120; t += 5)
      if (t <= 40 || t >= 40 + gap) SyntheticFix(t, (t - 10) * 1.2, 0),
  ],
  motionStartsAt: 10,
  recoveryStartsAt: 40 + gap,
);

ProbeResult coherentDrift({bool stationaryTruth = true}) => ProbeResult(
  stationaryTruth
      ? 'stationary_truth_coherent_bias_0.7m_s'
      : 'walking_truth_same_input_0.7m_s',
  [
    for (final t in [0.0, 5.0, 10.0]) SyntheticFix(t, 0, 0, reliable: true),
    for (var t = 15.0; t <= 60; t += 5)
      SyntheticFix(
        t,
        (t - 10) * 0.7,
        0,
        reliable: true,
        truthNorth: stationaryTruth ? 0 : (t - 10) * 0.7,
      ),
  ],
  motionStartsAt: 10,
);

ProbeResult phoneHandling() {
  final motion = PedestrianMotionClassifier();
  for (var ms = 0; ms <= 6000; ms += 100) {
    motion.addSample(0.36, Duration(milliseconds: ms));
  }
  return ProbeResult('phone_handling_then_isolated_20m_fix', [
    for (final t in [0.0, 5.0, 10.0]) SyntheticFix(t, 0, 0, reliable: true),
    SyntheticFix(
      15,
      20,
      0,
      moving: motion.moving,
      reliable: motion.isReliableAt(const Duration(seconds: 6)),
      truthNorth: 0,
    ),
    SyntheticFix(20, 0, 0, moving: motion.moving, reliable: true),
  ]);
}

ProbeResult initialOutlier() => ProbeResult('initial_300m_outlier_acc1', [
  const SyntheticFix(0, 300, 0, accuracy: 1, truthNorth: 0),
  for (final t in [5.0, 10.0, 15.0, 20.0, 25.0])
    SyntheticFix(t, 0, 0, accuracy: 3),
]);

ProbeResult dropout({bool walking = false}) => ProbeResult(
  walking
      ? 'dropout_then_moving_reacquisition'
      : 'dropout_then_stationary_reacquisition',
  [
    for (final t in [0.0, 5.0, 10.0]) SyntheticFix(t, 0, 0, accuracy: 3),
    for (final t in [100.0, 105.0, 110.0, 115.0, 120.0])
      SyntheticFix(t, 1000 + (walking ? (t - 100) * 1.4 : 0), 0, accuracy: 3),
  ],
  recoveryStartsAt: 100,
);

List<ProbeResult> candidateCases() => [
  for (final entry in cadencePatterns.entries)
    stationaryStart(entry.key, entry.value),
  for (final entry in cadencePatterns.entries)
    movingStart(entry.key, entry.value),
  for (final entry in cadencePatterns.entries)
    movingStart(entry.key, entry.value, accuracy: 5),
  movingStart('5s', [5], reliable: true),
  for (final entry in cadencePatterns.entries)
    walkingAfterRest(entry.key, entry.value),
  walkingAfterRest('5s', [5], speed: 0.3, accuracy: 10),
  cornersWithoutImu(),
  hairpinWithoutImu(),
  shortDropout(10),
  shortDropout(20),
  initialOutlier(),
  dropout(),
  dropout(walking: true),
  coherentDrift(),
  coherentDrift(stationaryTruth: false),
  phoneHandling(),
];

void main(List<String> arguments) {
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'label': arguments.isEmpty ? 'working_tree' : arguments.first,
      'evidence':
          'synthetic inputs to production estimator; no physical-device validation',
      'cases': candidateCases().map((result) => result.metrics()).toList(),
    }),
  );
}
