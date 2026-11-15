import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/detailed_diagnostic_upload.dart';

/// Consent is for this one selected session only; there is no saved toggle.
class DetailedDiagnosticUploadCard extends StatefulWidget {
  const DetailedDiagnosticUploadCard({
    super.key,
    required this.jsonl,
    this.senderOverride,
    this.configuredOverride,
  });

  final String jsonl;
  final Future<int> Function(DetailedDiagnosticUpload payload)? senderOverride;
  final bool? configuredOverride;

  @override
  State<DetailedDiagnosticUploadCard> createState() =>
      _DetailedDiagnosticUploadCardState();
}

class _DetailedDiagnosticUploadCardState
    extends State<DetailedDiagnosticUploadCard> {
  DetailedDiagnosticUpload? _payload;
  String? _prepareError, _status;
  bool _ownerConsent = false, _ackStoredData = false;
  final Set<int> _approvedPeers = {};
  bool _attempted = false, _busy = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(DetailedDiagnosticUploadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jsonl != widget.jsonl) {
      _ownerConsent = false;
      _ackStoredData = false;
      _approvedPeers.clear();
      _attempted = false;
      _busy = false;
      _status = null;
      _prepare();
    }
  }

  void _prepare() {
    try {
      _payload = DetailedDiagnosticUpload.fromJsonl(widget.jsonl);
      _prepareError = null;
    } catch (e) {
      _payload = null;
      _prepareError = e.toString();
    }
  }

  Future<void> _showPreview(DetailedDiagnosticUpload payload) async {
    final exact = const JsonEncoder.withIndent('  ').convert(payload.preview);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anteprima dati PostHog'),
        content: SizedBox(
          width: 680,
          height: 460,
          child: SingleChildScrollView(child: SelectableText(exact)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  Future<void> _send(DetailedDiagnosticUpload payload) async {
    if (_busy || _attempted || !_ownerConsent || !_ackStoredData ||
        _approvedPeers.length != payload.peerLabels.length) return;
    if (!(widget.configuredOverride ?? DetailedDiagnosticUploadSender.configured)) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confermi invio dettagliato?'),
        content: Text(
          'Invierai a PostHog EU ${payload.recordCount} eventi '
          '(${payload.bytes} byte circa) con ID, nickname, GPS e BLE '
          'dei partecipanti approvati e, se presenti, condizioni '
          'dichiarate durante la prova. '
          'Il file locale non viene cancellato. '
          'Dopo l’invio, annullare un consenso non ritira automaticamente '
          'i dati già ricevuti dal cloud.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Confermo invio a PostHog EU')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    // One attempt per mounted session, including after a timeout:
    // an ambiguous HTTP result may already have been ingested.
    setState(() {
      _attempted = true;
      _busy = true;
      _status = 'Un unico invio HTTPS in corso…';
    });
    try {
      final code = await (widget.senderOverride?.call(payload) ??
          DetailedDiagnosticUploadSender.sendOnce(payload));
      if (!mounted) return;
      setState(() {
        _status = code >= 200 && code < 300
            ? 'HTTP $code: PostHog ha accettato la richiesta. '
              'Archiviazione ancora da verificare cercando upload_id '
              '${payload.uploadId}. Nessun retry.'
            : 'HTTP $code: archiviazione NON confermata. '
              'Nessun retry automatico. upload_id ${payload.uploadId}.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Connessione fallita o esito incerto. '
          'Il cloud potrebbe aver ricevuto i dati: niente retry. '
          'upload_id ${payload.uploadId}.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    final configured =
        widget.configuredOverride ?? DetailedDiagnosticUploadSender.configured;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Invio diagnostico PostHog EU — beta chiusa',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Opzionale. Nessun invio durante la registrazione, '
                'all’avvio o allo stop. Invia SOLO la sessione mostrata, '
                'con una richiesta e senza retry o coda.'),
            if (payload == null)
              Text('Invio non disponibile: ${_prepareError ?? 'log non valido'}',
                  style: const TextStyle(color: Colors.red))
            else ...[
              Text('Sessione: ${payload.sessionId}'),
              Text('Telefono: ${payload.deviceName} • ID ${payload.deviceId}'),
              Text('Record inclusi: ${payload.recordCount} • '
                  'esclusi per sicurezza: ${payload.excludedRecords} • '
                  'dimensione stimata: ${payload.bytes} byte'),
              const Text('I record GPS contengono latitudine e longitudine '
                  'precise. I record BLE contengono ID, sequenze e RSSI. '
                  'Se registrate, includono anche condizioni e marcatori '
                  'dichiarati dal tester (NON verificati dai sensori). '
                  'Le note libere e i payload radio grezzi restano locali.'),
              OutlinedButton(
                onPressed: () => _showPreview(payload),
                child: const Text('Mostra JSON integrale da inviare'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _ownerConsent,
                title: const Text('Acconsento all’invio dei miei ID, '
                    'nickname, coordinate, condizioni dichiarate e log tecnici a PostHog EU '
                    'per analisi della beta.'),
                onChanged: _attempted ? null :
                    (v) => setState(() => _ownerConsent = v == true),
              ),
              if (payload.peerLabels.isNotEmpty) ...[
                const Text('Partecipanti rilevati: seleziona SOLO chi '
                    'ha già accettato espressamente questa raccolta cloud. '
                    'Se qualcuno non acconsente, questa sessione '
                    'non può essere inviata.'),
                for (final p in payload.peerLabels.entries)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _approvedPeers.contains(p.key),
                    title: Text('${p.value} • ID ${p.key}'),
                    onChanged: _attempted ? null : (v) => setState(() {
                      if (v == true) {
                        _approvedPeers.add(p.key);
                      } else {
                        _approvedPeers.remove(p.key);
                      }
                    }),
                  ),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _ackStoredData,
                title: const Text('Ho informato i partecipanti dei dati '
                    'trasmessi e della conservazione nel cloud; '
                    'so che revoca e cancellazione di dati già ricevuti '
                    'sono operazioni distinte.'),
                onChanged: _attempted ? null :
                    (v) => setState(() => _ackStoredData = v == true),
              ),
              if (!configured)
                const Text('Token di sola acquisizione PostHog non configurato: '
                    'invio disabilitato.',
                    style: TextStyle(color: Colors.red)),
              FilledButton.icon(
                onPressed: configured && !_attempted && !_busy &&
                        _ownerConsent && _ackStoredData &&
                        _approvedPeers.length == payload.peerLabels.length
                    ? () => _send(payload) : null,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Invia diagnostica a PostHog'),
              ),
              SelectableText('upload_id: ${payload.uploadId}'),
            ],
            if (_status != null) Text(_status!),
            if (_attempted)
              const Text('Un tentativo eseguito. Non riprovare alla cieca: '
                  'controlla prima upload_id sul progetto PostHog EU.'),
          ],
        ),
      ),
    );
  }
}
