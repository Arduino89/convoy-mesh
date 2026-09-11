import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/ble_tx_scheduler.dart';
import '../ble/convoy_ble_codec.dart';
import '../ble/native_ble_advertiser.dart';
import '../ble/native_ble_scan.dart';
import '../location/fused_location.dart';
import '../location/gps_pedestrian_filter.dart';
import 'background_runtime_service.dart';
import 'diagnostic_recorder.dart';
import 'location_fusion_service.dart';

class ConvoyMeshService extends ChangeNotifier {
  ConvoyMeshService._() : _now = DateTime.now;

  @visibleForTesting
  ConvoyMeshService.forTest({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static final instance = ConvoyMeshService._();
  final DateTime Function() _now;
  late final FlutterReactiveBle _ble = FlutterReactiveBle();
  final Stopwatch _clock = Stopwatch()..start();

  Future<void>? _nearbyStartFuture, _outingStartFuture, _stopFuture;
  Future<void> _advOp = Future.value();
  bool _running = false, _outingActive = false, _txBusy = false, _scanRestarting = false;
  bool get isRunning => _running;
  bool get isOutingActive => _outingActive;

  int _generation = 0, _myId = 0, _seq = 0;
  int get myId => _myId;
  String _myName = 'User';
  String get myName => _myName;

  BleStatus _bleStatus = BleStatus.unknown;
  BleStatus get bleStatus => _bleStatus;
  bool _advertising = false;
  bool get isAdvertising => _advertising;
  bool get isScanning => _scanSub != null;

  final Map<int, PeerState> _peers = {};
  Map<int, PeerState> get peers => Map.unmodifiable(_peers);
  BleTxScheduler _scheduler = BleTxScheduler();
  final List<_HistoryTransfer> _historyQueue = [];
  final List<_HistoryAckRequest> _historyAckQueue = [];

  StreamSubscription<BleStatus>? _statusSub;
  StreamSubscription<BleAdvertisement>? _scanSub;
  StreamSubscription<FusedLocation>? _locSub;
  Timer? _txTimer, _gcTimer, _scanRetry;
  Duration? _lastRuntimePulse, _lastScanRestart, _lastHistoryTx;
  bool? _lastLocationEnabled;

  static const peerOnlineTtl = Duration(seconds: 30);
  static const peerTtl = Duration(minutes: 30);
  static const gcEvery = Duration(seconds: 5);
  static const advMinInterval = Duration(seconds: 5);
  static const nameAdvInterval = Duration(seconds: 30);
  static const seqResetGrace = Duration(seconds: 20);
  static const trailRetention = Duration(minutes: 90);
  static const historySendEvery = Duration(seconds: 2);
  static const historyRetryEvery = Duration(seconds: 4);
  static const historyMaxAttempts = 4;
  static const maxHistoryCatchupPoints = 28;
  static const maxPeerWalkingSpeedKmh = 15.0;
  static const hardPeerRejectSpeedKmh = 40.0;

  String? lastAdvError;
  int lastPayloadBytes = 0, lastTxSeq = 0;
  String lastTxKind = '-', lastRxSummary = '-';
  DateTime? lastTxAt, lastRxAt, lastScanStartedAt, lastScanEventAt, lastScanRestartAt;
  String lastScanRestartReason = '-';
  int rxValid = 0, rxNoManufacturerData = 0, rxIgnoredSelf = 0, rxStale = 0;
  int rxFixPackets = 0, rxNamePackets = 0, rxHistoryPackets = 0, rxHistoryAckPackets = 0;
  int advOkCount = 0, advErrorCount = 0;
  int rxNoMagic = 0, rxBadPacket = 0, rxMagicFound = 0, lastMdBytes = 0;
  int scanRestartCount = 0, scanEventCount = 0;
  String lastMdHex = '-', lastParseReason = '-';
  int? lastMagicOffset;

  int get rxParseFailed => rxNoMagic + rxBadPacket;
  int get rxRejected => rxParseFailed;
  int get onlinePeerCount => _peers.values.where(isPeerOnline).length;
  int get offlinePeerCount => _peers.length - onlinePeerCount;
  int get pendingHistoryPoints => _historyQueue.length;
  int get pendingHistoryAcks => _historyAckQueue.length;
  bool get localLocationServiceEnabled =>
      myLast?.serviceEnabled ?? _lastLocationEnabled ?? false;
  bool get scanMayBeBlockedByLocation =>
      _bleStatus == BleStatus.ready && !localLocationServiceEnabled;
  FusedLocation? get myLast => LocationFusionService.instance.last;
  List<PeerPoint> get myTrail => LocationFusionService.instance.trackPoints
      .map((p) => PeerPoint(
            lat: p.lat,
            lon: p.lon,
            ts: p.ts,
            segment: p.segment,
          ))
      .toList(growable: false);

  /// Foreground-only lobby mode: scan + NAME/PING, no GPS and no FGS.
  Future<void> startNearby() =>
      _nearbyStartFuture ??= _startNearbyInternal().catchError((Object e, StackTrace s) async {
        await disposeService();
        Error.throwWithStackTrace(e, s);
      });

  /// Compatibility alias: old callers meant a full outing.
  Future<void> start() => startOuting();

  Future<void> startOuting() {
    if (_outingActive) return Future.value();
    return _outingStartFuture ??=
        _startOutingInternal().whenComplete(() => _outingStartFuture = null);
  }

  Future<void> _startNearbyInternal() async {
    if (_running) return;
    await _loadIdentity();
    _running = true;
    final epoch = ++_generation;
    _scheduler = BleTxScheduler();
    _lastRuntimePulse = null;
    _lastHistoryTx = null;

    await _statusSub?.cancel();
    _statusSub = _ble.statusStream.listen((status) {
      if (!_running || epoch != _generation) return;
      _bleStatus = status;
      DiagnosticRecorder.instance.record(
        'ble',
        'status',
        data: {'status': status.name, 'mode': _outingActive ? 'outing' : 'nearby'},
      );
      if (status == BleStatus.ready) {
        _ensureScanRunning();
        unawaited(refreshNow(reason: 'bluetooth_ready'));
      } else {
        unawaited(_stopScan());
        _advOp = _advOp.then((_) => _stopAdvertising());
      }
      notifyListeners();
    }, onError: (Object e) {
      _bleStatus = BleStatus.unknown;
      DiagnosticRecorder.instance.record(
        'ble',
        'status_error',
        data: {'error': e.toString()},
      );
      notifyListeners();
    });

    _txTimer?.cancel();
    _txTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_transmitTick()),
    );
    _gcTimer?.cancel();
    _gcTimer = Timer.periodic(gcEvery, (_) {
      final now = _now();
      _peers.removeWhere((_, p) => now.difference(p.lastSeen) > peerTtl);
      notifyListeners();
    });

    DiagnosticRecorder.instance.record('ble', 'nearby_started');
    notifyListeners();
  }

