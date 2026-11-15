import 'package:flutter/material.dart';
import '../services/background_runtime_service.dart';
import '../services/convoy_mesh_service.dart';
import '../services/diagnostic_capture_bridge.dart';
import '../services/diagnostic_recorder.dart';
import '../services/diagnostic_test_context.dart';
import 'manual_ping_card.dart';
import 'detailed_diagnostic_upload_card.dart';


class DiagnosticPage extends StatefulWidget {
  const DiagnosticPage({super.key, this.deviceIdOverride, this.deviceNameOverride, this.captureNowOverride});
  final int? deviceIdOverride;
  final String? deviceNameOverride;
  final VoidCallback? captureNowOverride;

  @override
  State<DiagnosticPage> createState() => _DiagnosticPageState();
}

class _DiagnosticPageState extends State<DiagnosticPage> {
  String _environment = 'unknown';
  String _selfMovement = 'unknown';
  String _peersMovement = 'unknown';
  String _placement = 'unknown';
  String _screen = 'unknown';
  String _outcome = 'not_checked';

  Map<String, Object> _contextData() => DiagnosticTestContext.context(
    environment: _environment, selfMovement: _selfMovement,
    peersMovement: _peersMovement, phonePlacement: _placement,
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
      DiagnosticRecorder.instance.record('test', 'context', data: _contextData());
    }
  }

  Widget _selector(String title, String key, String selected,
      Map<String, String> options) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title),
      DropdownButton<String>(
        value: selected,
        isExpanded: true,
        items: [for (final item in options.entries)
          DropdownMenuItem<String>(value: item.key, child: Text(item.value))],
        onChanged: (v) {
          if (v != null) _setCondition(key, v);
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final recorder = DiagnosticRecorder.instance;
    final runtime = BackgroundRuntimeService.instance;
    final overrides = widget.deviceIdOverride != null && widget.deviceNameOverride != null;
    final mesh = overrides ? null : ConvoyMeshService.instance;
    return AnimatedBuilder(animation: Listenable.merge([recorder, runtime, if (mesh != null) mesh]),
      builder: (context, _) {
        final id = widget.deviceIdOverride ?? mesh!.myId;
        final name = widget.deviceNameOverride ?? mesh!.myName;
        final ready = id > 0 && (overrides || mesh!.isRunning);
        return Scaffold(appBar: AppBar(title: const Text('Test diagnostico')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            _card([
              Text(recorder.isActive ? 'Registrazione locale in corso' : 'Registrazione diagnostica locale',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Telefono: $name • ID $id'),
              const Text('Registrazione diagnostica: massimo 4 minuti'),
              Text('App: ' + DiagnosticRecorder.appVersion),
              Text('Build: ${DiagnosticRecorder.buildCommit}'),
              const SizedBox(height: 8),
              Text(recorder.isPersistent ? 'Log salvato progressivamente sul telefono.' :
                  'Salvataggio su disco non disponibile: il log in memoria può andare perso.'),
              if (recorder.storageError != null) Text(recorder.storageError!, style: const TextStyle(color: Colors.red)),
              if (recorder.isActive) ...[
                Text('Durata ${DiagnosticRecorder.formatDuration(recorder.elapsed)} • restante ${DiagnosticRecorder.formatDuration(recorder.remaining)}'),
                Text('Eventi ${recorder.eventCount} • scartati per limite ${recorder.droppedEvents}'),
                OutlinedButton.icon(onPressed: () => _addMarker(context, recorder),
                    icon: const Icon(Icons.flag_outlined), label: const Text('Segna qui un problema')),
                FilledButton.icon(onPressed: () async {
                  recorder.record('test', 'outcome', data: DiagnosticTestContext.outcome(_outcome));
                  recorder.stop(reason: 'manual_stop');
                  await recorder.flush();
                }, icon: const Icon(Icons.stop_circle_outlined), label: const Text('Termina registrazione diagnostica')),
              ] else ...[
                FilledButton.icon(onPressed: ready ? () async {
                  recorder.start(deviceId: id, deviceName: name);
                  recorder.record('test', 'context', data: _contextData());
                  if (widget.captureNowOverride != null) { widget.captureNowOverride!(); }
                  else { await runtime.refreshCapabilities(); DiagnosticCaptureBridge.instance.captureNow(); }
                } : null, icon: const Icon(Icons.fiber_manual_record),
                  label: Text(ready ? 'Avvia registrazione diagnostica • max 4 min' : 'Attendo modalità Vicini')),
              ],
              const SizedBox(height: 8),
              const Text('Registrazione indipendente dall’uscita; non attiva GPS o servizi extra.'),
              const Text('Start/Stop non inviano dati. Il file locale può contenere nomi, ID e coordinate: condividilo solo con destinatari scelti.'),
            ]),
            _card([
              ExpansionTile(
                key: const Key('test-context-panel'),
                title: const Text('Condizioni reali della prova'),
                subtitle: const Text('Facoltativo • indicazioni umane, non misure GPS'),
                initiallyExpanded: false,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 6),
                children: [
                  const Text('Compila prima o durante il test. I cambi di scelta '
                      'mentre registri vengono annotati col tempo del telefono. '
                      'Se non sai, lascia «Non so».'),
                  _selector('Ambiente', 'environment', _environment,
                      DiagnosticTestContext.environments),
                  _selector('Questo telefono', 'self_movement',
                      _selfMovement, DiagnosticTestContext.movements),
                  _selector('Altri partecipanti (se osservati)',
                      'peers_movement', _peersMovement, DiagnosticTestContext.peers),
                  _selector('Dove si trova questo telefono',
                      'phone_placement', _placement, DiagnosticTestContext.placements),
                  _selector('Schermo durante la prova', 'screen_reported',
                      _screen, DiagnosticTestContext.screens),
                  const Text('Esito osservato (salvato al termine del test)'),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: _outcome,
                    items: [for (final o in DiagnosticTestContext.outcomes.entries)
                      DropdownMenuItem<String>(value: o.key, child: Text(o.value))],
                    onChanged: (v) {
                      if (v != null) setState(() => _outcome = v);
                    },
                  ),
                  if (recorder.isActive) ...[
                    const Divider(),
                    const Text('Segna subito i cambi di movimento o segnale '
                        'che osservi: sono dichiarazioni, non misure automatiche.'),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final marker in DiagnosticTestContext.markers.entries)
                        ActionChip(
                          label: Text(marker.value),
                          onPressed: () {
                            recorder.record('test', 'marker',
                              data: DiagnosticTestContext.marker(marker.key));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Annotato: ${marker.value}')),
                            );
                          },
                        ),
                    ]),
                  ],
                ],
              ),
            ]),
            if (!recorder.isActive && recorder.hasExport) _card([
              const Text('File pronto', style: TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(recorder.lastFileName ?? '-'),
              Text('Chiusura: ${recorder.lastStopReason ?? '-'}'),
              if (recorder.lastStopReason == 'recovered_file_check_session_stop')
                const Text('File recuperato: può essere parziale se il processo è stato interrotto.'),
              const Text('Condividi solo tramite la scelta esplicita di Android; il file può contenere coordinate e nomi.'),
              if (recorder.lastSummary != null) ...[
                const SizedBox(height: 8),
                const Text('Riepilogo tecnico locale',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Text('Conteggi dei campioni osservati, non tempi di disponibilità né errore GPS reale.'),
                for (final field in recorder.lastSummary!.toReviewFields().entries)
                  Text(field.key + ': ' + field.value.toString()),
                const SizedBox(height: 8),
                const Text('Invio dettagliato separato, manuale e soggetto al consenso di ogni partecipante; nessun invio automatico.'),
              ],
              FilledButton.icon(onPressed: () => _share(context, recorder),
                  icon: const Icon(Icons.share), label: const Text('Condividi file (manuale)')),
            ]),
            if (!recorder.isActive && recorder.hasExport && recorder.lastContent != null)
              DetailedDiagnosticUploadCard(
                key: ValueKey('upload-${recorder.lastFileName}'),
                jsonl: recorder.lastContent!,
              ),
            const ManualPingCard(),
            _card([
              const Text('Runtime e capacità hardware', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Servizio foreground: ${runtime.isRunning ? 'ATTIVO (uscita)' : 'NON ATTIVO'}'),
              Text('UWB: ${runtime.uwbSupported ? 'hardware supportato' : 'non rilevato'} • ranging non attivo'),
              Text('Wi-Fi RTT: ${runtime.wifiRttSupported ? 'hardware supportato' : 'non rilevato'} • ranging non attivo'),
              Text('Android API ${runtime.sdkInt ?? '-'} • ${runtime.model ?? '-'}'),
              if (runtime.lastError != null) Text(runtime.lastError!, style: const TextStyle(color: Colors.red)),
              const Text('Presenza BLE e posizione GPS recente sono stati distinti. Non sono garanzie di sicurezza.'),
            ]),
            _card(const [
              Text('Lettura dei log', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('TX richiesto, esito del plugin, pacchetto ricevuto e decisione GPS sono registrati separatamente.'),
              Text('UTC permette il confronto fra telefoni; il tempo monotono conserva l’ordine locale. Orologi diversi richiedono verifica.'),
              Text('Dopo uno stop o un riavvio puoi condividere l’ultimo file senza rifare il test.'),
            ]),
          ]));
      });
  }
  Widget _card(List<Widget> children) => Card(child: Padding(padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)));
  static Future<void> _share(BuildContext context, DiagnosticRecorder recorder) async {
    try {
      final result = await recorder.shareLast();
      if (result == null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nessun file disponibile.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Condivisione non riuscita: $e')));
    }
  }
  static Future<void> _addMarker(BuildContext context, DiagnosticRecorder recorder) async {
    var draft = '';
    var submitted = false;
    await showDialog<void>(context: context, builder: (dialogContext) {
      void submit(String value) {
        if (submitted) return;
        submitted = true;
        if (recorder.isActive && value.trim().isNotEmpty) recorder.addMarker(value.trim());
        Navigator.pop(dialogContext);
      }
      return AlertDialog(title: const Text('Segna il problema'), content: TextFormField(
        autofocus: true, maxLength: 120, onChanged: (value) => draft = value, onFieldSubmitted: submit,
        decoration: const InputDecoration(hintText: 'Es: Francesca non vede più Cama')),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annulla')),
          FilledButton(onPressed: () => submit(draft), child: const Text('Aggiungi'))]);
    });
  }
}
