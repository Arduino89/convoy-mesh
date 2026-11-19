import 'package:flutter/material.dart';

import '../design/design_direction_picker.dart';
import '../design/design_tokens.dart';
import '../design/diagnostic/designed_diagnostic_header.dart';
import '../design/outdoor_components.dart';
import '../services/background_runtime_service.dart';
import '../services/convoy_mesh_service.dart';
import '../services/diagnostic_capture_bridge.dart';
import '../services/diagnostic_recorder.dart';
import '../services/diagnostic_test_context.dart';
import 'detailed_diagnostic_upload_card.dart';
import 'manual_ping_card.dart';

class DiagnosticPage extends StatefulWidget {
  const DiagnosticPage({
    super.key,
    this.deviceIdOverride,
    this.deviceNameOverride,
    this.captureNowOverride,
  });

  final int? deviceIdOverride;
  final String? deviceNameOverride;
  final VoidCallback? captureNowOverride;

  @override
  State<DiagnosticPage> createState() => _DiagnosticPageState();
}

class _DiagnosticPageState extends State<DiagnosticPage> {
  static const _privacyLead =
      'Registrazione indipendente dall’uscita; non attiva GPS o servizi extra.';
  static const _privacyDetail =
      'Start/Stop non inviano dati. Il file locale può contenere nomi, ID e coordinate: condividilo solo con destinatari scelti.';
  static const _recoveredWarning =
      'File recuperato: può essere parziale se il processo è stato interrotto.';
  static const _uploadPrivacyNote =
      'Invio dettagliato separato, manuale e soggetto al consenso di ogni partecipante; nessun invio automatico.';
  static const _runtimeDisclaimer =
      'Presenza BLE e posizione GPS recente sono stati distinti. Non sono garanzie di sicurezza.';
  static const _guideBullets = [
    'TX richiesto, esito del plugin, pacchetto ricevuto e decisione GPS sono registrati separatamente.',
    'UTC permette il confronto fra telefoni; il tempo monotono conserva l’ordine locale. Orologi diversi richiedono verifica.',
    'Dopo uno stop o un riavvio puoi condividere l’ultimo file senza rifare il test.',
  ];

  String _environment = 'unknown';
  String _selfMovement = 'unknown';
  String _peersMovement = 'unknown';
  String _placement = 'unknown';
  String _screen = 'unknown';
  String _outcome = 'not_checked';
  late Listenable _mergedListenable;

  bool get _hasDeviceOverrides =>
      widget.deviceIdOverride != null && widget.deviceNameOverride != null;

  Listenable _buildListenable() {
    final recorder = DiagnosticRecorder.instance;
    final runtime = BackgroundRuntimeService.instance;
    final mesh = _hasDeviceOverrides ? null : ConvoyMeshService.instance;
    return Listenable.merge([recorder, runtime, if (mesh != null) mesh]);
  }

  @override
  void initState() {
    super.initState();
    _mergedListenable = _buildListenable();
  }

  @override
  void didUpdateWidget(DiagnosticPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hadOverrides = oldWidget.deviceIdOverride != null &&
        oldWidget.deviceNameOverride != null;
    if (hadOverrides != _hasDeviceOverrides) {
      _mergedListenable = _buildListenable();
    }
  }

  Map<String, Object> _contextData() => DiagnosticTestContext.context(
        environment: _environment,
        selfMovement: _selfMovement,
        peersMovement: _peersMovement,
        phonePlacement: _placement,
        screenReported: _screen,
      );

  void _setCondition(String key, String value) {
    setState(() {
      if (key == 'environment') _environment = value;
      if (key == 'self_movement') _selfMovement = value;
      if (key == 'peers_movement') _peersMovement = value;
      if (key == 'phone_placement') _placement = value;
      if (key == 'screen_reported') _screen = value;
    });
    if (DiagnosticRecorder.instance.isActive) {
      DiagnosticRecorder.instance
          .record('test', 'context', data: _contextData());
    }
  }

