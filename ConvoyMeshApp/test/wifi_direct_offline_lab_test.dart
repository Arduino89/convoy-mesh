import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:convoy_mesh/services/background_runtime_service.dart';
import 'package:convoy_mesh/services/convoy_mesh_service.dart';
import 'package:convoy_mesh/services/location_fusion_service.dart';
import 'package:convoy_mesh/wifi_direct_lab/wifi_direct_lab_controller.dart';
import 'package:convoy_mesh/wifi_direct_lab/wifi_direct_lab_models.dart';
import 'package:convoy_mesh/wifi_direct_lab/wifi_direct_lab_page.dart';
import 'package:convoy_mesh/wifi_direct_lab/wifi_direct_lab_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeWifiDirectPlatformBridge implements WifiDirectPlatformBridge {
  FakeWifiDirectPlatformBridge({
    WifiDirectEnvironmentStatus? initialEnvironment,
  }) : environment = initialEnvironment ??
            const WifiDirectEnvironmentStatus(
              sdkInt: 33,
              wifiDirectFeatureSupported: true,
              wifiP2pServiceAvailable: true,
              wifiEnabled: true,
              p2pStateEnabled: true,
              bluetoothEnabled: false,
              internetValidated: false,
              nearbyWifiPermissionGranted: true,
              fineLocationPermissionGranted: false,
              requiredRuntimePermissionGranted: true,
              requiredPermissionName: 'NEARBY_WIFI_DEVICES',
              locationServiceEnabled: true,
              manifestPermissionsOk: true,
              foregroundServiceRunning: false,
            );

  WifiDirectEnvironmentStatus environment;
  final StreamController<Map<String, Object?>> _events =
      StreamController<Map<String, Object?>>.broadcast();

  int discoverCalls = 0;
  int connectCalls = 0;
  int stopCalls = 0;
  String? lastConnectedPeerId;
  bool? lastConnectConsented;
  String? lastStopReason;
  bool grantPermissionOnRequest = true;
  Object? discoverError;
  Object? connectError;
  String? sessionId;
  Completer<void>? stopReply;
  Completer<void>? discoveryReply;
  Completer<void>? connectReply;

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  void emit(Map<String, Object?> event) {
    _events.add({'session_id': sessionId, ...event});
  }

  @override
  Future<WifiDirectEnvironmentStatus> getEnvironmentStatus() async =>
      environment;

  @override
  Future<WifiDirectEnvironmentStatus> requestRequiredPermission() async {
    environment = environment.copyWith(
      nearbyWifiPermissionGranted: grantPermissionOnRequest,
      requiredRuntimePermissionGranted: grantPermissionOnRequest,
    );
    return environment;
  }

  @override
  Future<void> openWifiSettings() async {}

  @override
  Future<void> openBluetoothSettings() async {}

  @override
  Future<void> openLocationSettings() async {}

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> discoverPeers({required String sessionId, String? declaredName}) async {
    discoveryNames.add(declaredName);
    this.sessionId = sessionId;
    discoverCalls++;
    if (discoverError != null) {
      throw discoverError!;
    }
    await discoveryReply?.future;
  }

  final discoveryNames = <String?>[];
  final advertisementChanges = <String?>[];

  @override
  Future<void> advertiseConvoyName({required String sessionId, required String? declaredName}) async {
    expect(sessionId, this.sessionId);
    advertisementChanges.add(declaredName);
  }

  @override
  Future<void> connectPeer({
    required String sessionId,
    required String peerId,
    required bool userConsented,
  }) async {
    connectCalls++;
    lastConnectedPeerId = peerId;
    lastConnectConsented = userConsented;
    if (connectError != null) {
      throw connectError!;
    }
    await connectReply?.future;
  }

  @override
  Future<void> stopAll({required String? sessionId, String reason = 'manual_stop'}) async {
    stopCalls++;
    lastStopReason = reason;
    await stopReply?.future;
  }

  Future<void> dispose() async {
    await _events.close();
  }
}

/// Deterministic in-memory full-duplex socket pair for synchronous protocol
/// edge-case injection (such as forged ACKs or mid-batch drops).
class PairedInMemorySocketTransport implements WifiDirectSocketTransport {
  PairedInMemorySocketTransport();

  PairedInMemorySocketTransport? _peer;
  bool _open = false;
  int? _port;
  void Function(String line)? _onLine;
  void Function(String reason)? _onDisconnected;
  void Function(String code, String message)? _onError;
  bool Function(WifiDirectSyntheticFrame frame)? outboundFilter;

  static (PairedInMemorySocketTransport, PairedInMemorySocketTransport)
      createPair() {
    final a = PairedInMemorySocketTransport();
    final b = PairedInMemorySocketTransport();
    a._peer = b;
    b._peer = a;
    return (a, b);
  }

  @override
  bool get isSocketOpen => _open;

  @override
  int? get boundPort => _port;

  @override
  Future<void> startGroupOwnerServer({
    required int port,
    required void Function(int port) onSocketOpen,
    required void Function(String line) onLineReceived,
    required void Function(String reason) onSocketDisconnected,
    required void Function(String code, String message) onSocketError,
  }) async {
    _port = port;
    _onLine = onLineReceived;
    _onDisconnected = onSocketDisconnected;
    _onError = onSocketError;
    _open = true;
    onSocketOpen(port);
  }

  @override
  Future<void> connectAsClient({
    required String host,
    required int port,
    required void Function(int port) onSocketOpen,
    required void Function(String line) onLineReceived,
    required void Function(String reason) onSocketDisconnected,
    required void Function(String code, String message) onSocketError,
  }) async {
    _port = port;
    _onLine = onLineReceived;
    _onDisconnected = onSocketDisconnected;
    _onError = onSocketError;
    _open = true;
    onSocketOpen(port);
  }

