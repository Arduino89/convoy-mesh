import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wifi_direct_lab_models.dart';
import 'wifi_direct_lab_pairing.dart';
import 'wifi_direct_lab_transport.dart';

/// State and protocol controller for the isolated Wi-Fi Direct Offline Lab
/// (First Gate).
///
/// Enforces:
/// - Bluetooth OFF and Wi-Fi Direct feature/permission preflight.
/// - Local user consent before connecting to a peer or sending synthetic probes.
/// -Strict separation between system events (`discover_requested`, `peer_seen`,
///  `connect_requested`, `group_formed`), transport events (`socket_open`,
///  `disconnect`), and application proof (`probe_sent`, `probe_received`,
///  `ack_received`).
/// - 20-probe bidirectional exchange with exact `(seq, nonce)` ACK matching
///   (`0` false confirmations) and receiver deduplication across reconnects.
/// - Immediate cleanup of sockets, P2P group, and native receiver on `Stop`,
///   page disposal, or app backgrounding without an explicit LAB lease.
class WifiDirectLabController extends ChangeNotifier {
  WifiDirectLabController({
    WifiDirectPlatformBridge? platform,
    WifiDirectSocketTransport? socketTransport,
    DateTime Function()? nowUtc,
    int Function()? elapsedMsProvider,
    Random? random,
    this.labPort = TcpWifiDirectSocketTransport.defaultLabPort,
  })  : _platform = platform ?? MethodChannelWifiDirectPlatformBridge(),
        _socket = socketTransport ?? TcpWifiDirectSocketTransport(),
        _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
        _random = random ?? Random.secure() {
    _stopwatch.start();
    _elapsedMs = elapsedMsProvider ?? (() => _stopwatch.elapsedMilliseconds);
    _sessionId = _buildSessionId();
    _localNodeId = WifiDirectSyntheticFrame.generateSyntheticNodeId(_random);
    _platformEventSub = _platform.events.listen(
      _handlePlatformEvent,
      onError: (Object error) {
        _record(
          WifiDirectLabEventKind.error,
          layer: WifiDirectEvidenceLayer.system,
          data: <String, Object?>{
            'stage': 'platform_event_stream',
            'code': 'PLATFORM_STREAM_ERROR',
            'message': error.toString(),
          },
        );
      },
    );
  }

  static const int defaultProbeBatchSize = 20;

  final WifiDirectPlatformBridge _platform;
  final WifiDirectSocketTransport _socket;
  final DateTime Function() _nowUtc;
  final Stopwatch _stopwatch = Stopwatch();
  late final int Function() _elapsedMs;
  final Random _random;
  final int labPort;

  StreamSubscription<Map<String, Object?>>? _platformEventSub;
  late String _sessionId;
  late String _localNodeId;

  WifiDirectEnvironmentStatus _environment = const WifiDirectEnvironmentStatus();
  final Map<String, WifiDirectSyntheticPeer> _peers =
      <String, WifiDirectSyntheticPeer>{};
  final List<WifiDirectLabLogEntry> _logs = <WifiDirectLabLogEntry>[];
  final Map<int, WifiDirectSentProbeRecord> _sentProbes =
      <int, WifiDirectSentProbeRecord>{};
  // Maps "$remoteNodeId:$seq" -> nonce for deduplication across link recovery.
  final Map<String, String> _deliveredProbesByRemote = <String, String>{};

  bool _isDiscovering = false;
  bool _isConnecting = false;
  bool _isGroupFormed = false;
  bool _isSocketOpen = false;
  bool _isSendingBatch = false;
  bool _disposed = false;
  static int _nextRadioSession = 0;
  String? _radioSessionId;
  int _radioEpoch = 0;
  int _stopsInProgress = 0;
  bool _discoveryPending = false;
  String? _advertisedName;
  bool _nameSettingPending = false;
  Future<void>? _radioCleanup;

  String? _backgroundCode;
  bool _startingBackground = false;
  String? _trustedNode;
  String? _trustedPeerAlias;
  WifiDirectLabPairing? _pairing;
  Timer? _labTick;
  Timer? _proofDeadline;
  Timer? _recovery;
  Timer? _connectDeadline;
  Future<void>? _socketCleanup;
  bool _groupSocketArmed = false;
  int _socketGeneration = 0;
  String _ownerHost = '';
  int _recoveryStep = 0;
  bool _probeTickPending = false;
  int? _pairedAt;
  int? _latestAck;
  int? _lossStarted;
  int _losses = 0;
  int _connectedMs = 0;
  int? _connectedSince;
  int? _backgroundStarted;
  static const _recoveryDelays = [2, 4, 8, 16, 30, 30];
  static const _ackTimeoutMs = 4000;

  bool get isBackgroundLab => _backgroundCode != null;
  bool get canStartBackgroundLab =>
      _platform is WifiDirectBackgroundBridge && _radioSessionId == null && !radioOperationPending;
  String get backgroundStatus {
    if (!isBackgroundLab) return 'Solo in primo piano';
    if (isSocketOpen) return 'Peer autorizzato, attivo anche a schermo spento';
    if (_trustedNode == null) return 'In attesa di autorizzare il peer';
    return _recoveryStep >= _recoveryDelays.length && _recovery == null && !_isConnecting
        ? 'Tentativi automatici esauriti'
        : 'Collegamento interrotto, ripresa in corso';
  }

  WifiDirectLabQuality get quality {
    final now = _elapsedMs();
    final recent = _sentProbes.values.where((probe) =>
        now - probe.lastSentElapsedMs <= 60000).toList(growable: false);
    final rtts = recent.map((probe) => probe.localRttMs).whereType<int>().toList()..sort();
    final timeouts = recent.where((probe) =>
        !probe.ackConfirmed && now - probe.lastSentElapsedMs >= _ackTimeoutMs).length;
    final retries = recent.fold(0, (int count, probe) => count + probe.attempts - 1);
    return WifiDirectLabQuality(
      connected: isSocketOpen,
      confirmed: rtts.length,
      timeouts: timeouts,
      retries: retries,
      medianRttMs: rtts.isEmpty ? null : rtts[(rtts.length - 1) ~/ 2],
      lastAckAgeMs: _latestAck == null ? null : now - _latestAck!,
      connectedMs: _connectedMs + (_connectedSince == null ? 0 : now - _connectedSince!),
      interruptions: _losses,
    );
  }

