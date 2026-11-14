import 'dart:convert';

/// Local-only aggregation from a diagnostic JSONL export.
///
/// Raw records may include coordinates, names, BLE identifiers and free text.
/// Only the fixed numeric/boolean allowlist below may be previewed or used for
/// a future opt-in cloud summary. No uploader is present.
class DiagnosticSummary {
  const DiagnosticSummary({
    required this.durationSeconds,
    required this.snapshotCount,
    required this.onlinePeerSamples,
    required this.stalePeerSamples,
    required this.captureGapCount,
    required this.maxCaptureGapSeconds,
    required this.acceptedBlePackets,
    required this.rejectedBlePackets,
    required this.txNativeErrors,
    required this.gpsFixCount,
    required this.gpsFreshFixCount,
    required this.droppedEvents,
    required this.invalidRecords,
    required this.completed,
  });

  final int durationSeconds;
  final int snapshotCount;
  final int onlinePeerSamples;
  final int stalePeerSamples;
  final int captureGapCount;
  final int maxCaptureGapSeconds;
  final int acceptedBlePackets;
  final int rejectedBlePackets;
  final int txNativeErrors;
  final int gpsFixCount;
  final int gpsFreshFixCount;
  final int droppedEvents;
  final int invalidRecords;
  final bool completed;

  static DiagnosticSummary fromJsonl(String jsonl) {
    var maxElapsedMs = 0;
    int? previousSnapshotMs;
    var snapshots = 0;
    var onlineSamples = 0;
    var staleSamples = 0;
    var gaps = 0;
    var maxGapMs = 0;
    var accepted = 0;
    var rejected = 0;
    var txErrors = 0;
    var gpsFixes = 0;
    var freshFixes = 0;
    var dropped = 0;
    var invalid = 0;
    var completed = false;

    for (final line in const LineSplitter().convert(jsonl)) {
      if (line.trim().isEmpty) continue;
      Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        invalid++;
        continue;
      }
      if (decoded is! Map) {
        invalid++;
        continue;
      }
      final elapsed = decoded['elapsed_ms'];
      if (elapsed is! int || elapsed < 0 ||
          elapsed > const Duration(hours: 24).inMilliseconds) {
        invalid++;
        continue;
      }
      if (elapsed > maxElapsedMs) maxElapsedMs = elapsed;
      final category = decoded['category'];
      final event = decoded['event'];
      final data = decoded['data'];
      final payload = data is Map ? data : const <String, Object?>{};

      if (category == 'session' && event == 'stop') {
        completed = true;
        final loss = payload['dropped_events'];
        if (loss is int && loss >= 0) dropped = loss;
      } else if (category == 'runtime' && event == 'snapshot') {
        snapshots++;
        if (previousSnapshotMs != null) {
          final delta = elapsed - previousSnapshotMs;
          // The bridge nominally samples every 5 s. Treat >9 s as a
          // capture gap, not necessarily an Android radio failure.
          if (delta > 9000) {
            gaps++;
            if (delta > maxGapMs) maxGapMs = delta;
          } else if (delta < 0) {
            invalid++;
          }
        }
        previousSnapshotMs = elapsed;
        final peers = payload['peers'];
        if (peers is List) {
          for (final peer in peers) {
            if (peer is! Map || peer['online'] != true) continue;
            onlineSamples++;
            if (peer['fix_fresh'] != true) staleSamples++;
          }
        }
      } else if (category == 'ble' && event == 'rx_decision') {
        if (payload['accepted_packet'] == true) {
          accepted++;
        } else if (payload['accepted_packet'] == false) {
          rejected++;
        }
      } else if (category == 'ble' && event == 'rx_parse_rejected') {
        rejected++;
      } else if (category == 'ble' && event == 'tx_native_error') {
        txErrors++;
      } else if (category == 'gps' && event == 'fix') {
        gpsFixes++;
        if (payload['fresh'] == true) freshFixes++;
      }
    }
    return DiagnosticSummary(
      durationSeconds: maxElapsedMs ~/ 1000,
      snapshotCount: snapshots,
      onlinePeerSamples: onlineSamples,
      stalePeerSamples: staleSamples,
      captureGapCount: gaps,
      maxCaptureGapSeconds: maxGapMs ~/ 1000,
      acceptedBlePackets: accepted,
      rejectedBlePackets: rejected,
      txNativeErrors: txErrors,
      gpsFixCount: gpsFixes,
      gpsFreshFixCount: freshFixes,
      droppedEvents: dropped,
      invalidRecords: invalid,
      completed: completed,
    );
  }

  /// Exact fixed allowlist. Never merge raw event fields into this map.
  Map<String, Object> toReviewFields() => {
        'schema_version': 1,
        'duration_s': durationSeconds,
        'snapshot_count': snapshotCount,
        'online_peer_samples': onlinePeerSamples,
        'stale_peer_samples': stalePeerSamples,
        'capture_gap_count': captureGapCount,
        'max_capture_gap_s': maxCaptureGapSeconds,
        'ble_rx_accepted': acceptedBlePackets,
        'ble_rx_rejected': rejectedBlePackets,
        'ble_tx_native_errors': txNativeErrors,
        'gps_fix_count': gpsFixCount,
        'gps_fresh_fix_count': gpsFreshFixCount,
        'dropped_events': droppedEvents,
        'invalid_records': invalidRecords,
        'completed': completed,
      };
}
