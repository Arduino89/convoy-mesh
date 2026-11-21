import '../../ble/ble_radar_ui.dart';
import '../../services/background_runtime_service.dart';
import '../../services/convoy_mesh_service.dart';
import '../../services/location_fusion_service.dart';
import 'radar_view_data.dart';

/// Read-only bridge from the existing services to [RadarViewData].
///
/// It reproduces the exact strings and conditions of the original
/// `BlePage` (mode line, peer GPS sentences, diagnostics lines) and calls only
/// existing public getters/static helpers. It never mutates service state.
class RadarLiveAdapter {
  const RadarLiveAdapter._();

  static RadarViewData read({
    required ConvoyMeshService mesh,
    required LocationFusionService location,
    required BackgroundRuntimeService runtime,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final fix = location.last;
    final fresh = fix?.hasFreshFixAt(at) ?? false;
    final peers = mesh.peers.values.toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    final modeText = runtime.isRunning
        ? fresh
            ? 'Uscita attiva • GPS recente • incertezza stimata ±${fix!.accuracyM!.toStringAsFixed(0)} m'
            : 'Uscita attiva • posizione non aggiornata • ultima misura ${ConvoyMeshService.ageLabel(fix?.measurementAt)}'
        : mesh.isRunning
            ? 'Modalità Vicini'
            : 'Ricerca vicini non attiva';
    final status = describeBleStatus(mesh.bleStatus.name);

    return RadarViewData(
      bleStatusName: mesh.bleStatus.name,
      bleLabel: status.label,
      bleReady: status.ready,
      scanning: mesh.isScanning,
      advertising: mesh.isAdvertising,
      onlineCount: mesh.onlinePeerCount,
      offlineCount: mesh.offlinePeerCount,
      modeText: modeText,
      outingActive: runtime.isRunning,
      gpsFresh: fresh,
      filterLine: runtime.isRunning && fix != null
          ? 'Filtro: ${fix.gpsDecision} • sensore movimento ${fix.motionReliable ? 'disponibile' : 'non affidabile / GPS-only'}'
          : null,
      myName: mesh.myName,
      myId: mesh.myId,
      peers: [for (final p in peers) peer(p)],
      diagnosticsLines: [
        'TX ${mesh.lastTxKind} seq ${mesh.lastTxSeq} • ${mesh.lastPayloadBytes} B',
        'Invii confermati Android ${mesh.advOkCount} • errori ${mesh.advErrorCount}',
        'Errore ADV: ${mesh.lastAdvError ?? '-'}',
        'RX: ${mesh.lastRxSummary}',
        'Ricezioni accettate ${mesh.rxValid} • POS ${mesh.rxFixPackets} • HISTORY ${mesh.rxHistoryPackets} • duplicati/stale ${mesh.rxStale} • parser ${mesh.rxRejected}',
        'Recupero traccia in attesa: ${mesh.pendingHistoryPoints} punti',
        'Eventi scan ${mesh.scanEventCount} • ultimo ${ConvoyMeshService.ageLabel(mesh.lastScanEventAt)}',
        'Restart ${mesh.scanRestartCount} • ${mesh.lastScanRestartReason}',
        'Il log distingue presenza radio, posizione live e punti di traccia recuperati.',
      ],
    );
  }

  /// Same wording/conditions as the original `_peerCard`.
  static RadarPeerView peer(PeerState peer) {
    final online = ConvoyMeshService.isPeerOnline(peer);
    final signal = peer.medianRssi;
    final name = peer.name?.trim().isNotEmpty == true ? peer.name! : 'User ${peer.userId}';

    final String gps;
    if (!peer.hasFix) {
      gps = peer.lastPositionPacketAt == null
          ? 'Peer presente • in attesa della prima posizione GPS'
          : 'Peer presente • posizione ricevuta ma non ancora utilizzabile';
    } else if (peer.lastFixMeasuredAt == null) {
      gps = 'Posizione ricevuta • età della misura sconosciuta';
    } else if (peer.hasFreshFix) {
      gps = 'Posizione recente • misura GPS ${ConvoyMeshService.ageLabel(peer.lastFixMeasuredAt)}';
    } else {
      gps = 'Peer presente • ultima posizione non recente (${ConvoyMeshService.ageLabel(peer.lastFixMeasuredAt)})';
    }
    final goodFix = peer.hasFreshFix && (peer.accuracyM ?? 9999) <= 50;

    return RadarPeerView(
      userId: peer.userId,
      name: name,
      color: ConvoyMeshService.colorForUser(peer.userId),
      online: online,
      gpsLine: gps,
      accuracyLine: peer.hasFix
          ? 'Incertezza stimata ±${(peer.accuracyM ?? 0).toStringAsFixed(0)} m'
          : null,
      historyLine: peer.rxHistoryPackets > 0
          ? 'Traccia recuperata: ${peer.rxHistoryPackets} punti'
          : null,
      signalQuality: ConvoyMeshService.rssiQuality(signal),
      rssi: signal,
      lastPacketLine: 'Ultimo pacchetto valido ${ConvoyMeshService.ageLabel(peer.lastSeen)}',
      locationState: goodFix
          ? PeerLocationState.fresh
          : online
              ? PeerLocationState.searching
              : PeerLocationState.off,
    );
  }
}
