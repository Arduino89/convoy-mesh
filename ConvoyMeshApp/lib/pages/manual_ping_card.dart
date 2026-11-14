import 'package:flutter/material.dart';
import '../services/manual_ping_service.dart';

/// Isolated beta-only manual test; consent is never persisted or inferred.
class ManualPingCard extends StatefulWidget {
  const ManualPingCard({super.key});

  @override
  State<ManualPingCard> createState() => _ManualPingCardState();
}

class _ManualPingCardState extends State<ManualPingCard> {
  final TextEditingController _token = TextEditingController();
  bool _consent = false;
  bool _attempted = false;
  bool _busy = false;
  String? _pingId;
  String? _status;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_consent || _busy || _attempted) return;
    final token = _token.text.trim();
    if (!ManualPingService.validProjectToken(token)) {
      setState(() => _status = 'Inserisci soltanto il token di progetto PostHog (phc_...).');
      return;
    }
    final id = ManualPingService.newPingId();
    setState(() {
      _attempted = true; // No accidental repeat, even on error or timeout.
      _busy = true;
      _pingId = id;
      _status = 'Invio singolo in corso...';
    });
    try {
      final http = await ManualPingService.sendOnce(
        projectToken: token, pingId: id,
      );
      if (!mounted) return;
      setState(() => _status = http >= 200 && http < 300
          ? 'HTTP $http: richiesta accettata. Verifica il ping_id in PostHog; salvataggio non ancora confermato.'
          : 'HTTP $http: evento NON confermato; nessun nuovo tentativo automatico.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _status =
          'Connessione non riuscita o incerta. Nessun ritentativo automatico.');
    } finally {
      if (mounted) setState(() {
        _busy = false;
        _consent = false;
      });
      // Do not retain the ingestion token in the widget after the attempt.
      _token.clear();
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Ping PostHog — laboratorio',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Solo prova manuale: un evento sintetico con ID casuale. '
                  'Nessun nome, GPS, percorso, ID Bluetooth o log. '
                  'Non abilita la telemetria automatica.'),
              const SizedBox(height: 8),
              TextField(
                controller: _token,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !_attempted,
                decoration: const InputDecoration(
                  labelText: 'Token di progetto PostHog (phc_...)',
                  helperText: 'Solo token di ingestione, NON una chiave API personale',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consent,
                onChanged: _attempted ? null : (value) =>
                    setState(() => _consent = value ?? false),
                title: const Text('Acconsento a inviare un singolo ping sintetico a PostHog EU.'),
                subtitle: const Text('L’indirizzo di rete è trattato dal servizio; '
                    'nessun dato GPS viene incluso nel messaggio.'),
              ),
              FilledButton.icon(
                onPressed: _consent && !_attempted && !_busy ? _send : null,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Invia ping di prova (una sola volta)'),
              ),
              if (_pingId != null) SelectableText('ping_id: $_pingId'),
              if (_status != null) Text(_status!),
              if (_attempted)
                const Text('Per un nuovo test è necessario riaprire questa schermata.'),
            ],
          ),
        ),
      );
}
