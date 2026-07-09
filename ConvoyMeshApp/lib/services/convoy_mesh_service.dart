// lib/services/convoy_mesh_service.dart
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/convoy_ble_codec.dart';
import '../location/fused_location.dart';
import 'location_fusion_service.dart';

class ConvoyMeshService extends ChangeNotifier {
  ConvoyMeshService._();
  static final ConvoyMeshService instance = ConvoyMeshService._();

  Future<void>? _startFuture;

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  // Identity persistente.
  int _myId = 0;
  int get myId => _myId;

  String _myName = 'User';
  String get myName => _myName;

  // Sequence advertising, volatile.
  int _seq = 0;

  // BLE status.
  BleStatus _bleStatus = BleStatus.unknown;
  BleStatus get bleStatus => _bleStatus;

  // Peers.
  final Map<int, PeerState> _peers = {};
  Map<int, PeerState> get peers => Map.unmodifiable(_peers);

  StreamSubscription<BleStatus>? _bleStatusSub;
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<FusedLocation>? _locSub;

  // Android BLE scan può rimanere "apparentemente ON" ma non consegnare più risultati,
  // soprattutto se la Posizione Android viene attivata/disattivata a runtime.
  // Teniamo un watchdog leggero per riavviare solo lo scanner, senza toccare codec/payload.
  Timer? _scanWatchdogTimer;
  bool _scanRestarting = false;
  DateTime? _lastScanStartedAt;
  DateTime? _lastScanEventAt;
  DateTime? _lastScanRestartAt;
  String _lastScanRestartReason = '-';
  int _scanRestartCount = 0;
  int _scanEventCount = 0;
  bool? _lastLocationServiceEnabled;

  // Advertising state.
  bool _advertising = false;
  bool get isAdvertising => _advertising;

  bool get isScanning => _scanSub != null;

  DateTime _lastAdvUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastNameAdv = DateTime.fromMillisecondsSinceEpoch(0);

  // Quando premi "Invia nome", forziamo alcuni pacchetti NAME nei cicli successivi.
  int _forcedNamePackets = 0;

  // Timer pulizia peers.
  Timer? _gcTimer;

  // Serializza start/stop adv per evitare crash plugin (Reply already submitted).
  Future<void> _advOp = Future.value();

  // Online/offline e rimozione: non rimuoviamo subito, ma evitiamo liste sporche.
  static const Duration peerOnlineTtl = Duration(seconds: 15);
  static const Duration peerTtl = Duration(seconds: 60);
  static const Duration gcEvery = Duration(seconds: 5);

  static const Duration advMinInterval = Duration(seconds: 5);
  static const Duration nameAdvInterval = Duration(seconds: 30);

  // Se un telefono riavvia l'app, la sequence riparte da zero.
  // Dopo un gap ragionevole accettiamo seq basse anche se sembrano "vecchie".
  static const Duration seqResetGrace = Duration(seconds: 20);
  static const Duration changedNameGrace = Duration(seconds: 3);

  // Trail retention default 90 min.
  static const Duration trailRetention = Duration(minutes: 90);

  // -------- Debug/stato diagnostico esposto alla UI --------
  String? _lastAdvError;
  String? get lastAdvError => _lastAdvError;

  int _lastPayloadBytes = 0;
  int get lastPayloadBytes => _lastPayloadBytes;

  String _lastTxKind = '-';
  String get lastTxKind => _lastTxKind;

  int _lastTxSeq = 0;
  int get lastTxSeq => _lastTxSeq;

  DateTime? _lastTxAt;
  DateTime? get lastTxAt => _lastTxAt;

  DateTime? _lastRxAt;
  DateTime? get lastRxAt => _lastRxAt;

  String _lastRxSummary = '-';
  String get lastRxSummary => _lastRxSummary;

  int _rxValid = 0;
  int get rxValid => _rxValid;

  // Compat: il vecchio contatore parse ora equivale a noMagic + badPacket.
  int get rxParseFailed => _rxNoMagic + _rxBadPacket;

  int _rxNoManufacturerData = 0;
  int get rxNoManufacturerData => _rxNoManufacturerData;

  int _rxIgnoredSelf = 0;
  int get rxIgnoredSelf => _rxIgnoredSelf;

  int _rxStale = 0;
  int get rxStale => _rxStale;

  int _rxFixPackets = 0;
  int get rxFixPackets => _rxFixPackets;

  int _rxNamePackets = 0;
  int get rxNamePackets => _rxNamePackets;

