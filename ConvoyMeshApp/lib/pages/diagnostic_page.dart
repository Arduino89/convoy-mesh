import 'package:flutter/material.dart';

import '../services/convoy_mesh_service.dart';
import '../services/diagnostic_capture_bridge.dart';
import '../services/diagnostic_recorder.dart';

class DiagnosticPage extends StatelessWidget {
  const DiagnosticPage({super.key});

  @override
  Widget build(BuildContext context) {
    final recorder = DiagnosticRecorder.instance;
    final mesh = ConvoyMeshService.instance;

    return AnimatedBuilder(
      animation: recorder,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Test diagnostico')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            recorder.isActive ? Icons.fiber_manual_record : Icons.description_outlined,
                            color: recorder.isActive ? Colors.red : Colors.blueGrey,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              recorder.isActive ? 'Registrazione in corso' : 'Registra un test breve',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        recorder.isActive
                            ? 'Durata ${DiagnosticRecorder.formatDuration(recorder.elapsed)} • restante ${DiagnosticRecorder.formatDuration(recorder.remaining)}'
                            : 'Massimo 4 minuti. Il file contiene eventi BLE, GPS, decisioni dei filtri e coordinate della sessione.',
                      ),
                      const SizedBox(height: 8),
                      Text('Telefono: ${mesh.myName} • ID ${mesh.myId}'),
                      if (recorder.isActive) ...[
                        const SizedBox(height: 6),
                        Text('Eventi registrati: ${recorder.eventCount}'),
                        Text('Sessione: ${recorder.sessionId ?? '-'}'),
                      ],
                      const SizedBox(height: 16),
                      if (!recorder.isActive)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () {
                              recorder.start(
                                deviceId: mesh.myId,
                                deviceName: mesh.myName,
                              );
                              DiagnosticCaptureBridge.instance.captureNow();
                            },
                            icon: const Icon(Icons.fiber_manual_record),
                            label: const Text('Avvia test • max 4 min'),
                          ),
                        )
                      else ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _addMarker(context, recorder),
                            icon: const Icon(Icons.flag_outlined),
                            label: const Text('Segna qui un problema'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () async {
                              recorder.stop(reason: 'manual_share');
                              await _share(context, recorder);
                            },
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: const Text('Termina e condividi'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (!recorder.isActive && recorder.hasExport) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green),
                            SizedBox(width: 8),
                            Text('File pronto', style: TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(recorder.lastFileName ?? '-'),
                        const SizedBox(height: 4),
                        Text('Motivo chiusura: ${recorder.lastStopReason ?? '-'}'),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _share(context, recorder),
                            icon: const Icon(Icons.share),
                            label: const Text('Condividi file'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Test consigliato su due telefoni', style: TextStyle(fontWeight: FontWeight.w700)),
                      SizedBox(height: 8),
                      Text('1. Avvia la registrazione su entrambi quasi nello stesso momento.'),
                      Text('2. Esegui il problema per 1–4 minuti.'),
                      Text('3. Premi “Segna qui un problema” quando noti qualcosa di strano.'),
                      Text('4. Termina e condividi entrambi i file.'),
                      SizedBox(height: 8),
                      Text('I file usano ora UTC e tempo monotono: posso allinearli e distinguere trasmissione, ricezione, filtro GPS e aggiornamento peer.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<void> _share(BuildContext context, DiagnosticRecorder recorder) async {
    try {
      final result = await recorder.shareLast();
      if (context.mounted && result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nessun file diagnostico disponibile.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Condivisione non riuscita: $error')),
        );
      }
    }
  }

  static Future<void> _addMarker(BuildContext context, DiagnosticRecorder recorder) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Segna il problema'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
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
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Aggiungi'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (note != null && note.trim().isNotEmpty) {
      recorder.addMarker(note);
    }
  }
}
