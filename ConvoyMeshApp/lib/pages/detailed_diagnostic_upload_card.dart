import 'dart:convert';
import 'dart:math' as math;

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
    this.temporarilyDisabledOverride,
    this.attemptStoreOverride,
  });

  final String jsonl;
  final Future<int> Function(DetailedDiagnosticUpload payload)? senderOverride;
  final bool? configuredOverride;
  final bool? temporarilyDisabledOverride;
  final DetailedDiagnosticUploadAttemptStore? attemptStoreOverride;

  @override
  State<DetailedDiagnosticUploadCard> createState() =>
      _DetailedDiagnosticUploadCardState();
}

class _DetailedDiagnosticUploadCardState
    extends State<DetailedDiagnosticUploadCard>
    with AutomaticKeepAliveClientMixin<DetailedDiagnosticUploadCard> {
  static const _title = 'Invio diagnostico PostHog EU — beta chiusa';
  static const _introText =
      'Opzionale. Nessun invio durante la registrazione, '
      'all’avvio o allo stop. Invia SOLO la sessione mostrata, '
      'con una richiesta e senza retry o coda.';
  static const _privacyNote =
      'I record GPS contengono latitudine e longitudine precise. '
      'I record BLE contengono ID, sequenze e RSSI. '
      'Se registrate, includono anche condizioni e marcatori '
      'dichiarati dal tester (NON verificati dai sensori). '
      'Le note libere e i payload radio grezzi restano locali. '
      'Analisi tecnica anche tramite ChatGPT. Durata di conservazione e '
      'cancellazione cloud non ancora verificate: per richieste di revoca o '
      'cancellazione, contatta il coordinatore della beta indicando upload_id.';
  static const _temporarilyDisabledText =
      'Invio a PostHog temporaneamente disattivato in questa build Outdoor LAB: '
      'nessun dato viene trasmesso al cloud. Puoi comunque registrare e '
      'condividere il file locale.';
  static const _unconfiguredText =
      'Token di sola acquisizione PostHog non configurato: invio disabilitato.';

  late DetailedDiagnosticUploadAttemptStore _store;
  DetailedDiagnosticUpload? _payload;
  String? _sessionKey;
  String? _prepareError;
  bool _ownerConsent = false, _ackStoredData = false;
  final Set<int> _approvedPeers = {};
  bool _dialogOpen = false;

  @override
  bool get wantKeepAlive => true;

  bool get _temporarilyDisabled =>
      widget.temporarilyDisabledOverride ??
      (widget.configuredOverride != null
          ? false
          : DetailedDiagnosticUploadSender.temporarilyDisabled);

  bool get _configured =>
      !_temporarilyDisabled &&
      (widget.configuredOverride ?? DetailedDiagnosticUploadSender.configured);

  DetailedDiagnosticUploadAttemptRecord? get _record =>
      _sessionKey == null ? null : _store.recordFor(_sessionKey!);

  @override
  void initState() {
    super.initState();
    _store =
        widget.attemptStoreOverride ?? DetailedDiagnosticUploadSender.attemptStore;
    _store.addListener(_onStoreChanged);
    _prepare();
  }

  @override
  void didUpdateWidget(DetailedDiagnosticUploadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextStore =
        widget.attemptStoreOverride ?? DetailedDiagnosticUploadSender.attemptStore;
    final storeChanged = !identical(nextStore, _store);
    if (storeChanged) {
      _store.removeListener(_onStoreChanged);
      _store = nextStore;
      _store.addListener(_onStoreChanged);
    }
    if (oldWidget.jsonl != widget.jsonl || storeChanged) {
      _ownerConsent = false;
      _ackStoredData = false;
      _approvedPeers.clear();
      _prepare();
    }
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    final record = _record;
    if (record != null && record.attempted) {
      _ownerConsent = record.ownerConsent;
      _ackStoredData = record.ackStoredData;
      _approvedPeers
        ..clear()
        ..addAll(record.approvedPeers);
    }
    if (mounted) setState(() {});
  }

  void _prepare() {
    try {
      var parsed = DetailedDiagnosticUpload.fromJsonl(widget.jsonl);
      final key = DetailedDiagnosticUploadAttemptStore.fingerprintFor(
        parsed.sessionId,
        widget.jsonl,
      );
      final existing = _store.recordFor(key);
      if (existing != null) {
        if (existing.uploadId != parsed.uploadId) {
          parsed = DetailedDiagnosticUpload.fromJsonl(
            widget.jsonl,
            uploadIdOverride: existing.uploadId,
          );
        }
        if (existing.attempted) {
          _ownerConsent = existing.ownerConsent;
          _ackStoredData = existing.ackStoredData;
          _approvedPeers
            ..clear()
            ..addAll(existing.approvedPeers);
        }
      }
      _payload = parsed;
      _sessionKey = key;
      _prepareError = null;
    } catch (e) {
      _payload = null;
      _sessionKey = null;
      _prepareError = e.toString();
    }
  }

  Future<void> _showPreview(DetailedDiagnosticUpload payload) async {
    final t = ConvoyDesignTokens.maybeOf(context);
    final exact = const JsonEncoder.withIndent('  ').convert(payload.preview);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        final maxWidth = math.min(680.0, size.width * 0.9);
        final maxHeight = math.min(460.0, size.height * 0.55);
        return AlertDialog(
          title: t != null
              ? OutdoorDialogTitle(
                  tokens: t,
                  icon: Icons.data_object,
                  title: 'Anteprima dati PostHog',
                )
              : const Text('Anteprima dati PostHog'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
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
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Chiudi'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _send(DetailedDiagnosticUpload payload) async {
    final key = _sessionKey;
    final record = _record;
    if (key == null ||
        _dialogOpen ||
        (record?.inFlight ?? false) ||
        (record?.attempted ?? false) ||
        !_ownerConsent ||
        !_ackStoredData ||
        _approvedPeers.length != payload.peerLabels.length) {
      return;
    }
    if (!_configured) {
      return;
    }
    final t = ConvoyDesignTokens.maybeOf(context);
    _dialogOpen = true;
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: t != null
              ? OutdoorDialogTitle(
                  tokens: t,
                  icon: Icons.cloud_upload_outlined,
                  title: 'Confermi invio dettagliato?',
                  tone: OutdoorTone.warning,
                )
              : const Text('Confermi invio dettagliato?'),
          content: SingleChildScrollView(
            child: Text(
              'Invierai a PostHog EU ${payload.recordCount} eventi '
              '(${payload.bytes} byte circa) con ID, nickname, GPS e BLE '
              'dei partecipanti approvati e, se presenti, condizioni '
              'dichiarate durante la prova. '
              'Il file locale non viene cancellato. '
              'Dopo l’invio, annullare un consenso non ritira automaticamente '
              'i dati già ricevuti dal cloud.',
              style: t?.body(14),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confermo invio a PostHog EU'),
            ),
          ],
        ),
      );
    } finally {
      _dialogOpen = false;
    }
    if (!mounted || confirmed != true) return;
    // A dialog may outlive a capture/configuration update. Consent and identity
    // must still refer to the exact payload shown when the dialog opened.
    if (_sessionKey != key ||
        !identical(_payload, payload) ||
        !_configured ||
        !_ownerConsent ||
        !_ackStoredData ||
        !_approvedPeers.containsAll(payload.peerLabels.keys)) {
      return;
    }
    // One attempt per session fingerprint in this launch, including after
    // ListView eviction, style switches, mid-flight unmounts, or ambiguous
    // HTTP timeouts where the cloud may already have ingested the batch.
    final store = _store;
    if (!store.beginAttempt(
      key,
      uploadId: payload.uploadId,
      ownerConsent: _ownerConsent,
      ackStoredData: _ackStoredData,
      approvedPeers: _approvedPeers,
    )) {
      return;
    }
    try {
      final code = await (widget.senderOverride?.call(payload) ??
          DetailedDiagnosticUploadSender.sendOnce(payload));
      store.completeAttempt(
        key,
        code >= 200 && code < 300
            ? 'HTTP $code: PostHog ha accettato la richiesta. '
                'Archiviazione ancora da verificare cercando upload_id '
                '${payload.uploadId}. Nessun retry.'
            : 'HTTP $code: archiviazione NON confermata. '
                'Nessun retry automatico. upload_id ${payload.uploadId}.',
      );
    } catch (_) {
      store.completeAttempt(
        key,
        'Connessione fallita o esito incerto. '
        'Il cloud potrebbe aver ricevuto i dati: niente retry. '
        'upload_id ${payload.uploadId}.',
      );
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

  Widget _classicInfoNotice(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = ConvoyDesignTokens.maybeOf(context);
    final payload = _payload;
    final record = _record;
    final attempted = record?.attempted ?? false;
    final busy = record?.inFlight ?? false;
    final status = record?.status;
    final temporarilyDisabled = _temporarilyDisabled;
    final configured = _configured;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (t == null) ...const [
          Text(_title, style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text(_introText),
        ] else ...[
          OutdoorCardHeader(
            tokens: t,
            icon: Icons.cloud_upload_outlined,
            title: _title,
          ),
          SizedBox(height: t.space(2)),
          Text(_introText, style: t.body(13, color: t.inkMuted)),
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
            const Text(_privacyNote),
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
              text: _privacyNote,
            ),
            SizedBox(height: t.space(2)),
          ],
          if (t == null)
            OutlinedButton(
              onPressed: () => _showPreview(payload),
              child: const Text('Mostra JSON integrale da inviare'),
            )
          else
            OutlinedButton.icon(
              onPressed: () => _showPreview(payload),
              icon: Icon(Icons.data_object, size: t.iconSize(18)),
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
            onChanged: attempted
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
                onChanged: attempted
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
            onChanged: attempted
                ? null
                : (v) => setState(() => _ackStoredData = v == true),
          ),
          if (temporarilyDisabled) ...[
            if (t == null)
              _classicInfoNotice(context, _temporarilyDisabledText)
            else ...[
              OutdoorCallout(
                tokens: t,
                icon: Icons.info_outline,
                text: _temporarilyDisabledText,
                tone: OutdoorTone.neutral,
              ),
              SizedBox(height: t.space(2)),
            ],
          ] else if (!configured) ...[
            if (t == null)
              const Text(
                _unconfiguredText,
                style: TextStyle(color: Colors.red),
              )
            else ...[
              OutdoorCallout(
                tokens: t,
                icon: Icons.lock_outline,
                text: _unconfiguredText,
                tone: OutdoorTone.critical,
              ),
              SizedBox(height: t.space(2)),
            ],
          ],
          FilledButton.icon(
            onPressed: configured &&
                    !attempted &&
                    !busy &&
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
        if (status != null) ...[
          if (t != null) SizedBox(height: t.space(2)),
          if (t == null)
            Text(status)
          else
            OutdoorCallout(
              tokens: t,
              icon: status.startsWith('HTTP 2')
                  ? Icons.cloud_done_outlined
                  : Icons.info_outline,
              text: status,
              tone: status.startsWith('HTTP 2')
                  ? OutdoorTone.positive
                  : OutdoorTone.warning,
            ),
        ],
        if (attempted) ...[
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
