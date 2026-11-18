import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../design/design_controller.dart';
import '../design/design_direction_picker.dart';
import '../design/design_tokens.dart';
import '../design/outdoor_components.dart';
import '../design/radar/designed_radar_view.dart';
import '../design/radar/radar_actions.dart';
import '../design/radar/radar_live_adapter.dart';
import '../services/background_runtime_service.dart';
import '../services/convoy_mesh_service.dart';
import '../services/location_fusion_service.dart';
import '../services/system_intents.dart';
import 'ble_radar_ui.dart';

class BlePage extends StatelessWidget {
  const BlePage({super.key});

  @override
  Widget build(BuildContext context) {
    final mesh = ConvoyMeshService.instance;
    final location = LocationFusionService.instance;
    final runtime = BackgroundRuntimeService.instance;
    final design = DesignDirectionController.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([mesh, location, runtime, design]),
      builder: (context, _) {
        if (!design.isClassic) {
          return DesignedRadarView(
            tokens: design.outdoorTokens,
            data: RadarLiveAdapter.read(
              mesh: mesh,
              location: location,
              runtime: runtime,
            ),
            actions: RadarActions(
              onStatusTap: () => _onBluetoothStatusTap(
                context, mesh.bleStatus.name, mesh.isScanning),
              onHelp: () => _showRadarHelp(context),
              onEditName: () => _editName(context, mesh),
              onOpenBluetooth: SystemIntents.openBluetoothSettings,
              onOpenLocation: SystemIntents.openLocationSettings,
              onOpenAppPermissions: () => ph.openAppSettings(),
              onSendName: mesh.spamMyNameNow,
              onRestartScan: () => mesh.restartScanForDebug(reason: 'manual_button'),
              onClearOffline: mesh.clearOfflinePeers,
              onRegenerateId: () => _regenerate(context, mesh),
              onChooseDesign: () => showDesignDirectionPicker(context),
            ),
          );
        }

        final fix = location.last;
        final fresh = fix?.hasFreshFixAt(DateTime.now()) ?? false;
        final peers = mesh.peers.values.toList()
          ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
        final modeText = runtime.isRunning
            ? fresh
                ? 'Uscita attiva • GPS recente • incertezza stimata ±${fix!.accuracyM!.toStringAsFixed(0)} m'
                : 'Uscita attiva • posizione non aggiornata • ultima misura ${ConvoyMeshService.ageLabel(fix?.measurementAt)}'
            : mesh.isRunning
                ? 'Modalità Vicini'
                : 'Ricerca vicini non attiva';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Radar BLE'),
            actions: [
              IconButton(
                key: const Key('radar-open-design-btn'),
                tooltip: 'Stili UI e Design Studio',
                icon: const Icon(Icons.palette_outlined),
                onPressed: () => showDesignDirectionPicker(context),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BleStatusBanner(
                        statusName: mesh.bleStatus.name,
                        onTap: () => _onBluetoothStatusTap(
                          context, mesh.bleStatus.name, mesh.isScanning),
                      ),
                      Wrap(
                        spacing: 6,
                        children: [
                          ScanStatusChip(scanning: mesh.isScanning),
                          Chip(label: Text(mesh.isAdvertising ? 'ADV ON' : 'ADV OFF')),
                          Chip(label: Text('Presenti ${mesh.onlinePeerCount}')),
                          Chip(label: Text('Non ricevuti ${mesh.offlinePeerCount}')),
                        ],
                      ),
                      Row(children: [
                        Expanded(child: Text(modeText,
                          style: Theme.of(context).textTheme.bodyMedium)),
                        IconButton(
                          tooltip: 'Come funzionano Vicini, GPS e segnale BLE',
                          icon: const Icon(Icons.help_outline),
                          onPressed: () => _showRadarHelp(context),
                        ),
                      ]),
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
                            label: Text('Nome: ${mesh.myName}',
                              style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
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
                      'Nessun partecipante rilevato. Tocca ? per sapere come funziona la ricerca.',
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
        title: Text('$name • ${online ? 'presente' : 'segnale non ricevuto'}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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

  Future<void> _onBluetoothStatusTap(
      BuildContext context, String statusName, bool scanning) async {
    final view = describeBleStatus(statusName);
    switch (view.action) {
      case BleStatusAction.readyInfo:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(scanning
                ? 'Bluetooth correttamente acceso. Ricerca vicini attiva.'
                : 'Bluetooth correttamente acceso. Ricerca vicini non attiva.'),
            duration: const Duration(seconds: 2),
          ),
        );
      case BleStatusAction.bluetoothSettings:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth spento: apro le impostazioni.'),
            duration: Duration(seconds: 2)),
        );
        await SystemIntents.openBluetoothSettings();
      case BleStatusAction.appPermissions:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'Permessi mancanti: controlla Dispositivi vicini nelle impostazioni dell’app.'),
            duration: Duration(seconds: 3)),
        );
        final opened = await ph.openAppSettings();
        if (!opened && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(
              'Non riesco ad aprire le impostazioni. Fallo dalle impostazioni Android.')),
          );
        }
      case BleStatusAction.locationSettings:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'Attiva la Posizione dalle impostazioni Android.'),
            duration: Duration(seconds: 3)),
        );
        await SystemIntents.openLocationSettings();
      case BleStatusAction.explain:
        final t = ConvoyDesignTokens.maybeOf(context);
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: t != null
                ? OutdoorDialogTitle(
                    tokens: t,
                    icon: Icons.bluetooth_searching,
                    title: view.label,
                    tone: OutdoorTone.warning,
                  )
                : Text(view.label),
            content: Text(view.explanation, style: t?.body(14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Ho capito'),
              ),
            ],
          ),
        );
    }
  }

  Future<void> _showRadarHelp(BuildContext context) async {
    final t = ConvoyDesignTokens.maybeOf(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: t != null
            ? OutdoorDialogTitle(
                tokens: t,
                icon: Icons.explore_outlined,
                title: 'Come funziona il Radar BLE?',
              )
            : const Text('Come funziona il Radar BLE?'),
        content: SingleChildScrollView(
          child: Text(
            'Modalità Vicini: trova gli altri telefoni che hanno Convoy Mesh '
            'aperto, senza avviare il GPS continuo. Non serve '
            'l’accoppiamento Bluetooth classico.\n\n'
            'Avvia uscita: abilita la raccolta e lo scambio delle posizioni '
            'GPS e la traccia, anche con schermo spento quando Android '
            'permette al servizio in primo piano di operare.\n\n'
            'Un telefono può essere visibile via Bluetooth anche se '
            'l’ultima posizione GPS è vecchia. Il segnale BLE (RSSI) '
            'non misura la distanza in metri; l’incertezza GPS '
            'non è la distanza tra i telefoni.\n\n'
            'Le mappe di sfondo online non diventano offline per il '
            'solo fatto che lo scambio BLE funziona senza Internet.',
            style: t?.body(14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  Future<void> _editName(BuildContext context, ConvoyMeshService mesh) async {
    final t = ConvoyDesignTokens.maybeOf(context);
    var name = mesh.myName;
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: t != null
            ? OutdoorDialogTitle(
                tokens: t,
                icon: Icons.badge_outlined,
                title: 'Imposta nome',
              )
            : const Text('Imposta nome'),
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
    final t = ConvoyDesignTokens.maybeOf(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: t != null
            ? OutdoorDialogTitle(
                tokens: t,
                icon: Icons.fingerprint,
                title: 'Cambiare identità?',
                tone: OutdoorTone.warning,
              )
            : const Text('Cambiare identità?'),
        content: Text(
          'Gli altri telefoni manterranno il vecchio ID come non ricevuto finché non verrà rimosso.',
          style: t?.body(14),
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
