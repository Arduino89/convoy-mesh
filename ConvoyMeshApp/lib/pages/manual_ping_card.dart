import 'package:flutter/material.dart';
import '../services/manual_ping_service.dart';

/// Pressing the only button authorizes one synthetic diagnostic event.
class ManualPingCard extends StatefulWidget {
  const ManualPingCard({
    super.key,
    this.pingSenderOverride,
    this.configuredOverride,
  });

  // Test-only injection points. Production uses the default service.
  final Future<int> Function(String pingId)? pingSenderOverride;
  final bool? configuredOverride;

  @override
  State<ManualPingCard> createState() => _ManualPingCardState();
}

class _ManualPingCardState extends State<ManualPingCard> {
  bool _attempted = false;
  bool _busy = false;
  String? _pingId;
  String? _status;

  Future<void> _send() async {
    final configured = widget.configuredOverride ?? ManualPingService.isConfigured;
    if (!configured || _busy || _attempted) return;
    final id = ManualPingService.newPingId();
    setState(() {
      _attempted = true; // At most one request, even if transport times out.
      _busy = true;
      _pingId = id;
      _status = 'Invio singolo in corso…';
    });
    try {
      final http = await (widget.pingSenderOverride?.call(id) ??
          ManualPingService.sendOnce(pingId: id));
      if (!mounted) return;
      setState(() => _status = http >= 200 && http < 300
          ? 'HTTP $http: richiesta accettata. Verifica il ping_id su PostHog: il salvataggio non è ancora confermato.'
          : 'HTTP $http: evento NON confermato. Nessun ritentativo automatico.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _status =
          'Connessione fallita o incerta. Nessun ritentativo automatico.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = widget.configuredOverride ?? ManualPingService.isConfigured;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Ping PostHog — laboratorio',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Premendo «Invia ping di prova» autorizzi UN SOLO invio '
                'sintetico a PostHog EU. Non vengono trasmessi nome, coordinate GPS, '
                'percorso, ID Bluetooth o file diagnostici. '
                'Il servizio tratta i dati tecnici della connessione. '
                'Nessun invio automatico.'),
            const SizedBox(height: 8),
            if (!configured)
              const Text('Invio non configurato in questa build: nessun '
                  'evento può essere trasmesso.',
                  style: TextStyle(color: Colors.red)),
            FilledButton.icon(
              onPressed: configured && !_attempted && !_busy ? _send : null,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Invia ping di prova'),
            ),
            if (_pingId != null) SelectableText('ping_id: $_pingId'),
            if (_status != null) Text(_status!),
            if (_attempted)
              const Text('Per ripetere il test, chiudi e riapri Convoy Ping LAB.'),
          ],
        ),
      ),
    );
  }
}
