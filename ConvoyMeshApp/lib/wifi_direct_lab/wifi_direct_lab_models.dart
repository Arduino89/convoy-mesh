import 'dart:convert';
import 'dart:math';

/// Distinguishable local test events required by the Wi-Fi Direct Offline Lab
/// contract (`experiments/wifi_direct_offline_lab/README.md`).
enum WifiDirectLabEventKind {
  discoverRequested('discover_requested', WifiDirectEvidenceLayer.system),
  peerSeen('peer_seen', WifiDirectEvidenceLayer.system),
  connectRequested('connect_requested', WifiDirectEvidenceLayer.system),
  groupFormed('group_formed', WifiDirectEvidenceLayer.system),
  socketOpen('socket_open', WifiDirectEvidenceLayer.transport),
  probeSent('probe_sent', WifiDirectEvidenceLayer.application),
  probeReceived('probe_received', WifiDirectEvidenceLayer.application),
  ackReceived('ack_received', WifiDirectEvidenceLayer.application),
  disconnect('disconnect', WifiDirectEvidenceLayer.transport),
  error('error', WifiDirectEvidenceLayer.system);

  const WifiDirectLabEventKind(this.wireName, this.defaultLayer);

  final String wireName;
  final WifiDirectEvidenceLayer defaultLayer;
}

/// System/radio events and application messages are distinct levels of proof.
/// `discover_requested`, `peer_seen`, `connect_requested`, and `group_formed`
/// never count as application delivery.
enum WifiDirectEvidenceLayer {
  system('system'),
  transport('transport'),
  application('application');

  const WifiDirectEvidenceLayer(this.wireName);

  final String wireName;
}

/// P2P group role assigned by Android Wi-Fi Direct negotiation.
enum WifiDirectGroupRole {
  none('none'),
  groupOwner('group_owner'),
  client('client');

  const WifiDirectGroupRole(this.wireName);

  final String wireName;

  static WifiDirectGroupRole fromWire(String? raw) {
    switch (raw) {
      case 'group_owner':
        return WifiDirectGroupRole.groupOwner;
      case 'client':
        return WifiDirectGroupRole.client;
      default:
        return WifiDirectGroupRole.none;
    }
  }
}

/// Immutable snapshot of Android platform readiness for the Wi-Fi Direct Lab.
class WifiDirectEnvironmentStatus {
  const WifiDirectEnvironmentStatus({
    this.sdkInt = 33,
    this.wifiDirectFeatureSupported = false,
    this.wifiP2pServiceAvailable = false,
    this.wifiEnabled = false,
    this.p2pStateEnabled = false,
    this.bluetoothEnabled = false,
    this.internetValidated = false,
    this.nearbyWifiPermissionGranted = false,
    this.fineLocationPermissionGranted = false,
    this.requiredRuntimePermissionGranted = false,
    this.requiredPermissionName = 'NEARBY_WIFI_DEVICES',
    this.locationServiceEnabled = false,
    this.manifestPermissionsOk = false,
    this.foregroundServiceRunning = false,
  });

  factory WifiDirectEnvironmentStatus.fromMap(Map<Object?, Object?> map) {
    final sdk = (map['sdkInt'] as num?)?.toInt() ?? 33;
    final nearbyGranted = map['nearbyWifiPermissionGranted'] == true;
    final fineGranted = map['fineLocationPermissionGranted'] == true;
    final requiredGranted = map.containsKey('requiredRuntimePermissionGranted')
        ? map['requiredRuntimePermissionGranted'] == true
        : (sdk >= 33 ? nearbyGranted : fineGranted);
    final requiredPermName = (map['requiredPermissionName'] as String?) ??
        (sdk >= 33 ? 'NEARBY_WIFI_DEVICES' : 'ACCESS_FINE_LOCATION');
    final wifiOn = map['wifiEnabled'] == true;
    return WifiDirectEnvironmentStatus(
      sdkInt: sdk,
      wifiDirectFeatureSupported: map['wifiDirectFeatureSupported'] == true,
      wifiP2pServiceAvailable: map['wifiP2pServiceAvailable'] == true,
      wifiEnabled: wifiOn,
      p2pStateEnabled:
          map.containsKey('p2pStateEnabled') ? map['p2pStateEnabled'] == true : wifiOn,
      bluetoothEnabled: map['bluetoothEnabled'] == true,
      internetValidated: map['internetValidated'] == true,
      nearbyWifiPermissionGranted: nearbyGranted,
      fineLocationPermissionGranted: fineGranted,
      requiredRuntimePermissionGranted: requiredGranted,
      requiredPermissionName: requiredPermName,
      locationServiceEnabled: map['locationServiceEnabled'] == true,
      manifestPermissionsOk: map['manifestPermissionsOk'] == true,
      foregroundServiceRunning: map['foregroundServiceRunning'] == true,
    );
  }

