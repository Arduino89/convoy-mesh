import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../location/fused_location.dart';
import '../services/convoy_mesh_service.dart';
import '../services/location_fusion_service.dart';
import '../services/system_intents.dart';

class BlePage extends StatelessWidget {
  const BlePage({super.key});

  Color _btColor(BleStatus s) {
    if (s == BleStatus.ready) return Colors.green;
    if (s == BleStatus.poweredOff) return Colors.red;
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    final svc = ConvoyMeshService.instance;
    final loc = LocationFusionService.instance;

    return AnimatedBuilder(
      animation: Listenable.merge([svc, loc]),
      builder: (context, _) {
        final status = svc.bleStatus;

        final peers = svc.peers.values.toList()
          ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
        final onlinePeers = peers.where(ConvoyMeshService.isPeerOnline).length;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Radar BLE'),
            actions: [
              Icon(Icons.bluetooth, color: _btColor(status)),
              const SizedBox(width: 12),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _StatusCard(
                status: status,
                peersCount: peers.length,
                onlinePeers: onlinePeers,
                offlinePeers: svc.offlinePeerCount,
                location: loc.last,
              ),
              const SizedBox(height: 10),
              _DebugCard(),
              const SizedBox(height: 10),
              const _TestGuideCard(),
              const SizedBox(height: 10),
              if (peers.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'Nessun peer trovato. Per testare: Bluetooth ON, Posizione Android ON, app aperta su entrambi i telefoni. Se resta vuoto, prova “Riavvia scan”. Non serve accoppiamento Bluetooth classico.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                ),
              ...peers.map((p) => _PeerCard(peer: p)),
            ],
          ),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  final BleStatus status;
  final int peersCount;
  final int onlinePeers;
  final int offlinePeers;
  final FusedLocation? location;

  const _StatusCard({
    required this.status,
    required this.peersCount,
    required this.onlinePeers,
    required this.offlinePeers,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    final svc = ConvoyMeshService.instance;
    final gps = _gpsInfo(location);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _btLabel(status),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(
                  icon: Icons.radar,
                  label: svc.isScanning ? 'Scan ON' : 'Scan OFF',
                  ok: svc.isScanning && !svc.scanMayBeBlockedByLocation,
                ),
                _Chip(
                  icon: Icons.campaign,
                  label: svc.isAdvertising ? 'ADV ON' : 'ADV OFF',
                  ok: svc.isAdvertising,
                ),
                _Chip(
                  icon: Icons.people,
                  label: 'Peer $peersCount',
                  ok: peersCount > 0,
                ),
                _Chip(
                  icon: Icons.wifi_tethering,
                  label: 'Online $onlinePeers',
                  ok: onlinePeers > 0,
                ),
                if (offlinePeers > 0)
                  _Chip(
                    icon: Icons.history,
                    label: 'Offline $offlinePeers',
                    ok: false,
                  ),
                _Chip(
                  icon: gps.icon,
                  label: gps.label,
                  ok: gps.ok,
                ),
              ],
            ),
            if (svc.scanMayBeBlockedByLocation) ...[
              const SizedBox(height: 10),
              Text(
                'Su molti Android la ricezione BLE richiede Posizione ON: potresti trasmettere ma non ricevere peer.',
                style: TextStyle(color: Colors.orange.shade900),
              ),
            ],
            if (!gps.ok) ...[
              const SizedBox(height: 10),
              Text(gps.help, style: TextStyle(color: Colors.orange.shade800)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => SystemIntents.openBluetoothSettings(),
                    icon: const Icon(Icons.settings_bluetooth),
                    label: const Text('Impostazioni BT'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => SystemIntents.openLocationSettings(),
                    icon: const Icon(Icons.location_on),
                    label: const Text('Impostazioni GPS'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => svc.spamMyNameNow(),
                    icon: const Icon(Icons.badge),
                    label: const Text('Invia nome'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => svc.restartScanForDebug(reason: 'manual_button'),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Riavvia scan'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ph.openAppSettings(),
                    icon: const Icon(Icons.app_settings_alt),
                    label: const Text('Permessi app'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final res = await _editName(context, svc.myName);
                      if (res != null) await svc.setMyName(res);
                    },
                    icon: const Icon(Icons.edit),
                    label: Text('Nome: ${svc.myName}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText('Il mio ID: ${svc.myId}'),
            const SizedBox(height: 8),
            if (offlinePeers > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => svc.clearOfflinePeers(),
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: Text('Pulisci peer offline ($offlinePeers)'),
                ),
              ),
            const SizedBox(height: 4),
            const Text(
              'Avanzate: cambia ID solo se due telefoni hanno lo stesso ID o se stai facendo debug.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            _HoldToRegenerateIdButton(
              onComplete: () async {
                await svc.regenerateMyId();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nuovo ID generato. Gli altri telefoni ti vedranno come nuovo dispositivo.')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  String _btLabel(BleStatus s) {
    if (s == BleStatus.ready) return 'Bluetooth OK';
    if (s == BleStatus.poweredOff) return 'Bluetooth SPENTO';
    return 'Bluetooth: $s';
  }

  _GpsInfo _gpsInfo(FusedLocation? loc) {
    if (loc == null) {
      return const _GpsInfo(
        ok: false,
        icon: Icons.location_searching,
        label: 'GPS avvio',
        help: 'Sto inizializzando la posizione.',
      );
    }

    if (!loc.hasPermission) {
      return const _GpsInfo(
        ok: false,
        icon: Icons.location_disabled,
        label: 'Permesso GPS mancante',
        help: 'Concedi il permesso posizione dalle impostazioni app.',
      );
    }

    if (!loc.serviceEnabled || loc.gpsState == GpsUiState.off) {
      return const _GpsInfo(
        ok: false,
        icon: Icons.location_off,
        label: 'Posizione spenta',
        help: 'Attiva la posizione Android per trasmettere coordinate agli altri telefoni.',
      );
    }

    if (loc.gpsState == GpsUiState.ok) {
      return _GpsInfo(
        ok: true,
        icon: Icons.gps_fixed,
        label: 'GPS OK ${loc.gpsBars}/4',
        help: '',
      );
    }

    return _GpsInfo(
      ok: false,
      icon: Icons.location_searching,
      label: 'Ricerca GPS ${loc.gpsBars}/4',
      help: 'Se sei al chiuso, avvicinati a una finestra o prova all’aperto.',
    );
  }

  Future<String?> _editName(BuildContext context, String current) async {
    final ctrl = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Imposta nome'),
          content: TextField(
            controller: ctrl,
            maxLength: 10,
            decoration: const InputDecoration(
              helperText: 'Consiglio: nome corto, es. Cama / Fra',
              hintText: 'Es: Cama',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Salva')),
          ],
        );
      },
    );
  }
}

class _GpsInfo {
  final bool ok;
  final IconData icon;
  final String label;
  final String help;

  const _GpsInfo({
    required this.ok,
    required this.icon,
    required this.label,
    required this.help,
  });
}

class _HoldToRegenerateIdButton extends StatefulWidget {
  final Future<void> Function() onComplete;

  const _HoldToRegenerateIdButton({required this.onComplete});

  @override
  State<_HoldToRegenerateIdButton> createState() => _HoldToRegenerateIdButtonState();
}

class _HoldToRegenerateIdButtonState extends State<_HoldToRegenerateIdButton> {
  static const _holdDuration = Duration(seconds: 3);
  static const _tick = Duration(milliseconds: 40);

  Timer? _timer;
  DateTime? _startedAt;
  double _progress = 0;
  bool _busy = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startHold() {
    if (_busy || _timer != null) return;

    _startedAt = DateTime.now();
    setState(() => _progress = 0);

    _timer = Timer.periodic(_tick, (timer) async {
      final started = _startedAt;
      if (started == null) return;

      final elapsedMs = DateTime.now().difference(started).inMilliseconds;
      final next = (elapsedMs / _holdDuration.inMilliseconds).clamp(0.0, 1.0).toDouble();

      if (mounted) setState(() => _progress = next);

      if (next >= 1.0) {
        timer.cancel();
        _timer = null;
        _startedAt = null;
        if (!mounted) return;

        setState(() => _busy = true);
        try {
          await widget.onComplete();
        } finally {
          if (mounted) {
            setState(() {
              _busy = false;
              _progress = 0;
            });
          }
        }
      }
    });
  }

  void _cancelHold() {
    if (_timer == null) return;
    _timer?.cancel();
    _timer = null;
    _startedAt = null;
    if (mounted) setState(() => _progress = 0);
  }

  @override
  Widget build(BuildContext context) {
    final isHolding = _timer != null;
    final secondsLeft = (3 - (_progress * 3)).ceil().clamp(1, 3).toInt();
    final text = _busy
        ? 'Rigenero ID...'
        : isHolding
            ? 'Tieni premuto... $secondsLeft'
            : 'Tieni premuto 3s per rigenerare ID';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _startHold(),
      onTapUp: (_) => _cancelHold(),
      onTapCancel: _cancelHold,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade700),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _progress,
                child: Container(color: Colors.orange.withOpacity(0.22)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _TestGuideCard extends StatelessWidget {
  const _TestGuideCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        title: const Text('Test v0.3'),
        subtitle: const Text('Checklist rapida per due telefoni'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: const [
          _TestStep('1', 'Apri l’app su entrambi i telefoni: Radar deve mostrare Scan ON, ADV ON e almeno 1 peer.'),
          _TestStep('2', 'Cambia nome su un telefono e premi “Invia nome”: sull’altro deve aggiornarsi nome, name RX e ultimo RX NAME.'),
          _TestStep('3', 'Spegni Bluetooth o chiudi l’app su un telefono: l’altro deve passare da online a offline e poi pulibile.'),
          _TestStep('4', 'Spegni/riaccendi la Posizione Android: se non ricevi più peer, deve riprendersi da solo o col pulsante “Riavvia scan”.'),
        ],
      ),
    );
  }
}

class _TestStep extends StatelessWidget {
  final String n;
  final String text;

  const _TestStep(this.n, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 11, child: Text(n, style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _DebugCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final svc = ConvoyMeshService.instance;

    return Card(
      child: ExpansionTile(
        initiallyExpanded: false,
        title: const Text('Debug BLE'),
        subtitle: Text('TX ${svc.lastTxKind} ${svc.lastPayloadBytes}B • RX ${svc.rxValid}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          _DebugRow('Ultimo TX', '${svc.lastTxKind} seq ${svc.lastTxSeq} • ${svc.lastPayloadBytes} bytes • ${ConvoyMeshService.ageLabel(svc.lastTxAt)}'),
          _DebugRow('ADV ok/errori', '${svc.advOkCount} / ${svc.advErrorCount}'),
          _DebugRow('Ultimo errore ADV', svc.lastAdvError ?? '-'),
          _DebugRow('Scan eventi', '${svc.scanEventCount} • ultimo ${ConvoyMeshService.ageLabel(svc.lastScanEventAt)}'),
          _DebugRow('Restart scan', '${svc.scanRestartCount} • ${svc.lastScanRestartReason} • ${ConvoyMeshService.ageLabel(svc.lastScanRestartAt)}'),
          const Divider(),
          _DebugRow('Ultimo RX', '${svc.lastRxSummary} • ${ConvoyMeshService.ageLabel(svc.lastRxAt)}'),
          _DebugRow('RX validi', '${svc.rxValid}'),
          _DebugRow('RX pos/name', '${svc.rxFixPackets} / ${svc.rxNamePackets}'),
          _DebugRow('Magic trovati', '${svc.rxMagicFound} • offset ${svc.lastMagicOffset ?? '-'}'),
          _DebugRow('Ultimo MD', '${svc.lastMdBytes}B • ${svc.lastMdHex}'),
          _DebugRow('Parse', svc.lastParseReason),
          _DebugRow('RX scartati', 'self ${svc.rxIgnoredSelf} • stale ${svc.rxStale} • noMagic ${svc.rxNoMagic} • bad ${svc.rxBadPacket} • noMD ${svc.rxNoManufacturerData}'),
        ],
      ),
    );
  }
}

class _PeerCard extends StatelessWidget {
  final PeerState peer;

  const _PeerCard({required this.peer});

  @override
  Widget build(BuildContext context) {
    final qual = ConvoyMeshService.rssiQuality(peer.rssi);
    final colorInt = ConvoyMeshService.colorForUser(peer.userId);
    final title = (peer.name != null && peer.name!.trim().isNotEmpty) ? peer.name! : 'User ${peer.userId}';
    final online = ConvoyMeshService.isPeerOnline(peer);
    final hasFreshFix = peer.hasFreshFix;

    final fixText = peer.hasFix
        ? hasFreshFix
            ? 'fix GPS recente • acc ${(peer.accuracyM ?? 0).toStringAsFixed(1)}m'
            : 'ultimo fix GPS ${ConvoyMeshService.ageLabel(peer.lastFixSeen)} • non recente'
        : 'nessun fix GPS ricevuto';

    return Card(
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              backgroundColor: Color(colorInt),
              child: const Icon(Icons.person, color: Colors.white),
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: online ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
        title: Text('$title ${online ? '• online' : '• offline'}'),
        subtitle: Text(
          'ID ${peer.userId}\n'
          'BLE $qual • RSSI ${peer.rssi} • seq ${peer.lastSeq}\n'
          '$fixText • visto ${ConvoyMeshService.ageLabel(peer.lastSeen)}\n'
          'nome ${ConvoyMeshService.ageLabel(peer.lastNameSeen)} • addr ${peer.lastAddress ?? '-'}\n'
          'rx ${peer.rxPackets} • pos ${peer.rxFixPackets} • name ${peer.rxNamePackets}',
        ),
        isThreeLine: true,
        trailing: hasFreshFix
            ? const Icon(Icons.location_on, color: Colors.green)
            : const Icon(Icons.location_off, color: Colors.grey),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool ok;

  const _Chip({required this.icon, required this.label, required this.ok});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18, color: ok ? Colors.green : Colors.orange),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DebugRow extends StatelessWidget {
  final String label;
  final String value;

  const _DebugRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