  Future<bool> startBackgroundLab(String enteredCode) async {
    final bridge = _platform;
    final code = enteredCode.trim().toLowerCase();
    if (bridge is! WifiDirectBackgroundBridge || !canStartBackgroundLab) return false;
    if (!WifiDirectLabPairing.isCode(code)) {
      _recordError(stage: 'background_lab', code: 'LAB_CODE_REQUIRED',
          message: 'Inserisci il codice LAB generato di 32 caratteri.');
      return false;
    }
    _startingBackground = true;
    final id = _newRadioSession();
    _radioSessionId = id;
    _notify();
    try {
      await refreshEnvironment();
      if (!_isRadioSessionCurrent(id)) return false;
      final blocker = _checkPreflightCodeAndMessage();
      if (blocker != null) {
        _recordError(stage: 'background_lab', code: blocker.$1, message: blocker.$2);
        _radioSessionId = null;
        return false;
      }
      final started = await (bridge as WifiDirectBackgroundBridge).startBackgroundLab(id);
      if (!_isRadioSessionCurrent(id)) return false;
      if (!started) throw StateError('Servizio LAB non disponibile');
      _backgroundCode = code;
      _localNodeId = WifiDirectSyntheticFrame.generateSyntheticNodeId(_random);
      _backgroundStarted = _elapsedMs();
      _sentProbes.clear();
      _deliveredProbesByRemote.clear();
      _resetQuality();
      _labTick = Timer.periodic(const Duration(seconds: 5), (_) {
        unawaited(_sampleBackground());
      });
      _record(WifiDirectLabEventKind.lifecycle, data: {'state': 'background_lab_started'});
      return true;
    } catch (_) {
      if (_isRadioSessionCurrent(id)) {
        await stopAll(reason: 'background_start_failed');
        _recordError(stage: 'background_lab', code: 'LAB_START_FAILED',
            message: 'Riapri il LAB in primo piano e verifica il permesso Notifiche.');
      }
      return false;
    } finally {
      if (_isRadioSessionCurrent(id) || _radioSessionId == null) {
        _startingBackground = false;
        _notify();
      }
    }
  }

  String _newRadioSession() =>
      '${DateTime.now().microsecondsSinceEpoch}-${++_nextRadioSession}';

  void _resetQuality() {
    _pairedAt = null;
    _latestAck = null;
    _lossStarted = null;
    _losses = 0;
    _connectedMs = 0;
    _connectedSince = null;
  }

  Future<void> _sampleBackground() async {
    if (_probeTickPending || !isBackgroundLab) return;
    final now = _elapsedMs();
    if (_trustedNode == null && now - _backgroundStarted! >= 120000) {
      await stopAll(reason: 'pairing_deadline');
      return;
    }
    if (!isSocketOpen) {
      _notify();
      return;
    }
    final lastResponse = max(_pairedAt ?? 0, _latestAck ?? 0);
    if (now - lastResponse >= 20000) {
      await _dropBackgroundSocket('probe_ack_deadline');
      return;
    }
    if (_isSendingBatch) return;
    final epoch = _radioEpoch;
    _probeTickPending = true;
    try {
      await sendSingleProbe(userConsented: true);
      if (!_isRadioEpochCurrent(epoch) || !isBackgroundLab) return;
      final sample = quality;
      _record(WifiDirectLabEventKind.linkQuality, data: sample.toLog());
    } finally {
      if (_isRadioEpochCurrent(epoch)) _probeTickPending = false;
    }
  }

  bool get sharesConvoyName => _advertisedName != null;
  bool get radioOperationPending =>
      _startingBackground || _discoveryPending || _nameSettingPending || _stopsInProgress > 0;

  bool _isRadioEpochCurrent(int epoch) => !_disposed && _radioEpoch == epoch;

  bool _isRadioSessionCurrent(String sessionId) =>
      !_disposed && _radioSessionId == sessionId;
  String? _selectedPeerId;
  String? _lastError;
  WifiDirectGroupRole _groupRole = WifiDirectGroupRole.none;
  int _activePort = TcpWifiDirectSocketTransport.defaultLabPort;
  int _nextSeq = 1;
  int _batchEpoch = 0;

  int _uniqueProbesDelivered = 0;
  int _duplicateProbesSuppressed = 0;
  int _falseAcksRejected = 0;
  int _duplicateAcksIgnored = 0;
  int _invalidFramesRejected = 0;
  int _acksSentCount = 0;

  String get sessionId => _sessionId;
  String get localNodeId => _localNodeId;
  WifiDirectEnvironmentStatus get environment => _environment;
  List<WifiDirectSyntheticPeer> get peers =>
      _peers.values.toList(growable: false);
  List<WifiDirectLabLogEntry> get logs => List.unmodifiable(_logs);
  List<WifiDirectSentProbeRecord> get sentProbes =>
      _sentProbes.values.toList(growable: false);

  bool get isDiscovering => _isDiscovering;
  bool get isConnecting => _isConnecting;
  bool get isGroupFormed => _isGroupFormed;
  bool get isSocketOpen => _isSocketOpen && _socket.isSocketOpen;
  bool get isSendingBatch => _isSendingBatch;
  String? get selectedPeerId => _selectedPeerId;
  String? get lastError => _lastError;
  WifiDirectGroupRole get groupRole => _groupRole;
  int get activePort => _activePort;

  int get probesSentCount => _sentProbes.length;
  int get acksConfirmedCount =>
      _sentProbes.values.where((p) => p.ackConfirmed).length;
  int get unconfirmedProbesCount =>
      _sentProbes.values.where((p) => !p.ackConfirmed).length;
  int get uniqueProbesDelivered => _uniqueProbesDelivered;
  int get duplicateProbesSuppressed => _duplicateProbesSuppressed;
  int get falseAcksRejected => _falseAcksRejected;
  int get duplicateAcksIgnored => _duplicateAcksIgnored;
  int get invalidFramesRejected => _invalidFramesRejected;
  int get acksSentCount => _acksSentCount;

  List<int> get confirmedRttsMs => _sentProbes.values
      .where((p) => p.ackConfirmed && p.localRttMs != null)
      .map((p) => p.localRttMs!)
      .toList(growable: false);

  int? get minRttMs {
    final rtts = confirmedRttsMs;
    if (rtts.isEmpty) return null;
    return rtts.reduce(min);
  }

  int? get maxRttMs {
    final rtts = confirmedRttsMs;
    if (rtts.isEmpty) return null;
    return rtts.reduce(max);
  }

  double? get meanRttMs {
    final rtts = confirmedRttsMs;
    if (rtts.isEmpty) return null;
    final sum = rtts.fold<int>(0, (acc, v) => acc + v);
    return sum / rtts.length;
  }

