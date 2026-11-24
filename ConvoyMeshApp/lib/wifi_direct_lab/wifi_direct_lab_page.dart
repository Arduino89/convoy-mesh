import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'wifi_direct_lab_controller.dart';
import 'wifi_direct_lab_models.dart';

/// Isolated Flutter application root for the Wi-Fi Direct Offline Lab.
///
/// Mounting this widget never instantiates `AppShell`, `ConvoyMeshService`,
/// `BackgroundRuntimeService`, `LocationFusionService`, or PostHog uploaders.
class WifiDirectOfflineLabApp extends StatelessWidget {
  const WifiDirectOfflineLabApp({
    super.key,
    this.controller,
  });

  final WifiDirectLabController? controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Convoy Wi-Fi Direct LAB',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: WifiDirectLabPage(controller: controller),
    );
  }
}

class WifiDirectLabPage extends StatefulWidget {
  const WifiDirectLabPage({
    super.key,
    this.controller,
    this.integratedMode = false,
  });

  final WifiDirectLabController? controller;
  /// When embedded in the Outdoor app, Stop must finish before route exit.
  final bool integratedMode;

  @override
  State<WifiDirectLabPage> createState() => _WifiDirectLabPageState();
}

class _WifiDirectLabPageState extends State<WifiDirectLabPage>
    with WidgetsBindingObserver {
  late WifiDirectLabController _controller;
  late bool _ownsController;
  bool _probeSendConsented = false;
  bool _exitInProgress = false;

  Future<void> _returnToOutdoor() async {
    if (_exitInProgress) return;
    _exitInProgress = true;
    try {
      await _controller.stopAll(reason: 'return_to_outdoor');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } finally {
      _exitInProgress = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? WifiDirectLabController();
    _controller.addListener(_onChanged);
    unawaited(_controller.refreshEnvironment());
  }

  @override
  void didUpdateWidget(WifiDirectLabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onChanged);
      if (_ownsController) {
        _controller.dispose();
      }
      _ownsController = widget.controller == null;
      _controller = widget.controller ?? WifiDirectLabController();
      _controller.addListener(_onChanged);
      unawaited(_controller.refreshEnvironment());
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_controller.onAppLifecycleStateChanged(state));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChanged);
    if (_ownsController) {
      _controller.dispose();
    } else {
      unawaited(_controller.stopAll(reason: 'page_disposed'));
    }
    super.dispose();
  }

  Future<void> _confirmAndConnectPeer(String peerId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Conferma connessione a $peerId'),
        content: Text(
          'Stai per richiedere una connessione Wi-Fi Direct locale a $peerId.\n\n'
          '• Nessuna connessione automatica a sconosciuti.\n'
          '• Verranno scambiati solo probe sintetici e ACK con nonce.\n'
          '• Il collegamento scambia solo dati sintetici. Il nome Convoy è visibile in scoperta solo a scelta dell’utente e non autentica il peer.',
        ),
        actions: [
          TextButton(
            key: const Key('wfd_cancel_connect_button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            key: const Key('wfd_confirm_connect_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Acconsento e connetti'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _controller.requestConnect(
        peerId: peerId,
        userConsented: true,
      );
    }
  }

  Future<void> _copyJsonlToClipboard() async {
    final jsonl = _controller.exportJsonl();
    await Clipboard.setData(ClipboardData(text: jsonl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Log JSONL sintetico copiato (${_controller.logs.length} eventi, 0 MAC/SSID/coordinate).',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final env = _controller.environment;
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !widget.integratedMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.integratedMode) {
          unawaited(_returnToOutdoor());
        }
      },
      child: Scaffold(
      appBar: AppBar(
        leading: widget.integratedMode
            ? IconButton(
                key: const Key('wfd_return_to_outdoor'),
                tooltip: 'Chiudi LAB e torna a Convoy',
                onPressed: _exitInProgress ? null : _returnToOutdoor,
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        title: const Text('Convoy Wi-Fi Direct LAB • Gate 1'),
        actions: [
          IconButton(
            key: const Key('wfd_appbar_stop_button'),
            tooltip: 'Stop e chiudi risorse',
            onPressed: () => _controller.stopAll(reason: 'manual_stop'),
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildIsolationBanner(scheme),
            const SizedBox(height: 10),
            if (_controller.lastError != null) ...[
              _buildErrorBanner(_controller.lastError!, scheme),
              const SizedBox(height: 10),
            ],
            _buildEnvironmentCard(env, scheme),
            const SizedBox(height: 10),
            _buildDiscoveryAndPeersCard(env, scheme),
            const SizedBox(height: 10),
            _buildSocketAndProbesCard(scheme),
            const SizedBox(height: 10),
            _buildEventLogCard(scheme),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildIsolationBanner(ColorScheme scheme) {
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.integratedMode
                  ? 'Wi-Fi Direct LAB — opzione sperimentale Outdoor'
                  : 'Laboratorio Wi-Fi Direct Offline (app separata)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Bluetooth spento • Internet assente • Solo probe sintetici e ACK '
              '(nessuna coordinata reale, nessun BLE, nessun FGS, nessun PostHog o Rescue).',
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              'Sessione: ${_controller.sessionId} • Nodo locale: ${_controller.localNodeId}',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String errorText, ColorScheme scheme) {
    return Container(
      key: const Key('wfd_error_banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorText,
              style: TextStyle(
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnvironmentCard(
    WifiDirectEnvironmentStatus env,
    ColorScheme scheme,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '1. Verifica ambiente Android (BT spento / Offline / Permessi)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            _statusRow(
              label: 'Feature Wi-Fi Direct (PackageManager)',
              value: env.wifiDirectFeatureSupported && env.wifiP2pServiceAvailable
                  ? 'Supportato (OK)'
                  : 'Non disponibile',
              ok: env.wifiDirectFeatureSupported && env.wifiP2pServiceAvailable,
            ),
            _statusRow(
              label: 'Bluetooth (deve restare SPENTO)',
              value: env.isBluetoothOffClean
                  ? 'SPENTO (OK)'
                  : 'ATTIVO — Spegnere Bluetooth',
              ok: env.isBluetoothOffClean,
            ),
            _statusRow(
              label: 'Wi-Fi / Stato P2P',
              value: env.wifiEnabled && env.p2pStateEnabled
                  ? 'ATTIVO (OK)'
                  : 'SPENTO — Attivare Wi-Fi',
              ok: env.wifiEnabled && env.p2pStateEnabled,
            ),
            _statusRow(
              label: 'Internet (prova offline senza router)',
              value: env.isOfflineClean
                  ? 'ASSENTE (OK offline)'
                  : 'Connessione Internet rilevata (disattivare dati/router)',
              ok: env.isOfflineClean,
            ),
            _statusRow(
              label: 'Permesso P2P (${env.requiredPermissionName}, SDK ${env.sdkInt})',
              value: env.requiredRuntimePermissionGranted
                  ? 'Concesso (OK)'
                  : 'Non concesso',
              ok: env.requiredRuntimePermissionGranted,
            ),
            if (env.requiresLegacyLocationToggle)
              _statusRow(
                label: 'Toggle Posizione Android <=12 (richiesto da OS per P2P)',
                value: env.locationServiceEnabled ? 'Attivo (OK)' : 'Disattivato',
                ok: env.locationServiceEnabled,
              ),
            _statusRow(
              label: 'Servizio Foreground (FGS)',
              value: !env.foregroundServiceRunning
                  ? 'Inattivo (OK)'
                  : 'Attivo (non consentito nel LAB)',
              ok: !env.foregroundServiceRunning,
            ),
            if (env.readinessBlockers.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final blocker in env.readinessBlockers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $blocker',
                    style: TextStyle(color: scheme.error, fontSize: 12.5),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('wfd_refresh_env_button'),
                  onPressed: _controller.refreshEnvironment,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Aggiorna stato'),
                ),
                OutlinedButton.icon(
                  key: const Key('wfd_request_permission_button'),
                  onPressed: _controller.requestPermission,
                  icon: const Icon(Icons.verified_user_outlined, size: 18),
                  label: const Text('Richiedi permesso P2P'),
                ),
                OutlinedButton.icon(
                  key: const Key('wfd_open_bt_settings_button'),
                  onPressed: _controller.openBluetoothSettings,
                  icon: const Icon(Icons.bluetooth_disabled, size: 18),
                  label: const Text('Impostazioni BT'),
                ),
                OutlinedButton.icon(
                  key: const Key('wfd_open_wifi_settings_button'),
                  onPressed: _controller.openWifiSettings,
                  icon: const Icon(Icons.wifi, size: 18),
                  label: const Text('Impostazioni Wi-Fi'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveryAndPeersCard(
    WifiDirectEnvironmentStatus env,
    ColorScheme scheme,
  ) {
    final peers = _controller.peers;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '2. Scoperta e connessione Wi-Fi Direct (Consenso locale)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            const Text(
              'Ogni peer ha un ID temporaneo. Un nome Convoy dichiarato può '
              'essere condiviso o imitato da più dispositivi e non autentica il peer.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              key: const Key('wfd_share_convoy_name'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostra il mio nome Convoy ai dispositivi vicini'),
              subtitle: const Text('Solo nel LAB. Puoi disattivarlo qui o usare Stop.'),
              value: _controller.sharesConvoyName,
              onChanged: _controller.nameSettingPending ? null : _controller.setShareConvoyName,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('wfd_discover_button'),
                  onPressed: (_controller.isConnecting || _controller.isGroupFormed)
                      ? null
                      : _controller.requestDiscovery,
                  icon: const Icon(Icons.radar),
                  label: Text(
                    _controller.isDiscovering
                        ? 'Riavvia scoperta peer P2P'
                        : 'Scopri peer Wi-Fi Direct',
                  ),
                ),
                if (peers.isEmpty)
                  OutlinedButton.icon(
                    key: const Key('wfd_no_peers_button'),
                    onPressed: _controller.reportNoPeersObserved,
                    icon: const Icon(Icons.search_off),
                    label: const Text('Annota 0 peer rilevati'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (peers.isEmpty)
              const Text(
                'Nessun peer sintetico in elenco. Avvia la scoperta su entrambi i telefoni.',
                style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
              )
            else
              Column(
                children: [
                  for (final peer in peers)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.phonelink_ring),
                      title: Text(
                        peer.declaredName == null
                            ? '${peer.peerId} (${peer.status})'
                            : '${peer.declaredName} — ${peer.peerId} (${peer.status})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${peer.declaredName == null ? '' : 'Nome dichiarato, non autenticato.\n'}'
                        'Rilevato a t=${peer.firstSeenElapsedMs} ms • agg. ${peer.lastSeenElapsedMs} ms',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: FilledButton.tonal(
                        key: Key('wfd_connect_${peer.peerId}'),
                        onPressed: (_controller.isConnecting || _controller.isGroupFormed)
                            ? null
                            : () => _confirmAndConnectPeer(peer.peerId),
                        child: const Text('Connetti'),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocketAndProbesCard(ColorScheme scheme) {
    final rttMean = _controller.meanRttMs;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '3. Connessione Socket TCP & Scambio Bidirezionale (20 Probe + ACK)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            _statusRow(
              label: 'Gruppo Wi-Fi Direct (group_formed)',
              value: _controller.isGroupFormed
                  ? 'FORMATO (ruolo: ${_controller.groupRole.wireName})'
                  : 'Non formato',
              ok: _controller.isGroupFormed,
            ),
            _statusRow(
              label: 'Socket TCP locale (socket_open)',
              value: _controller.isSocketOpen
                  ? 'APERTO (porta ${_controller.activePort})'
                  : 'Chiuso',
              ok: _controller.isSocketOpen,
            ),
            const Divider(height: 16),
            CheckboxListTile(
              key: const Key('wfd_probe_consent_checkbox'),
              contentPadding: EdgeInsets.zero,
              value: _probeSendConsented,
              onChanged: (val) =>
                  setState(() => _probeSendConsented = val ?? false),
              title: const Text(
                'Confermo l’invio locale di soli probe sintetici (seq + nonce casuale, 0 coordinate)',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('wfd_send_20_probes_button'),
                  onPressed: _controller.isSendingBatch
                      ? null
                      : () => _controller.sendProbeBatch(
                            userConsented: _probeSendConsented,
                            count: WifiDirectLabController.defaultProbeBatchSize,
                          ),
                  icon: const Icon(Icons.send),
                  label: const Text('Invia 20 probe sintetici'),
                ),
                OutlinedButton.icon(
                  key: const Key('wfd_send_single_probe_button'),
                  onPressed: _controller.isSendingBatch
                      ? null
                      : () => _controller.sendSingleProbe(
                            userConsented: _probeSendConsented,
                          ),
                  icon: const Icon(Icons.bolt),
                  label: const Text('Invia 1 probe'),
                ),
                OutlinedButton.icon(
                  key: const Key('wfd_resume_probes_button'),
                  onPressed: _controller.isSendingBatch
                      ? null
                      : () => _controller.resumeAfterReconnect(
                            userConsented: _probeSendConsented,
                          ),
                  icon: const Icon(Icons.replay),
                  label: const Text('Riprendi non confermati'),
                ),
                FilledButton.tonalIcon(
                  key: const Key('wfd_stop_all_button'),
                  onPressed: () => _controller.stopAll(reason: 'manual_stop'),
                  icon: const Icon(Icons.stop),
                  label: const Text('STOP • Chiudi tutto'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Inviati (probe_sent): ${_controller.probesSentCount} • '
                    'Confermati (ack_received): ${_controller.acksConfirmedCount} • '
                    'Non confermati/persi: ${_controller.unconfirmedProbesCount}',
                    key: const Key('wfd_outbound_counters_text'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Falsi ACK respinti: ${_controller.falseAcksRejected} (0 false conferme) • '
                    'ACK duplicati ignorati: ${_controller.duplicateAcksIgnored}',
                    key: const Key('wfd_ack_integrity_text'),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ricevuti unici (probe_received): ${_controller.uniqueProbesDelivered} • '
                    'Duplicati soppressi: ${_controller.duplicateProbesSuppressed} • '
                    'ACK inviati: ${_controller.acksSentCount}',
                    key: const Key('wfd_inbound_counters_text'),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'RTT locale (ms): min=${_controller.minRttMs ?? "-"} • '
                    'medio=${rttMean != null ? rttMean.toStringAsFixed(1) : "-"} • '
                    'max=${_controller.maxRttMs ?? "-"}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventLogCard(ColorScheme scheme) {
    final entries = _controller.logs.reversed.toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '4. Log eventi distinguibili (${_controller.logs.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                TextButton.icon(
                  key: const Key('wfd_copy_jsonl_button'),
                  onPressed:
                      _controller.logs.isEmpty ? null : _copyJsonlToClipboard,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copia JSONL'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Eventi di sistema (system), trasporto (transport) e applicativi (application) registrati separatamente.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const Text(
                'Nessun evento registrato.',
                style: TextStyle(fontStyle: FontStyle.italic),
              )
            else
              for (final e in entries.take(60))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: SelectableText(
                    '#${e.index} [${e.layer.wireName}] +${e.elapsedMs}ms ${e.kind.wireName} ${e.data}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow({
    required String label,
    required String value,
    required bool ok,
  }) {
    final color = ok ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