  final int sdkInt;
  final bool wifiDirectFeatureSupported;
  final bool wifiP2pServiceAvailable;
  final bool wifiEnabled;
  final bool p2pStateEnabled;
  final bool bluetoothEnabled;
  final bool internetValidated;
  final bool nearbyWifiPermissionGranted;
  final bool fineLocationPermissionGranted;
  final bool requiredRuntimePermissionGranted;
  final String requiredPermissionName;
  final bool locationServiceEnabled;
  final bool manifestPermissionsOk;
  final bool foregroundServiceRunning;

  bool get isBluetoothOffClean => !bluetoothEnabled;
  bool get isOfflineClean => !internetValidated;
  bool get requiresLegacyLocationToggle => sdkInt < 33;

  bool get canOperateP2p =>
      wifiDirectFeatureSupported &&
      wifiP2pServiceAvailable &&
      manifestPermissionsOk &&
      wifiEnabled &&
      p2pStateEnabled &&
      !bluetoothEnabled &&
      requiredRuntimePermissionGranted &&
      (!requiresLegacyLocationToggle || locationServiceEnabled) &&
      !foregroundServiceRunning;

  List<String> get readinessBlockers {
    final reasons = <String>[];
    if (!wifiDirectFeatureSupported || !wifiP2pServiceAvailable) {
      reasons.add('Wi-Fi Direct non supportato dal dispositivo (PackageManager).');
    }
    if (!manifestPermissionsOk) {
      reasons.add('Permessi AndroidManifest Wi-Fi Direct incompleti.');
    }
    if (bluetoothEnabled) {
      reasons.add('Bluetooth attivo: spegnere il Bluetooth per una prova pulita.');
    }
    if (!wifiEnabled || !p2pStateEnabled) {
      reasons.add('Wi-Fi spento o P2P non attivo: attivare il Wi-Fi (senza router).');
    }
    if (!requiredRuntimePermissionGranted) {
      reasons.add('Permesso runtime $requiredPermissionName non concesso.');
    }
    if (requiresLegacyLocationToggle && !locationServiceEnabled) {
      reasons.add(
        'Su Android <= 12 il sistema operativo richiede il toggle Posizione attivo per WifiP2pManager.',
      );
    }
    if (foregroundServiceRunning) {
      reasons.add('Servizio foreground Convoy in esecuzione: chiudere ogni uscita attiva.');
    }
    return reasons;
  }

  WifiDirectEnvironmentStatus copyWith({
    int? sdkInt,
    bool? wifiDirectFeatureSupported,
    bool? wifiP2pServiceAvailable,
    bool? wifiEnabled,
    bool? p2pStateEnabled,
    bool? bluetoothEnabled,
    bool? internetValidated,
    bool? nearbyWifiPermissionGranted,
    bool? fineLocationPermissionGranted,
    bool? requiredRuntimePermissionGranted,
    String? requiredPermissionName,
    bool? locationServiceEnabled,
    bool? manifestPermissionsOk,
    bool? foregroundServiceRunning,
  }) {
    return WifiDirectEnvironmentStatus(
      sdkInt: sdkInt ?? this.sdkInt,
      wifiDirectFeatureSupported:
          wifiDirectFeatureSupported ?? this.wifiDirectFeatureSupported,
      wifiP2pServiceAvailable:
          wifiP2pServiceAvailable ?? this.wifiP2pServiceAvailable,
      wifiEnabled: wifiEnabled ?? this.wifiEnabled,
      p2pStateEnabled: p2pStateEnabled ?? this.p2pStateEnabled,
      bluetoothEnabled: bluetoothEnabled ?? this.bluetoothEnabled,
      internetValidated: internetValidated ?? this.internetValidated,
      nearbyWifiPermissionGranted:
          nearbyWifiPermissionGranted ?? this.nearbyWifiPermissionGranted,
      fineLocationPermissionGranted:
          fineLocationPermissionGranted ?? this.fineLocationPermissionGranted,
      requiredRuntimePermissionGranted: requiredRuntimePermissionGranted ??
          this.requiredRuntimePermissionGranted,
      requiredPermissionName:
          requiredPermissionName ?? this.requiredPermissionName,
      locationServiceEnabled:
          locationServiceEnabled ?? this.locationServiceEnabled,
      manifestPermissionsOk:
          manifestPermissionsOk ?? this.manifestPermissionsOk,
      foregroundServiceRunning:
          foregroundServiceRunning ?? this.foregroundServiceRunning,
    );
  }
}

