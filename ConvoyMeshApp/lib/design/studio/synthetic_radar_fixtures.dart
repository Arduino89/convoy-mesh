import '../../ble/ble_radar_ui.dart';
import '../../location/gps_visual_state.dart';
import '../../services/convoy_mesh_service.dart';
import '../radar/radar_view_data.dart';

/// Synthetic scenarios used solely for design studio previews and rendered
/// comparison screenshots. No real device IDs, logs, or GPS traces are used.
enum SyntheticScenario {
  groupHike,
  activeOuting,
  emptySearch,
  bluetoothBlocked,
}

extension SyntheticScenarioMeta on SyntheticScenario {
  String get label => switch (this) {
        SyntheticScenario.groupHike => 'Gruppo in cammino (3)',
        SyntheticScenario.activeOuting => 'Uscita GPS attiva',
        SyntheticScenario.emptySearch => 'Solo ricerca (0 peer)',
        SyntheticScenario.bluetoothBlocked => 'Bluetooth spento',
      };
}

class SyntheticRadarFixtures {
  const SyntheticRadarFixtures._();

  static RadarViewData of(SyntheticScenario scenario) {
    final statusName = switch (scenario) {
      SyntheticScenario.bluetoothBlocked => 'poweredOff',
      _ => 'ready',
    };
    final status = describeBleStatus(statusName);

    final peers = switch (scenario) {
      SyntheticScenario.emptySearch || SyntheticScenario.bluetoothBlocked =>
        const <RadarPeerView>[],
      SyntheticScenario.groupHike || SyntheticScenario.activeOuting => [
          RadarPeerView(
            userId: 1042,
            name: 'Marco R.',
            color: ConvoyMeshService.colorForUser(1042),
            online: true,
            gpsLine: 'Posizione recente • misura GPS 4s fa',
            accuracyLine: 'Incertezza stimata ±8 m',
            historyLine: null,
            signalQuality: 'Ottimo',
            rssi: -58,
            lastPacketLine: 'Ultimo pacchetto valido 2s fa',
            locationState: PeerLocationState.fresh,
          ),
          RadarPeerView(
            userId: 2089,
            name: 'Elena V.',
            color: ConvoyMeshService.colorForUser(2089),
            online: true,
            gpsLine: 'Peer presente • in attesa della prima posizione GPS',
            accuracyLine: null,
            historyLine: null,
            signalQuality: 'Buono',
            rssi: -68,
            lastPacketLine: 'Ultimo pacchetto valido 5s fa',
            locationState: PeerLocationState.searching,
          ),
          RadarPeerView(
            userId: 3317,
            name: 'Luca B.',
            color: ConvoyMeshService.colorForUser(3317),
            online: false,
            gpsLine: 'Peer presente • ultima posizione non recente (1m fa)',
            accuracyLine: 'Incertezza stimata ±24 m',
            historyLine: 'Traccia recuperata: 6 punti',
            signalQuality: 'Scarso',
            rssi: -88,
            lastPacketLine: 'Ultimo pacchetto valido 46s fa',
            locationState: PeerLocationState.off,
          ),
        ],
    };

    final onlineCount = peers.where((p) => p.online).length;
    final offlineCount = peers.length - onlineCount;
    final scanning = scenario != SyntheticScenario.bluetoothBlocked;
    final advertising = scenario != SyntheticScenario.bluetoothBlocked;
    final outing = scenario == SyntheticScenario.activeOuting;

    return RadarViewData(
      bleStatusName: statusName,
      bleLabel: status.label,
      bleReady: status.ready,
      scanning: scanning,
      advertising: advertising,
      onlineCount: onlineCount,
      offlineCount: offlineCount,
      modeText: outing
          ? 'Uscita attiva • GPS recente • incertezza stimata ±7 m'
          : (scanning ? 'Modalità Vicini' : 'Ricerca vicini non attiva'),
      outingActive: outing,
      gpsFresh: outing,
      filterLine: outing
          ? 'Filtro: accept_moving • sensore movimento disponibile'
          : null,
      myName: 'Chiara M.',
      myId: 4096,
      peers: peers,
      diagnosticsLines: [
        'TX ${outing ? 'POS' : 'NAME'} seq 18 • ${outing ? 28 : 19} B',
        'Invii confermati Android ${scanning ? 42 : 0} • errori ${scanning ? 0 : 1}',
        'Errore ADV: ${scanning ? '-' : 'adapter_disabled'}',
        'RX: ${peers.isEmpty ? '-' : 'Marco R. (-58 dBm) • Elena V. (-68 dBm)'}',
        'Ricezioni accettate ${peers.isEmpty ? 0 : 19} • POS ${peers.isEmpty ? 0 : 8} • HISTORY ${peers.isEmpty ? 0 : 6} • duplicati/stale 3 • parser 0',
        'Recupero traccia in attesa: 0 punti',
        'Eventi scan ${scanning ? 64 : 0} • ultimo ${scanning ? '2s fa' : '-'}',
        'Restart 0 • -',
        'Il log distingue presenza radio, posizione live e punti di traccia recuperati.',
      ],
    );
  }

  static GpsVisualState gpsVisualOf(SyntheticScenario scenario) => switch (scenario) {
        SyntheticScenario.activeOuting => const GpsVisualState(
            mode: GpsVisualMode.stable,
            quality: 92,
            blinkPeriod: null,
            label: 'GPS agganciato • qualità 92%',
          ),
        SyntheticScenario.groupHike => const GpsVisualState(
            mode: GpsVisualMode.searching,
            quality: 0,
            blinkPeriod: Duration(milliseconds: 1500),
            label: 'Ricerca posizione…',
          ),
        _ => const GpsVisualState(
            mode: GpsVisualMode.off,
            quality: 0,
            blinkPeriod: null,
            label: 'Posizione non agganciata',
          ),
      };

  static String gpsTextOf(SyntheticScenario scenario) => switch (scenario) {
        SyntheticScenario.activeOuting => 'GPS pronto. Incertezza ±7 m.',
        SyntheticScenario.groupHike => 'Ricerca GPS in corso…',
        _ => 'GPS non agganciato. Tocca il mirino per cercare la posizione.',
      };
}
