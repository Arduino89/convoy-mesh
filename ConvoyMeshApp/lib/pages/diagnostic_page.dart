import 'package:flutter/material.dart';

import '../services/background_runtime_service.dart';
import '../services/convoy_mesh_service.dart';
import '../services/diagnostic_capture_bridge.dart';
import '../services/diagnostic_recorder.dart';

class DiagnosticPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final recorder = DiagnosticRecorder.instance;
    final runtime = BackgroundRuntimeService.instance;
    final useOverrides = deviceIdOverride != null && deviceNameOverride != null;
    final mesh = useOverrides ? null : ConvoyMeshService.instance;

    final listenables = <Listenable>[recorder, runtime];
    if (mesh != null) listenables.add(mesh);

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        final deviceId = deviceIdOverride ?? mesh!.myId;
        final deviceName = deviceNameOverride ?? mesh!.myName;
        final identityReady = deviceId != 0 && deviceName.trim().isNotEmpty;

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
                      Text(
                        identityReady
                            ? 'Telefono: $deviceName • ID $deviceId'
                            : 'Identità telefono in inizializzazione…',
                      ),
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
                            onPressed: !identityReady
                                ? null
                                : () async {
                                    recorder.start(
                                      deviceId: deviceId,
                                      deviceName: deviceName,
                                    );

                                    if (captureNowOverride != null) {
                                      captureNowOverride!();
                                    } else {
                                      await runtime.refreshCapabilities();
                                      DiagnosticCaptureBridge.instance.captureNow();
                                    }
                                  },
                            icon: const Icon(Icons.fiber_manual_record),
                            label: Text(
                              identityReady
                                  ? 'Avvia test • max 4 min'
                                  : 'Attendo inizializzazione…',
                            ),
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
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Protezione background e precisione',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      _CapabilityRow(
                        label: 'Servizio background',
                        value: runtime.isRunning ? 'ATTIVO' : 'NON ATTIVO',
                        ok: runtime.isRunning,
                      ),
                      _CapabilityRow(
                        label: 'UWB',
                        value: runtime.uwbSupported ? 'supportato' : 'non disponibile',
                        ok: runtime.uwbSupported,
                      ),
                      _CapabilityRow(
                        label: 'Wi-Fi RTT',
                        value: runtime.wifiRttSupported ? 'supportato' : 'non disponibile',
                        ok: runtime.wifiRttSupported,
                      ),
                      _CapabilityRow(
                        label: 'BLE advertising multiplo',
                        value: runtime.bleMultipleAdvertisingSupported ? 'supportato' : 'limitato',
                        ok: runtime.bleMultipleAdvertisingSupported,
                      ),
                      if (runtime.sdkInt != null)
                        Text('Android API ${runtime.sdkInt}', style: const TextStyle(fontSize: 12)),
                      if (runtime.lastError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Errore runtime: ${runtime.lastError}',
                          style: TextStyle(color: Colors.red.shade700, fontSize: 12),
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
                      Text('2. Blocca uno dei due telefoni per 1–2 minuti.'),
                      Text('3. Sbloccalo e controlla se ricompare subito.'),
                      Text('4. Termina e condividi entrambi i file.'),
                      SizedBox(height: 8),
                      Text('I file usano ora UTC e tempo monotono: posso allinearli e distinguere background, heartbeat, trasmissione, ricezione e GPS.'),
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
    String draft = '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        void submit(String value) {
          final cleaned = value.trim();
          if (cleaned.isNotEmpty) {
            recorder.addMarker(cleaned);
          }
          Navigator.pop(dialogContext);
        }

        return AlertDialog(
          title: const Text('Segna il problema'),
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

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.label,
    required this.value,
    required this.ok,
  });

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.info_outline,
            size: 18,
            color: ok ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
