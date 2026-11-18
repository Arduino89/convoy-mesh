import 'package:flutter/material.dart';

import '../design/design_tokens.dart';
import '../design/outdoor_components.dart';
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
      setState(
        () => _status = http >= 200 && http < 300
            ? 'HTTP $http: richiesta accettata. Verifica il ping_id su PostHog: il salvataggio non è ancora confermato.'
            : 'HTTP $http: evento NON confermato. Nessun ritentativo automatico.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _status =
            'Connessione fallita o incerta. Nessun ritentativo automatico.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ConvoyDesignTokens.maybeOf(context);
    final configured =
        widget.configuredOverride ?? ManualPingService.isConfigured;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (t == null) ...const [
          Text(
            'Ping PostHog — laboratorio',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Premendo «Invia ping di prova» autorizzi UN SOLO invio '
            'sintetico a PostHog EU. Non vengono trasmessi nome, coordinate GPS, '
            'percorso, ID Bluetooth o file diagnostici. '
            'Il servizio tratta i dati tecnici della connessione. '
            'Nessun invio automatico.',
          ),
          SizedBox(height: 8),
        ] else ...[
          OutdoorCardHeader(
            tokens: t,
            icon: Icons.wifi_tethering,
            title: 'Ping PostHog — laboratorio',
          ),
          SizedBox(height: t.space(2)),
          Text(
            'Premendo «Invia ping di prova» autorizzi UN SOLO invio '
            'sintetico a PostHog EU. Non vengono trasmessi nome, coordinate GPS, '
            'percorso, ID Bluetooth o file diagnostici. '
            'Il servizio tratta i dati tecnici della connessione. '
            'Nessun invio automatico.',
            style: t.body(13, color: t.inkMuted),
          ),
          SizedBox(height: t.space(2)),
        ],
        if (!configured) ...[
          if (t == null)
            const Text(
              'Invio non configurato in questa build: nessun '
              'evento può essere trasmesso.',
              style: TextStyle(color: Colors.red),
            )
          else ...[
            OutdoorCallout(
              tokens: t,
              icon: Icons.cloud_off_outlined,
              text:
                  'Invio non configurato in questa build: nessun evento può essere trasmesso.',
              tone: OutdoorTone.critical,
            ),
            SizedBox(height: t.space(2)),
          ],
        ],
        FilledButton.icon(
          onPressed: configured && !_attempted && !_busy ? _send : null,
          icon: const Icon(Icons.wifi_tethering),
          label: const Text('Invia ping di prova'),
        ),
        if (_pingId != null) ...[
          if (t != null) SizedBox(height: t.space(2)),
          if (t == null)
            SelectableText('ping_id: $_pingId')
          else
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: t.space(2.75),
                vertical: t.space(1.5),
              ),
              decoration: BoxDecoration(
                color: t.surfaceRaised,
                borderRadius: BorderRadius.circular(t.radiusSmall),
                border: Border.all(color: t.outline, width: t.borderWidth),
              ),
              child: SelectableText(
                'ping_id: $_pingId',
                style: t.data(12, color: t.ink),
              ),
            ),
        ],
        if (_status != null) ...[
          if (t != null) SizedBox(height: t.space(1.75)),
          if (t == null)
            Text(_status!)
          else
            OutdoorCallout(
              tokens: t,
              icon: _status!.startsWith('HTTP 2')
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_rounded,
              text: _status!,
              tone: _status!.startsWith('HTTP 2')
                  ? OutdoorTone.positive
                  : OutdoorTone.warning,
            ),
        ],
        if (_attempted) ...[
          if (t != null) SizedBox(height: t.space(1.5)),
          Text(
            'Per ripetere il test, chiudi e riapri Convoy Ping LAB.',
            style: t?.body(12.5, color: t.inkMuted),
          ),
        ],
      ],
    );

    if (t != null) return OutdoorCard(tokens: t, child: content);
    return Card(
      child: Padding(padding: const EdgeInsets.all(14), child: content),
    );
  }
}