  int _advOkCount = 0;
  int get advOkCount => _advOkCount;

  int _advErrorCount = 0;
  int get advErrorCount => _advErrorCount;

  int _rxNoMagic = 0;
  int get rxNoMagic => _rxNoMagic;

  int _rxBadPacket = 0;
  int get rxBadPacket => _rxBadPacket;

  int _rxMagicFound = 0;
  int get rxMagicFound => _rxMagicFound;

  int _lastMdBytes = 0;
  int get lastMdBytes => _lastMdBytes;

  String _lastMdHex = '-';
  String get lastMdHex => _lastMdHex;

  String _lastParseReason = '-';
  String get lastParseReason => _lastParseReason;

  int? _lastMagicOffset;
  int? get lastMagicOffset => _lastMagicOffset;

  int get rxRejected => _rxNoMagic + _rxBadPacket;

  int get onlinePeerCount => _peers.values.where(isPeerOnline).length;

  int get offlinePeerCount => _peers.values.where((p) => !isPeerOnline(p)).length;

  int get scanRestartCount => _scanRestartCount;
  int get scanEventCount => _scanEventCount;
  DateTime? get lastScanStartedAt => _lastScanStartedAt;
  DateTime? get lastScanEventAt => _lastScanEventAt;
  DateTime? get lastScanRestartAt => _lastScanRestartAt;
  String get lastScanRestartReason => _lastScanRestartReason;

  bool get localLocationServiceEnabled {
    final f = LocationFusionService.instance.last;
    if (f == null) return _lastLocationServiceEnabled ?? false;
    return f.serviceEnabled;
  }

  bool get scanMayBeBlockedByLocation =>
      _bleStatus == BleStatus.ready && !localLocationServiceEnabled;

  Future<void> start() {
    // Evita doppie inizializzazioni se la UI richiama start più volte
    // (hot reload, ritorno alla pagina, rebuild rapidi).
    _startFuture ??= _startInternal();
    return _startFuture!;
  }

  Future<void> _startInternal() async {
    await _loadIdentity();

    // 1) Start location fusion.
    await LocationFusionService.instance.start();

    // 2) BLE status live.
    await _bleStatusSub?.cancel();
    _bleStatusSub = _ble.statusStream.listen((s) {
      _bleStatus = s;
      notifyListeners();

      if (_bleStatus == BleStatus.ready) {
        _ensureScanRunning();
        _startScanWatchdog();
        _advertiseName(force: false); // ping identificativo leggero all'avvio BLE.
      } else {
        _scanWatchdogTimer?.cancel();
        _scanWatchdogTimer = null;
        _stopScan();
        _advertising = false;
      }
    });

    // 3) Aggiorna advertising con la posizione fusa.
    await _locSub?.cancel();
    _locSub = LocationFusionService.instance.stream.listen((f) async {
      final now = DateTime.now();

      final wasLocationEnabled = _lastLocationServiceEnabled;
      _lastLocationServiceEnabled = f.serviceEnabled;
      if (wasLocationEnabled != null && wasLocationEnabled != f.serviceEnabled) {
        // Se Android Location viene riattivata mentre lo scan era già partito,
        // alcuni telefoni non riprendono davvero a consegnare risultati BLE.
        // Riavviamo solo lo scan: il cuore BLE e i pacchetti restano invariati.
        if (f.serviceEnabled && _bleStatus == BleStatus.ready) {
          unawaited(restartScanForDebug(reason: 'location_on'));
          _forcedNamePackets = max(_forcedNamePackets, 2);
        }
        notifyListeners();
      }

      if (now.difference(_lastAdvUpdate) < advMinInterval) return;
      _lastAdvUpdate = now;

      final hasFix = f.lat != null && f.lon != null;
      final shouldSendName =
          _forcedNamePackets > 0 || now.difference(_lastNameAdv) >= nameAdvInterval;

      // Priorità: posizione se disponibile. Ogni tanto alterniamo un pacchetto NAME.
      if (shouldSendName && (!hasFix || _advOkCount > 0)) {
        if (_forcedNamePackets > 0) _forcedNamePackets--;
        await _advertiseName(force: true);
      } else if (hasFix) {
        await _advertisePosition(f);
      } else {
        // Se non c'è ancora GPS, almeno trasmetti identità/nome.
        await _advertiseName(force: false);
      }
    });

    // 4) Scan sempre attivo quando BLE è ready.
    _ensureScanRunning();
    _startScanWatchdog();

    // 5) GC peers.
    _gcTimer?.cancel();
    _gcTimer = Timer.periodic(gcEvery, (_) => _gcPeers());
  }