/// Discovered peer represented strictly by an ephemeral session-scoped
/// synthetic slot ID (`peer-01`, `peer-02`, ...).
class WifiDirectSyntheticPeer {
  const WifiDirectSyntheticPeer({
    required this.peerId,
    required this.status,
    required this.firstSeenElapsedMs,
    required this.lastSeenElapsedMs,
  });

  final String peerId;
  final String status;
  final int firstSeenElapsedMs;
  final int lastSeenElapsedMs;

  static final RegExp validSyntheticPeerId = RegExp(r'^peer-[0-9]{2,4}$');
}

/// Ephemeral synthetic frame exchanged over the local Wi-Fi Direct TCP socket.
///
/// The first gate uses unauthenticated TCP and therefore MUST NOT carry
/// coordinates, device names, nicknames, MAC addresses, or persistent IDs.
enum WifiDirectFrameType {
  probe('probe'),
  ack('ack');

  const WifiDirectFrameType(this.wireName);

  final String wireName;
}

class WifiDirectSyntheticFrame {
  const WifiDirectSyntheticFrame._({
    required this.version,
    required this.type,
    required this.senderNodeId,
    required this.seq,
    required this.nonce,
    required this.elapsedMs,
    this.syntheticState,
    this.ackForSenderNodeId,
  });

  factory WifiDirectSyntheticFrame.probe({
    required String senderNodeId,
    required int seq,
    required String nonce,
    required int sentElapsedMs,
    String syntheticState = defaultSyntheticState,
  }) {
    _validateCommon(
      senderNodeId: senderNodeId,
      seq: seq,
      nonce: nonce,
      elapsedMs: sentElapsedMs,
    );
    if (!_syntheticStatePattern.hasMatch(syntheticState)) {
      throw const FormatException('Stato sintetico non valido');
    }
    return WifiDirectSyntheticFrame._(
      version: protocolVersion,
      type: WifiDirectFrameType.probe,
      senderNodeId: senderNodeId,
      seq: seq,
      nonce: nonce,
      elapsedMs: sentElapsedMs,
      syntheticState: syntheticState,
    );
  }

  factory WifiDirectSyntheticFrame.ack({
    required String senderNodeId,
    required String ackForSenderNodeId,
    required int seq,
    required String nonce,
    required int rxElapsedMs,
  }) {
    _validateCommon(
      senderNodeId: senderNodeId,
      seq: seq,
      nonce: nonce,
      elapsedMs: rxElapsedMs,
    );
    if (!validSyntheticNodeId(ackForSenderNodeId)) {
      throw const FormatException('ack_for_sender sintetico non valido');
    }
    return WifiDirectSyntheticFrame._(
      version: protocolVersion,
      type: WifiDirectFrameType.ack,
      senderNodeId: senderNodeId,
      ackForSenderNodeId: ackForSenderNodeId,
      seq: seq,
      nonce: nonce,
      elapsedMs: rxElapsedMs,
    );
  }

  static const int protocolVersion = 1;
  static const int maxWireBytes = 512;
  static const String defaultSyntheticState = 'SYNTH_PROBE_OK';

  static final RegExp _nodeIdPattern = RegExp(r'^node-[a-f0-9]{8}$');
  static final RegExp _noncePattern = RegExp(r'^[a-f0-9]{32}$');
  static final RegExp _syntheticStatePattern =
      RegExp(r'^SYNTH_[A-Z0-9_]{2,24}$');

  static const Set<String> _probeAllowedKeys = {
    'v',
    'type',
    'sender',
    'seq',
    'nonce',
    'synthetic_state',
    'elapsed_ms',
  };

  static const Set<String> _ackAllowedKeys = {
    'v',
    'type',
    'sender',
    'ack_for_sender',
    'seq',
    'nonce',
    'elapsed_ms',
  };