  String _buildSessionId() {
    final stamp =
        _nowUtc().toIso8601String().replaceAll(RegExp(r'[^0-9TZ]'), '');
    final suffix = List.generate(
      3,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'WFD-$stamp-$suffix';
  }

  Future<WifiDirectEnvironmentStatus> refreshEnvironment() async {
    try {
      _environment = await _platform.getEnvironmentStatus();
      _notify();
    } catch (e) {
      _recordError(
        stage: 'environment_check',
        code: 'ENVIRONMENT_CHECK_FAILED',
        message: e.toString(),
      );
    }
    return _environment;
  }

  Future<WifiDirectEnvironmentStatus> requestPermission() async {
    try {
      _environment = await _platform.requestRequiredPermission();
      if (!_environment.requiredRuntimePermissionGranted) {
        _recordError(
          stage: 'permission_request',
          code: 'PERMISSION_DENIED',
          message:
              'Permesso runtime ${_environment.requiredPermissionName} negato dall’utente.',
        );
      } else {
        _lastError = null;
      }
      _notify();
    } catch (e) {
      _recordError(
        stage: 'permission_request',
        code: 'PERMISSION_REQUEST_ERROR',
        message: e.toString(),
      );
    }
    return _environment;
  }

  Future<void> openWifiSettings() => _platform.openWifiSettings();
  Future<void> openBluetoothSettings() => _platform.openBluetoothSettings();
  Future<void> openLocationSettings() => _platform.openLocationSettings();
  Future<void> openAppSettings() => _platform.openAppSettings();

  Future<void> setShareConvoyName(bool enabled) async {
    if (_disposed || radioOperationPending || _isConnecting) return;
    final epoch = _radioEpoch;
    _nameSettingPending = true;
    _notify();
    try {
      final name = enabled
          ? WifiDirectSyntheticPeer.cleanDeclaredName(
              (await SharedPreferences.getInstance()).getString('my_name'))
          : null;
      if (!_isRadioEpochCurrent(epoch)) return;
      if (enabled && name == null) {
        _recordError(
          stage: 'name_advertisement',
          code: 'NO_SHAREABLE_CONVOY_NAME',
          message: 'Imposta un nome Convoy con lettere, numeri, spazi, trattini o apostrofi.',
        );
        return;
      }
      _advertisedName = name;
      final sessionId = _radioSessionId;
      if (sessionId != null) {
        await _platform.advertiseConvoyName(
          sessionId: sessionId,
          declaredName: name,
        );
      }
    } catch (_) {
      if (!_isRadioEpochCurrent(epoch)) return;
      _advertisedName = null;
      _recordError(
        stage: 'name_advertisement',
        code: 'NAME_ADVERTISEMENT_UNAVAILABLE',
        message: 'Annuncio del nome non disponibile.',
      );
    } finally {
      if (_isRadioEpochCurrent(epoch)) {
        _nameSettingPending = false;
        _notify();
      }
    }
  }

  /// Step 1: Request Wi-Fi Direct peer discovery.
  ///
  /// Fails closed (with an explicit `error` event and zero BLE fallback) if
  /// Bluetooth is enabled, Wi-Fi is off, Wi-Fi Direct is unsupported, or the
  /// required permission is missing.
  Future<bool> requestDiscovery() async {
    if (_disposed || radioOperationPending) return false;
    if (_isConnecting || _isGroupFormed) {
      _recordError(
        stage: 'discover_preflight',
        code: 'P2P_CONNECTION_ACTIVE',
        message: 'Connessione Wi-Fi Direct in corso: attendere oppure usare Stop prima di cercare altri peer.',
      );
      return false;
    }
    final epoch = _radioEpoch;
    _discoveryPending = true;
    _notify();
    try {
      return await _discoverInEpoch(epoch);
    } finally {
      if (_isRadioEpochCurrent(epoch)) {
        _discoveryPending = false;
        _notify();
      }
    }
  }

  Future<bool> _discoverInEpoch(int epoch) async {
    await refreshEnvironment();
    if (!_isRadioEpochCurrent(epoch)) return false;
    _record(
      WifiDirectLabEventKind.discoverRequested,
      layer: WifiDirectEvidenceLayer.system,
      data: <String, Object?>{
        'bluetooth_off': _environment.isBluetoothOffClean,
        'wifi_enabled': _environment.wifiEnabled,
        'internet_absent': _environment.isOfflineClean,
        'permission_granted': _environment.requiredRuntimePermissionGranted,
        'location_enabled': _environment.locationServiceEnabled,
      },
    );

    final preflightFailure = _checkPreflightCodeAndMessage();
    if (preflightFailure != null) {
      _isDiscovering = false;
      _recordError(
        stage: 'discover_preflight',
        code: preflightFailure.$1,
        message: preflightFailure.$2,
      );
      return false;
    }

    if (!_isRadioEpochCurrent(epoch)) return false;
    final sessionId = _radioSessionId ??= _newRadioSession();
    try {
      await _platform.discoverPeers(sessionId: sessionId, declaredName: _advertisedName);
      if (!_isRadioSessionCurrent(sessionId)) return false;
      _isDiscovering = true;
      _lastError = null;
      _notify();
      return true;
    } catch (e) {
      if (!_isRadioSessionCurrent(sessionId)) return false;
      _isDiscovering = false;
      _recordError(
        stage: 'discover_peers',
        code: 'DISCOVER_PEERS_FAILED',
        message: e.toString(),
      );
      return false;
    }
  }

  /// Reports an explicit `no_peers` error when a discovery window completes
  /// with zero peers observed.
  void reportNoPeersObserved() {
    if (_peers.isNotEmpty) return;
    _recordError(
      stage: 'discover_peers',
      code: 'NO_PEERS_FOUND',
      message:
          'Nessun peer Wi-Fi Direct rilevato. Verificare che anche l’altro telefono sia in scoperta con Wi-Fi attivo.',
    );
  }

  /// Step 2: Request P2P connection to an explicitly selected synthetic peer.
  ///
  /// Never auto-connects to unknown devices; [userConsented] must be `true`.
  Future<bool> requestConnect({
    required String peerId,
    required bool userConsented,
  }) async {
    if (_disposed || radioOperationPending) return false;
    if (!userConsented) {
      _recordError(
        stage: 'connect_preflight',
        code: 'CONSENT_REQUIRED',
        message:
            'Consenso locale richiesto per avviare la connessione al peer $peerId.',
      );
      return false;
    }
    if (!WifiDirectSyntheticPeer.validSyntheticPeerId.hasMatch(peerId)) {
      _recordError(
        stage: 'connect_preflight',
        code: 'INVALID_SYNTHETIC_PEER_ID',
        message: 'ID peer non sintetico o non valido: $peerId',
      );
      return false;
    }
    if (!_peers.containsKey(peerId)) {
      _recordError(
        stage: 'connect_preflight',
        code: 'PEER_NOT_FOUND',
        message: 'Peer $peerId non presente nell’elenco scoperto.',
      );
      return false;
    }

    if (isBackgroundLab && _trustedNode != null && peerId != _trustedPeerAlias) {
      return false;
    }
    final sessionId = _radioSessionId;
    if (sessionId == null) return false;
    await refreshEnvironment();
    if (!_isRadioSessionCurrent(sessionId) || radioOperationPending || !_peers.containsKey(peerId)) return false;
    final preflightFailure = _checkPreflightCodeAndMessage();
    if (preflightFailure != null) {
      _recordError(
        stage: 'connect_preflight',
        code: preflightFailure.$1,
        message: preflightFailure.$2,
      );
      return false;
    }

    // The environment check is asynchronous: recheck here to prevent two
    // taps from starting concurrent P2P negotiations with the same radio.
    if (_isConnecting || _isGroupFormed) {
      _recordError(
        stage: 'connect_preflight',
        code: 'P2P_CONNECTION_ACTIVE',
        message: 'Una richiesta Wi-Fi Direct è già in corso. Attendere oppure usare Stop prima di riprovare.',
      );
      return false;
    }
    _selectedPeerId = peerId;
    _isConnecting = true;
    _record(
      WifiDirectLabEventKind.connectRequested,
      layer: WifiDirectEvidenceLayer.system,
      data: <String, Object?>{
        'peer_id': peerId,
        'user_consented': true,
      },
    );

    if (!_isRadioSessionCurrent(sessionId)) return false;
    try {
      await _platform.connectPeer(
        sessionId: sessionId,
        peerId: peerId,
        userConsented: true,
      );
      if (!_isRadioSessionCurrent(sessionId)) return false;
      _lastError = null;
      if (isBackgroundLab && _isConnecting) {
        _connectDeadline?.cancel();
        _connectDeadline = Timer(const Duration(seconds: 30), () {
          if (_isRadioSessionCurrent(sessionId) && _isConnecting) {
            unawaited(stopAll(reason: 'android_negotiation_deadline'));
          }
        });
      }
      _notify();
      return true;
    } catch (e) {
      if (!_isRadioSessionCurrent(sessionId)) return false;
      _isConnecting = false;
      _recordError(
        stage: 'connect_peer',
        code: 'CONNECT_PEER_FAILED',
        message: e.toString(),
      );
      return false;
    }
  }

  /// Step 3: Send a single synthetic probe over the open Wi-Fi Direct socket.
  Future<bool> sendSingleProbe({
    required bool userConsented,
    String syntheticState = WifiDirectSyntheticFrame.defaultSyntheticState,
  }) async {
    if (!userConsented) {
      _recordError(
        stage: 'send_probe',
        code: 'CONSENT_REQUIRED',
        message: 'Consenso locale richiesto prima di inviare probe sintetici.',
      );
      return false;
    }
    if (!isSocketOpen) {
      _recordError(
        stage: 'send_probe',
        code: 'SOCKET_NOT_OPEN',
        message:
            'Impossibile inviare probe: socket TCP Wi-Fi Direct non aperto.',
      );
      return false;
    }
    if (_environment.bluetoothEnabled) {
      _recordError(
        stage: 'send_probe',
        code: 'BLUETOOTH_MUST_BE_OFF',
        message:
            'Bluetooth attivo: spegnere il Bluetooth prima di inviare probe Wi-Fi Direct.',
      );
      return false;
    }

    final seq = _nextSeq++;
    final nonce = WifiDirectSyntheticFrame.generateNonce(_random);
    final nowElapsed = _elapsedMs();
    final frame = WifiDirectSyntheticFrame.probe(
      senderNodeId: _localNodeId,
      seq: seq,
      nonce: nonce,
      sentElapsedMs: nowElapsed,
      syntheticState: syntheticState,
    );

    final record = WifiDirectSentProbeRecord(
      seq: seq,
      nonce: nonce,
      syntheticState: syntheticState,
      firstSentElapsedMs: nowElapsed,
      lastSentElapsedMs: nowElapsed,
    );
    _sentProbes[seq] = record;

    try {
      await _sendFrame(frame);
      _record(
        WifiDirectLabEventKind.probeSent,
        layer: WifiDirectEvidenceLayer.application,
        data: <String, Object?>{
          'seq': seq,
          'nonce': nonce,
          'synthetic_state': syntheticState,
          'attempt': 1,
          'retransmit': false,
        },
      );
      return true;
    } catch (e) {
      _sentProbes.remove(seq);
      _recordError(
        stage: 'send_probe',
        code: 'SOCKET_SEND_FAILED',
        message: 'Errore invio probe seq=$seq: $e',
        layer: WifiDirectEvidenceLayer.transport,
      );
      return false;
    }
  }

  /// Step 3b: Send the standard 20-probe synthetic batch over the open socket.
  Future<int> sendProbeBatch({
    required bool userConsented,
    int count = defaultProbeBatchSize,
    Duration interval = const Duration(milliseconds: 40),
  }) async {
    if (!userConsented) {
      _recordError(
        stage: 'send_probe_batch',
        code: 'CONSENT_REQUIRED',
        message:
            'Consenso locale richiesto per avviare la sequenza di $count probe sintetici.',
      );
      return 0;
    }
    if (count < 1 || count > 200) {
      throw ArgumentError.value(count, 'count', 'Must be between 1 and 200');
    }
    if (!isSocketOpen) {
      _recordError(
        stage: 'send_probe_batch',
        code: 'SOCKET_NOT_OPEN',
        message:
            'Impossibile avviare i $count probe: socket TCP Wi-Fi Direct non aperto.',
      );
      return 0;
    }

    final myEpoch = ++_batchEpoch;
    _isSendingBatch = true;
    _notify();
    var sentInBatch = 0;

    try {
      for (var i = 0; i < count; i++) {
        if (myEpoch != _batchEpoch || !isSocketOpen || _disposed) {
          break;
        }
        final ok = await sendSingleProbe(userConsented: true);
        if (!ok) {
          break;
        }
        sentInBatch++;
        if (i + 1 < count && interval > Duration.zero) {
          await Future<void>.delayed(interval);
        }
      }
    } finally {
      if (myEpoch == _batchEpoch) {
        _isSendingBatch = false;
        _notify();
      }
    }
    return sentInBatch;
  }

  /// Step 4: After link loss and reconnection, retransmit unconfirmed probes
  /// with their original `(seq, nonce)` (so the receiver deduplicates already
  /// delivered probes while re-ACKing lost confirmations) and complete any
  /// remaining probes up to [targetTotalProbes].
  Future<int> resumeAfterReconnect({
    required bool userConsented,
    int targetTotalProbes = defaultProbeBatchSize,
    int? maxRetransmissions,
    Duration interval = const Duration(milliseconds: 40),
  }) async {
    if (!userConsented) {
      _recordError(
        stage: 'resume_probes',
        code: 'CONSENT_REQUIRED',
        message: 'Consenso locale richiesto per riprendere i probe dopo la riconnessione.',
      );
      return 0;
    }
    if (!isSocketOpen) {
      _recordError(
        stage: 'resume_probes',
        code: 'SOCKET_NOT_OPEN',
        message: 'Socket TCP non aperto: attendere socket_open prima della ripresa.',
      );
      return 0;
    }

    final myEpoch = ++_batchEpoch;
    _isSendingBatch = true;
    _notify();
    var transmitted = 0;

    try {
      final unacked = _sentProbes.values
          .where((p) => !p.ackConfirmed)
          .toList(growable: false)
        ..sort((a, b) => a.seq.compareTo(b.seq));

      final toRetry = maxRetransmissions == null
          ? unacked
          : unacked.reversed.where((record) => record.attempts < 3).take(maxRetransmissions);
      for (final record in toRetry) {
        if (myEpoch != _batchEpoch || !isSocketOpen || _disposed) break;
        final nowElapsed = _elapsedMs();
        record.lastSentElapsedMs = nowElapsed;
        record.attempts += 1;
        final frame = WifiDirectSyntheticFrame.probe(
          senderNodeId: _localNodeId,
          seq: record.seq,
          nonce: record.nonce,
          sentElapsedMs: nowElapsed,
          syntheticState: record.syntheticState,
        );
        try {
          await _sendFrame(frame);
          transmitted++;
          _record(
            WifiDirectLabEventKind.probeSent,
            layer: WifiDirectEvidenceLayer.application,
            data: <String, Object?>{
              'seq': record.seq,
              'nonce': record.nonce,
              'synthetic_state': record.syntheticState,
              'attempt': record.attempts,
              'retransmit': true,
            },
          );
        } catch (e) {
          _recordError(
            stage: 'retransmit_probe',
            code: 'SOCKET_SEND_FAILED',
            message: 'Errore ritrasmissione seq=${record.seq}: $e',
            layer: WifiDirectEvidenceLayer.transport,
          );
          break;
        }
        if (interval > Duration.zero) {
          await Future<void>.delayed(interval);
        }
      }

      while (_sentProbes.length < targetTotalProbes &&
          myEpoch == _batchEpoch &&
          isSocketOpen &&
          !_disposed) {
        final ok = await sendSingleProbe(userConsented: true);
        if (!ok) break;
        transmitted++;
        if (_sentProbes.length < targetTotalProbes && interval > Duration.zero) {
          await Future<void>.delayed(interval);
        }
      }
    } finally {
      if (myEpoch == _batchEpoch) {
        _isSendingBatch = false;
        _notify();
      }
    }
    return transmitted;
  }

  /// Step 5: Stop discovery, close TCP sockets, tear down Wi-Fi Direct group,
  /// and unregister native receivers.
  Future<void> stopAll({String reason = 'manual_stop'}) async {
    final sessionId = _invalidateRadioSession();
    _stopsInProgress++;
    _batchEpoch++;
    _isSendingBatch = false;
    final hadActiveResources =
        sessionId != null || _isDiscovering || _isConnecting || _isGroupFormed || _isSocketOpen || _socket.isSocketOpen;
    final stateBeforeStop = _radioLogState;

    _isDiscovering = false;
    _isConnecting = false;
    _isGroupFormed = false;
    _isSocketOpen = false;
    _groupRole = WifiDirectGroupRole.none;
    _selectedPeerId = null;
    _peers.clear();
    final cleanup = _releaseRadio(sessionId, reason);
    _notify();

    try {
      await cleanup;
    } finally {
      _stopsInProgress--;
    }

    if (hadActiveResources) {
      _record(
        WifiDirectLabEventKind.disconnect,
        layer: WifiDirectEvidenceLayer.transport,
        data: <String, Object?>{
          'reason': reason,
          'source': 'local_stop',
          ...stateBeforeStop,
          'probes_sent': probesSentCount,
          'acks_confirmed': acksConfirmedCount,
          'unconfirmed_probes': unconfirmedProbesCount,
        },
      );
    } else {
      _notify();
    }
  }

  Map<String, Object?> get _radioLogState => {
    'discovering': _isDiscovering,
    'connecting': _isConnecting,
    'group_formed': _isGroupFormed,
    'socket_open': _isSocketOpen,
  };

  /// Losing window focus to an Android system dialog keeps the LAB session.
  /// Hidden, paused and detached indicate that its route is no longer visible.
  Future<void> onAppLifecycleStateChanged(AppLifecycleState state) async {
    if (isBackgroundLab &&
        (state == AppLifecycleState.hidden || state == AppLifecycleState.paused)) {
      _record(WifiDirectLabEventKind.lifecycle, data: {
        'state': state.name, 'background_lab': true, ..._radioLogState,
      });
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      await stopAll(reason: 'app_backgrounded_${state.name}');
    } else if (state == AppLifecycleState.inactive && _radioSessionId != null) {
      _record(WifiDirectLabEventKind.lifecycle, data: {
        'state': state.name,
        ..._radioLogState,
      });
    } else if (state == AppLifecycleState.resumed) {
      await refreshEnvironment();
    }
  }

  String exportJsonl() =>
      _logs.isEmpty ? '' : '${_logs.map((e) => e.toJsonLine()).join('\n')}\n';

  String? _invalidateRadioSession() {
    final sessionId = _radioSessionId;
    _radioSessionId = null;
    _backgroundCode = null;
    _startingBackground = false;
    _trustedNode = null;
    _trustedPeerAlias = null;
    _pairing = null;
    _labTick?.cancel();
    _proofDeadline?.cancel();
    _connectDeadline?.cancel();
    _recovery?.cancel();
    _recovery = null;
    _recoveryStep = 0;
    _probeTickPending = false;
    _groupSocketArmed = false;
    _socketGeneration++;
    _closeQualityInterval();
    _advertisedName = null;
    _radioEpoch++;
    _discoveryPending = false;
    _nameSettingPending = false;
    return sessionId;
  }

  void _handlePlatformEvent(Map<String, Object?> event) {
    final sessionId = event['session_id'];
    if (sessionId is! String || !_isRadioSessionCurrent(sessionId)) return;
    final type = event['type'] as String?;
    switch (type) {
      case 'p2p_state_changed':
        final enabled = event['enabled'] == true;
        _environment = _environment.copyWith(p2pStateEnabled: enabled);
        if (!enabled) {
          _recordError(
            stage: 'p2p_state',
            code: 'WIFI_P2P_DISABLED',
            message: 'Wi-Fi Direct disabilitato a livello di sistema.',
          );
          unawaited(_closeTransportOnDisconnect('wifi_p2p_disabled'));
        } else {
          _notify();
        }
        break;

      case 'peers_updated':
        final rawPeers = event['peers'];
        final now = _elapsedMs();
        final seenIds = <String>{};
        if (rawPeers is List) {
          for (final item in rawPeers) {
            if (item is Map) {
              final peerId = item['peer_id']?.toString() ?? '';
              final status = item['status']?.toString() ?? 'available';
              if (!WifiDirectSyntheticPeer.validSyntheticPeerId.hasMatch(peerId)) {
                continue;
              }
              seenIds.add(peerId);
              final existing = _peers[peerId];
              final isNewOrChanged = existing == null || existing.status != status;
              _peers[peerId] = WifiDirectSyntheticPeer(
                peerId: peerId,
                status: status,
                firstSeenElapsedMs: existing?.firstSeenElapsedMs ?? now,
                lastSeenElapsedMs: now,
                declaredName: WifiDirectSyntheticPeer.cleanDeclaredName(
                  item['declared_name'] is String ? item['declared_name'] as String : null,
                ),
              );
              if (isNewOrChanged) {
                _record(
                  WifiDirectLabEventKind.peerSeen,
                  layer: WifiDirectEvidenceLayer.system,
                  data: <String, Object?>{
                    'peer_id': peerId,
                    'status': status,
                    'peer_count': rawPeers.length,
                  },
                );
              }
            }
          }
        }
        _peers.removeWhere((id, _) => !seenIds.contains(id));
        _notify();
        break;

      case 'group_formed':
        final role = WifiDirectGroupRole.fromWire(event['role']?.toString());
        final clientCount = (event['client_count'] as num?)?.toInt() ?? 0;
        final ownerHost = event['group_owner_host']?.toString().trim() ?? '';
        final port = (event['port'] as num?)?.toInt() ?? labPort;
        _connectDeadline?.cancel();
        _isConnecting = false;
        if (isBackgroundLab && _isGroupFormed && _groupRole == role && _ownerHost == ownerHost) break;
        _isGroupFormed = true;
        _groupSocketArmed = false;
        _ownerHost = ownerHost;
        _recovery?.cancel();
        _recovery = null;
        _groupRole = role;
        _activePort = port;

        // Log group_formed WITHOUT storing IP/MAC/SSID in the diagnostic log.
        _record(
          WifiDirectLabEventKind.groupFormed,
          layer: WifiDirectEvidenceLayer.system,
          data: <String, Object?>{
            'role': role.wireName,
            'client_count': clientCount,
            if (_selectedPeerId != null) 'peer_id': _selectedPeerId,
          },
        );
        unawaited(_openSocketForGroup(sessionId: sessionId, role: role, ownerHost: ownerHost, port: port));
        break;

      case 'p2p_disconnected':
        final reason = event['reason']?.toString() ?? 'p2p_disconnected';
        if (isBackgroundLab && _trustedNode != null && reason == 'p2p_group_lost' &&
            event['session_ended'] != true) {
          unawaited(_recoverAfterGroupLoss(reason));
        } else {
          unawaited(_closeTransportOnDisconnect(reason));
        }
        break;

      case 'dns_sd_status':
        final stage = event['stage'];
        final outcome = event['outcome'];
        const stages = {'clear_advertisement', 'advertisement', 'remove_advertisement', 'clear_request',
          'add_request', 'query', 'txt', 'peer_mapping'};
        const outcomes = {'accepted', 'rejected', 'unavailable', 'received', 'mapped', 'retrying', 'timed_out'};
        const mappings = {'mapped', 'unchanged', 'waiting_peer', 'invalid_label', 'other_domain'};
        if (!stages.contains(stage) || !outcomes.contains(outcome)) break;
        _record(WifiDirectLabEventKind.dnsSdStatus, data: {
          'stage': stage,
          'outcome': outcome,
          if (mappings.contains(event['mapping'])) 'mapping': event['mapping'],
          for (final key in ['android_code', 'txt_received', 'domain_matched', 'peer_mapped'])
            if (event[key] is int) key: event[key],
        });
        break;

      case 'native_error':
        final stage = event['stage']?.toString() ?? 'native';
        final code = event['code']?.toString() ?? 'NATIVE_ERROR';
        final msg = event['message']?.toString() ?? 'Errore nativo Wi-Fi Direct';
        _recordError(stage: stage, code: code, message: msg);
        break;
    }
  }

  Future<void> _openSocketForGroup({
    required String sessionId,
    required WifiDirectGroupRole role,
    required String ownerHost,
    required int port,
  }) async {
    if (!_isRadioSessionCurrent(sessionId) || !_isGroupFormed || _groupSocketArmed) return;
    _groupSocketArmed = true;
    final generation = ++_socketGeneration;
    bool current() => _isRadioSessionCurrent(sessionId) && _isGroupFormed &&
        generation == _socketGeneration;
    void opened(int activePort) {
      if (!current()) return;
      _activePort = activePort;
      final code = _backgroundCode;
      if (code == null) {
        _markSocketOpen(role);
      } else {
        final proof = WifiDirectLabPairing(code,
            owner: role == WifiDirectGroupRole.groupOwner, localNode: _localNodeId,
            initiated: _selectedPeerId != null);
        _pairing = proof;
        _proofDeadline?.cancel();
        _proofDeadline = Timer(const Duration(seconds: 6), () {
          if (current() && !isSocketOpen) {
            unawaited(_dropBackgroundSocket('peer_proof_deadline'));
          }
        });
        _sendProof(proof.hello, generation);
      }
    }
    void receive(String line) {
      if (!current()) return;
      final proof = _pairing;
      if (!isBackgroundLab) {
        _handleIncomingJsonLine(line);
        return;
      }
      if (proof == null) return;
      try {
        final wasVerified = proof.verified;
        final message = proof.receive(line);
        if (message.reply != null) _sendProof(message.reply!, generation);
        if (!wasVerified && proof.verified) {
          if (_trustedNode != null && _trustedNode != proof.remoteNode) {
            throw const FormatException('Peer LAB diverso');
          }
          final recovered = _trustedNode != null;
          _trustedNode = proof.remoteNode;
          if (!recovered && (!proof.remoteInitiated ||
              _localNodeId.compareTo(proof.remoteNode!) < 0)) {
            _trustedPeerAlias = _selectedPeerId;
          }
          _pairedAt = _elapsedMs();
          _proofDeadline?.cancel();
          _recoveryStep = 0;
          _markSocketOpen(role);
          final lostAt = _lossStarted;
          _lossStarted = null;
          _record(WifiDirectLabEventKind.lifecycle, data: {
            'state': recovered ? 'background_peer_recovered' : 'background_peer_verified',
            if (lostAt != null) 'outage_ms': _elapsedMs() - lostAt,
          });
          if (recovered) {
            unawaited(resumeAfterReconnect(userConsented: true,
              targetTotalProbes: 0, maxRetransmissions: 3));
          }
        }
        if (message.payload != null) _handleIncomingJsonLine(message.payload!);
      } on FormatException {
        unawaited(_dropBackgroundSocket('peer_proof_rejected'));
      }
    }
    void disconnected(String reason) {
      if (!current()) return;
      if (isBackgroundLab) {
        unawaited(_dropBackgroundSocket(reason));
      } else {
        unawaited(_handleSocketClosed(reason));
      }
    }
    void failed(String code, String message) {
      if (!current()) return;
      _recordError(stage: 'socket_${role.wireName}', code: code,
          message: isBackgroundLab ? 'Connessione TCP Wi-Fi Direct non disponibile.' : message,
          layer: WifiDirectEvidenceLayer.transport);
      if (isBackgroundLab) unawaited(_dropBackgroundSocket('socket_setup_failed'));
    }

    final transport = _socket;
    if (transport is TcpWifiDirectSocketTransport) {
      transport.pairedOnly = isBackgroundLab;
      transport.pairedOwnerAddress = isBackgroundLab ? ownerHost : null;
    }
    if (role == WifiDirectGroupRole.groupOwner) {
      if (isBackgroundLab && ownerHost.isEmpty) {
        failed('P2P_OWNER_ADDRESS_MISSING', 'Indirizzo Wi-Fi Direct non disponibile.');
        return;
      }
      await _socket.startGroupOwnerServer(port: port, onSocketOpen: opened,
          onLineReceived: receive, onSocketDisconnected: disconnected, onSocketError: failed);
    } else if (role == WifiDirectGroupRole.client) {
      await _socket.connectAsClient(host: ownerHost, port: port, onSocketOpen: opened,
          onLineReceived: receive, onSocketDisconnected: disconnected, onSocketError: failed);
    }
  }

  void _sendProof(String line, int generation) {
    unawaited(_socket.sendJsonLine(line).catchError((Object _) async {
      if (generation == _socketGeneration && isBackgroundLab) {
        await _dropBackgroundSocket('peer_proof_send_failed');
      }
    }));
  }

  Future<void> _sendFrame(WifiDirectSyntheticFrame frame) async {
    final line = frame.toJsonLine();
    final proof = _pairing;
    if (isBackgroundLab && (proof == null || !isSocketOpen)) {
      throw StateError('Peer LAB non autorizzato');
    }
    await _socket.sendJsonLine(proof?.seal(line.trimRight()) ?? line);
  }

  void _markSocketOpen(WifiDirectGroupRole role) {
    _isSocketOpen = true;
    _connectedSince = _elapsedMs();
    _lastError = null;
    _record(WifiDirectLabEventKind.socketOpen, data: {
      'role': role.wireName, 'port': _activePort, 'transport': 'tcp_p2p',
      if (isBackgroundLab) 'peer_verified': true,
    });
  }

  void _closeQualityInterval() {
    if (_connectedSince != null) _connectedMs += _elapsedMs() - _connectedSince!;
    _connectedSince = null;
  }

  Future<void> _dropBackgroundSocket(String reason) async {
    final id = _radioSessionId;
    if (id == null || !isBackgroundLab || !_groupSocketArmed) return;
    _groupSocketArmed = false;
    _socketGeneration++;
    _pairing = null;
    _proofDeadline?.cancel();
    if (_trustedNode != null && _lossStarted == null) {
      _lossStarted = _elapsedMs();
      _losses++;
    }
    final cleanup = _closeSocket();
    try {
      if (_isSocketOpen) {
        await _handleSocketClosed(reason);
      } else {
        _record(WifiDirectLabEventKind.disconnect, data: {
          'reason': reason, 'source': 'socket',
        });
      }
    } finally {
      await cleanup;
      if (_isRadioSessionCurrent(id)) _scheduleRecovery(id);
    }
  }

  Future<void> _recoverAfterGroupLoss(String reason) async {
    final id = _radioSessionId;
    if (id == null) return;
    _isGroupFormed = false;
    _isConnecting = false;
    _isDiscovering = false;
    _connectDeadline?.cancel();
    _recovery?.cancel();
    _recovery = null;
    _peers.clear();
    final cleanup = _dropBackgroundSocket(reason);
    _record(WifiDirectLabEventKind.disconnect, layer: WifiDirectEvidenceLayer.system,
        data: {'reason': reason, 'source': 'android_p2p'});
    await cleanup;
    if (_isRadioSessionCurrent(id)) _scheduleRecovery(id);
  }

  void _scheduleRecovery(String id) {
    if (!isBackgroundLab || _recovery != null || _recoveryStep >= _recoveryDelays.length) return;
    // Until the first proof succeeds, only reopen TCP inside an existing group.
    if (!_isGroupFormed && _trustedNode == null) return;
    final seconds = _recoveryDelays[_recoveryStep++];
    _recovery = Timer(Duration(seconds: seconds), () {
      _recovery = null;
      if (_isRadioSessionCurrent(id) && isBackgroundLab) {
        unawaited(_tryRecovery(id));
      }
    });
    _record(WifiDirectLabEventKind.lifecycle, data: {
      'state': 'background_recovery_scheduled', 'attempt': _recoveryStep, 'delay_seconds': seconds,
    });
  }

  Future<void> _tryRecovery(String id) async {
    if (isSocketOpen || _isConnecting) return;
    if (_isGroupFormed) {
      await _openSocketForGroup(sessionId: id, role: _groupRole, ownerHost: _ownerHost,
          port: _activePort);
      return;
    }
    // The original initiator alone may reconnect, and only to the same
    // session-scoped Android alias. The application proof is required again.
    final alias = _trustedPeerAlias;
    if (_isDiscovering && alias != null && _peers[alias]?.status == 'available') {
      if (await requestConnect(peerId: alias, userConsented: true)) return;
    } else if (!_discoveryPending && (!_isDiscovering || alias != null)) {
      await requestDiscovery();
    }
    if (_isRadioSessionCurrent(id) && !_isGroupFormed) {
      _scheduleRecovery(id);
      _notify();
    }
  }

  void _handleIncomingJsonLine(String rawLine) {
    if (_disposed) return;
    WifiDirectSyntheticFrame frame;
    try {
      frame = WifiDirectSyntheticFrame.parseJsonLine(rawLine);
    } catch (e) {
      _invalidFramesRejected++;
      _recordError(
        stage: 'frame_parse',
        code: 'INVALID_SYNTHETIC_FRAME',
        message: 'Frame sintetico non valido.',
        layer: WifiDirectEvidenceLayer.application,
      );
      return;
    }

    if (_pairing != null && frame.senderNodeId != _pairing!.remoteNode) {
      unawaited(_dropBackgroundSocket('peer_node_mismatch'));
      return;
    }
    if (frame.type == WifiDirectFrameType.probe) {
      _handleIncomingProbe(frame);
    } else if (frame.type == WifiDirectFrameType.ack) {
      _handleIncomingAck(frame);
    }
  }

  void _handleIncomingProbe(WifiDirectSyntheticFrame probe) {
    if (probe.senderNodeId == _localNodeId) {
      _invalidFramesRejected++;
      _recordError(
        stage: 'probe_rx',
        code: 'SELF_PROBE_REJECTED',
        message: 'Ricevuto probe con lo stesso localNodeId',
        layer: WifiDirectEvidenceLayer.application,
      );
      return;
    }

    final dedupKey = '${probe.senderNodeId}:${probe.seq}';
    final existingNonce = _deliveredProbesByRemote[dedupKey];
    var isDuplicate = false;

    if (existingNonce != null) {
      if (existingNonce != probe.nonce) {
        _invalidFramesRejected++;
        _recordError(
          stage: 'probe_rx',
          code: 'CONFLICTING_SEQ_NONCE',
          message:
              'Ricevuto probe seq=${probe.seq} da ${probe.senderNodeId} con nonce differente dal precedente',
          layer: WifiDirectEvidenceLayer.application,
        );
        return;
      }
      isDuplicate = true;
      _duplicateProbesSuppressed++;
    } else {
      _deliveredProbesByRemote[dedupKey] = probe.nonce;
      _uniqueProbesDelivered++;
    }

    _record(
      WifiDirectLabEventKind.probeReceived,
      layer: WifiDirectEvidenceLayer.application,
      data: <String, Object?>{
        'remote_node': probe.senderNodeId,
        'seq': probe.seq,
        'nonce': probe.nonce,
        'synthetic_state':
            probe.syntheticState ?? WifiDirectSyntheticFrame.defaultSyntheticState,
        'duplicate': isDuplicate,
        'unique_delivered_total': _uniqueProbesDelivered,
        'duplicates_suppressed_total': _duplicateProbesSuppressed,
      },
    );

    // Always reply with the matching ACK (even for a duplicate retransmission
    // after link recovery, so the sender can complete its ACK state without
    // duplicating delivery on the receiver).
    final ackFrame = WifiDirectSyntheticFrame.ack(
      senderNodeId: _localNodeId,
      ackForSenderNodeId: probe.senderNodeId,
      seq: probe.seq,
      nonce: probe.nonce,
      rxElapsedMs: _elapsedMs(),
    );
    unawaited(
      _sendFrame(ackFrame).then((_) {
        _acksSentCount++;
        _notify();
      }).catchError((Object e) {
        _recordError(
          stage: 'send_ack',
          code: 'ACK_SEND_FAILED',
          message: 'Errore invio ACK per seq=${probe.seq}: $e',
          layer: WifiDirectEvidenceLayer.transport,
        );
      }),
    );
  }

  void _handleIncomingAck(WifiDirectSyntheticFrame ack) {
    if (ack.ackForSenderNodeId != _localNodeId) {
      _falseAcksRejected++;
      _recordError(
        stage: 'ack_rx',
        code: 'ACK_TARGET_MISMATCH',
        message:
            'ACK destinato a ${ack.ackForSenderNodeId} anziché $_localNodeId (seq=${ack.seq})',
        layer: WifiDirectEvidenceLayer.application,
      );
      return;
    }

    final sent = _sentProbes[ack.seq];
    if (sent == null) {
      _falseAcksRejected++;
      _recordError(
        stage: 'ack_rx',
        code: 'ACK_UNKNOWN_SEQ',
        message: 'ACK ricevuto per seq=${ack.seq} mai inviato',
        layer: WifiDirectEvidenceLayer.application,
      );
      return;
    }

    if (sent.nonce != ack.nonce) {
      _falseAcksRejected++;
      _recordError(
        stage: 'ack_rx',
        code: 'ACK_NONCE_MISMATCH',
        message: 'ACK ricevuto per seq=${ack.seq} con nonce non corrispondente',
        layer: WifiDirectEvidenceLayer.application,
      );
      return;
    }

    if (sent.ackConfirmed) {
      _duplicateAcksIgnored++;
      _notify();
      return;
    }

    final nowElapsed = _elapsedMs();
    final rtt = max(0, nowElapsed - sent.lastSentElapsedMs);
    sent.ackConfirmed = true;
    sent.ackReceivedElapsedMs = nowElapsed;
    _latestAck = nowElapsed;
    sent.localRttMs = rtt;

    _record(
      WifiDirectLabEventKind.ackReceived,
      layer: WifiDirectEvidenceLayer.application,
      data: <String, Object?>{
        'remote_node': ack.senderNodeId,
        'seq': ack.seq,
        'nonce': ack.nonce,
        'local_rtt_ms': rtt,
        'confirmed_total': acksConfirmedCount,
        'unconfirmed_total': unconfirmedProbesCount,
      },
    );
  }

  Future<void> _handleSocketClosed(String reason) async {
    if (_disposed) return;
    _batchEpoch++;
    _isSendingBatch = false;
    final wasOpen = _isSocketOpen;
    final stateBeforeClose = _radioLogState;
    _isSocketOpen = false;
    _closeQualityInterval();
    if (!isBackgroundLab) _groupSocketArmed = false;
    if (wasOpen) {
      _record(
        WifiDirectLabEventKind.disconnect,
        layer: WifiDirectEvidenceLayer.transport,
        data: <String, Object?>{
          'reason': reason,
          'source': 'socket',
          ...stateBeforeClose,
          'probes_sent': probesSentCount,
          'acks_confirmed': acksConfirmedCount,
          'unconfirmed_probes': unconfirmedProbesCount,
        },
      );
    } else {
      _notify();
    }
  }

  Future<void> _closeTransportOnDisconnect(String reason) async {
    if (_disposed) return;
    _batchEpoch++;
    _isSendingBatch = false;
    final sessionId = _invalidateRadioSession();
    final stateBeforeClose = _radioLogState;
    _stopsInProgress++;
    _isDiscovering = false;
    _peers.clear();
    _selectedPeerId = null;
    _isConnecting = false;
    _isGroupFormed = false;
    _isSocketOpen = false;
    _groupRole = WifiDirectGroupRole.none;
    final cleanup = _releaseRadio(sessionId, reason);
    try {
      _record(
        WifiDirectLabEventKind.disconnect,
        layer: WifiDirectEvidenceLayer.system,
        data: <String, Object?>{
          'reason': reason,
          'source': 'android_p2p',
          ...stateBeforeClose,
          'probes_sent': probesSentCount,
          'acks_confirmed': acksConfirmedCount,
          'unconfirmed_probes': unconfirmedProbesCount,
        },
      );
      await cleanup;
    } finally {
      _stopsInProgress--;
      _notify();
    }
  }

  Future<void> _releaseRadio(String? sessionId, String reason) async {
    final cleanup = _radioCleanup ??= Future.wait([
      _closeSocket(),
      _platform.stopAll(sessionId: sessionId, reason: reason).catchError((Object _) {}),
    ]).then<void>((_) {});
    try {
      await cleanup;
    } finally {
      if (identical(_radioCleanup, cleanup)) _radioCleanup = null;
    }
  }

  Future<void> _closeSocket() async {
    final closing = _socketCleanup ??= _socket.close();
    try {
      await closing;
    } finally {
      if (identical(_socketCleanup, closing)) _socketCleanup = null;
    }
  }

  (String, String)? _checkPreflightCodeAndMessage() {
    if (!_environment.wifiDirectFeatureSupported ||
        !_environment.wifiP2pServiceAvailable) {
      return (
        'WIFI_DIRECT_UNSUPPORTED',
        'Wi-Fi Direct non supportato dal dispositivo (PackageManager).'
      );
    }
    if (!_environment.manifestPermissionsOk) {
      return (
        'MANIFEST_PERMISSIONS_MISSING',
        'Permessi AndroidManifest Wi-Fi Direct mancanti.'
      );
    }
    if (_environment.bluetoothEnabled) {
      return (
        'BLUETOOTH_MUST_BE_OFF',
        'Bluetooth attivo: spegnere il Bluetooth prima di usare il laboratorio Wi-Fi Direct.'
      );
    }
    if (!_environment.wifiEnabled || !_environment.p2pStateEnabled) {
      return (
        'WIFI_DISABLED',
        'Wi-Fi spento o P2P disabilitato: attivare il Wi-Fi (senza connessione Internet).'
      );
    }
    if (!_environment.requiredRuntimePermissionGranted) {
      return (
        'PERMISSION_DENIED',
        'Permesso runtime ${_environment.requiredPermissionName} non concesso.'
      );
    }
    if (!_environment.locationServiceEnabled) {
      return (
        'LOCATION_SERVICES_DISABLED_P2P',
        'Attiva Posizione nelle impostazioni Android per la scoperta Wi-Fi Direct.'
      );
    }
    if (_environment.foregroundServiceRunning) {
      return (
        'FOREGROUND_SERVICE_ACTIVE',
        'Servizio foreground attivo: il laboratorio Wi-Fi Direct richiede zero servizi in background.'
      );
    }
    return null;
  }

  void _recordError({
    required String stage,
    required String code,
    required String message,
    WifiDirectEvidenceLayer layer = WifiDirectEvidenceLayer.system,
  }) {
    _lastError = '[$code] $message';
    _record(
      WifiDirectLabEventKind.error,
      layer: layer,
      data: <String, Object?>{
        'stage': stage,
        'code': code,
        'message': message,
      },
    );
  }

  void _record(
    WifiDirectLabEventKind kind, {
    WifiDirectEvidenceLayer? layer,
    Map<String, Object?> data = const {},
  }) {
    if (_disposed) return;
    final entry = WifiDirectLabLogEntry(
      index: _logs.length,
      sessionId: _sessionId,
      localNodeId: _localNodeId,
      kind: kind,
      layer: layer ?? kind.defaultLayer,
      elapsedMs: _elapsedMs(),
      timestampUtcIso: _nowUtc().toIso8601String(),
      data: data,
    );
    _logs.add(entry);
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _batchEpoch++;
    _platformEventSub?.cancel();
    _platformEventSub = null;
    final sessionId = _invalidateRadioSession();
    unawaited(_closeSocket());
    if (sessionId != null) {
      unawaited(_platform.stopAll(sessionId: sessionId, reason: 'controller_disposed'));
    }
    super.dispose();
  }
}