  Future<void> _loadIdentity() async {
    final prefs = await SharedPreferences.getInstance();

    _myId = prefs.getInt('my_id') ?? 0;
    if (_myId == 0) {
      _myId = _newRandomId();
      await prefs.setInt('my_id', _myId);
    }

    _myName = (prefs.getString('my_name') ?? 'User').trim();
    if (_myName.isEmpty) _myName = 'User';
  }

  int _newRandomId() {
    return (DateTime.now().microsecondsSinceEpoch.remainder(0x7fffffff) ^
            Random().nextInt(1 << 30))
        .abs();
  }

  Future<void> regenerateMyId() async {
    final prefs = await SharedPreferences.getInstance();
    _myId = _newRandomId();
    _seq = 0;
    _peers.clear();
    await prefs.setInt('my_id', _myId);
    _forcedNamePackets = 6;
    notifyListeners();
    await _advertiseName(force: true);
  }

  Future<void> setMyName(String name) async {
    final cleaned = _sanitizeName(name);
    _myName = cleaned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('my_name', _myName);
    _forcedNamePackets = 6;
    notifyListeners();
    await _advertiseName(force: true);
  }

  void spamMyNameNow() {
    _forcedNamePackets = 6;
    _advertiseName(force: true);
    notifyListeners();
  }

  void clearOfflinePeers() {
    final ids = _peers.entries
        .where((e) => !isPeerOnline(e.value))
        .map((e) => e.key)
        .toList(growable: false);

    if (ids.isEmpty) return;
    for (final id in ids) {
      _peers.remove(id);
    }
    notifyListeners();
  }

  String _sanitizeName(String s) {
    var t = s.trim();
    if (t.isEmpty) return 'User';

    // Limite a rune, non a code unit. Il codec poi limita anche i byte UTF-8.
    final runes = t.runes.toList();
    if (runes.length > 10) {
      t = String.fromCharCodes(runes.take(10));
    }
    return t;
  }

  void disposeService() {
    _startFuture = null;
    _bleStatusSub?.cancel();
    _scanWatchdogTimer?.cancel();
    _scanWatchdogTimer = null;
    _scanSub?.cancel();
    _locSub?.cancel();
    _gcTimer?.cancel();
    _stopScan();
    _stopAdvertising();
  }

  void _ensureScanRunning() {
    if (_bleStatus != BleStatus.ready) return;
    if (_scanSub != null) return;

    _lastScanStartedAt = DateTime.now();

    // BLE Stability:
    // scan senza serviceUuid filter. Riconosciamo Convoy Mesh dal magic "CM"
    // dentro manufacturerData. È più robusto quando non pubblichiamo serviceUuid.
    _scanSub = _ble
        .scanForDevices(
          withServices: const <Uuid>[],
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: false,
        )
        .listen(_handleScanResult, onError: (Object e) {
          _lastRxSummary = 'scan error: $e';
          _scanSub = null;
          notifyListeners();
          Future<void>.delayed(const Duration(milliseconds: 800), _ensureScanRunning);
        });

    notifyListeners();
  }

  void _startScanWatchdog() {
    _scanWatchdogTimer ??= Timer.periodic(const Duration(seconds: 12), (_) {
      _scanWatchdogTick();
    });
  }

  void _scanWatchdogTick() {
    if (_bleStatus != BleStatus.ready) return;

    if (_scanSub == null) {
      _ensureScanRunning();
      return;
    }

    final now = DateTime.now();
    final started = _lastScanStartedAt;
    if (started == null) return;

    // Se lo scan è ON ma non arriva nemmeno un advertisement casuale, spesso Android
    // è rimasto incastrato dopo cambio Posizione/BT oppure dopo rientro in app.
    final lastAny = _lastScanEventAt ?? started;
    final silentFor = now.difference(lastAny);
    final scanAge = now.difference(started);

    if (scanAge > const Duration(seconds: 18) && silentFor > const Duration(seconds: 24)) {
      unawaited(restartScanForDebug(reason: 'watchdog_silent_${silentFor.inSeconds}s'));
    }
  }

