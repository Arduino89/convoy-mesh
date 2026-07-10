import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'convoy_mesh_service.dart';
import 'diagnostic_recorder.dart';

class DiagnosticCaptureBridge {
  DiagnosticCaptureBridge._();

  static final DiagnosticCaptureBridge instance = DiagnosticCaptureBridge._();

  bool _attached = false;
  DateTime? _lastTxAt;
  DateTime? _lastRxAt;
  DateTime? _lastScanRestartAt;
  BleStatus? _lastBleStatus;
  String _lastPeerFingerprint = '';

  void attach() {
    if (_attached) return;
    _attached = true;
    ConvoyMeshService.instance.addListener(_onMeshChanged);
  }

  void captureNow() {
    _lastTxAt = null;
    _lastRxAt = null;
    _lastScanRestartAt = null;
    _lastBleStatus = null;
    _lastPeerFingerprint = '';
    _onMeshChanged();
  }

  void _onMeshChanged() {
    final recorder = DiagnosticRecorder.instance;
    if (!recorder.isActive) return;

    final mesh = ConvoyMeshService.instance;

    if (_lastBleStatus != mesh.bleStatus) {
      _lastBleStatus = mesh.bleStatus;
      recorder.record(
        'ble',
        'status',
        data: <String, Object?>{
          'status': mesh.bleStatus.name,
          'scanning': mesh.isScanning,
          'advertising': mesh.isAdvertising,
          'location_enabled': mesh.localLocationServiceEnabled,
          'scan_may_be_blocked': mesh.scanMayBeBlockedByLocation,
        },
      );
    }

    if (_lastTxAt != mesh.lastTxAt) {
      _lastTxAt = mesh.lastTxAt;
      if (_lastTxAt != null) {
        recorder.record(
          'ble',
          'tx',
          data: <String, Object?>{
            'kind': mesh.lastTxKind,
            'seq': mesh.lastTxSeq,
            'payload_bytes': mesh.lastPayloadBytes,
            'advertising': mesh.isAdvertising,
            'adv_ok_count': mesh.advOkCount,
            'adv_error_count': mesh.advErrorCount,
            'last_adv_error': mesh.lastAdvError,
          },
        );
      }
    }

    if (_lastRxAt != mesh.lastRxAt) {
      _lastRxAt = mesh.lastRxAt;
      if (_lastRxAt != null) {
        recorder.record(
          'ble',
          'rx',
          data: <String, Object?>{
            'summary': mesh.lastRxSummary,
            'valid_total': mesh.rxValid,
            'fix_total': mesh.rxFixPackets,
            'name_total': mesh.rxNamePackets,
            'self_total': mesh.rxIgnoredSelf,
            'stale_total': mesh.rxStale,
            'no_magic_total': mesh.rxNoMagic,
            'bad_total': mesh.rxBadPacket,
            'no_manufacturer_data_total': mesh.rxNoManufacturerData,
            'parse_reason': mesh.lastParseReason,
            'magic_offset': mesh.lastMagicOffset,
            'manufacturer_bytes': mesh.lastMdBytes,
            'manufacturer_preview': mesh.lastMdHex,
          },
        );
      }
    }

    if (_lastScanRestartAt != mesh.lastScanRestartAt) {
      _lastScanRestartAt = mesh.lastScanRestartAt;
      if (_lastScanRestartAt != null) {
        recorder.record(
          'ble',
          'scan_restart',
          data: <String, Object?>{
            'count': mesh.scanRestartCount,
            'reason': mesh.lastScanRestartReason,
            'scan_events': mesh.scanEventCount,
            'scanning': mesh.isScanning,
          },
        );
      }
    }

    final peers = mesh.peers.values.toList()
      ..sort((a, b) => a.userId.compareTo(b.userId));
    final fingerprint = peers
        .map(
          (peer) => '${peer.userId}:${peer.lastSeq}:${peer.lastFixSeq}:${peer.lastNameSeq}:${peer.rssi}:${peer.lastSeen.microsecondsSinceEpoch}:${peer.lastFixSeen?.microsecondsSinceEpoch ?? 0}',
        )
        .join('|');

    if (_lastPeerFingerprint != fingerprint) {
      _lastPeerFingerprint = fingerprint;
      recorder.record(
        'peer',
        'snapshot',
        data: <String, Object?>{
          'online_count': mesh.onlinePeerCount,
          'offline_count': mesh.offlinePeerCount,
          'peers': peers
              .map(
                (peer) => <String, Object?>{
                  'id': peer.userId,
                  'name': peer.name,
                  'online': ConvoyMeshService.isPeerOnline(peer),
                  'rssi': peer.rssi,
                  'last_seq': peer.lastSeq,
                  'last_fix_seq': peer.lastFixSeq,
                  'last_name_seq': peer.lastNameSeq,
                  'lat': peer.lat,
                  'lon': peer.lon,
                  'accuracy_m': peer.accuracyM,
                  'last_seen_utc': peer.lastSeen.toUtc().toIso8601String(),
                  'last_heard_utc': peer.lastHeardAt.toUtc().toIso8601String(),
                  'last_fix_utc': peer.lastFixSeen?.toUtc().toIso8601String(),
                  'rx_packets': peer.rxPackets,
                  'rx_fix_packets': peer.rxFixPackets,
                  'rx_name_packets': peer.rxNamePackets,
                },
              )
              .toList(growable: false),
        },
      );
    }
  }
}