  Widget _selector(
    ConvoyDesignTokens? t,
    String title,
    String key,
    String selected,
    Map<String, String> options,
  ) {
    final dropdown = DropdownButton<String>(
      value: selected,
      isExpanded: true,
      items: [
        for (final item in options.entries)
          DropdownMenuItem<String>(value: item.key, child: Text(item.value)),
      ],
      onChanged: (v) {
        if (v != null) _setCondition(key, v);
      },
    );
    if (t == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Text(title), dropdown],
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: t.caption(color: t.inkMuted, size: 11.5)),
          SizedBox(height: t.space(0.75)),
          Container(
            padding: EdgeInsets.symmetric(horizontal: t.space(3)),
            decoration: BoxDecoration(
              color: t.surfaceRaised,
              borderRadius: BorderRadius.circular(t.radiusSmall),
              border: Border.all(color: t.outline, width: t.borderWidth),
            ),
            child: DropdownButtonHideUnderline(child: dropdown),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recorder = DiagnosticRecorder.instance;
    final runtime = BackgroundRuntimeService.instance;
    final overrides = _hasDeviceOverrides;
    final mesh = overrides ? null : ConvoyMeshService.instance;
    return AnimatedBuilder(
      animation: _mergedListenable,
      builder: (context, _) {
        final id = widget.deviceIdOverride ?? mesh!.myId;
        final name = widget.deviceNameOverride ?? mesh!.myName;
        final ready = id > 0 && (overrides || mesh!.isRunning);
        final t = ConvoyDesignTokens.maybeOf(context);
        return Scaffold(
          backgroundColor: t?.canvas,
          appBar: AppBar(
            title: Text(t != null ? t.copy.diagnosticTitle : 'Test diagnostico'),
            actions: [
              IconButton(
                key: const Key('diag-open-design-btn'),
                tooltip: 'Personalizza Outdoor Premium o torna a Originale',
                icon: const Icon(Icons.palette_outlined),
                onPressed: () => showDesignDirectionPicker(context),
              ),
            ],
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              t?.hPad ?? 16,
              t?.space(3) ?? 16,
              t?.hPad ?? 16,
              t?.space(6) ?? 16,
            ),
            children: [
              _card(t, [
                if (t != null)
                  DesignedDiagnosticStatusStrip(
                    tokens: t,
                    active: recorder.isActive,
                    ready: ready,
                    persistent: recorder.isPersistent,
                    elapsed: recorder.elapsed,
                    remaining: recorder.remaining,
                    eventCount: recorder.eventCount,
                    droppedEvents: recorder.droppedEvents,
                  ),
                Text(
                  t != null
                      ? (recorder.isActive
                          ? t.copy.diagnosticActiveTitle
                          : t.copy.diagnosticStartTitle)
                      : (recorder.isActive
                          ? 'Registrazione locale in corso'
                          : 'Registrazione diagnostica locale'),
                  style: t != null
                      ? t.display(18)
                      : Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: t?.space(1.25) ?? 8),
                if (t == null) ...[
                  Text('Telefono: $name • ID $id'),
                  const Text('Registrazione diagnostica: massimo 4 minuti'),
                  Text('App: ${DiagnosticRecorder.appVersion}'),
                  Text('Build: ${DiagnosticRecorder.buildCommit}'),
                  const SizedBox(height: 8),
                  Text(
                    recorder.isPersistent
                        ? 'Log salvato progressivamente sul telefono.'
                        : 'Salvataggio su disco non disponibile: il log in memoria può andare perso.',
                  ),
                  if (recorder.storageError != null)
                    Text(recorder.storageError!,
                        style: const TextStyle(color: Colors.red)),
                ] else ...[
                  Text(
                    'Telefono: $name • ID $id',
                    style: t.body(13.5, weight: FontWeight.w700),
                  ),
                  SizedBox(height: t.space(2)),
                ],
                if (recorder.isActive) ...[
                  if (t == null) ...[
                    Text(
                      'Durata ${DiagnosticRecorder.formatDuration(recorder.elapsed)} • restante ${DiagnosticRecorder.formatDuration(recorder.remaining)}',
                    ),
                    Text(
                      'Eventi ${recorder.eventCount} • scartati per limite ${recorder.droppedEvents}',
                    ),
                  ],
                  OutlinedButton.icon(
                    onPressed: () => _addMarker(context, recorder),
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Segna qui un problema'),
                  ),
                  if (t != null) SizedBox(height: t.space(1.5)),
                  FilledButton.icon(
                    style: t != null
                        ? FilledButton.styleFrom(
                            backgroundColor: t.critical,
                            foregroundColor: t.onCritical,
                          )
                        : null,
                    onPressed: () async {
                      recorder.record(
                        'test',
                        'outcome',
                        data: DiagnosticTestContext.outcome(_outcome),
                      );
                      recorder.stop(reason: 'manual_stop');
                      await recorder.flush();
                    },
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Termina registrazione diagnostica'),
                  ),
                ] else ...[
                  FilledButton.icon(
                    onPressed: ready
                        ? () async {
                            recorder.start(deviceId: id, deviceName: name);
                            recorder.record(
                              'test',
                              'context',
                              data: _contextData(),
                            );
                            if (widget.captureNowOverride != null) {
                              widget.captureNowOverride!();
                            } else {
                              await runtime.refreshCapabilities();
                              DiagnosticCaptureBridge.instance.captureNow();
                            }
                          }
                        : null,
                    icon: const Icon(Icons.fiber_manual_record),
                    label: Text(
                      ready
                          ? 'Avvia registrazione diagnostica • max 4 min'
                          : 'Attendo modalità Vicini',
                    ),
                  ),
                ],
                SizedBox(height: t?.space(2) ?? 8),
                if (t == null) ...const [
                  Text(_privacyLead),
                  Text(_privacyDetail),
                ] else ...[
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: t.space(2.75),
                      vertical: t.space(1.75),
                    ),
                    decoration: BoxDecoration(
                      color: t.surfaceRaised,
                      borderRadius: BorderRadius.circular(t.radiusSmall),
                      border:
                          Border.all(color: t.outline, width: t.borderWidth),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Registrazione diagnostica: massimo 4 minuti',
                          style: t.body(12.5,
                              color: t.ink, weight: FontWeight.w600),
                        ),
                        SizedBox(height: t.space(0.5)),
                        Wrap(
                          spacing: t.space(2.5),
                          runSpacing: t.space(0.5),
                          children: [
                            Text(
                              'App: ${DiagnosticRecorder.appVersion}',
                              style: t.data(11.5,
                                  color: t.inkMuted, weight: FontWeight.w600),
                            ),
                            Text(
                              'Build: ${DiagnosticRecorder.buildCommit}',
                              style: t.data(11.5,
                                  color: t.inkMuted, weight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: t.space(1.5)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          recorder.isPersistent
                              ? Icons.save_outlined
                              : Icons.warning_amber_rounded,
                          size: t.iconSize(16),
                          color: recorder.isPersistent ? t.positive : t.warning,
                        ),
                      ),
                      SizedBox(width: t.space(1.5)),
                      Expanded(
                        child: Text(
                          recorder.isPersistent
                              ? 'Log salvato progressivamente sul telefono.'
                              : 'Salvataggio su disco non disponibile: il log in memoria può andare perso.',
                          style: t.body(
                            12.5,
                            color: recorder.isPersistent ? t.inkMuted : t.warning,
                            weight: recorder.isPersistent
                                ? FontWeight.w500
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (recorder.storageError != null) ...[
                    SizedBox(height: t.space(1.5)),
                    OutdoorCallout(
                      tokens: t,
                      icon: Icons.error_outline,
                      text: recorder.storageError!,
                      tone: OutdoorTone.critical,
                    ),
                  ],
                  SizedBox(height: t.space(1.75)),
                  OutdoorCallout(
                    tokens: t,
                    icon: Icons.privacy_tip_outlined,
                    text: '$_privacyLead\n$_privacyDetail',
                  ),
                ],
              ]),
              _card(t, [
                ExpansionTile(
                  key: const Key('test-context-panel'),
                  leading: t != null
                      ? Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: t.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(t.radiusSmall),
                          ),
                          child: Icon(Icons.fact_check_outlined,
                              color: t.accent, size: t.iconSize(18)),
                        )
                      : null,
                  title: Text(
                    t != null
                        ? t.copy.diagnosticContextTitle
                        : 'Condizioni reali della prova',
                    style: t?.display(17.5),
                  ),
                  subtitle: Text(
                    'Facoltativo • indicazioni umane, non misure GPS',
                    style: t?.body(12, color: t.inkMuted),
                  ),
                  initiallyExpanded: false,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.only(top: t?.space(2) ?? 6),
                  children: [
                    Text(
                      'Compila prima o durante il test. I cambi di scelta '
                      'mentre registri vengono annotati col tempo del telefono. '
                      'Se non sai, lascia «Non so».',
                      style: t?.body(13, color: t.inkMuted),
                    ),
                    if (!recorder.isActive && recorder.hasExport) ...[
                      if (t != null) SizedBox(height: t.space(1.5)),
                      Text(
                        'Il file appena chiuso NON cambia: le nuove '
                        'scelte valgono per una prossima registrazione.',
                        style: t?.body(12.5,
                            color: t.warning, weight: FontWeight.w600),
                      ),
                    ],
                    if (t != null) SizedBox(height: t.space(2)),
                    _selector(
                      t,
                      'Ambiente',
                      'environment',
                      _environment,
                      DiagnosticTestContext.environments,
                    ),
                    _selector(
                      t,
                      'Questo telefono',
                      'self_movement',
                      _selfMovement,
                      DiagnosticTestContext.movements,
                    ),
                    _selector(
                      t,
                      'Altri partecipanti (se osservati)',
                      'peers_movement',
                      _peersMovement,
                      DiagnosticTestContext.peers,
                    ),
                    _selector(
                      t,
                      'Dove si trova questo telefono',
                      'phone_placement',
                      _placement,
                      DiagnosticTestContext.placements,
                    ),
                    _selector(
                      t,
                      'Schermo durante la prova',
                      'screen_reported',
                      _screen,
                      DiagnosticTestContext.screens,
                    ),
                    Text(
                      'Esito osservato (salvato al termine del test)',
                      style: t?.caption(color: t.inkMuted, size: 11.5),
                    ),
                    if (t != null) SizedBox(height: t.space(0.75)),
                    _outcomeDropdown(t),
                    if (recorder.isActive) ...[
                      const Divider(),
                      Text(
                        'Segna subito i cambi di movimento o segnale '
                        'che osservi: sono dichiarazioni, non misure automatiche.',
                        style: t?.body(12.5, color: t.inkMuted),
                      ),
                      if (t != null) SizedBox(height: t.space(1.5)),
                      Wrap(
                        spacing: t?.space(2) ?? 6,
                        runSpacing: t?.space(1.5) ?? 4,
                        children: [
                          for (final marker
                              in DiagnosticTestContext.markers.entries)
                            ActionChip(
                              avatar: t != null
                                  ? Icon(Icons.add_circle_outline,
                                      size: t.iconSize(15), color: t.accent)
                                  : null,
                              label: Text(marker.value),
                              onPressed: () {
                                recorder.record(
                                  'test',
                                  'marker',
                                  data:
                                      DiagnosticTestContext.marker(marker.key),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Annotato: ${marker.value}'),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ]),
              if (!recorder.isActive && recorder.hasExport)
                _card(t, [
                  if (t == null)
                    const Text('File pronto',
                        style: TextStyle(fontWeight: FontWeight.bold))
                  else
                    OutdoorCardHeader(
                      tokens: t,
                      icon: Icons.description_outlined,
                      title: 'File pronto',
                      subtitle:
                          'Chiusura: ${recorder.lastStopReason ?? '-'}',
                      tone: OutdoorTone.positive,
                    ),
                  SizedBox(height: t?.space(2) ?? 4),
                  if (t == null) ...[
                    SelectableText(recorder.lastFileName ?? '-'),
                    Text('Chiusura: ${recorder.lastStopReason ?? '-'}'),
                  ] else
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: t.space(3),
                        vertical: t.space(2),
                      ),
                      decoration: BoxDecoration(
                        color: t.surfaceRaised,
                        borderRadius: BorderRadius.circular(t.radiusSmall),
                        border:
                            Border.all(color: t.outline, width: t.borderWidth),
                      ),
                      child: SelectableText(
                        recorder.lastFileName ?? '-',
                        style: t.data(12.5, weight: FontWeight.w700),
                      ),
                    ),
                  if (recorder.lastStopReason ==
                      'recovered_file_check_session_stop') ...[
                    if (t != null) SizedBox(height: t.space(1.5)),
                    if (t == null)
                      const Text(_recoveredWarning)
                    else
                      OutdoorCallout(
                        tokens: t,
                        icon: Icons.restore,
                        text: _recoveredWarning,
                        tone: OutdoorTone.warning,
                      ),
                  ],
                  if (t != null) SizedBox(height: t.space(1.5)),
                  Text(
                    'Condividi solo tramite la scelta esplicita di Android; il file può contenere coordinate e nomi.',
                    style: t?.body(12.5, color: t.inkMuted),
                  ),
                  if (recorder.lastSummary != null) ...[
                    SizedBox(height: t?.space(2.5) ?? 8),
                    Text(
                      'Riepilogo tecnico locale',
                      style: t != null
                          ? t.body(15, weight: FontWeight.w800)
                          : const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: t?.space(0.5) ?? 2),
                    Text(
                      'Conteggi dei campioni osservati, non tempi di disponibilità né errore GPS reale.',
                      style: t?.body(12, color: t.inkMuted),
                    ),
                    ..._buildReviewSummary(t, recorder.lastSummary!.toReviewFields()),
                    SizedBox(height: t?.space(2) ?? 8),
                    if (t == null)
                      const Text(_uploadPrivacyNote)
                    else
                      OutdoorCallout(
                        tokens: t,
                        icon: Icons.verified_user_outlined,
                        text: _uploadPrivacyNote,
                      ),
                  ],
                  SizedBox(height: t?.space(2) ?? 4),
                  FilledButton.icon(
                    onPressed: () => _share(context, recorder),
                    icon: const Icon(Icons.share),
                    label: const Text('Condividi file (manuale)'),
                  ),
                ]),
              if (!recorder.isActive &&
                  recorder.hasExport &&
                  recorder.lastContent != null)
                DetailedDiagnosticUploadCard(
                  key: ValueKey('upload-${recorder.lastFileName}'),
                  jsonl: recorder.lastContent!,
                ),
              const ManualPingCard(),
              _card(t, [
                if (t == null) ...[
                  const Text('Runtime e capacità hardware',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                      'Servizio foreground: ${runtime.isRunning ? 'ATTIVO (uscita)' : 'NON ATTIVO'}'),
                  Text(
                      'UWB: ${runtime.uwbSupported ? 'hardware supportato' : 'non rilevato'} • ranging non attivo'),
                  Text(
                      'Wi-Fi RTT: ${runtime.wifiRttSupported ? 'hardware supportato' : 'non rilevato'} • ranging non attivo'),
                  Text('Android API ${runtime.sdkInt ?? '-'} • ${runtime.model ?? '-'}'),
                  if (runtime.lastError != null)
                    Text(runtime.lastError!,
                        style: const TextStyle(color: Colors.red)),
                  const Text(_runtimeDisclaimer),
                ] else ...[
                  OutdoorCardHeader(
                    tokens: t,
                    icon: Icons.memory_outlined,
                    title: t.copy.diagnosticRuntimeTitle,
                  ),
                  SizedBox(height: t.space(2)),
                  OutdoorSpecRow(
                    tokens: t,
                    label: 'Servizio foreground',
                    value:
                        runtime.isRunning ? 'ATTIVO (uscita)' : 'NON ATTIVO',
                    valueColor: runtime.isRunning ? t.positive : t.ink,
                  ),
                  OutdoorSpecRow(
                    tokens: t,
                    label: 'UWB',
                    value:
                        '${runtime.uwbSupported ? 'hardware supportato' : 'non rilevato'} • ranging non attivo',
                  ),
                  OutdoorSpecRow(
                    tokens: t,
                    label: 'Wi-Fi RTT',
                    value:
                        '${runtime.wifiRttSupported ? 'hardware supportato' : 'non rilevato'} • ranging non attivo',
                  ),
                  OutdoorSpecRow(
                    tokens: t,
                    label: 'Dispositivo',
                    value:
                        'Android API ${runtime.sdkInt ?? '-'} • ${runtime.model ?? '-'}',
                    showDivider: false,
                  ),
                  if (runtime.lastError != null) ...[
                    SizedBox(height: t.space(2)),
                    OutdoorCallout(
                      tokens: t,
                      icon: Icons.error_outline,
                      text: runtime.lastError!,
                      tone: OutdoorTone.critical,
                    ),
                  ],
                  SizedBox(height: t.space(2)),
                  OutdoorCallout(
                    tokens: t,
                    icon: Icons.info_outline,
                    text: _runtimeDisclaimer,
                  ),
                ],
              ]),
              _card(t, [
                if (t == null) ...[
                  const Text('Lettura dei log',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final bullet in _guideBullets) Text(bullet),
                ] else ...[
                  OutdoorCardHeader(
                    tokens: t,
                    icon: Icons.menu_book_outlined,
                    title: t.copy.diagnosticGuideTitle,
                  ),
                  SizedBox(height: t.space(2.25)),
                  for (final bullet in _guideBullets) _guideBullet(t, bullet),
                ],
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _outcomeDropdown(ConvoyDesignTokens? t) {
    final dropdown = DropdownButton<String>(
      isExpanded: true,
      value: _outcome,
      items: [
        for (final o in DiagnosticTestContext.outcomes.entries)
          DropdownMenuItem<String>(value: o.key, child: Text(o.value)),
      ],
      onChanged: (v) {
        if (v != null) setState(() => _outcome = v);
      },
    );
    if (t == null) return dropdown;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.space(3)),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(t.radiusSmall),
        border: Border.all(color: t.outline, width: t.borderWidth),
      ),
      child: DropdownButtonHideUnderline(child: dropdown),
    );
  }

  List<Widget> _buildReviewSummary(
    ConvoyDesignTokens? t,
    Map<String, Object?> fields,
  ) {
    final entries = fields.entries.toList(growable: false);
    if (t == null) {
      return [
        for (final field in entries) Text('${field.key}: ${field.value}'),
      ];
    }
    return [
      SizedBox(height: t.space(1.75)),
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
            for (var i = 0; i < entries.length; i++)
              OutdoorSpecRow(
                tokens: t,
                label: entries[i].key,
                value: entries[i].value.toString(),
                showDivider: i < entries.length - 1,
              ),
          ],
        ),
      ),
    ];
  }

  Widget _guideBullet(ConvoyDesignTokens t, String text) => Padding(
        padding: EdgeInsets.only(bottom: t.space(1.75)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
          ),
          SizedBox(width: t.space(2.25)),
          Expanded(child: Text(text, style: t.body(13, color: t.inkMuted))),
        ]),
      );

  Widget _card(ConvoyDesignTokens? t, List<Widget> children) {
    if (t != null) {
      return OutdoorCard(
        tokens: t,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  static Future<void> _share(
      BuildContext context, DiagnosticRecorder recorder) async {
    try {
      final result = await recorder.shareLast();
      if (result == null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nessun file disponibile.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Condivisione non riuscita: $e')),
        );
      }
    }
  }

  static Future<void> _addMarker(
      BuildContext context, DiagnosticRecorder recorder) async {
    final t = ConvoyDesignTokens.maybeOf(context);
    var draft = '';
    var submitted = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        void submit(String value) {
          if (submitted) return;
          submitted = true;
          if (recorder.isActive && value.trim().isNotEmpty) {
            recorder.addMarker(value.trim());
          }
          Navigator.pop(dialogContext);
        }

        return AlertDialog(
          title: t != null
              ? OutdoorDialogTitle(
                  tokens: t,
                  icon: Icons.flag_outlined,
                  title: 'Segna il problema',
                  tone: OutdoorTone.warning,
                )
              : const Text('Segna il problema'),
          content: TextFormField(
            autofocus: true,
            maxLength: 120,
            onChanged: (value) => draft = value,
            onFieldSubmitted: submit,
            decoration: const InputDecoration(
              hintText: 'Es: Francesca non vede più Cama',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => submit(draft),
              child: const Text('Aggiungi'),
            ),
          ],
        );
      },
    );
  }
}
