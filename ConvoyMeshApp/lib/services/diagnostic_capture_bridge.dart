import 'dart:async';
import 'convoy_mesh_service.dart';
import 'diagnostic_recorder.dart';
import 'background_runtime_service.dart';

/// RX/TX decisions are recorded at source by ConvoyMeshService.
/// These periodic records are snapshots, not individual radio events.
class DiagnosticCaptureBridge {
  DiagnosticCaptureBridge._();
  static final instance = DiagnosticCaptureBridge._();
  Timer? _timer;
  void attach() { _timer ??= Timer.periodic(const Duration(seconds: 5), (_) => captureNow()); }
  void captureNow() {
    final recorder = DiagnosticRecorder.instance;
    if (!recorder.isActive) return;
    final mesh = ConvoyMeshService.instance;
    final now = DateTime.now();
    recorder.record('runtime', 'snapshot', data: {
      'foreground_service': BackgroundRuntimeService.instance.isRunning,
      'outing_running': mesh.isRunning, 'ble_status': mesh.bleStatus.name,
      'scanning': mesh.isScanning, 'advertising': mesh.isAdvertising,
      'rx_valid_total': mesh.rxValid, 'rx_stale_total': mesh.rxStale,
      'scan_events_total': mesh.scanEventCount, 'tx_ok_total': mesh.advOkCount,
      'tx_error_total': mesh.advErrorCount,
      'local_fix_fresh': mesh.myLast?.hasFreshFixAt(now) ?? false,
      'peers': mesh.peers.values.map((p) => {
        'id': p.userId, 'name': p.name, 'online': ConvoyMeshService.isPeerOnline(p),
        'rssi': p.rssi, 'median_rssi': p.medianRssi,
        'last_seq': p.lastSeq, 'lat': p.lat, 'lon': p.lon, 'accuracy_m': p.accuracyM,
        'last_seen_utc': p.lastSeen.toUtc().toIso8601String(),
        'last_heard_utc': p.lastHeardAt.toUtc().toIso8601String(),
        'last_fix_received_utc': p.lastFixSeen?.toUtc().toIso8601String(),
        'last_fix_source_utc': p.lastFixMeasuredAt?.toUtc().toIso8601String(),
        'fix_fresh': p.hasFreshFix,
      }).toList(growable: false),
    });
  }
}
