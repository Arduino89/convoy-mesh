import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../services/background_runtime_service.dart';
import '../services/convoy_mesh_service.dart';
import '../services/location_fusion_service.dart';
import '../services/system_intents.dart';

class BlePage extends StatelessWidget {
  const BlePage({super.key});

  @override
  Widget build(BuildContext context) {
    final mesh = ConvoyMeshService.instance;
    final location = LocationFusionService.instance;
    final runtime = BackgroundRuntimeService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([mesh, location, runtime]),
      builder: (context, _) {
        final fix = location.last;
        final fresh = fix?.hasFreshFixAt(DateTime.now()) ?? false;
        final peers = mesh.peers.values.toList()
          ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
        final modeText = runtime.isRunning
            ? fresh
                ? 'Uscita attiva • GPS recente • incertezza stimata ±${fix!.accuracyM!.toStringAsFixed(0)} m'
                : 'Uscita attiva • posizione non aggiornata • ultima misura ${ConvoyMeshService.ageLabel(fix?.measurementAt)}'
            : mesh.isRunning
                ? 'Modalità Vicini • rilevo persone con Convoy Mesh aperto; GPS non condiviso finché non avvii l’uscita.'
                : 'Ricerca vicini non attiva';

        return Scaffold(
          appBar: AppBar(title: const Text('Radar BLE')),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bluetooth: ${mesh.bleStatus.name}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Wrap(
                        spacing: 6,
                        children: [
                          Chip(label: Text(mesh.isScanning ? 'Scan ON' : 'Scan OFF')),
                          Chip(label: Text(mesh.isAdvertising ? 'ADV ON' : 'ADV OFF')),
                          Chip(label: Text('Presenti ${mesh.onlinePeerCount}')),
                          Chip(label: Text('Non ricevuti ${mesh.offlinePeerCount}')),
                        ],
                      ),
                      Text(modeText),
                      const Text(
                        'L’incertezza GPS non è la distanza fra i telefoni. Il segnale BLE non misura metri.',
                      ),
                      if (runtime.isRunning && fix != null)
                        Text(
                          'Filtro: ${fix.gpsDecision} • sensore movimento ${fix.motionReliable ? 'disponibile' : 'non affidabile / GPS-only'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: SystemIntents.openBluetoothSettings,
                            icon: const Icon(Icons.settings_bluetooth),
                            label: const Text('Bluetooth'),
                          ),
                          OutlinedButton.icon(
                            onPressed: SystemIntents.openLocationSettings,
                            icon: const Icon(Icons.location_on),
                            label: const Text('Posizione'),
                          ),
                          OutlinedButton(
                            onPressed: () => ph.openAppSettings(),
                            child: const Text('Permessi app'),
                          ),
                          OutlinedButton(
                            onPressed: mesh.spamMyNameNow,
                            child: const Text('Invia nome'),
                          ),
                          OutlinedButton(
                            onPressed: () => mesh.restartScanForDebug(reason: 'manual_button'),
                            child: const Text('Riavvia scan'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _editName(context, mesh),
                            icon: const Icon(Icons.edit),
                            label: Text('Nome: ${mesh.myName}'),
                          ),
                        ],
                      ),
                      SelectableText('Il mio ID: ${mesh.myId}'),
                      if (mesh.offlinePeerCount > 0)
                        TextButton(
                          onPressed: mesh.clearOfflinePeers,
                          child: const Text('Rimuovi dalla lista i peer non ricevuti'),
                        ),
                    ],
                  ),
                ),
              ),
              if (peers.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'Nessun partecipante ricevuto. Basta tenere Convoy Mesh aperto su entrambi i telefoni per vedersi nel Radar; “Avvia uscita” serve per condividere posizione, traccia e continuare in background. Non serve l’accoppiamento Bluetooth classico.',
                    ),
                  ),
                ),
              ...peers.map((peer) => _peerCard(peer)),
              Card(
                child: ExpansionTile(
                  title: const Text('Diagnostica BLE'),
                  childrenPadding: const EdgeInsets.all(14),
                  children: [
                    Text('TX ${mesh.lastTxKind} seq ${mesh.lastTxSeq} • ${mesh.lastPayloadBytes} B'),
                    Text('Invii confermati Android ${mesh.advOkCount} • errori ${mesh.advErrorCount}'),
                    Text('Errore ADV: ${mesh.lastAdvError ?? '-'}'),
                    Text('RX: ${mesh.lastRxSummary}'),
                    Text(
                      'Ricezioni accettate ${mesh.rxValid} • POS ${mesh.rxFixPackets} • HISTORY ${mesh.rxHistoryPackets} • duplicati/stale ${mesh.rxStale} • parser ${mesh.rxRejected}',
                    ),
                    Text(
                      'Recupero traccia in attesa: ${mesh.pendingHistoryPoints} punti',
                    ),
                    Text(
                      'Eventi scan ${mesh.scanEventCount} • ultimo ${ConvoyMeshService.ageLabel(mesh.lastScanEventAt)}',
                    ),
                    Text('Restart ${mesh.scanRestartCount} • ${mesh.lastScanRestartReason}'),
                    const Text(
                      'Il log distingue presenza radio, posizione live e punti di traccia recuperati.',
                    ),
                  ],
                ),
              ),
              Card(
                child: ExpansionTile(
                  title: const Text('Avanzate'),
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Cambia ID solo in caso di collisione. Gli altri telefoni vedranno un nuovo partecipante.',
                      ),
                    ),
                    TextButton(
                      onPressed: () => _regenerate(context, mesh),
                      child: const Text('Rigenera ID…'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _peerCard(PeerState peer) {
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

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Color(ConvoyMeshService.colorForUser(peer.userId)),
          child: Icon(online ? Icons.person : Icons.person_off, color: Colors.white),
        ),
        title: Text('$name • ${online ? 'presente' : 'segnale non ricevuto'}'),
        subtitle: Text(
          '$gps\n'
          '${peer.hasFix ? 'Incertezza stimata ±${(peer.accuracyM ?? 0).toStringAsFixed(0)} m\n' : ''}'
          '${peer.rxHistoryPackets > 0 ? 'Traccia recuperata: ${peer.rxHistoryPackets} punti\n' : ''}'
          'Segnale BLE: ${ConvoyMeshService.rssiQuality(signal)} • mediana $signal dBm\n'
          'Ultimo pacchetto valido ${ConvoyMeshService.ageLabel(peer.lastSeen)}',
        ),
        trailing: Icon(
          peer.hasFreshFix && (peer.accuracyM ?? 9999) <= 50
              ? Icons.location_on
              : online
                  ? Icons.location_searching
                  : Icons.location_off,
          color: peer.hasFreshFix && (peer.accuracyM ?? 9999) <= 50
              ? Colors.green
              : Colors.orange,
        ),
      ),
    );
  }

  Future<void> _editName(BuildContext context, ConvoyMeshService mesh) async {
    var name = mesh.myName;
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Imposta nome'),
        content: TextFormField(
          initialValue: name,
          maxLength: 10,
          onChanged: (v) => name = v,
          decoration: const InputDecoration(hintText: 'Es: Cama / Fra'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, name),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (value != null) await mesh.setMyName(value);
  }

  Future<void> _regenerate(BuildContext context, ConvoyMeshService mesh) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiare identità?'),
        content: const Text(
          'Gli altri telefoni manterranno il vecchio ID come non ricevuto finché non verrà rimosso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rigenera'),
          ),
        ],
      ),
    );
    if (yes == true) await mesh.regenerateMyId();
  }
}
