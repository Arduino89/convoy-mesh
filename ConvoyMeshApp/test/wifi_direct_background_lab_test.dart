import 'package:convoy_mesh/wifi_direct_lab/wifi_direct_lab_controller.dart';
import 'package:convoy_mesh/wifi_direct_lab/wifi_direct_lab_pairing.dart';
import 'package:convoy_mesh/wifi_direct_lab/wifi_direct_lab_transport.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wifi_direct_offline_lab_test.dart' show FakeWifiDirectPlatformBridge;

class _BackgroundBridge extends FakeWifiDirectPlatformBridge
    implements WifiDirectBackgroundBridge {
  @override
  Future<bool> startBackgroundLab(String id) async {
    sessionId = id;
    return true;
  }
}

Future<void> _until(bool Function() ready, String description) async {
  final clock = Stopwatch()..start();
  while (!ready() && clock.elapsed < const Duration(seconds: 16)) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  expect(ready(), isTrue, reason: description);
}

void main() {
  test(
    'LAB proof rejects wrong codes, reflection, replay and modified data',
    () {
      final code = WifiDirectLabPairing.newCode();
      WifiDirectLabPairing owner() =>
          WifiDirectLabPairing(code, owner: true, localNode: 'node-00000001');
      WifiDirectLabPairing client([String? other]) => WifiDirectLabPairing(
        other ?? code,
        owner: false,
        localNode: 'node-00000002',
      );
      final group = owner();
      final peer = client();
      final groupProof = group.receive(peer.hello).reply!;
      final peerProof = peer.receive(group.hello).reply!;
      expect(() => group.receive(groupProof), throwsFormatException);
      group.receive(peerProof);
      peer.receive(groupProof);

      final message = group.seal('synthetic probe');
      expect(() => peer.receive('${message}changed'), throwsFormatException);
      expect(peer.receive(message).payload, 'synthetic probe');
      expect(() => peer.receive(message), throwsFormatException);

      final nextGroup = owner();
      final nextPeer = client();
      final nextGroupProof = nextGroup.receive(nextPeer.hello).reply!;
      final nextPeerProof = nextPeer.receive(nextGroup.hello).reply!;
      expect(() => nextGroup.receive(peerProof), throwsFormatException);
      nextGroup.receive(nextPeerProof);
      nextPeer.receive(nextGroupProof);
      expect(() => nextPeer.receive(message), throwsFormatException);

      final stranger = client(WifiDirectLabPairing.newCode());
      final anotherGroup = owner();
      anotherGroup.receive(stranger.hello);
      final strangerProof = stranger.receive(anotherGroup.hello).reply!;
      expect(() => anotherGroup.receive(strangerProof), throwsFormatException);
      expect(() => anotherGroup.seal('synthetic probe'), throwsStateError);
    },
  );

  test('background TCP probes, same-peer radio recovery and Stop', () async {
    final a = _BackgroundBridge();
    final b = _BackgroundBridge();
    final tcpA = TcpWifiDirectSocketTransport();
    final tcpB = TcpWifiDirectSocketTransport();
    final owner = WifiDirectLabController(platform: a, socketTransport: tcpA);
    final client = WifiDirectLabController(platform: b, socketTransport: tcpB);
    addTearDown(() async {
      owner.dispose();
      client.dispose();
      await a.dispose();
      await b.dispose();
    });

    final code = WifiDirectLabPairing.newCode();
    expect(await owner.startBackgroundLab(code), isTrue);
    expect(await client.startBackgroundLab(code), isTrue);
    await owner.requestDiscovery();
    await client.requestDiscovery();

    void peers(_BackgroundBridge bridge, String alias) => bridge.emit({
      'type': 'peers_updated',
      'peers': [
        {'peer_id': alias, 'status': 'available'},
      ],
    });
    peers(a, 'peer-01');
    await _until(() => owner.peers.isNotEmpty, 'first Android discovery');
    expect(
      await owner.requestConnect(peerId: 'peer-01', userConsented: true),
      isTrue,
    );

    Future<void> formGroup() async {
      a.emit({
        'type': 'group_formed',
        'role': 'group_owner',
        'group_owner_host': '127.0.0.1',
        'port': 0,
      });
      await _until(() => tcpA.boundPort != null, 'owner listens on loopback');
      b.emit({
        'type': 'group_formed',
        'role': 'client',
        'group_owner_host': '127.0.0.1',
        'port': tcpA.boundPort,
      });
      await _until(
        () => owner.isSocketOpen && client.isSocketOpen,
        'peer proof accepted',
      );
    }

    await formGroup();
    await owner.onAppLifecycleStateChanged(AppLifecycleState.paused);
    await client.onAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(
      await owner.sendProbeBatch(
        userConsented: true,
        count: 5,
        interval: Duration.zero,
      ),
      5,
    );
    await _until(
      () => owner.acksConfirmedCount >= 5,
      'verified ACKs while hidden',
    );
    expect(owner.quality.label, 'Stabile');
    expect(owner.quality.ackPercentage, 100);

    a.emit({'type': 'p2p_disconnected', 'reason': 'p2p_group_lost'});
    b.emit({'type': 'p2p_disconnected', 'reason': 'p2p_group_lost'});
    await _until(
      () => a.discoverCalls >= 2 && b.discoverCalls >= 2,
      'recovery scans on both peers',
    );
    peers(a, 'peer-02');
    await _until(
      () => a.discoverCalls >= 3,
      'initiator searches again instead of choosing another alias',
    );
    expect(a.connectCalls, 1);
    expect(b.connectCalls, 0);
    peers(a, 'peer-01');
    await _until(
      () => a.connectCalls == 2,
      'initiator reuses the previously approved alias',
    );
    expect(a.lastConnectedPeerId, 'peer-01');
    expect(b.connectCalls, 0);
    await formGroup();
    expect(await client.sendSingleProbe(userConsented: true), isTrue);
    await _until(
      () => client.acksConfirmedCount > 0,
      'application delivery after recovery',
    );
    expect(owner.quality.interruptions, 1);
    expect(owner.exportJsonl(), isNot(contains(code)));
    expect(owner.exportJsonl(), isNot(contains('L1A:')));

    final oldId = a.sessionId;
    a.emit({'type': 'p2p_disconnected', 'reason': 'p2p_group_lost'});
    await _until(
      () => !owner.isGroupFormed,
      'second outage starts before Stop',
    );
    await owner.stopAll();
    b.emit({
      'type': 'p2p_disconnected',
      'reason': 'notification_stop',
      'session_ended': true,
    });
    await _until(
      () => !client.isBackgroundLab,
      'notification Stop ends the passive side',
    );
    final discoveryCount = a.discoverCalls;
    a.emit({
      'type': 'group_formed',
      'role': 'group_owner',
      'session_id': oldId,
    });
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    expect(a.discoverCalls, discoveryCount);
    expect(owner.isSocketOpen, isFalse);
    expect(client.isSocketOpen, isFalse);
    expect(owner.isBackgroundLab, isFalse);
  }, timeout: const Timeout(Duration(seconds: 38)));
}
