import 'package:flutter/material.dart';

import '../../ble/ble_radar_ui.dart';
import '../radar/radar_actions.dart';
import '../radar/radar_view_data.dart';

/// Faithful reproduction of the pre-redesign (LAB +15) Radar BLE layout driven
/// by [RadarViewData] and [RadarActions], used in the Design Studio and
/// side-by-side comparison renders without touching live services.
class OriginalRadarPreview extends StatelessWidget {
  const OriginalRadarPreview({
    super.key,
    required this.data,
    required this.actions,
  });

  final RadarViewData data;
  final RadarActions actions;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      child: Scaffold(
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
                    BleStatusBanner(
                      statusName: data.bleStatusName,
                      onTap: actions.onStatusTap,
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        ScanStatusChip(scanning: data.scanning),
                        Chip(label: Text(data.advertising ? 'ADV ON' : 'ADV OFF')),
                        Chip(label: Text('Presenti ${data.onlineCount}')),
                        Chip(label: Text('Non ricevuti ${data.offlineCount}')),
                      ],
                    ),
                    Row(children: [
                      Expanded(
                        child: Text(
                          data.modeText,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Come funzionano Vicini, GPS e segnale BLE',
                        icon: const Icon(Icons.help_outline),
                        onPressed: actions.onHelp,
                      ),
                    ]),
                    if (data.filterLine != null)
                      Text(data.filterLine!, style: const TextStyle(fontSize: 12)),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: actions.onOpenBluetooth,
                          icon: const Icon(Icons.settings_bluetooth),
                          label: const Text('Bluetooth'),
                        ),
                        OutlinedButton.icon(
                          onPressed: actions.onOpenLocation,
                          icon: const Icon(Icons.location_on),
                          label: const Text('Posizione'),
                        ),
                        OutlinedButton(
                          onPressed: actions.onOpenAppPermissions,
                          child: const Text('Permessi app'),
                        ),
                        OutlinedButton(
                          onPressed: actions.onSendName,
                          child: const Text('Invia nome'),
                        ),
                        OutlinedButton(
                          onPressed: actions.onRestartScan,
                          child: const Text('Riavvia scan'),
                        ),
                        OutlinedButton.icon(
                          onPressed: actions.onEditName,
                          icon: const Icon(Icons.edit),
                          label: Text(
                            'Nome: ${data.myName}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    SelectableText('Il mio ID: ${data.myId}'),
                    if (data.offlineCount > 0)
                      TextButton(
                        onPressed: actions.onClearOffline,
                        child: const Text('Rimuovi dalla lista i peer non ricevuti'),
                      ),
                  ],
                ),
              ),
            ),
            if (data.peers.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Nessun partecipante rilevato. Tocca ? per sapere come funziona la ricerca.',
                  ),
                ),
              ),
            for (final peer in data.peers) _originalPeerCard(peer),
            Card(
              child: ExpansionTile(
                title: const Text('Diagnostica BLE'),
                childrenPadding: const EdgeInsets.all(14),
                children: [
                  for (final line in data.diagnosticsLines) Text(line),
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
                    onPressed: actions.onRegenerateId,
                    child: const Text('Rigenera ID…'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _originalPeerCard(RadarPeerView peer) {
    final trailingIcon = switch (peer.locationState) {
      PeerLocationState.fresh => Icons.location_on,
      PeerLocationState.searching => Icons.location_searching,
      PeerLocationState.off => Icons.location_off,
    };
    final trailingColor =
        peer.locationState == PeerLocationState.fresh ? Colors.green : Colors.orange;
    final lines = [
      peer.gpsLine,
      if (peer.accuracyLine != null) peer.accuracyLine!,
      if (peer.historyLine != null) peer.historyLine!,
      peer.signalLine,
      peer.lastPacketLine,
    ];
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Color(peer.color),
          child: Icon(peer.online ? Icons.person : Icons.person_off, color: Colors.white),
        ),
        title: Text(
          '${peer.name} • ${peer.statusLabel}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(lines.join('\n')),
        trailing: Icon(trailingIcon, color: trailingColor),
      ),
    );
  }
}