  Future<void> restartScanForDebug({String reason = 'manual'}) async {
    if (_bleStatus != BleStatus.ready) return;
    if (_scanRestarting) return;

    _scanRestarting = true;
    try {
      await _scanSub?.cancel();
      _scanSub = null;
      await Future<void>.delayed(const Duration(milliseconds: 350));

      _scanRestartCount++;
      _lastScanRestartAt = DateTime.now();
      _lastScanRestartReason = reason;
      _ensureScanRunning();
      notifyListeners();
    } finally {
      _scanRestarting = false;
    }
  }

  void _handleScanResult(DiscoveredDevice d) {
    _scanEventCount++;
    _lastScanEventAt = DateTime.now();

    final md = d.manufacturerData;
    if (md.isEmpty) {
      _rxNoManufacturerData++;
      if (_rxNoManufacturerData % 100 == 0) notifyListeners();
      return;
    }

    final raw = Uint8List.fromList(md);
    final parsed = ConvoyBleCodec.parseManufacturerData(raw);

    _lastMdBytes = parsed.inputLength;
    _lastMdHex = parsed.inputPreviewHex;
    _lastParseReason = parsed.reason;
    _lastMagicOffset = parsed.magicOffset;

    if (!parsed.ok) {
      if (parsed.reason == 'no_magic') {
        _rxNoMagic++;
        // Non notifichiamo a ogni ADV casuale dell'ambiente: sono tantissimi.
        // Aggiorniamo comunque la UI ogni tanto, così i contatori respirano.
        if (_rxNoMagic % 100 == 0) notifyListeners();
      } else {
        _rxBadPacket++;
        _lastRxAt = DateTime.now();
        _lastRxSummary = 'bad ${parsed.reason} off ${parsed.magicOffset ?? '-'}';
        notifyListeners();
      }
      return;
    }

    final pkt = parsed.packet!;
    _rxMagicFound++;

    if (pkt.userId == _myId) {
      _rxIgnoredSelf++;
      _lastRxAt = DateTime.now();
      _lastRxSummary = 'self ${pkt.kindLabel} seq ${pkt.seq} off ${parsed.magicOffset}';
      // I pacchetti self/duplicati possono arrivare spesso: aggiorniamo la UI a campioni
      // per ridurre rebuild e warning di frame saltati, senza perdere i contatori.
      if (_rxIgnoredSelf % 10 == 0) notifyListeners();
      return;
    }

    final peer = _peers.putIfAbsent(pkt.userId, () => PeerState(userId: pkt.userId));
    final now = DateTime.now();

    // Anche se l'advertisement è duplicato, aggiorniamo presenza/RSSI.
    peer.lastSeen = now;
    peer.rssi = d.rssi;
    peer.lastAddress = d.id;

    var acceptedAny = false;
    final staleParts = <String>[];

    if (pkt.hasName) {
      final incomingName = pkt.name!.trim();
      final nameChanged = incomingName.isNotEmpty && incomingName != peer.name;
      final acceptName = _isSeqAcceptable(
            incoming: pkt.seq,
            current: peer.lastNameSeq,
            lastAcceptedAt: peer.lastNameSeen,
          ) ||
          (nameChanged && _nameChangeWindowExpired(peer.lastNameSeen, now));

      if (acceptName) {
        peer.name = incomingName;
        peer.lastNameSeen = now;
        peer.lastNameSeq = pkt.seq;
        peer.rxNamePackets++;
        _rxNamePackets++;
        acceptedAny = true;
      } else {
        staleParts.add('name');
      }
    }

    if (pkt.hasFix) {
      final acceptFix = _isSeqAcceptable(
        incoming: pkt.seq,
        current: peer.lastFixSeq,
        lastAcceptedAt: peer.lastFixSeen,
      );

      if (acceptFix) {
        peer.accuracyM = pkt.accuracyM;
        peer.lat = pkt.lat;
        peer.lon = pkt.lon;
        peer.lastFixSeen = now;
        peer.lastFixSeq = pkt.seq;
        peer.rxFixPackets++;
        _rxFixPackets++;
        peer.addPointIfValid(retention: trailRetention);
        acceptedAny = true;
      } else {
        staleParts.add('pos');
      }
    }

    // Pacchetto PING senza fix/nome: per ora serve solo a mantenere presenza.
    if (!pkt.hasName && !pkt.hasFix) {
      final acceptPing = _isSeqAcceptable(
        incoming: pkt.seq,
        current: peer.lastSeq,
        lastAcceptedAt: peer.lastSeen,
      );
      acceptedAny = acceptPing;
      if (!acceptPing) staleParts.add('ping');
    }

    if (!acceptedAny) {
      _rxStale++;
      _lastRxAt = now;
      final parts = staleParts.isEmpty ? pkt.kindLabel : staleParts.join('+');
      _lastRxSummary = 'stale $parts from ${pkt.userId} seq ${pkt.seq} off ${parsed.magicOffset}';
      // I duplicati BLE fanno rumore: notifichiamo ogni 10 scarti per alleggerire la UI.
      if (_rxStale % 10 == 0) notifyListeners();
      return;
    }

    peer.lastSeq = pkt.seq;
    peer.rxPackets++;

    _rxValid++;
    _lastRxAt = now;
    _lastRxSummary = '${pkt.kindLabel} from ${pkt.userId} seq ${pkt.seq} rssi ${d.rssi} off ${parsed.magicOffset}';
    notifyListeners();
  }

