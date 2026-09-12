import 'dart:convert';
import 'dart:io';
import 'package:convoy_mesh/location/pedestrian_position_estimator.dart';

/// Run locally: dart run tool/replay_diagnostics.dart /private/path/test.jsonl
/// Input files are never uploaded. No absolute accuracy claim without ground truth.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/replay_diagnostics.dart <file.jsonl> [...]');
    exitCode = 64; return;
  }
  for (final path in args) {
    final estimator = PedestrianPositionEstimator();
    final decisions = <String, int>{};
    var fixes = 0, malformed = 0, receiptTimeFallbacks = 0, accuracyFallbacks = 0;
    try {
      await for (final line in File(path).openRead().transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        try {
          final event = jsonDecode(line) as Map<String, dynamic>;
          if (event['category'] != 'gps' || event['event'] != 'fix') continue;
          final data = event['data'] as Map<String, dynamic>;
          final received = DateTime.parse(event['ts_utc'] as String).toUtc();
          final source = data['source_ts_utc'] is String ? DateTime.parse(data['source_ts_utc'] as String).toUtc() : received;
          if (data['source_ts_utc'] == null) receiptTimeFallbacks++;
          if (data['raw_accuracy_m'] == null) accuracyFallbacks++;
          final observation = GpsObservation((data['raw_lat'] as num).toDouble(),
              (data['raw_lon'] as num).toDouble(),
              ((data['raw_accuracy_m'] ?? data['accuracy_m']) as num).toDouble(), source);
          final result = estimator.add(observation, receivedAt: received,
              moving: data['moving'] == true, motionReliable: data['motion_reliable'] == true);
          fixes++;
          decisions.update(result.decision, (n) => n + 1, ifAbsent: () => 1);
        } catch (_) { malformed++; }
      }
      stdout.writeln(jsonEncode({
        'input_file': File(path).uri.pathSegments.last, 'gps_fixes': fixes,
        'malformed_records': malformed, 'decision_counts': decisions,
        'receipt_timestamp_fallbacks': receiptTimeFallbacks,
        'display_accuracy_fallbacks': accuracyFallbacks,
        'initial_estimator_state': 'not_recorded_warm_up_from_log_prefix',
        'absolute_position_accuracy': 'not_measurable_without_ground_truth',
        'scope': 'production_estimator_replay_not_radio_or_Android_runtime_test',
      }));
    } catch (e) { stderr.writeln('Cannot read input: $e'); exitCode = 1; }
  }
}
