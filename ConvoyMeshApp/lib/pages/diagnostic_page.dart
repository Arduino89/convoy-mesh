import 'package:flutter/material.dart';
import '../services/background_runtime_service.dart';
import '../services/convoy_mesh_service.dart';
import '../services/diagnostic_capture_bridge.dart';
import '../services/diagnostic_recorder.dart';

class DiagnosticPage extends StatelessWidget {
  const DiagnosticPage({super.key, this.deviceIdOverride, this.deviceNameOverride, this.captureNowOverride});
  final int? deviceIdOverride;
  final String? deviceNameOverride;
  final VoidCallback? captureNowOverride;
  @override
  Widget build(BuildContext context) {
    final recorder = DiagnosticRecorder.instance;
    final runtime = BackgroundRuntimeService.instance;
    final overrides = deviceIdOverride != null && deviceNameOverride != null;
    final mesh = overrides ? null : ConvoyMeshService.instance;
    return AnimatedBuilder(animation: Listenable.merge([recorder, runtime, if (mesh != null) mesh]),
      builder: (context, _) {
        final id = deviceIdOverride ?? mesh!.myId;
        final name = deviceNameOverride ?? mesh!.myName;
        final ready = id > 0 && (overrides || mesh!.isRunning);
        return Scaffold(appBar: AppBar(title: const Text('Test diagnostico')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            _card([
              Text(recorder.isActive ? 'Registrazione in corso' : 'Registra un test breve',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Telefono: $name • ID $id'),
              const Text('0.7.0 candidato • test diagnostici di massimo 4 minuti'),
              Text('Build: ${DiagnosticRecorder.buildCommit}'),
              const SizedBox(height: 8),
              Text(recorder.isPersistent ? 'Log salvato progressivamente sul telefono.' :
                  'Salvataggio su disco non disponibile: il log in memoria può andare perso.'),
              if (recorder.storageError != null) Text(recorder.storageError!, style: const TextStyle(color: Colors.red)),
              const Text('Il test è indipendente dall’uscita: può iniziare prima o dopo e non si chiude con Termina uscita.'),
              const Text('Il file contiene coordinate: condividilo solo per analizzare il test.'),
              if (recorder.isActive) ...[
                Text('Durata ${DiagnosticRecorder.formatDuration(recorder.elapsed)} • restante ${DiagnosticRecorder.formatDuration(recorder.remaining)}'),
                Text('Eventi ${recorder.eventCount} • scartati per limite ${recorder.droppedEvents}'),
                OutlinedButton.icon(onPressed: () => _addMarker(context, recorder),
                    icon: const Icon(Icons.flag_outlined), label: const Text('Segna qui un problema')),
                FilledButton.icon(onPressed: () async {
                  recorder.stop(reason: 'manual_share'); await _share(context, recorder);
                }, icon: const Icon(Icons.stop_circle_outlined), label: const Text('Termina e condividi')),
              ] else ...[
                FilledButton.icon(onPressed: ready ? () async {
                  recorder.start(deviceId: id, deviceName: name);
                  if (captureNowOverride != null) { captureNowOverride!(); }
                  else { await runtime.refreshCapabilities(); DiagnosticCaptureBridge.instance.captureNow(); }
                } : null, icon: const Icon(Icons.fiber_manual_record),
                  label: Text(ready ? 'Avvia test • max 4 min' : 'Attendo modalità Vicini')),
              ],
            ]),
            if (!recorder.isActive && recorder.hasExport) _card([
              const Text('File pronto', style: TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(recorder.lastFileName ?? '-'),
              Text('Chiusura: ${recorder.lastStopReason ?? '-'}'),
              if (recorder.lastStopReason == 'recovered_file_check_session_stop')
                const Text('File recuperato: può essere parziale se il processo è stato interrotto.'),
              FilledButton.icon(onPressed: () => _share(context, recorder),
                  icon: const Icon(Icons.share), label: const Text('Condividi file')),
            ]),
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
