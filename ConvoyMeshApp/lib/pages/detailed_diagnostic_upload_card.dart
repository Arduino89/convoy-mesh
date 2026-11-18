import 'dart:convert';

import 'package:flutter/material.dart';

import '../design/design_tokens.dart';
import '../design/outdoor_components.dart';
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
    final t = ConvoyDesignTokens.maybeOf(context);
    final exact = const JsonEncoder.withIndent('  ').convert(payload.preview);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: t != null
            ? OutdoorDialogTitle(
                tokens: t,
                icon: Icons.data_object,
                title: 'Anteprima dati PostHog',
              )
            : const Text('Anteprima dati PostHog'),
        content: SizedBox(
          width: 680,
          height: 460,
          child: t == null
              ? SingleChildScrollView(child: SelectableText(exact))
              : Container(
                  padding: EdgeInsets.all(t.space(3)),
                  decoration: BoxDecoration(
                    color: t.surfaceRaised,
                    borderRadius: BorderRadius.circular(t.radiusSmall),
                    border:
                        Border.all(color: t.outline, width: t.borderWidth),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      exact,
                      style: t.data(12, weight: FontWeight.w500),
                    ),
                  ),
                ),
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
    if (_busy ||
        _attempted ||
        !_ownerConsent ||
        !_ackStoredData ||
        _approvedPeers.length != payload.peerLabels.length) {
      return;
    }
    if (!(widget.configuredOverride ??
        DetailedDiagnosticUploadSender.configured)) {
      return;
    }
    final t = ConvoyDesignTokens.maybeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: t != null
            ? OutdoorDialogTitle(
                tokens: t,
                icon: Icons.cloud_upload_outlined,
                title: 'Confermi invio dettagliato?',
                tone: OutdoorTone.warning,
              )
            : const Text('Confermi invio dettagliato?'),
        content: Text(
          'Invierai a PostHog EU ${payload.recordCount} eventi '
          '(${payload.bytes} byte circa) con ID, nickname, GPS e BLE '
          'dei partecipanti approvati e, se presenti, condizioni '
          'dichiarate durante la prova. '
          'Il file locale non viene cancellato. '
          'Dopo l’invio, annullare un consenso non ritira automaticamente '
          'i dati già ricevuti dal cloud.',
          style: t?.body(14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confermo invio a PostHog EU'),
          ),
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
      setState(
        () => _status = 'Connessione fallita o esito incerto. '
            'Il cloud potrebbe aver ricevuto i dati: niente retry. '
            'upload_id ${payload.uploadId}.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _consentTile(
    ConvoyDesignTokens? t, {
    required bool value,
    required Widget title,
    required ValueChanged<bool?>? onChanged,
  }) {
    final tile = CheckboxListTile(
      contentPadding: t != null
          ? EdgeInsets.symmetric(
              horizontal: t.space(2),
              vertical: t.space(0.5),
            )
          : EdgeInsets.zero,
      value: value,
      title: title,
      onChanged: onChanged,
    );
    if (t == null) return tile;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(1.75)),
      child: Material(
        color: t.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radiusSmall),
          side: BorderSide(
            color: value ? t.accent.withValues(alpha: 0.55) : t.outline,
            width: t.borderWidth,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: tile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ConvoyDesignTokens.maybeOf(context);
    final payload = _payload;
    final configured =
        widget.configuredOverride ?? DetailedDiagnosticUploadSender.configured;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (t == null) ...const [
          Text(
            'Invio diagnostico PostHog EU — beta chiusa',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Opzionale. Nessun invio durante la registrazione, '
            'all’avvio o allo stop. Invia SOLO la sessione mostrata, '
            'con una richiesta e senza retry o coda.',
          ),
        ] else ...[
          OutdoorCardHeader(
            tokens: t,
            icon: Icons.cloud_upload_outlined,
            title: 'Invio diagnostico PostHog EU — beta chiusa',
          ),
          SizedBox(height: t.space(2)),
          Text(
            'Opzionale. Nessun invio durante la registrazione, '
            'all’avvio o allo stop. Invia SOLO la sessione mostrata, '
            'con una richiesta e senza retry o coda.',
            style: t.body(13, color: t.inkMuted),
          ),
          SizedBox(height: t.space(2.25)),
        ],
        if (payload == null)
          t == null
              ? Text(
                  'Invio non disponibile: ${_prepareError ?? 'log non valido'}',
                  style: const TextStyle(color: Colors.red),
                )
              : OutdoorCallout(
                  tokens: t,
                  icon: Icons.error_outline,
                  text:
                      'Invio non disponibile: ${_prepareError ?? 'log non valido'}',
                  tone: OutdoorTone.critical,
                )
        else ...[
          if (t == null) ...[
            Text('Sessione: ${payload.sessionId}'),
            Text('Telefono: ${payload.deviceName} • ID ${payload.deviceId}'),
            Text(
              'Record inclusi: ${payload.recordCount} • '
              'esclusi per sicurezza: ${payload.excludedRecords} • '
              'dimensione stimata: ${payload.bytes} byte',
            ),
            const Text(
              'I record GPS contengono latitudine e longitudine '
              'precise. I record BLE contengono ID, sequenze e RSSI. '
              'Se registrate, includono anche condizioni e marcatori '
              'dichiarati dal tester (NON verificati dai sensori). '
              'Le note libere e i payload radio grezzi restano locali.',
            ),
          ] else ...[
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: t.space(3),
                vertical: t.space(1),
              ),
              decoration: BoxDecoration(
                color: t.surfaceRaised,
                borderRadius: BorderRadius.circular(t.radiusSmall),
                border: Border.all(color: t.outline, width: t.borderWidth),
              ),
              child: Column(
                children: [
                  OutdoorSpecRow(
                    tokens: t,
                    label: 'Sessione',
                    value: payload.sessionId,
                  ),
                  OutdoorSpecRow(
                    tokens: t,
                    label: 'Telefono',
                    value: '${payload.deviceName} • ID ${payload.deviceId}',
                  ),
                  OutdoorSpecRow(
                    tokens: t,
                    label: 'Record inclusi / esclusi',
                    value:
                        '${payload.recordCount} / ${payload.excludedRecords}',
                  ),
                  OutdoorSpecRow(
                    tokens: t,
                    label: 'Dimensione stimata',
                    value: '${payload.bytes} byte',
                    showDivider: false,
                  ),
                ],
              ),
            ),
            SizedBox(height: t.space(2)),
            OutdoorCallout(
              tokens: t,
              icon: Icons.shield_outlined,
              text:
                  'I record GPS contengono latitudine e longitudine precise. I record BLE contengono ID, sequenze e RSSI. '
                  'Se registrate, includono anche condizioni e marcatori dichiarati dal tester (NON verificati dai sensori). '
                  'Le note libere e i payload radio grezzi restano locali.',
            ),
            SizedBox(height: t.space(2)),
          ],
          OutlinedButton.icon(
            onPressed: () => _showPreview(payload),
            icon: t != null
                ? Icon(Icons.data_object, size: t.iconSize(18))
                : const SizedBox.shrink(),
            label: const Text('Mostra JSON integrale da inviare'),
          ),
          if (t != null) SizedBox(height: t.space(2.25)),
          _consentTile(
            t,
            value: _ownerConsent,
            title: Text(
              'Acconsento all’invio dei miei ID, '
              'nickname, coordinate, condizioni dichiarate e log tecnici a PostHog EU '
              'per analisi della beta.',
              style: t?.body(13),
            ),
            onChanged: _attempted
                ? null
                : (v) => setState(() => _ownerConsent = v == true),
          ),
          if (payload.peerLabels.isNotEmpty) ...[
            if (t != null) SizedBox(height: t.space(0.75)),
            Text(
              'Partecipanti rilevati: seleziona SOLO chi '
              'ha già accettato espressamente questa raccolta cloud. '
              'Se qualcuno non acconsente, questa sessione '
              'non può essere inviata.',
              style: t?.body(12.5, color: t.inkMuted, weight: FontWeight.w600),
            ),
            if (t != null) SizedBox(height: t.space(1.5)),
            for (final p in payload.peerLabels.entries)
              _consentTile(
                t,
                value: _approvedPeers.contains(p.key),
                title: Text(
                  '${p.value} • ID ${p.key}',
                  style: t?.body(13.5, weight: FontWeight.w700),
                ),
                onChanged: _attempted
                    ? null
                    : (v) => setState(() {
                          if (v == true) {
                            _approvedPeers.add(p.key);
                          } else {
                            _approvedPeers.remove(p.key);
                          }
                        }),
              ),
          ],
          _consentTile(
            t,
            value: _ackStoredData,
            title: Text(
              'Ho informato i partecipanti dei dati '
              'trasmessi e della conservazione nel cloud; '
              'so che revoca e cancellazione di dati già ricevuti '
              'sono operazioni distinte.',
              style: t?.body(13),
            ),
            onChanged: _attempted
                ? null
                : (v) => setState(() => _ackStoredData = v == true),
          ),
          if (!configured) ...[
            if (t == null)
              const Text(
                'Token di sola acquisizione PostHog non configurato: '
                'invio disabilitato.',
                style: TextStyle(color: Colors.red),
              )
            else ...[
              OutdoorCallout(
                tokens: t,
                icon: Icons.lock_outline,
                text:
                    'Token di sola acquisizione PostHog non configurato: invio disabilitato.',
                tone: OutdoorTone.critical,
              ),
              SizedBox(height: t.space(2)),
            ],
          ],
          FilledButton.icon(
            onPressed: configured &&
                    !_attempted &&
                    !_busy &&
                    _ownerConsent &&
                    _ackStoredData &&
                    _approvedPeers.length == payload.peerLabels.length
                ? () => _send(payload)
                : null,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Invia diagnostica a PostHog'),
          ),
          if (t != null) SizedBox(height: t.space(2)),
          if (t == null)
            SelectableText('upload_id: ${payload.uploadId}')
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
                'upload_id: ${payload.uploadId}',
                style: t.data(12, color: t.inkMuted),
              ),
            ),
        ],
        if (_status != null) ...[
          if (t != null) SizedBox(height: t.space(2)),
          if (t == null)
            Text(_status!)
          else
            OutdoorCallout(
              tokens: t,
              icon: _status!.startsWith('HTTP 2')
                  ? Icons.cloud_done_outlined
                  : Icons.info_outline,
              text: _status!,
              tone: _status!.startsWith('HTTP 2')
                  ? OutdoorTone.positive
                  : OutdoorTone.warning,
            ),
        ],
        if (_attempted) ...[
          if (t != null) SizedBox(height: t.space(1.5)),
          Text(
            'Un tentativo eseguito. Non riprovare alla cieca: '
            'controlla prima upload_id sul progetto PostHog EU.',
            style: t?.body(12.5, color: t.inkMuted),
          ),
        ],
      ],
    );

    if (t != null) return OutdoorCard(tokens: t, child: body);
    return Card(
      child: Padding(padding: const EdgeInsets.all(14), child: body),
    );
  }
}
