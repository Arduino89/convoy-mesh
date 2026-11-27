import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final adapter = File(
    'android/app/src/main/kotlin/com/example/convoy_mesh/'
    'ConvoyWifiDirectLabAdapter.kt',
  ).readAsStringSync();

  // The Flutter bridge fakes cannot observe calls inside WifiP2pManager.
  // Guard the native call sequence here without requiring a Wi-Fi P2P radio.
  test('native connect leaves discovery teardown to Android', () {
    final connect = _method(adapter, 'handleConnectPeer');

    expect(connect, contains(RegExp(r'\bmanager\.connect\s*\(')));
    expect(connect, isNot(contains(RegExp(r'\.stopPeerDiscovery\s*\('))));
  });

  test('native Stop cancels the pending reply and requests P2P cleanup', () {
    final stop = _method(adapter, 'stopAllInternal');

    expect(
      stop,
      stringContainsInOrder([
        'p2pSession?.invalidate()',
        'pendingDiscoverResult?.error("DISCOVERY_CANCELLED"',
        'pendingConnectResult?.error("CONNECT_CANCELLED"',
        'pendingConnectResult = null',
        'manager.stopPeerDiscovery(channel, null)',
        'manager.cancelConnect(channel, null)',
        'manager.removeGroup(channel, it)',
      ]),
    );
    expect(stop, contains('app.unregisterReceiver(receiver)'));
    expect(stop, contains('channel?.close()'));
    expect(stop, contains(') { _, _ -> finish() }'));
  });

  test('native discovery sets up the name before selecting one scan path', () {
    final discover = _method(adapter, 'handleDiscoverPeers');
    expect(discover, stringContainsInOrder([
      'pendingDiscoverResult = result',
      'updateNameAdvertisement(',
      'discoverConvoyNames(',
      'if (outcome == "timed_out")',
      'endSession(session, "dns_sd_callback_timed_out")',
      'else if (outcome == "accepted" || !current())',
      'manager.discoverPeers(channel, it)',
    ]));
    final advertise = _method(adapter, 'updateNameAdvertisement');
    expect(advertise, isNot(contains('clearLocalServices(')));
    expect(advertise, contains('manager.removeLocalService('));
    final peers = _method(adapter, 'requestCurrentPeers');
    expect(peers, isNot(contains('discoverConvoyNames(')));
  });
}

String _method(String source, String name) {
  final start = source.indexOf('    private fun $name(');
  return source.substring(start, source.indexOf('\n    }', start));
}
