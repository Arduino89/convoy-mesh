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
        'manager.removeGroup(channel, null)',
        'channel.close()',
        'app.unregisterReceiver(receiver)',
      ]),
    );
  });
}

String _method(String source, String name) {
  final start = source.indexOf('    private fun $name(');
  return source.substring(start, source.indexOf('\n    }', start));
}