  Future<void> _startOutingInternal() async {
    await startNearby();
    if (_outingActive) return;
    _outingActive = true;
    final epoch = _generation;
    try {
      await LocationFusionService.instance.start();
      if (!_running || epoch != _generation || !_outingActive) {
        await LocationFusionService.instance.disposeService();
        return;
      }
      await _locSub?.cancel();
      _locSub = LocationFusionService.instance.stream.listen((f) {
        if (!_running || epoch != _generation || !_outingActive) return;
        final was = _lastLocationEnabled;
        _lastLocationEnabled = f.serviceEnabled;
        if (was == false && f.serviceEnabled) {
          unawaited(restartScanForDebug(reason: 'location_on'));
        }
        notifyListeners();
      });
      DiagnosticRecorder.instance.record('runtime', 'outing_mode', data: {'active': true});
      await refreshNow(reason: 'outing_mode_started');
      notifyListeners();
    } catch (_) {
      _outingActive = false;
      await _locSub?.cancel();
      _locSub = null;
      await LocationFusionService.instance.disposeService();
      rethrow;
    }
  }

  Future<void> stopOuting() async {
    if (!_outingActive && _locSub == null) return;
    _outingActive = false;
    _historyQueue.clear();
    _lastHistoryTx = null;
    await _locSub?.cancel();
    _locSub = null;
    await LocationFusionService.instance.disposeService();
    _lastLocationEnabled = null;
    _scheduler.requestName();
    DiagnosticRecorder.instance.record('runtime', 'outing_mode', data: {'active': false});
    if (_running) await refreshNow(reason: 'nearby_after_outing');
    notifyListeners();
  }