  bool _isSeqAcceptable({
    required int incoming,
    required int current,
    required DateTime? lastAcceptedAt,
  }) {
    if (current < 0) return true;
    if (_isSeqNewer(incoming, current)) return true;

    // Probabile riavvio app lato peer: seq ripartita bassa dopo un gap.
    final gap = lastAcceptedAt == null ? const Duration(days: 1) : DateTime.now().difference(lastAcceptedAt);
    if (gap > seqResetGrace && incoming < current && incoming < 256) return true;

    return false;
  }

  bool _nameChangeWindowExpired(DateTime? lastNameSeen, DateTime now) {
    if (lastNameSeen == null) return true;
    return now.difference(lastNameSeen) > changedNameGrace;
  }

  bool _isSeqNewer(int incoming, int current) {
    if (incoming == current) return false;
    final diff = (incoming - current) & 0xFFFF;
    return diff > 0 && diff < 0x8000;
  }

  void _stopScan() {
    _scanSub?.cancel();
    _scanSub = null;
    _lastScanStartedAt = null;
  }

  Future<void> _advertisePosition(FusedLocation f) {
    _seq = (_seq + 1) & 0xFFFF;
    final payload = ConvoyBleCodec.buildPositionManufacturerData(
      userId: _myId,
      seq: _seq,
      lat: f.lat,
      lon: f.lon,
      accuracyM: f.accuracyM,
    );
    return _updateAdvertisingWithPayload(
      payload: payload,
      kind: 'POS',
      seq: _seq,
    );
  }

  Future<void> _advertiseName({required bool force}) {
    if (_bleStatus != BleStatus.ready) return Future.value();

    final now = DateTime.now();
    if (!force && now.difference(_lastNameAdv) < nameAdvInterval) {
      return Future.value();
    }

    _lastNameAdv = now;
    _seq = (_seq + 1) & 0xFFFF;
    final payload = ConvoyBleCodec.buildNameManufacturerData(
      userId: _myId,
      seq: _seq,
      name: _myName,
    );
    return _updateAdvertisingWithPayload(
      payload: payload,
      kind: 'NAME',
      seq: _seq,
    );
  }

  Future<void> _updateAdvertisingWithPayload({
    required Uint8List payload,
    required String kind,
    required int seq,
  }) {
    _advOp = _advOp.then((_) async {
      if (_bleStatus != BleStatus.ready) return;

      _lastPayloadBytes = payload.length;
      _lastTxKind = kind;
      _lastTxSeq = seq;
      _lastTxAt = DateTime.now();
      _lastAdvError = null;

      // Niente serviceUuid nell'advertising, per ridurre payload e fallimenti.
      final data = AdvertiseData(
        manufacturerId: ConvoyBleCodec.manufacturerId,
        manufacturerData: payload,
        includeDeviceName: false,
        includePowerLevel: false,
      );

      try {
        if (_advertising) {
          await _peripheral.stop();
          _advertising = false;
        }
        await _peripheral.start(advertiseData: data);
        _advertising = true;
        _advOkCount++;
        notifyListeners();
      } catch (e) {
        _advertising = false;
        _advErrorCount++;
        _lastAdvError = e.toString();
        notifyListeners();
      }
    });

    return _advOp;
  }

  Future<void> _stopAdvertising() async {
    try {
      await _peripheral.stop();
    } catch (_) {}
    _advertising = false;
  }

  void _gcPeers() {
    final now = DateTime.now();
    final toRemove = <int>[];

    _peers.forEach((id, p) {
      if (now.difference(p.lastSeen) > peerTtl) {
        toRemove.add(id);
      }
    });

    if (toRemove.isNotEmpty) {
      for (final id in toRemove) {
        _peers.remove(id);
      }
      notifyListeners();
    }
  }