  @override
  Future<void> sendJsonLine(String jsonLine) async {
    if (!_open) {
      throw StateError('In-memory socket closed');
    }
    final peer = _peer;
    if (peer == null || !peer._open) {
      throw StateError('Peer socket not connected');
    }
    final trimmed = jsonLine.trim();
    if (outboundFilter != null) {
      final parsed = WifiDirectSyntheticFrame.parseJsonLine(trimmed);
      if (!outboundFilter!(parsed)) {
        // Simulates a dropped packet on the radio link.
        return;
      }
    }
    peer._onLine?.call(trimmed);
  }

  void injectRawLine(String rawLine) {
    _onLine?.call(rawLine);
  }

  void simulateLinkDrop([String reason = 'simulated_link_loss']) {
    final wasOpen = _open;
    _open = false;
    if (wasOpen) {
      _onDisconnected?.call(reason);
    }
  }

  void simulateError(String code, String message) {
    _onError?.call(code, message);
  }

  @override
  Future<void> close() async {
    _open = false;
  }
}

void main() {
  group('Wi-Fi Direct Offline Lab — Isolation & Environment Gates', () {
    test('rejects discovery when Bluetooth is ON, Wi-Fi OFF, or permission denied (zero BLE fallback)', () async {
      final bridge = FakeWifiDirectPlatformBridge(
        initialEnvironment: const WifiDirectEnvironmentStatus(
          sdkInt: 33,
          wifiDirectFeatureSupported: true,
          wifiP2pServiceAvailable: true,
          wifiEnabled: true,
          p2pStateEnabled: true,
          bluetoothEnabled: true, // Violation: BT must be OFF!
          internetValidated: false,
          nearbyWifiPermissionGranted: true,
          requiredRuntimePermissionGranted: true,
          manifestPermissionsOk: true,
        ),
      );
      final controller = WifiDirectLabController(
        platform: bridge,
        random: Random(1),
      );
      addTearDown(() async {
        controller.dispose();
        await bridge.dispose();
      });

      final btOnOk = await controller.requestDiscovery();
      expect(btOnOk, isFalse);
      expect(bridge.discoverCalls, 0);
      expect(
        controller.logs.map((e) => e.kind),
        [WifiDirectLabEventKind.discoverRequested, WifiDirectLabEventKind.error],
      );
      expect(controller.logs.last.data['code'], 'BLUETOOTH_MUST_BE_OFF');
      expect(ConvoyMeshService.instance.isRunning, isFalse);
      expect(BackgroundRuntimeService.instance.isRunning, isFalse);

      // Now turn BT off, but disable Wi-Fi:
      bridge.environment = bridge.environment.copyWith(
        bluetoothEnabled: false,
        wifiEnabled: false,
        p2pStateEnabled: false,
      );
      final wifiOffOk = await controller.requestDiscovery();
      expect(wifiOffOk, isFalse);
      expect(bridge.discoverCalls, 0);
      expect(controller.logs.last.data['code'], 'WIFI_DISABLED');

      // Now turn Wi-Fi on, but revoke NEARBY_WIFI_DEVICES permission:
      bridge.environment = bridge.environment.copyWith(
        wifiEnabled: true,
        p2pStateEnabled: true,
        nearbyWifiPermissionGranted: false,
        requiredRuntimePermissionGranted: false,
      );
      final permDeniedOk = await controller.requestDiscovery();
      expect(permDeniedOk, isFalse);
      expect(bridge.discoverCalls, 0);
      expect(controller.logs.last.data['code'], 'PERMISSION_DENIED');

      // Android's location mode gate also applies with Nearby Wi-Fi granted.
      for (final sdk in [29, 35]) {
        bridge.environment = bridge.environment.copyWith(
          sdkInt: sdk,
          locationServiceEnabled: false,
          requiredRuntimePermissionGranted: true,
        );
        expect(await controller.requestDiscovery(), isFalse);
        expect(bridge.discoverCalls, 0);
        expect(controller.logs.last.data['code'], 'LOCATION_SERVICES_DISABLED_P2P');
        expect(controller.environment.readinessBlockers, isNotEmpty);
      }
      bridge.environment = bridge.environment.copyWith(locationServiceEnabled: true);
      expect(await controller.requestDiscovery(), isTrue);
      expect(bridge.discoverCalls, 1);
    });

    test('distinguishes system events from transport and application confirmations', () async {
      final bridge = FakeWifiDirectPlatformBridge();
      final (sockA, _) = PairedInMemorySocketTransport.createPair();
      final controller = WifiDirectLabController(
        platform: bridge,
        socketTransport: sockA,
        random: Random(7),
      );
      addTearDown(() async {
        controller.dispose();
        await bridge.dispose();
      });

      // 1. discoverPeers() success only logs discover_requested (system).
      final discovered = await controller.requestDiscovery();
      expect(discovered, isTrue);
      expect(controller.isGroupFormed, isFalse);
      expect(controller.isSocketOpen, isFalse);
      expect(controller.acksConfirmedCount, 0);
      expect(
        controller.logs.map((e) => e.kind),
        [WifiDirectLabEventKind.discoverRequested],
      );
      expect(controller.logs.single.layer, WifiDirectEvidenceLayer.system);

      // 2. Peer seen is logged only when peers_updated arrives.
      bridge.emit(<String, Object?>{
        'type': 'peers_updated',
        'peer_count': 1,
        'peers': [
          <String, Object?>{'peer_id': 'peer-01', 'status': 'available'},
        ],
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.peers.single.peerId, 'peer-01');
      expect(controller.logs.last.kind, WifiDirectLabEventKind.peerSeen);
      expect(controller.logs.last.layer, WifiDirectEvidenceLayer.system);

      // 3. Connect without user consent is rejected with CONSENT_REQUIRED.
      final unconsented = await controller.requestConnect(
        peerId: 'peer-01',
        userConsented: false,
      );
      expect(unconsented, isFalse);
      expect(bridge.connectCalls, 0);
      expect(controller.logs.last.kind, WifiDirectLabEventKind.error);
      expect(controller.logs.last.data['code'], 'CONSENT_REQUIRED');

      // 4. Consented connect logs connect_requested, still not group_formed or socket_open.
      final consented = await controller.requestConnect(
        peerId: 'peer-01',
        userConsented: true,
      );
      expect(consented, isTrue);
      expect(bridge.connectCalls, 1);
      expect(controller.isGroupFormed, isFalse);
      expect(controller.isSocketOpen, isFalse);
      expect(controller.logs.last.kind, WifiDirectLabEventKind.connectRequested);
    });
  });

  group('Wi-Fi Direct Offline Lab — Real TCP Bidirectional 20-Probe + ACK Exchange', () {
    test('two phones exchange 20 synthetic probes in both directions over real TCP sockets with 0 false confirmations and zero leaked identifiers', () async {
      final bridgeA = FakeWifiDirectPlatformBridge();
      final bridgeB = FakeWifiDirectPlatformBridge();

      final tcpA = TcpWifiDirectSocketTransport(
        defaultBindHost: '127.0.0.1',
      );
      final tcpB = TcpWifiDirectSocketTransport(
        defaultBindHost: '127.0.0.1',
      );

      var clockA = 1000;
      var clockB = 5000;
      final phoneA = WifiDirectLabController(
        platform: bridgeA,
        socketTransport: tcpA,
        elapsedMsProvider: () => clockA += 12,
        random: Random(101),
        labPort: 0, // Bind ephemeral loopback port on Group Owner
      );
      final phoneB = WifiDirectLabController(
        platform: bridgeB,
        socketTransport: tcpB,
        elapsedMsProvider: () => clockB += 15,
        random: Random(202),
      );

      addTearDown(() async {
        phoneA.dispose();
        phoneB.dispose();
        await bridgeA.dispose();
        await bridgeB.dispose();
      });

      // Both phones start discovery with Bluetooth OFF & Internet OFF:
      expect(await phoneA.requestDiscovery(), isTrue);
      expect(await phoneB.requestDiscovery(), isTrue);

      bridgeA.emit(<String, Object?>{
        'type': 'peers_updated',
        'peer_count': 1,
        'peers': [
          <String, Object?>{'peer_id': 'peer-01', 'status': 'available'},
        ],
      });
      bridgeB.emit(<String, Object?>{
        'type': 'peers_updated',
        'peer_count': 1,
        'peers': [
          <String, Object?>{'peer_id': 'peer-01', 'status': 'available'},
        ],
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        await phoneA.requestConnect(peerId: 'peer-01', userConsented: true),
        isTrue,
      );
      expect(
        await phoneB.requestConnect(peerId: 'peer-01', userConsented: true),
        isTrue,
      );

      // Phone A becomes Group Owner (binds ServerSocket on port 0 -> actual port):
      bridgeA.emit(<String, Object?>{
        'type': 'group_formed',
        'role': 'group_owner',
        'is_group_owner': true,
        'group_owner_host': '127.0.0.1',
        'client_count': 1,
        'port': 0,
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final boundPort = tcpA.boundPort;
      expect(boundPort, isNotNull);
      expect(boundPort, greaterThan(0));

      // Phone B becomes Client and connects to Group Owner's port:
      bridgeB.emit(<String, Object?>{
        'type': 'group_formed',
        'role': 'client',
        'is_group_owner': false,
        'group_owner_host': '127.0.0.1',
        'client_count': 1,
        'port': boundPort,
      });

      // Wait for real TCP handshake to complete on both phones:
      for (var i = 0; i < 40 && (!phoneA.isSocketOpen || !phoneB.isSocketOpen); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(phoneA.isSocketOpen, isTrue);
      expect(phoneB.isSocketOpen, isTrue);

      // Bidirectional 20-probe exchange: Phone A -> Phone B (20) and Phone B -> Phone A (20)
      final results = await Future.wait<int>([
        phoneA.sendProbeBatch(
          userConsented: true,
          count: 20,
          interval: Duration.zero,
        ),
        phoneB.sendProbeBatch(
          userConsented: true,
          count: 20,
          interval: Duration.zero,
        ),
      ]);
      expect(results, [20, 20]);

      // Allow final ACKs to flush across the loopback TCP socket:
      for (var i = 0;
          i < 40 &&
              (phoneA.acksConfirmedCount < 20 || phoneB.acksConfirmedCount < 20);
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      // Verify Phone A metrics:
      expect(phoneA.probesSentCount, 20);
      expect(phoneA.acksConfirmedCount, 20);
      expect(phoneA.unconfirmedProbesCount, 0);
      expect(phoneA.falseAcksRejected, 0);
      expect(phoneA.uniqueProbesDelivered, 20);
      expect(phoneA.duplicateProbesSuppressed, 0);
      expect(phoneA.acksSentCount, 20);
      expect(phoneA.minRttMs, isNotNull);

      // Verify Phone B metrics:
      expect(phoneB.probesSentCount, 20);
      expect(phoneB.acksConfirmedCount, 20);
      expect(phoneB.unconfirmedProbesCount, 0);
      expect(phoneB.falseAcksRejected, 0);
      expect(phoneB.uniqueProbesDelivered, 20);
      expect(phoneB.duplicateProbesSuppressed, 0);
      expect(phoneB.acksSentCount, 20);
      expect(phoneB.minRttMs, isNotNull);

      // Verify every sent probe on Phone A and Phone B matched its exact nonce in ack_received:
      for (final controller in [phoneA, phoneB]) {
        expect(controller.logs.where((e) => e.kind == WifiDirectLabEventKind.error), isEmpty);
        final ackEvents = controller.logs
            .where((e) => e.kind == WifiDirectLabEventKind.ackReceived)
            .toList();
        expect(ackEvents.length, 20);
        for (final sent in controller.sentProbes) {
          expect(sent.ackConfirmed, isTrue);
          final matchingAck = ackEvents.singleWhere(
            (e) => e.data['seq'] == sent.seq,
          );
          expect(matchingAck.data['nonce'], sent.nonce);
          expect(matchingAck.layer, WifiDirectEvidenceLayer.application);
        }
      }

      // Stop and verify clean teardown + disconnect event:
      await phoneA.stopAll(reason: 'test_complete');
      await phoneB.stopAll(reason: 'test_complete');
      expect(phoneA.isSocketOpen, isFalse);
      expect(phoneB.isSocketOpen, isFalse);
      expect(phoneA.logs.last.kind, WifiDirectLabEventKind.disconnect);
      expect(phoneB.logs.last.kind, WifiDirectLabEventKind.disconnect);

      // Verify exported JSONL contains all 9 non-error event types and 0 MAC/IP/SSID/coordinates:
      for (final controller in [phoneA, phoneB]) {
        final jsonl = controller.exportJsonl();
        expect(jsonl, isNotEmpty);
        expect(WifiDirectLabPrivacyGuard.containsForbiddenIdentifiers(jsonl), isFalse);
        expect(jsonl.contains('127.0.0.1'), isFalse);
        final observedEvents = controller.logs.map((e) => e.kind.wireName).toSet();
        expect(
          observedEvents,
          containsAll(<String>[
            'discover_requested',
            'peer_seen',
            'connect_requested',
            'group_formed',
            'socket_open',
            'probe_sent',
            'probe_received',
            'ack_received',
            'disconnect',
          ]),
        );
      }
    });
  });

  test('ordered concurrent TCP writes and queued cancellation do not reach a replacement socket', () async {
    final transport = TcpWifiDirectSocketTransport(defaultBindHost: '127.0.0.1');
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final connections = StreamIterator(server);
    addTearDown(() async {
      await transport.close();
      await connections.cancel();
      await server.close();
    });
    Future<Socket> connect() async {
      final incoming = connections.moveNext();
      await transport.connectAsClient(
        host: '127.0.0.1',
        port: server.port,
        onSocketOpen: (_) {},
        onLineReceived: (_) {},
        onSocketDisconnected: (_) {},
        onSocketError: (code, _) => fail(code),
      );
      expect(await incoming, isTrue);
      return connections.current;
    }

    final first = await connect();
    final frames = List.generate(40, (i) => '{"sequence":$i}');
    final received = first.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).take(frames.length).toList();
    await Future.wait(frames.map(transport.sendJsonLine));
    expect(await received.timeout(const Duration(seconds: 3)), frames);

    final queued = List.generate(40, (i) =>
      transport.sendJsonLine('stale-$i').then((_) => false, onError: (Object error) => error is SocketException));
    await transport.close();
    expect(await Future.wait(queued), everyElement(isTrue));
    first.destroy();
    final next = await connect();
    addTearDown(next.destroy);
    final newLine = next.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).first;
    await transport.sendJsonLine('fresh');
    expect(await newLine.timeout(const Duration(seconds: 3)), 'fresh');
  });

  group('Wi-Fi Direct Offline Lab — Anti-False-ACK, Link Loss Recovery & Deduplication', () {
    test('rejects forged/mismatched ACKs (0 false confirmations) and deduplicates retransmitted probes after link drop/recovery', () async {
      final bridgeA = FakeWifiDirectPlatformBridge();
      final bridgeB = FakeWifiDirectPlatformBridge();
      final (sockA, sockB) = PairedInMemorySocketTransport.createPair();

      var clockA = 100;
      var clockB = 200;
      final phoneA = WifiDirectLabController(
        platform: bridgeA,
        socketTransport: sockA,
        elapsedMsProvider: () => clockA += 10,
        random: Random(303),
      );
      final phoneB = WifiDirectLabController(
        platform: bridgeB,
        socketTransport: sockB,
        elapsedMsProvider: () => clockB += 10,
        random: Random(404),
      );
      addTearDown(() async {
        phoneA.dispose();
        phoneB.dispose();
        await bridgeA.dispose();
        await bridgeB.dispose();
      });

      expect(await phoneA.requestDiscovery(), isTrue);
      expect(await phoneB.requestDiscovery(), isTrue);
      // Form group and open paired sockets:
      bridgeA.emit(<String, Object?>{
        'type': 'group_formed',
        'role': 'group_owner',
        'is_group_owner': true,
        'group_owner_host': '192.168.49.1',
        'client_count': 1,
      });
      bridgeB.emit(<String, Object?>{
        'type': 'group_formed',
        'role': 'client',
        'is_group_owner': false,
        'group_owner_host': '192.168.49.1',
        'client_count': 1,
      });
      await Future<void>.delayed(Duration.zero);
      expect(phoneA.isSocketOpen, isTrue);
      expect(phoneB.isSocketOpen, isTrue);

      // Drop ACKs for seq 4 and seq 5 from Phone B -> Phone A so Phone B
      // receives 1..5, while Phone A only receives ACKs for 1..3:
      sockB.outboundFilter = (frame) {
        if (frame.type == WifiDirectFrameType.ack &&
            (frame.seq == 4 || frame.seq == 5)) {
          return false; // Simulate radio loss of ACK #4 and ACK #5
        }
        return true;
      };

      await phoneA.sendProbeBatch(
        userConsented: true,
        count: 5,
        interval: Duration.zero,
      );
      await Future<void>.delayed(Duration.zero);

      expect(phoneA.probesSentCount, 5);
      expect(phoneA.acksConfirmedCount, 3);
      expect(phoneA.unconfirmedProbesCount, 2);
      expect(phoneB.uniqueProbesDelivered, 5);
      expect(phoneB.duplicateProbesSuppressed, 0);

      // Inject 3 bogus ACKs into Phone A:
      // (1) wrong nonce for seq=4
      sockA.injectRawLine(
        WifiDirectSyntheticFrame.ack(
          senderNodeId: phoneB.localNodeId,
          ackForSenderNodeId: phoneA.localNodeId,
          seq: 4,
          nonce: '00000000000000000000000000000000',
          rxElapsedMs: 999,
        ).toJsonLine(),
      );
      // (2) unknown seq=99
      sockA.injectRawLine(
        WifiDirectSyntheticFrame.ack(
          senderNodeId: phoneB.localNodeId,
          ackForSenderNodeId: phoneA.localNodeId,
          seq: 99,
          nonce: '11111111111111111111111111111111',
          rxElapsedMs: 999,
        ).toJsonLine(),
      );
      // (3) wrong target node
      sockA.injectRawLine(
        WifiDirectSyntheticFrame.ack(
          senderNodeId: phoneB.localNodeId,
          ackForSenderNodeId: 'node-deadbeef',
          seq: 4,
          nonce: phoneA.sentProbes.firstWhere((p) => p.seq == 4).nonce,
          rxElapsedMs: 999,
        ).toJsonLine(),
      );

      // Confirm 0 false confirmations occurred!
      expect(phoneA.acksConfirmedCount, 3);
      expect(phoneA.unconfirmedProbesCount, 2);
      expect(phoneA.falseAcksRejected, 3);

      // Now simulate link drop (movement out of range):
      sockA.simulateLinkDrop('peer_out_of_range');
      sockB.simulateLinkDrop('peer_out_of_range');
      await Future<void>.delayed(Duration.zero);
      expect(phoneA.isSocketOpen, isFalse);
      expect(phoneB.isSocketOpen, isFalse);
      expect(phoneA.logs.last.kind, WifiDirectLabEventKind.disconnect);

      // Restore link (reconnection in range) and remove the ACK drop filter:
      sockB.outboundFilter = null;
      bridgeA.emit(<String, Object?>{
        'type': 'group_formed',
        'role': 'group_owner',
        'is_group_owner': true,
        'group_owner_host': '192.168.49.1',
        'client_count': 1,
      });
      bridgeB.emit(<String, Object?>{
        'type': 'group_formed',
        'role': 'client',
        'is_group_owner': false,
        'group_owner_host': '192.168.49.1',
        'client_count': 1,
      });
      await Future<void>.delayed(Duration.zero);
      expect(phoneA.isSocketOpen, isTrue);
      expect(phoneB.isSocketOpen, isTrue);

      // Resume on Phone A: retransmits unconfirmed seq 4 & 5 with original nonces,
      // then sends remaining seq 6..20:
      final resumed = await phoneA.resumeAfterReconnect(
        userConsented: true,
        targetTotalProbes: 20,
        interval: Duration.zero,
      );
      await Future<void>.delayed(Duration.zero);

      expect(resumed, 17); // 2 retransmitted (4, 5) + 15 new (6..20)
      expect(phoneA.probesSentCount, 20);
      expect(phoneA.acksConfirmedCount, 20);
      expect(phoneA.unconfirmedProbesCount, 0);

      // Phone B delivered exactly 20 unique probes and suppressed 2 duplicates (4 and 5):
      expect(phoneB.uniqueProbesDelivered, 20);
      expect(phoneB.duplicateProbesSuppressed, 2);
    });

    test('privacy guard and frame parser reject forbidden personal or network identifiers', () {
      expect(
        () => WifiDirectLabPrivacyGuard.sanitizeData(<String, Object?>{
          'mac_address': 'AA:BB:CC:DD:EE:FF',
        }),
        throwsFormatException,
      );
      expect(
        () => WifiDirectLabPrivacyGuard.sanitizeData(<String, Object?>{
          'lat': 45.1234,
          'lon': 10.5678,
        }),
        throwsFormatException,
      );
      expect(
        () => WifiDirectLabPrivacyGuard.sanitizeData(<String, Object?>{
          'ssid': 'DIRECT-xy-Phone',
        }),
        throwsFormatException,
      );

      final sanitized = WifiDirectLabPrivacyGuard.sanitizeData(<String, Object?>{
        'message':
            'Errore connessione a AA:BB:CC:DD:EE:FF su 192.168.49.1 rete DIRECT-AB-Test',
      });
      final msg = sanitized['message'] as String;
      expect(msg.contains('AA:BB:CC:DD:EE:FF'), isFalse);
      expect(msg.contains('192.168.49.1'), isFalse);
      expect(msg.contains('DIRECT-AB-Test'), isFalse);
      expect(WifiDirectLabPrivacyGuard.containsForbiddenIdentifiers(msg), isFalse);

      // Frame with extra coordinate field must fail closed:
      final illegalJson = jsonEncode(<String, Object?>{
        'v': 1,
        'type': 'probe',
        'sender': 'node-1234abcd',
        'seq': 1,
        'nonce': '0123456789abcdef0123456789abcdef',
        'synthetic_state': 'SYNTH_PROBE_OK',
        'elapsed_ms': 10,
        'lat': 45.0,
      });
      expect(
        () => WifiDirectSyntheticFrame.parseJsonLine(illegalJson),
        throwsFormatException,
      );
    });
  });

  group('Wi-Fi Direct Offline Lab — Isolated Widget UI & Lifecycle Cleanup', () {
    testWidgets('renders lab UI, enforces peer & probe consent dialogs, and cleans up on background/stop without touching BLE or GPS', (tester) async {
      final bridge = FakeWifiDirectPlatformBridge();
      final (sockA, sockB) = PairedInMemorySocketTransport.createPair();
      final controller = WifiDirectLabController(
        platform: bridge,
        socketTransport: sockA,
        random: Random(99),
      );
      // Configure peer responder on sockB to auto-ACK probes sent by UI:
      await sockB.startGroupOwnerServer(
        port: 41071,
        onSocketOpen: (_) {},
        onLineReceived: (line) {
          final frame = WifiDirectSyntheticFrame.parseJsonLine(line);
          if (frame.type == WifiDirectFrameType.probe) {
            final ack = WifiDirectSyntheticFrame.ack(
              senderNodeId: 'node-fedcba98',
              ackForSenderNodeId: frame.senderNodeId,
              seq: frame.seq,
              nonce: frame.nonce,
              rxElapsedMs: 50,
            );
            unawaited(sockB.sendJsonLine(ack.toJsonLine()));
          }
        },
        onSocketDisconnected: (_) {},
        onSocketError: (_, _) {},
      );

      await tester.pumpWidget(WifiDirectOfflineLabApp(controller: controller));
      await tester.pumpAndSettle();

      // Verify Outdoor +20 / BLE / GPS / FGS are completely untouched:
      expect(ConvoyMeshService.instance.isRunning, isFalse);
      expect(BackgroundRuntimeService.instance.isRunning, isFalse);
      expect(LocationFusionService.instance.last, isNull);
      expect(find.textContaining('Convoy Wi-Fi Direct LAB'), findsWidgets);
      expect(find.text('SPENTO (OK)'), findsOneWidget);

      // Tap Discover:
      final discoverBtn = find.byKey(const Key('wfd_discover_button'));
      await tester.ensureVisible(discoverBtn);
      await tester.tap(discoverBtn);
      await tester.pumpAndSettle();
      expect(bridge.discoverCalls, 1);

      // Emit synthetic peer-01:
      bridge.emit(<String, Object?>{
        'type': 'peers_updated',
        'peer_count': 1,
        'peers': [
          <String, Object?>{'peer_id': 'peer-01', 'status': 'available'},
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('Servizio Convoy rilevato (0)'), findsOneWidget);
      final otherDevices = find.byKey(const Key('wfd_other_p2p'));
      await tester.ensureVisible(otherDevices);
      await tester.tap(otherDevices);
      await tester.pumpAndSettle();
      expect(find.text('peer-01 (available)'), findsOneWidget);

      // Tap Connetti -> verify consent dialog appears and confirm:
      final connectBtn = find.byKey(const Key('wfd_connect_peer-01'));
      await tester.ensureVisible(connectBtn);
      await tester.tap(connectBtn);
      await tester.pumpAndSettle();
      expect(find.text('Conferma connessione a peer-01'), findsOneWidget);
      await tester.tap(find.byKey(const Key('wfd_confirm_connect_button')));
      await tester.pumpAndSettle();
      expect(bridge.connectCalls, 1);
      expect(bridge.lastConnectedPeerId, 'peer-01');
      expect(bridge.lastConnectConsented, isTrue);

      // Form P2P group -> opens socket:
      bridge.emit(<String, Object?>{
        'type': 'group_formed',
        'role': 'client',
        'is_group_owner': false,
        'group_owner_host': '192.168.49.1',
        'client_count': 1,
      });
      await tester.pumpAndSettle();
      expect(controller.isSocketOpen, isTrue);

      // Check probe consent checkbox and send 1 synthetic probe:
      final checkbox = find.byKey(const Key('wfd_probe_consent_checkbox'));
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      final sendOneBtn = find.byKey(const Key('wfd_send_single_probe_button'));
      await tester.ensureVisible(sendOneBtn);
      await tester.tap(sendOneBtn);
      await tester.pumpAndSettle();

      expect(controller.probesSentCount, 1);
      expect(controller.acksConfirmedCount, 1);

      // Simulate app moving to background -> must close socket and call stopAll:
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(controller.isSocketOpen, isFalse);
      expect(bridge.stopCalls, greaterThanOrEqualTo(1));
      expect(controller.logs.last.kind, WifiDirectLabEventKind.disconnect);

      controller.dispose();
      await bridge.dispose();
    });
    testWidgets('integrated Wi-Fi LAB stops P2P before returning to Outdoor route', (tester) async {
      final bridge = FakeWifiDirectPlatformBridge();
      final controller = WifiDirectLabController(platform: bridge, random: Random(727));
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => WifiDirectLabPage(
                  controller: controller, integratedMode: true,
                ),
              ),
            ),
            child: const Text('Open synthetic LAB'),
          ),
        )),
      ));
      await tester.tap(find.text('Open synthetic LAB'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wfd_return_to_outdoor')), findsOneWidget);
      expect(find.byKey(const Key('wfd_discover_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('wfd_return_to_outdoor')));
      await tester.pumpAndSettle();
      expect(find.text('Open synthetic LAB'), findsOneWidget);
      expect(find.byKey(const Key('wfd_return_to_outdoor')), findsNothing);
      expect(bridge.stopCalls, greaterThanOrEqualTo(1));
      expect(bridge.lastStopReason, isNotNull);
      expect(controller.isSocketOpen, isFalse);
      controller.dispose();
      await bridge.dispose();
    });
  });
 
  test('focus loss preserves pairing and the group, while hidden and paused stop', () async {
    for (final background in [AppLifecycleState.hidden, AppLifecycleState.paused]) {
      final bridge = FakeWifiDirectPlatformBridge();
      final (socket, _) = PairedInMemorySocketTransport.createPair();
      final controller = WifiDirectLabController(platform: bridge, socketTransport: socket);
      expect(await controller.requestDiscovery(), isTrue);
      bridge.emit({'type': 'peers_updated', 'peers': [{'peer_id': 'peer-01'}]});
      await Future<void>.delayed(Duration.zero);
      expect(await controller.requestConnect(peerId: 'peer-01', userConsented: true), isTrue);
      await controller.onAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(controller.isConnecting, isTrue);
      expect(controller.logs.last.data['connecting'], isTrue);
      expect(bridge.stopCalls, 0);

      bridge.emit({'type': 'group_formed', 'role': 'group_owner'});
      await Future<void>.delayed(Duration.zero);
      await controller.onAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(controller.isGroupFormed, isTrue);
      expect(controller.isSocketOpen, isTrue);
      expect(controller.logs.last.data['group_formed'], isTrue);
      expect(bridge.stopCalls, 0);

      await controller.onAppLifecycleStateChanged(background);
      expect(bridge.stopCalls, 1);
      expect(controller.isGroupFormed, isFalse);
      expect(controller.isSocketOpen, isFalse);
      expect(controller.logs.last.data['reason'], 'app_backgrounded_${background.name}');
      controller.dispose();
      await bridge.dispose();
    }
  });

  test('voluntary Convoy names are session-only, display-only and revocable', () async {
    SharedPreferences.setMockInitialValues({'my_name': 'Nome Origine Lungo'});
    final bridge = FakeWifiDirectPlatformBridge();
    final controller = WifiDirectLabController(platform: bridge);
    addTearDown(() async {
      controller.dispose();
      await bridge.dispose();
    });
    expect(controller.sharesConvoyName, isFalse);
    expect(await controller.requestDiscovery(), isTrue);
    expect(bridge.discoveryNames, [null]);
    await controller.setShareConvoyName(true);
    expect(controller.sharesConvoyName, isTrue);
    expect(bridge.advertisementChanges, ['Nome Origi']);
    expect(await controller.requestDiscovery(), isTrue);
    expect(bridge.discoveryNames.last, 'Nome Origi');

    bridge.emit({
      'type': 'peers_updated',
      'peers': [
        {'peer_id': 'peer-01', 'declared_name': 'Nome Finto'},
        {'peer_id': 'peer-02', 'declared_name': 'Nome Finto'},
        {'peer_id': 'peer-03'},
        {'peer_id': 'peer-04', 'declared_name': 'A\u202eB'},
      ],
    });
    await Future<void>.delayed(Duration.zero);
    expect(controller.peers.map((p) => p.declaredName), ['Nome Finto', 'Nome Finto', null, null]);
    expect(bridge.connectCalls, 0);
    bridge.emit({
      'type': 'dns_sd_status',
      'stage': 'txt',
      'outcome': 'received',
      'mapping': 'mapped',
      'txt_received': 2,
      'domain_matched': 2,
      'peer_mapped': 1,
      'declared_name': 'Nome Finto',
      'device_address': '00:00:00:00:00:00',
    });
    await Future<void>.delayed(Duration.zero);
    expect(controller.logs.last.data, {
      'stage': 'txt', 'outcome': 'received', 'mapping': 'mapped',
      'txt_received': 2, 'domain_matched': 2, 'peer_mapped': 1,
    });
    expect(controller.exportJsonl(), isNot(contains('Nome Finto')));
    expect(controller.exportJsonl(), isNot(contains('Nome Origi')));
    await controller.setShareConvoyName(false);
    expect(controller.sharesConvoyName, isFalse);
    expect(bridge.advertisementChanges, ['Nome Origi', null]);
    await controller.setShareConvoyName(true);
    await controller.stopAll();
    expect(controller.peers, isEmpty);
    expect(controller.sharesConvoyName, isFalse);
    expect(await controller.requestDiscovery(), isTrue);
    expect(bridge.discoveryNames.last, isNull);
  });

  test('Android group loss waits for teardown before a fresh discovery session', () async {
    final bridge = FakeWifiDirectPlatformBridge();
    final (socket, _) = PairedInMemorySocketTransport.createPair();
    final controller = WifiDirectLabController(platform: bridge, socketTransport: socket);
    addTearDown(() async {
      controller.dispose();
      await bridge.dispose();
    });
    expect(await controller.requestDiscovery(), isTrue);
    final oldSession = bridge.sessionId;
    bridge.emit({'type': 'group_formed', 'role': 'group_owner'});
    await Future<void>.delayed(Duration.zero);
    socket.simulateLinkDrop('socket_closed');
    bridge.stopReply = Completer<void>();
    bridge.emit({'type': 'p2p_disconnected', 'reason': 'p2p_group_lost'});
    await Future<void>.delayed(Duration.zero);
    expect(controller.logs.where((e) => e.kind == WifiDirectLabEventKind.disconnect)
      .map((e) => e.data['source']), ['socket', 'android_p2p']);
    expect(controller.isGroupFormed, isFalse);
    expect(bridge.stopCalls, 1);
    expect(bridge.lastStopReason, 'p2p_group_lost');
    expect(await controller.requestDiscovery(), isFalse);
    expect(bridge.discoverCalls, 1);
    final stopping = controller.stopAll();
    bridge.emit({'type': 'group_formed', 'role': 'group_owner', 'session_id': oldSession});
    await Future<void>.delayed(Duration.zero);
    expect(bridge.stopCalls, 1);
    expect(controller.isSocketOpen, isFalse);
    bridge.stopReply!.complete();
    await stopping;
    expect(await controller.requestDiscovery(), isTrue);
    expect(bridge.sessionId, isNot(oldSession));
    await controller.stopAll();
    expect(controller.logs.last.data['source'], 'local_stop');
    expect(controller.logs.last.data['reason'], 'manual_stop');
  });

  test('Stop drops queued peer, group and disconnect events across rediscovery', () async {
    final bridge = FakeWifiDirectPlatformBridge();
    final (socket, _) = PairedInMemorySocketTransport.createPair();
    final controller = WifiDirectLabController(platform: bridge, socketTransport: socket);
    addTearDown(() async {
      controller.dispose();
      await bridge.dispose();
    });
    Map<String, Object?> peers(String id) => {
      'type': 'peers_updated',
      'peers': [{'peer_id': id, 'status': 'available'}],
    };
    const group = {
      'type': 'group_formed',
      'role': 'group_owner',
      'client_count': 1,
    };

    expect(await controller.requestDiscovery(), isTrue);
    final old = bridge.sessionId;
    bridge.emit(peers('peer-01'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.peers.single.peerId, 'peer-01');

    bridge.emit(peers('peer-02'));
    bridge.emit(group);
    final stopping = controller.stopAll();
    bridge.emit(group);
    await stopping;
    expect(controller.peers, isEmpty);
    expect(controller.isGroupFormed, isFalse);
    expect(socket.boundPort, isNull);

    expect(await controller.requestDiscovery(), isTrue);
    expect(bridge.sessionId, isNot(old));
    bridge.emit({...peers('peer-02'), 'session_id': old});
    bridge.emit({...group, 'session_id': old});
    await Future<void>.delayed(Duration.zero);
    expect(controller.peers, isEmpty);
    expect(controller.isGroupFormed, isFalse);
    expect(socket.boundPort, isNull);
    expect(controller.logs.where((e) => e.kind == WifiDirectLabEventKind.groupFormed), isEmpty);

    bridge.emit(peers('peer-01'));
    bridge.emit(group);
    bridge.emit({'type': 'p2p_disconnected', 'session_id': old});
    await Future<void>.delayed(Duration.zero);
    expect(controller.peers.single.peerId, 'peer-01');
    expect(controller.isGroupFormed, isTrue);
    expect(socket.boundPort, isNotNull);
    expect(controller.logs.where((e) => e.kind == WifiDirectLabEventKind.groupFormed), hasLength(1));
  });

  test('Stop ignores old discovery and connect replies', () async {
    final bridge = FakeWifiDirectPlatformBridge();
    final controller = WifiDirectLabController(platform: bridge);
    addTearDown(() async {
      controller.dispose();
      await bridge.dispose();
    });
    final discoveryReply = Completer<void>();
    bridge.discoveryReply = discoveryReply;
    final oldDiscovery = controller.requestDiscovery();
    await Future<void>.delayed(Duration.zero);
    expect(bridge.discoverCalls, 1);
    await controller.stopAll();
    bridge.discoveryReply = null;
    expect(await controller.requestDiscovery(), isTrue);
    discoveryReply.completeError(StateError('stale discovery error'));
    expect(await oldDiscovery, isFalse);
    expect(controller.isDiscovering, isTrue);

    bridge.emit({
      'type': 'peers_updated',
      'peers': [{'peer_id': 'peer-01', 'status': 'available'}],
    });
    await Future<void>.delayed(Duration.zero);
    final connectReply = Completer<void>();
    bridge.connectReply = connectReply;
    final oldConnect = controller.requestConnect(peerId: 'peer-01', userConsented: true);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.connectCalls, 1);
    await controller.stopAll();
    expect(await controller.requestDiscovery(), isTrue);
    connectReply.complete();
    expect(await oldConnect, isFalse);
    expect(controller.isConnecting, isFalse);
    expect(controller.peers, isEmpty);
  });

  test('TCP Stop cancels a queued server bind', () async {
    final socket = TcpWifiDirectSocketTransport();
    final opening = socket.startGroupOwnerServer(
      port: 0,
      onSocketOpen: (_) => fail('stopped server opened a socket'),
      onLineReceived: (_) => fail('stopped server received data'),
      onSocketDisconnected: (_) {},
      onSocketError: (code, message) => fail('$code: $message'),
    );
    await socket.close();
    await opening;
    expect(socket.boundPort, isNull);
  });

  test('P2P pairing is serialized: no duplicate connect or discovery while connecting', () async {
    final bridge = FakeWifiDirectPlatformBridge();
    final controller = WifiDirectLabController(platform: bridge, random: Random(989));
    addTearDown(() async {
      controller.dispose();
      await bridge.dispose();
    });

    expect(await controller.requestDiscovery(), isTrue);
    bridge.emit(<String, Object?>{
      'type': 'peers_updated',
      'peer_count': 1,
      'peers': [
        <String, Object?>{'peer_id': 'peer-01', 'status': 'available'},
      ],
    });
    await Future<void>.delayed(const Duration(milliseconds: 15));

    expect(
      await controller.requestConnect(peerId: 'peer-01', userConsented: true),
      isTrue,
    );
    expect(controller.isConnecting, isTrue);
    expect(
      await controller.requestConnect(peerId: 'peer-01', userConsented: true),
      isFalse,
    );
    expect(await controller.requestDiscovery(), isFalse);
    expect(bridge.connectCalls, 1);
    expect(bridge.discoverCalls, 1);
    expect(controller.logs.last.data['code'], 'P2P_CONNECTION_ACTIVE');

    await controller.stopAll(reason: 'test_done');
    expect(controller.isConnecting, isFalse);
    expect(bridge.stopCalls, greaterThanOrEqualTo(1));
  });

}