  Future<void> _loadIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    _myId = prefs.getInt('my_id') ?? 0;
    if (_myId <= 0) {
      _myId = _newId();
      await prefs.setInt('my_id', _myId);
    }
    _myName = _cleanName(prefs.getString('my_name') ?? 'User');
    notifyListeners();
  }

  int _newId() => Random.secure().nextInt(0x7ffffffe) + 1;

  String _cleanName(String text) {
    final cleaned = text.trim();
    return cleaned.isEmpty ? 'User' : String.fromCharCodes(cleaned.runes.take(10));
  }

  Future<void> setMyName(String value) async {
    _myName = _cleanName(value);
    await (await SharedPreferences.getInstance()).setString('my_name', _myName);
    spamMyNameNow();
  }

  Future<void> regenerateMyId() async {
    _myId = _newId();
    _seq = 0;
    _peers.clear();
    await (await SharedPreferences.getInstance()).setInt('my_id', _myId);
    spamMyNameNow();
  }

  void spamMyNameNow() {
    _scheduler.requestName();
    unawaited(_transmitTick());
    notifyListeners();
  }

  void clearOfflinePeers() {
    _peers.removeWhere((_, p) => !isPeerOnline(p));
    notifyListeners();
  }

  void clearMyTrail() {
    LocationFusionService.instance.clearTrack();
    notifyListeners();
  }

  Future<void> refreshNow({String reason = 'manual'}) async {
    if (!_running) return;
    _ensureScanRunning();
    DiagnosticRecorder.instance.record(
      'ble',
      'refresh_requested',
      data: {'reason': reason, 'mode': _outingActive ? 'outing' : 'nearby'},
    );
    await _transmitTick(refresh: true);
  }

  Future<void> _transmitTick({bool refresh = false}) async {
    if (!_running || _txBusy) return;
    _txBusy = true;
    final epoch = _generation;
    try {
      if (_outingActive && BackgroundRuntimeService.instance.isRunning &&
          (_lastRuntimePulse == null ||
              _clock.elapsed - _lastRuntimePulse! >= const Duration(seconds: 5))) {
        _lastRuntimePulse = _clock.elapsed;
        await BackgroundRuntimeService.instance.pulse();
      }
      if (!_running || epoch != _generation || _bleStatus != BleStatus.ready || _myId == 0) {
        return;
      }

      final f = _outingActive ? myLast : null;
      final kind = _scheduler.choose(
        now: _clock.elapsed,
        hasFreshPosition: _outingActive && (f?.hasFreshFixAt(_now()) ?? false),
        refresh: refresh,
      );

      if (kind != null) {
        _seq = (_seq + 1) & 0xFFFF;
        final payload = switch (kind) {
          BleTxKind.position => ConvoyBleCodec.buildPositionManufacturerData(
              userId: _myId,
              seq: _seq,
              lat: f!.lat,
              lon: f.lon,
              accuracyM: f.accuracyM,
              fixAgeSeconds: _now().difference(f.measurementAt!).inSeconds,
            ),
          BleTxKind.name => ConvoyBleCodec.buildNameManufacturerData(
              userId: _myId,
              seq: _seq,
              name: _myName,
            ),
          BleTxKind.ping => ConvoyBleCodec.buildPingManufacturerData(
              userId: _myId,
              seq: _seq,
            ),
        };
        final label = kind == BleTxKind.position ? 'POS' : kind.name.toUpperCase();
        final succeeded = await _sendPayload(payload, label, _seq, epoch);
        if (succeeded) _scheduler.didSend(kind, _clock.elapsed);
        return;
      }

      // ACKs are transport control: send them promptly in idle radio slots,
      // but never ahead of a due live POS/NAME/PING packet.
      if (_historyAckQueue.isNotEmpty) {
        final ack = _historyAckQueue.removeAt(0);
        _seq = (_seq + 1) & 0xFFFF;
        final payload = ConvoyBleCodec.buildHistoryAckManufacturerData(
          userId: _myId,
          seq: _seq,
          targetUserId: ack.targetUserId,
          historySeq: ack.historySeq,
        );
        final succeeded = await _sendPayload(payload, 'HISTORY_ACK', _seq, epoch);
        if (!succeeded) _historyAckQueue.insert(0, ack);
        return;
      }

      if (!_outingActive || _historyQueue.isEmpty ||
          (_lastHistoryTx != null &&
              _clock.elapsed - _lastHistoryTx! < historySendEvery)) {
        return;
      }

      _historyQueue.removeWhere((transfer) {
        final age = _now().difference(transfer.point.ts).inSeconds;
        return transfer.complete || age < 0 || age > trailRetention.inSeconds;
      });
      if (_historyQueue.isEmpty) return;

      _HistoryTransfer? transfer;
      for (final candidate in _historyQueue) {
        final due = candidate.lastAttemptAt == null ||
            _clock.elapsed - candidate.lastAttemptAt! >= historyRetryEvery;
        if (!candidate.complete && candidate.attempts < historyMaxAttempts && due) {
          transfer = candidate;
          break;
        }
      }

      // A transfer that exhausted retries is dropped explicitly instead of
      // blocking later points forever. Missing targets remain visible in logs.
      if (transfer == null) {
        final exhausted = _historyQueue
            .where((item) => !item.complete && item.attempts >= historyMaxAttempts)
            .toList(growable: false);
        for (final item in exhausted) {
          DiagnosticRecorder.instance.record('ble', 'history_abandoned', data: {
            'history_seq': item.wireSeq,
            'attempts': item.attempts,
            'unacked_peer_ids': item.unackedTargets.toList()..sort(),
          });
          _historyQueue.remove(item);
        }
        return;
      }

      if (transfer.wireSeq == null) {
        _seq = (_seq + 1) & 0xFFFF;
        transfer.wireSeq = _seq;
      }
      final age = _now().difference(transfer.point.ts).inSeconds;
      final payload = ConvoyBleCodec.buildHistoryManufacturerData(
        userId: _myId,
        seq: transfer.wireSeq!,
        lat: transfer.point.lat,
        lon: transfer.point.lon,
        accuracyM: transfer.point.accuracyM,
        historyAgeSeconds: age,
      );
      final succeeded =
          await _sendPayload(payload, 'HISTORY', transfer.wireSeq!, epoch);
      if (succeeded) {
        transfer.attempts++;
        transfer.lastAttemptAt = _clock.elapsed;
        _lastHistoryTx = _clock.elapsed;
        DiagnosticRecorder.instance.record('ble', 'history_attempt', data: {
          'history_seq': transfer.wireSeq,
          'attempt': transfer.attempts,
          'target_peer_ids': transfer.targets.toList()..sort(),
          'unacked_peer_ids': transfer.unackedTargets.toList()..sort(),
        });
      }
    } catch (e) {
      lastAdvError = e.toString();
      DiagnosticRecorder.instance.record(
        'ble',
        'tx_error',
        data: {'error': e.toString()},
      );
    } finally {
      _txBusy = false;
    }
  }

  Future<bool> _sendPayload(Uint8List payload, String kind, int seq, int epoch) async {
    var success = false;
    _advOp = _advOp.then((_) async {
      if (!_running || epoch != _generation || _bleStatus != BleStatus.ready) return;
      lastPayloadBytes = payload.length;
      lastTxKind = kind;
      lastTxSeq = seq;
      lastTxAt = _now();
      lastAdvError = null;
      DiagnosticRecorder.instance.record('ble', 'tx_requested', data: {
        'kind': kind,
        'seq': seq,
        'device_id': _myId,
        'payload_hex': ConvoyBleCodec.previewHex(payload),
        'fix_source_utc': myLast?.measurementAt?.toUtc().toIso8601String(),
      });
      try {
        await NativeBleAdvertiser.replace(payload).timeout(const Duration(seconds: 5));
        if (!_running || epoch != _generation) {
          await _stopAdvertising();
          return;
        }
        _advertising = true;
        advOkCount++;
        success = true;
        DiagnosticRecorder.instance.record('ble', 'tx_native_success', data: {
          'kind': kind,
          'seq': seq,
          'manufacturer_id': ConvoyBleCodec.manufacturerId,
        });
      } catch (e) {
        advErrorCount++;
        lastAdvError = e.toString();
        await _stopAdvertising();
        DiagnosticRecorder.instance.record('ble', 'tx_native_error', data: {
          'kind': kind,
          'seq': seq,
          'manufacturer_id': ConvoyBleCodec.manufacturerId,
          'error': e.toString(),
        });
      }
      notifyListeners();
    });
    await _advOp;
    return success;
  }

  Future<void> _stopAdvertising() async {
    try {
      await NativeBleAdvertiser.stop().timeout(const Duration(seconds: 3));
    } catch (_) {}
    _advertising = false;
  }

  void _ensureScanRunning() {
    if (!_running || _bleStatus != BleStatus.ready || _scanSub != null || _scanRetry != null) {
      return;
    }
    final epoch = _generation;
    lastScanStartedAt = _now();
    _scanSub = NativeBleScan.scan().listen((d) {
      if (_running && epoch == _generation) _handleScanResult(d);
    }, onError: (Object e) {
      if (!_running || epoch != _generation) return;
      final failed = _scanSub;
      _scanSub = null;
      unawaited(failed?.cancel());
      lastRxSummary = 'scan error: $e';
      DiagnosticRecorder.instance.record(
        'ble',
        'scan_error',
        data: {'error': e.toString()},
      );
      _scanRetry?.cancel();
      _scanRetry = Timer(const Duration(seconds: 10), () {
        _scanRetry = null;
        _ensureScanRunning();
      });
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> _stopScan() async {
    final sub = _scanSub;
    _scanSub = null;
    await sub?.cancel();
    lastScanStartedAt = null;
  }

  Future<void> restartScanForDebug({String reason = 'manual'}) async {
    if (!_running || _bleStatus != BleStatus.ready || _scanRestarting) return;
    if (_lastScanRestart != null &&
        _clock.elapsed - _lastScanRestart! < const Duration(seconds: 10)) {
      return;
    }
    _lastScanRestart = _clock.elapsed;
    _scanRestarting = true;
    final epoch = _generation;
    try {
      _scanRetry?.cancel();
      _scanRetry = null;
      await _stopScan();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!_running || epoch != _generation) return;
      scanRestartCount++;
      lastScanRestartAt = _now();
      lastScanRestartReason = reason;
      _ensureScanRunning();
      DiagnosticRecorder.instance.record(
        'ble',
        'scan_restart',
        data: {'reason': reason, 'count': scanRestartCount},
      );
    } finally {
      _scanRestarting = false;
    }
  }

  @visibleForTesting
  void ingestForTest(Uint8List payload, {int rssi = -65}) => _handleScanResult(
        BleAdvertisement(
          id: 'synthetic',
          rssi: rssi,
          manufacturerData: payload,
        ),
      );

  @visibleForTesting
  void setIdentityForTest(int userId) {
    _myId = userId;
  }

  @visibleForTesting
  void queueHistoryForTest(
    TrackPoint point, {
    required int peerId,
    int? wireSeq,
  }) {
    final transfer = _HistoryTransfer(point: point, targets: {peerId})
      ..wireSeq = wireSeq;
    _historyQueue.add(transfer);
  }

  @visibleForTesting
  Set<int> unackedHistoryPeersForTest(int wireSeq) {
    for (final transfer in _historyQueue) {
      if (transfer.wireSeq == wireSeq) return transfer.unackedTargets;
    }
    return const <int>{};
  }

  void _handleScanResult(BleAdvertisement d) {
    final now = _now();
    scanEventCount++;
    lastScanEventAt = now;
    if (d.manufacturerData.isEmpty) {
      rxNoManufacturerData++;
      return;
    }

    final parsed = ConvoyBleCodec.parseManufacturerData(d.manufacturerData);
    lastMdBytes = parsed.inputLength;
    lastMdHex = parsed.inputPreviewHex;
    lastParseReason = parsed.reason;
    lastMagicOffset = parsed.magicOffset;
    if (!parsed.ok) {
      if (parsed.reason == 'no_magic') {
        rxNoMagic++;
      } else {
        rxBadPacket++;
      }
      DiagnosticRecorder.instance.record(
        'ble',
        'rx_parse_rejected',
        data: {'reason': parsed.reason},
      );
      return;
    }

    final pkt = parsed.packet!;
    rxMagicFound++;
    DiagnosticRecorder.instance.record('ble', 'rx_packet', data: {
      'peer_id': pkt.userId,
      'seq': pkt.seq,
      'kind': pkt.kindLabel,
      'rssi': d.rssi,
      'source_age_s': pkt.isHistory ? pkt.historyAgeSeconds : pkt.fixAgeSeconds,
      'observed_elapsed_nanos': d.observedElapsedNanos,
      'payload_hex': parsed.inputPreviewHex,
    });
    if (pkt.userId == 0) {
      rxBadPacket++;
      return;
    }
    if (pkt.userId == _myId) {
      rxIgnoredSelf++;
      return;
    }
    if (!_peers.containsKey(pkt.userId) && _peers.length >= 128) {
      rxBadPacket++;
      return;
    }

    final peer = _peers.putIfAbsent(pkt.userId, () => PeerState(userId: pkt.userId));
    final previousLastSeen = peer.lastSeen;
    final previouslyValid = peer.rxPackets > 0;
    peer.markHeard(now: now, rssi: d.rssi, address: d.id);

    var valid = false,
        acceptedFix = false,
        acceptedHistory = false,
        acceptedHistoryAck = false;
    final rejected = <String>[];

    if (pkt.isHistoryAck) {
      if (_seqAcceptable(
          pkt.seq, peer.lastHistoryAckSeq, peer.lastHistoryAckSeen, now)) {
        peer.lastHistoryAckSeq = pkt.seq;
        peer.lastHistoryAckSeen = now;
        peer.rxHistoryAckPackets++;
        rxHistoryAckPackets++;
        valid = true;
        if (pkt.ackTargetUserId == _myId && pkt.ackHistorySeq != null) {
          acceptedHistoryAck = _acceptHistoryAck(
            fromPeerId: pkt.userId,
            historySeq: pkt.ackHistorySeq!,
          );
        }
      } else {
        rejected.add('history_ack_sequence');
      }
    }

    if (pkt.hasName) {
      if (_seqAcceptable(pkt.seq, peer.lastNameSeq, peer.lastNameSeen, now)) {
        peer.name = pkt.name;
        peer.lastNameSeq = pkt.seq;
        peer.lastNameSeen = now;
        peer.rxNamePackets++;
        rxNamePackets++;
        valid = true;
      } else {
        rejected.add('name_sequence');
      }
    }

    if (pkt.isHistory) {
      // ACK means "radio packet received", not "point accepted into trail".
      // Even duplicates are ACKed again so a lost ACK can be repaired.
      _queueHistoryAck(targetUserId: pkt.userId, historySeq: pkt.seq);
      final newSequence =
          _seqAcceptable(pkt.seq, peer.lastHistorySeq, peer.lastHistorySeen, now);
      if (newSequence) {
        peer.lastHistorySeq = pkt.seq;
        peer.lastHistorySeen = now;
        valid = true;
        final age = pkt.historyAgeSeconds;
        final accuracy = pkt.accuracyM ?? double.infinity;
        if (age != null &&
            age >= 0 &&
            age <= trailRetention.inSeconds &&
            accuracy.isFinite &&
            accuracy >= 0 &&
            accuracy <= 80) {
          peer.addRecoveredPoint(
            lat: pkt.lat!,
            lon: pkt.lon!,
            accuracyM: accuracy,
            measuredAt: now.subtract(Duration(seconds: age)),
            retention: trailRetention,
          );
          peer.rxHistoryPackets++;
          rxHistoryPackets++;
          acceptedHistory = true;
        } else {
          rejected.add('history_unusable');
        }
      } else {
        rejected.add('history_sequence');
      }
    } else if (pkt.hasFix) {
      final newSequence =
          _seqAcceptable(pkt.seq, peer.lastFixSeq, peer.lastPositionPacketAt, now);
      if (newSequence) {
        peer.lastFixSeq = pkt.seq;
        peer.lastPositionPacketAt = now;
        valid = true;
        final measured = pkt.fixAgeSeconds == null
            ? now
            : now.subtract(Duration(seconds: pkt.fixAgeSeconds!));
        final usableAge = (pkt.fixAgeSeconds ?? 0) <= 15;
        final plausible = !peer.hasFix ||
            peer.lastFixSeen == null ||
            isPeerMovementPlausible(
              previousLat: peer.lat!,
              previousLon: peer.lon!,
              previousAccuracyM: peer.accuracyM,
              previousAt: peer.lastFixMeasuredAt ?? peer.lastFixSeen!,
              nextLat: pkt.lat!,
              nextLon: pkt.lon!,
              nextAccuracyM: pkt.accuracyM,
              nextAt: measured,
            );
        if (usableAge && plausible) {
          peer.lat = pkt.lat;
          peer.lon = pkt.lon;
          peer.accuracyM = pkt.accuracyM;
          peer.lastFixSeen = now;
          peer.lastFixMeasuredAt = pkt.fixAgeSeconds == null ? null : measured;
          peer.rxFixPackets++;
          rxFixPackets++;
          acceptedFix = true;
          peer.addPointIfValid(retention: trailRetention);
        } else {
          rejected.add(!usableAge ? 'pos_age' : 'pos_jump');
        }
      } else {
        rejected.add('pos_sequence');
      }
    }

    if (!pkt.hasName && !pkt.hasFix && !pkt.isHistoryAck) {
      if (_seqAcceptable(pkt.seq, peer.lastPingSeq, peer.lastPingSeen, now)) {
        peer.lastPingSeq = pkt.seq;
        peer.lastPingSeen = now;
        valid = true;
      } else {
        rejected.add('ping_sequence');
      }
    }

    DiagnosticRecorder.instance.record('ble', 'rx_decision', data: {
      'peer_id': pkt.userId,
      'seq': pkt.seq,
      'kind': pkt.kindLabel,
      'accepted_packet': valid,
      'accepted_fix': acceptedFix,
      'accepted_history': acceptedHistory,
      'accepted_history_ack': acceptedHistoryAck,
      'rejected_parts': rejected,
    });

    lastRxAt = now;
    if (!valid) {
      rxStale++;
      lastRxSummary = 'stale ${pkt.kindLabel} from ${pkt.userId} seq ${pkt.seq}';
    } else {
      final gap = previouslyValid ? now.difference(previousLastSeen) : Duration.zero;
      peer.lastSeen = now;
      peer.lastSeq = pkt.seq;
      peer.rxPackets++;
      rxValid++;
      lastRxSummary = '${pkt.kindLabel} from ${pkt.userId} seq ${pkt.seq} rssi ${d.rssi}';
      if (_outingActive && previouslyValid && gap > peerOnlineTtl && gap <= trailRetention) {
        _queueHistorySince(previousLastSeen, now, peer.userId);
      }
    }
    notifyListeners();
  }

  void _queueHistorySince(DateTime since, DateTime now, int peerId) {
    final selected = selectHistoryCatchupPoints(
      LocationFusionService.instance.trackPoints,
      since: since,
      until: now,
      maxPoints: maxHistoryCatchupPoints,
    );
    if (selected.isEmpty) return;

    for (final point in selected) {
      _HistoryTransfer? existing;
      for (final queued in _historyQueue) {
        if ((queued.point.ts.difference(point.ts).inMilliseconds).abs() <= 500 &&
            PeerState.distanceMeters(queued.point.lat, queued.point.lon, point.lat, point.lon) < 1) {
          existing = queued;
          break;
        }
      }
      if (existing == null) {
        _historyQueue.add(_HistoryTransfer(point: point, targets: {peerId}));
      } else {
        existing.targets.add(peerId);
      }
    }
    _historyQueue.sort((a, b) => a.point.ts.compareTo(b.point.ts));
    DiagnosticRecorder.instance.record('ble', 'history_queued', data: {
      'peer_id': peerId,
      'gap_seconds': now.difference(since).inSeconds,
      'queued_points': selected.length,
      'pending_total': _historyQueue.length,
    });
  }

  void _queueHistoryAck({required int targetUserId, required int historySeq}) {
    final exists = _historyAckQueue.any(
      (ack) => ack.targetUserId == targetUserId && ack.historySeq == historySeq,
    );
    if (!exists) {
      _historyAckQueue.add(
        _HistoryAckRequest(targetUserId: targetUserId, historySeq: historySeq),
      );
    }
  }

  bool _acceptHistoryAck({required int fromPeerId, required int historySeq}) {
    var matched = false;
    final completed = <_HistoryTransfer>[];
    for (final transfer in _historyQueue) {
      if (transfer.wireSeq != historySeq || !transfer.targets.contains(fromPeerId)) {
        continue;
      }
      matched = true;
      transfer.acknowledgedBy.add(fromPeerId);
      DiagnosticRecorder.instance.record('ble', 'history_acknowledged', data: {
        'history_seq': historySeq,
        'peer_id': fromPeerId,
        'attempts': transfer.attempts,
        'remaining_peer_ids': transfer.unackedTargets.toList()..sort(),
      });
      if (transfer.complete) completed.add(transfer);
    }
    for (final transfer in completed) {
      _historyQueue.remove(transfer);
    }
    return matched;
  }

  @visibleForTesting
  static List<TrackPoint> selectHistoryCatchupPoints(
    List<TrackPoint> track, {
    required DateTime since,
    required DateTime until,
    int maxPoints = maxHistoryCatchupPoints,
  }) {
    if (maxPoints <= 0) return const [];
    final eligible = track
        .where((p) => p.ts.isAfter(since) && !p.ts.isAfter(until))
        .toList(growable: false);
    if (eligible.length <= maxPoints) return eligible;
    if (maxPoints == 1) return [eligible.last];

    final result = <TrackPoint>[];
    var lastIndex = -1;
    for (var i = 0; i < maxPoints; i++) {
      final index = (i * (eligible.length - 1) / (maxPoints - 1)).round();
      if (index != lastIndex) {
        result.add(eligible[index]);
        lastIndex = index;
      }
    }
    return result;
  }

  bool _seqAcceptable(int incoming, int current, DateTime? last, DateTime now) {
    if (current < 0) return true;
    final diff = (incoming - current) & 0xFFFF;
    if (diff > 0 && diff < 0x8000) return true;
    return incoming < current &&
        incoming < 256 &&
        last != null &&
        now.difference(last) > seqResetGrace;
  }

  @visibleForTesting
  static bool isPeerMovementPlausible({
    required double previousLat,
    required double previousLon,
    required double? previousAccuracyM,
    required DateTime previousAt,
    required double nextLat,
    required double nextLon,
    required double? nextAccuracyM,
    required DateTime nextAt,
  }) {
    final dt = max(1.0, nextAt.difference(previousAt).inMilliseconds / 1000);
    final distance = PeerState.distanceMeters(previousLat, previousLon, nextLat, nextLon);
    final accuracy = max(
      max(0.0, previousAccuracyM ?? 100),
      max(0.0, nextAccuracyM ?? 100),
    );
    final allowance = maxPeerWalkingSpeedKmh / 3.6 * dt;
    if (!distance.isFinite ||
        distance / dt * 3.6 > hardPeerRejectSpeedKmh ||
        distance > max(80.0, allowance * 3 + accuracy * 1.3)) {
      return false;
    }
    return (nextAccuracyM ?? 100) <= 25 ||
        distance <= max(30.0, allowance + accuracy * 1.3);
  }

  Future<void> disposeService() =>
      _stopFuture ??= _stopInternal().whenComplete(() => _stopFuture = null);

  Future<void> _stopInternal() async {
    await stopOuting();
    _running = false;
    _generation++;
    _txTimer?.cancel();
    _txTimer = null;
    _gcTimer?.cancel();
    _gcTimer = null;
    _scanRetry?.cancel();
    _scanRetry = null;
    _historyAckQueue.clear();
    _historyQueue.clear();
    await _statusSub?.cancel();
    _statusSub = null;
    await _stopScan();
    await _advOp;
    if (_advertising) await _stopAdvertising();
    _nearbyStartFuture = null;
    _outingStartFuture = null;
    DiagnosticRecorder.instance.record('ble', 'nearby_stopped');
    notifyListeners();
  }

  static bool isPeerOnline(PeerState p) {
    final age = DateTime.now().difference(p.lastSeen);
    return !age.isNegative && age <= peerOnlineTtl;
  }

  static int colorForUser(int id) {
    final h = ((id * 37) % 360) / 60;
    const c = 0.585, m = 0.2575;
    final x = c * (1 - ((h % 2) - 1).abs());
    final rgb = h < 1
        ? [c, x, 0.0]
        : h < 2
            ? [x, c, 0.0]
            : h < 3
                ? [0.0, c, x]
                : h < 4
                    ? [0.0, x, c]
                    : h < 5
                        ? [x, 0.0, c]
                        : [c, 0.0, x];
    final v = rgb
        .map((v) => ((v + m) * 255).round().clamp(0, 255).toInt())
        .toList();
    return 0xFF000000 | v[0] << 16 | v[1] << 8 | v[2];
  }

  static String rssiQuality(int rssi) {
    if (rssi >= 0 || rssi < -127) return 'non disponibile';
    return rssi >= -60
        ? 'Ottimo'
        : rssi >= -70
            ? 'Buono'
            : rssi >= -80
                ? 'Medio'
                : 'Scarso';
  }

  static double rssiToMeters(int rssi) {
    if (rssi >= 0) return double.infinity;
    final ratio = rssi / -59.0;
    return ratio < 1
        ? pow(ratio, 10).toDouble()
        : (0.89976 * pow(ratio, 7.7095) + 0.111).toDouble();
  }

  static String ageLabel(DateTime? t) {
    if (t == null) return '-';
    final s = DateTime.now().difference(t).inSeconds;
    return s < 0
        ? 'orologio da verificare'
        : s < 60
            ? '${s}s fa'
            : '${s ~/ 60}m fa';
  }
}

class _HistoryTransfer {
  _HistoryTransfer({required this.point, required Set<int> targets})
      : targets = {...targets};

  final TrackPoint point;
  final Set<int> targets;
  final Set<int> acknowledgedBy = {};
  int? wireSeq;
  int attempts = 0;
  Duration? lastAttemptAt;

  Set<int> get unackedTargets => targets.difference(acknowledgedBy);
  bool get complete => unackedTargets.isEmpty;
}

class _HistoryAckRequest {
  const _HistoryAckRequest({required this.targetUserId, required this.historySeq});
  final int targetUserId;
  final int historySeq;
}

class PeerState {
  final int userId;
  PeerState({required this.userId});

  String? name, lastAddress;
  double? lat, lon, accuracyM;
  int rssi = 0,
      lastSeq = -1,
      lastFixSeq = -1,
      lastNameSeq = -1,
      lastPingSeq = -1,
      lastHistorySeq = -1,
      lastHistoryAckSeq = -1;
  int rxPackets = 0,
      rxFixPackets = 0,
      rxNamePackets = 0,
      rxHistoryPackets = 0,
      rxHistoryAckPackets = 0;
  DateTime lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastHeardAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? lastFixSeen,
      lastFixMeasuredAt,
      lastNameSeen,
      lastPingSeen,
      lastHistorySeen,
      lastHistoryAckSeen,
      lastPositionPacketAt;
  final List<PeerPoint> trail = [];
  final List<({DateTime at, int value})> _signal = [];

  bool get hasFix => lat != null && lon != null;

  bool get hasFreshFix {
    final time = lastFixMeasuredAt ?? lastFixSeen;
    if (!hasFix || time == null) return false;
    final age = DateTime.now().difference(time);
    return !age.isNegative && age <= const Duration(seconds: 15);
  }

  DateTime get lastActivityAt =>
      lastHeardAt.isAfter(lastSeen) ? lastHeardAt : lastSeen;

  int get medianRssi {
    _signal.removeWhere(
      (p) => DateTime.now().difference(p.at) > const Duration(seconds: 8),
    );
    if (_signal.isEmpty) return 0;
    final values = _signal.map((p) => p.value).toList()..sort();
    return values[values.length ~/ 2];
  }

  void markHeard({required DateTime now, required int rssi, required String address}) {
    lastHeardAt = now;
    this.rssi = rssi;
    lastAddress = address;
    if (rssi < 0 && rssi >= -127) {
      _signal.add((at: now, value: rssi));
      if (_signal.length > 20) _signal.removeAt(0);
    }
  }

  void addPointIfValid({required Duration retention}) {
    final accuracy = accuracyM ?? double.infinity;
    if (!hasFix || !accuracy.isFinite || accuracy > 80 || accuracy < 0) return;
    final now = DateTime.now();
    final pointTs = lastFixMeasuredAt ?? now;
    trail.removeWhere((p) => now.difference(p.ts) > retention);
    final previous = trail.isEmpty ? null : trail.last;
    final segment = previous == null
        ? 0
        : previous.segment +
            (pointTs.difference(previous.ts) > const Duration(seconds: 30) ? 1 : 0);
    if (previous != null &&
        previous.segment == segment &&
        distanceMeters(previous.lat, previous.lon, lat!, lon!) < max(3.0, accuracy * 0.35)) {
      return;
    }
    trail.add(PeerPoint(
      lat: lat!,
      lon: lon!,
      ts: pointTs,
      segment: segment,
      recovered: false,
    ));
    trail.sort((a, b) => a.ts.compareTo(b.ts));
  }

  void addRecoveredPoint({
    required double lat,
    required double lon,
    required double accuracyM,
    required DateTime measuredAt,
    required Duration retention,
  }) {
    final now = DateTime.now();
    if (!lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180 ||
        !accuracyM.isFinite ||
        accuracyM < 0 ||
        accuracyM > 80 ||
        now.difference(measuredAt) > retention) {
      return;
    }
    trail.removeWhere((p) => now.difference(p.ts) > retention);
    final duplicate = trail.any((p) =>
        (p.ts.difference(measuredAt).inSeconds).abs() <= 2 &&
        distanceMeters(p.lat, p.lon, lat, lon) < max(3.0, accuracyM * 0.35));
    if (duplicate) return;

    PeerPoint? previous;
    for (final point in trail) {
      if (!point.ts.isAfter(measuredAt)) previous = point;
    }
    final segment = previous?.segment ?? 0;
    trail.add(PeerPoint(
      lat: lat,
      lon: lon,
      ts: measuredAt,
      segment: segment,
      recovered: true,
    ));
    trail.sort((a, b) => a.ts.compareTo(b.ts));
  }

  static double distanceMeters(double lat1, double lon1, double lat2, double lon2) =>
      PedestrianGpsFilter.distanceMeters(lat1, lon1, lat2, lon2);
}

class PeerPoint {
  final double lat, lon;
  final DateTime ts;
  final int segment;
  final bool recovered;

  PeerPoint({
    required this.lat,
    required this.lon,
    required this.ts,
    this.segment = 0,
    this.recovered = false,
  });
}