  // ---------- UI helpers (mappa) ----------

  FusedLocation? get myLast => LocationFusionService.instance.last;

  List<PeerPoint> get myTrail {
    final pts = LocationFusionService.instance.trackPoints;
    return pts.map((t) => PeerPoint(lat: t.lat, lon: t.lon, ts: t.ts)).toList(growable: false);
  }

  void clearMyTrail() {
    LocationFusionService.instance.clearTrack();
    notifyListeners();
  }

  // ---------- UI helpers (colori e RSSI) ----------

  static bool isPeerOnline(PeerState peer) {
    return DateTime.now().difference(peer.lastSeen) <= peerOnlineTtl;
  }

  static int colorForUser(int userId) {
    final hue = (userId * 37) % 360;
    return _hslToColorInt(hue.toDouble(), 0.65, 0.55);
  }

  static int _hslToColorInt(double h, double s, double l) {
    final c = (1 - (2 * l - 1).abs()) * s;
    final x = c * (1 - ((h / 60.0) % 2 - 1).abs());
    final m = l - c / 2;

    double r = 0, g = 0, b = 0;
    if (h < 60) {
      r = c;
      g = x;
    } else if (h < 120) {
      r = x;
      g = c;
    } else if (h < 180) {
      g = c;
      b = x;
    } else if (h < 240) {
      g = x;
      b = c;
    } else if (h < 300) {
      r = x;
      b = c;
    } else {
      r = c;
      b = x;
    }

    final ri = ((r + m) * 255).round().clamp(0, 255);
    final gi = ((g + m) * 255).round().clamp(0, 255);
    final bi = ((b + m) * 255).round().clamp(0, 255);

    return 0xFF000000 | (ri << 16) | (gi << 8) | bi;
  }

  static String rssiQuality(int rssi) {
    if (rssi >= -60) return 'Ottimo';
    if (rssi >= -70) return 'Buono';
    if (rssi >= -80) return 'Medio';
    return 'Scarso';
  }

  static double rssiToMeters(int rssi) {
    const txPower = -59.0;
    if (rssi == 0) return 999;
    final ratio = rssi / txPower;
    if (ratio < 1.0) return pow(ratio, 10).toDouble();
    return (0.89976 * pow(ratio, 7.7095) + 0.111).toDouble();
  }

  static String ageLabel(DateTime? t) {
    if (t == null) return '-';
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 60) return '${s}s fa';
    final m = s ~/ 60;
    return '${m}m fa';
  }
}

class PeerState {
  final int userId;

  String? name;

  double? lat;
  double? lon;
  double? accuracyM;
  int rssi = 0;

  // lastSeq è ora solo informativo/compat UI.
  // Per evitare che POS renda stale i NAME (e viceversa), teniamo sequenze separate.
  int lastSeq = -1;
  int lastFixSeq = -1;
  int lastNameSeq = -1;

  DateTime lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? lastFixSeen;
  DateTime? lastNameSeen;
  String? lastAddress;

  int rxPackets = 0;
  int rxFixPackets = 0;
  int rxNamePackets = 0;

  final List<PeerPoint> trail = [];
  bool _hasFirst = false;

  PeerState({required this.userId});

  bool get hasFix => lat != null && lon != null;

  bool get hasFreshFix {
    final t = lastFixSeen;
    if (!hasFix || t == null) return false;
    return DateTime.now().difference(t) <= ConvoyMeshService.peerOnlineTtl;
  }

  void addPointIfValid({required Duration retention}) {
    if (lat == null || lon == null) return;

    final acc = accuracyM ?? 9999;
    if (acc > 80) return;

    final now = DateTime.now();
    final p = PeerPoint(lat: lat!, lon: lon!, ts: now);

    trail.removeWhere((e) => now.difference(e.ts) > retention);

    if (!_hasFirst || trail.isEmpty) {
      trail.add(p);
      _hasFirst = true;
      return;
    }

    final last = trail.last;
    final d = _haversine(last.lat, last.lon, p.lat, p.lon);

    final minMove = max(3.0, acc * 0.35);
    if (d < minMove) return;

    trail.add(p);
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static double _deg2rad(double d) => d * (pi / 180.0);
}

class PeerPoint {
  final double lat;
  final double lon;
  final DateTime ts;
  PeerPoint({required this.lat, required this.lon, required this.ts});
}