  final int version;
  final WifiDirectFrameType type;
  final String senderNodeId;
  final String? ackForSenderNodeId;
  final int seq;
  final String nonce;
  final String? syntheticState;
  final int elapsedMs;

  static bool validSyntheticNodeId(String id) => _nodeIdPattern.hasMatch(id);
  static bool validNonce(String nonce) => _noncePattern.hasMatch(nonce);

  static String generateSyntheticNodeId([Random? random]) {
    final rng = random ?? Random.secure();
    final hex = List.generate(
      4,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'node-$hex';
  }

  static String generateNonce([Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(
      16,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static void _validateCommon({
    required String senderNodeId,
    required int seq,
    required String nonce,
    required int elapsedMs,
  }) {
    if (!validSyntheticNodeId(senderNodeId)) {
      throw const FormatException('ID nodo sintetico non valido');
    }
    if (seq < 1 || seq > 10000) {
      throw const FormatException('Sequenza probe fuori intervallo (1..10000)');
    }
    if (!validNonce(nonce)) {
      throw const FormatException('Nonce sintetico non valido');
    }
    if (elapsedMs < 0) {
      throw const FormatException('Tempo locale elapsed_ms negativo');
    }
  }

  Map<String, Object> toMap() {
    switch (type) {
      case WifiDirectFrameType.probe:
        return <String, Object>{
          'v': version,
          'type': type.wireName,
          'sender': senderNodeId,
          'seq': seq,
          'nonce': nonce,
          'synthetic_state': syntheticState ?? defaultSyntheticState,
          'elapsed_ms': elapsedMs,
        };
      case WifiDirectFrameType.ack:
        return <String, Object>{
          'v': version,
          'type': type.wireName,
          'sender': senderNodeId,
          'ack_for_sender': ackForSenderNodeId!,
          'seq': seq,
          'nonce': nonce,
          'elapsed_ms': elapsedMs,
        };
    }
  }

  String toJsonLine() => '${jsonEncode(toMap())}\n';

  static WifiDirectSyntheticFrame parseJsonLine(String rawLine) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty || utf8.encode(trimmed).length > maxWireBytes) {
      throw const FormatException('Frame sintetico vuoto o oltre il limite di 512 byte');
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) {
      throw const FormatException('Frame sintetico non è un oggetto JSON');
    }
    final map = Map<String, Object?>.from(decoded);
    final v = map['v'];
    final typeRaw = map['type'];
    final sender = map['sender'];
    final seq = map['seq'];
    final nonce = map['nonce'];
    final elapsed = map['elapsed_ms'];

    if (v != protocolVersion ||
        typeRaw is! String ||
        sender is! String ||
        seq is! int ||
        nonce is! String ||
        elapsed is! int) {
      throw const FormatException('Campi obbligatori del frame sintetico mancanti o errati');
    }

    if (typeRaw == WifiDirectFrameType.probe.wireName) {
      if (!map.keys.toSet().containsAll(_probeAllowedKeys) ||
          map.keys.length != _probeAllowedKeys.length) {
        throw const FormatException('Chiavi non autorizzate nel frame probe');
      }
      final state = map['synthetic_state'];
      if (state is! String) {
        throw const FormatException('synthetic_state mancante');
      }
      return WifiDirectSyntheticFrame.probe(
        senderNodeId: sender,
        seq: seq,
        nonce: nonce,
        sentElapsedMs: elapsed,
        syntheticState: state,
      );
    } else if (typeRaw == WifiDirectFrameType.ack.wireName) {
      if (!map.keys.toSet().containsAll(_ackAllowedKeys) ||
          map.keys.length != _ackAllowedKeys.length) {
        throw const FormatException('Chiavi non autorizzate nel frame ack');
      }
      final ackFor = map['ack_for_sender'];
      if (ackFor is! String) {
        throw const FormatException('ack_for_sender mancante');
      }
      return WifiDirectSyntheticFrame.ack(
        senderNodeId: sender,
        ackForSenderNodeId: ackFor,
        seq: seq,
        nonce: nonce,
        rxElapsedMs: elapsed,
      );
    } else {
      throw const FormatException('Tipo di frame sintetico sconosciuto');
    }
  }
}

/// Tracked status of an outbound synthetic probe awaiting ACK confirmation.
class WifiDirectSentProbeRecord {
  WifiDirectSentProbeRecord({
    required this.seq,
    required this.nonce,
    required this.syntheticState,
    required this.firstSentElapsedMs,
    required this.lastSentElapsedMs,
    this.attempts = 1,
    this.ackConfirmed = false,
    this.ackReceivedElapsedMs,
    this.localRttMs,
  });

  final int seq;
  final String nonce;
  final String syntheticState;
  final int firstSentElapsedMs;
  int lastSentElapsedMs;
  int attempts;
  bool ackConfirmed;
  int? ackReceivedElapsedMs;
  int? localRttMs;
}

/// Fail-closed privacy guard ensuring no MAC, SSID, IP address, device name,
/// nickname, or GPS coordinate can enter the Wi-Fi Direct lab event log.
class WifiDirectLabPrivacyGuard {
  static final RegExp _macPattern =
      RegExp(r'\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b');
  static final RegExp _ipv4Pattern =
      RegExp(r'\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b');
  static final RegExp _directSsidPattern =
      RegExp(r'DIRECT-[A-Za-z0-9_-]+', caseSensitive: false);

  static const Set<String> forbiddenKeys = {
    'mac',
    'mac_address',
    'device_address',
    'device_name',
    'ssid',
    'bssid',
    'passphrase',
    'network_name',
    'group_owner_host',
    'ip',
    'ip_address',
    'host_address',
    'lat',
    'lon',
    'latitude',
    'longitude',
    'coordinates',
    'nickname',
  };

  static Map<String, Object?> sanitizeData(Map<String, Object?> input) {
    final out = <String, Object?>{};
    for (final entry in input.entries) {
      final keyLower = entry.key.toLowerCase();
      if (forbiddenKeys.contains(keyLower)) {
        throw FormatException('Campo non consentito nel log Wi-Fi Direct LAB: ${entry.key}');
      }
      out[entry.key] = _sanitizeValue(entry.value);
    }
    return Map.unmodifiable(out);
  }

  static Object? _sanitizeValue(Object? value) {
    if (value == null || value is bool || value is int) return value;
    if (value is double) {
      if (!value.isFinite) return null;
      return value;
    }
    if (value is String) {
      var cleaned = value;
      cleaned = cleaned.replaceAll(_macPattern, '[REDACTED_MAC]');
      cleaned = cleaned.replaceAll(_ipv4Pattern, '[REDACTED_IP]');
      cleaned = cleaned.replaceAll(_directSsidPattern, '[REDACTED_SSID]');
      return cleaned.length > 240 ? cleaned.substring(0, 240) : cleaned;
    }
    if (value is List) {
      return value.map(_sanitizeValue).toList(growable: false);
    }
    if (value is Map) {
      final nested = <String, Object?>{};
      for (final e in value.entries) {
        final k = e.key.toString();
        if (forbiddenKeys.contains(k.toLowerCase())) {
          throw FormatException('Campo annidato non consentito: $k');
        }
        nested[k] = _sanitizeValue(e.value);
      }
      return Map.unmodifiable(nested);
    }
    return _sanitizeValue(value.toString());
  }

  static bool containsForbiddenIdentifiers(String text) {
    return _macPattern.hasMatch(text) ||
        _ipv4Pattern.hasMatch(text) ||
        _directSsidPattern.hasMatch(text);
  }
}

/// Single immutable entry in the Wi-Fi Direct Offline Lab event log.
class WifiDirectLabLogEntry {
  WifiDirectLabLogEntry({
    required this.index,
    required this.sessionId,
    required this.localNodeId,
    required this.kind,
    required this.layer,
    required this.elapsedMs,
    required this.timestampUtcIso,
    Map<String, Object?> data = const {},
  }) : data = WifiDirectLabPrivacyGuard.sanitizeData(data);

  final int index;
  final String sessionId;
  final String localNodeId;
  final WifiDirectLabEventKind kind;
  final WifiDirectEvidenceLayer layer;
  final int elapsedMs;
  final String timestampUtcIso;
  final Map<String, Object?> data;

  Map<String, Object?> toJsonMap() => <String, Object?>{
        'schema_version': 1,
        'event_index': index,
        'session_id': sessionId,
        'local_node': localNodeId,
        'elapsed_ms': elapsedMs,
        'ts_utc': timestampUtcIso,
        'evidence_layer': layer.wireName,
        'event': kind.wireName,
        'data': data,
      };

  String toJsonLine() => jsonEncode(toJsonMap());
}
