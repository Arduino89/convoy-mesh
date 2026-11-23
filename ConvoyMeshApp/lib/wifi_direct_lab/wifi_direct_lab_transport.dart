import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'wifi_direct_lab_models.dart';

/// Platform abstraction over the native Android [WifiP2pManager] adapter.
abstract class WifiDirectPlatformBridge {
  Stream<Map<String, Object?>> get events;

  Future<WifiDirectEnvironmentStatus> getEnvironmentStatus();
  Future<WifiDirectEnvironmentStatus> requestRequiredPermission();
  Future<void> openWifiSettings();
  Future<void> openBluetoothSettings();
  Future<void> openLocationSettings();
  Future<void> openAppSettings();
  Future<void> discoverPeers({required String sessionId});
  Future<void> connectPeer({
    required String sessionId,
    required String peerId,
    required bool userConsented,
  });
  Future<void> stopAll({required String? sessionId, String reason = 'manual_stop'});
}

/// Production [MethodChannel] + [EventChannel] bridge to
/// `ConvoyWifiDirectLabAdapter.kt`.
class MethodChannelWifiDirectPlatformBridge implements WifiDirectPlatformBridge {
  MethodChannelWifiDirectPlatformBridge({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _method =
            methodChannel ?? const MethodChannel('convoy_mesh/wifi_direct_lab'),
        _events = eventChannel ??
            const EventChannel('convoy_mesh/wifi_direct_lab_events');

  final MethodChannel _method;
  final EventChannel _events;
  Stream<Map<String, Object?>>? _cachedStream;

  @override
  Stream<Map<String, Object?>> get events {
    return _cachedStream ??= _events.receiveBroadcastStream().map((dynamic raw) {
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), v as Object?));
      }
      return const <String, Object?>{};
    });
  }

  @override
  Future<WifiDirectEnvironmentStatus> getEnvironmentStatus() async {
    final raw =
        await _method.invokeMapMethod<Object?, Object?>('getEnvironmentStatus');
    return WifiDirectEnvironmentStatus.fromMap(raw ?? const {});
  }

  @override
  Future<WifiDirectEnvironmentStatus> requestRequiredPermission() async {
    final raw = await _method
        .invokeMapMethod<Object?, Object?>('requestRequiredPermission');
    return WifiDirectEnvironmentStatus.fromMap(raw ?? const {});
  }

  @override
  Future<void> openWifiSettings() async {
    await _method.invokeMethod<bool>('openWifiSettings');
  }

  @override
  Future<void> openBluetoothSettings() async {
    await _method.invokeMethod<bool>('openBluetoothSettings');
  }

  @override
  Future<void> openLocationSettings() async {
    await _method.invokeMethod<bool>('openLocationSettings');
  }

  @override
  Future<void> openAppSettings() async {
    await _method.invokeMethod<bool>('openAppSettings');
  }

  @override
  Future<void> discoverPeers({required String sessionId}) async {
    await _method.invokeMapMethod<String, Object?>(
      'discoverPeers',
      <String, Object?>{'sessionId': sessionId},
    );
  }

  @override
  Future<void> connectPeer({
    required String sessionId,
    required String peerId,
    required bool userConsented,
  }) async {
    await _method.invokeMapMethod<String, Object?>(
      'connectPeer',
      <String, Object?>{
        'sessionId': sessionId,
        'peerId': peerId,
        'userConsented': userConsented,
      },
    );
  }

  @override
  Future<void> stopAll({required String? sessionId, String reason = 'manual_stop'}) async {
    await _method.invokeMethod<bool>(
      'stopAll',
      <String, Object?>{'sessionId': sessionId, 'reason': reason},
    );
  }
}

/// Full-duplex local socket abstraction used once a Wi-Fi Direct group forms.
abstract class WifiDirectSocketTransport {
  bool get isSocketOpen;
  int? get boundPort;

  Future<void> startGroupOwnerServer({
    required int port,
    required void Function(int port) onSocketOpen,
    required void Function(String line) onLineReceived,
    required void Function(String reason) onSocketDisconnected,
    required void Function(String code, String message) onSocketError,
  });

  Future<void> connectAsClient({
    required String host,
    required int port,
    required void Function(int port) onSocketOpen,
    required void Function(String line) onLineReceived,
    required void Function(String reason) onSocketDisconnected,
    required void Function(String code, String message) onSocketError,
  });

  Future<void> sendJsonLine(String jsonLine);
  Future<void> close();
}

/// Real `dart:io` TCP [ServerSocket] / [Socket] transport over the Wi-Fi Direct
/// P2P interface (or local loopback in automated multi-node tests).
class TcpWifiDirectSocketTransport implements WifiDirectSocketTransport {
  TcpWifiDirectSocketTransport({
    this.defaultBindHost = '0.0.0.0',
    this.clientConnectTimeout = const Duration(seconds: 3),
    this.clientMaxAttempts = 8,
    this.clientRetryDelay = const Duration(milliseconds: 350),
  });

  static const int defaultLabPort = 41071;

  final String defaultBindHost;
  final Duration clientConnectTimeout;
  final int clientMaxAttempts;
  final Duration clientRetryDelay;

  ServerSocket? _serverSocket;
  Socket? _activeSocket;
  StreamSubscription<Socket>? _serverSub;
  StreamSubscription<List<int>>? _socketSub;
  int? _boundPort;
  int _epoch = 0;

  @override
  bool get isSocketOpen => _activeSocket != null;

  @override
  int? get boundPort => _boundPort;

  @override
  Future<void> startGroupOwnerServer({
    required int port,
    required void Function(int port) onSocketOpen,
    required void Function(String line) onLineReceived,
    required void Function(String reason) onSocketDisconnected,
    required void Function(String code, String message) onSocketError,
  }) async {
    final closing = close();
    final myEpoch = _epoch;
    await closing;
    if (myEpoch != _epoch) return;
    try {
      final server = await ServerSocket.bind(
        defaultBindHost,
        port,
        shared: true,
      );
      if (myEpoch != _epoch) {
        await server.close();
        return;
      }
      _serverSocket = server;
      _boundPort = server.port;
      _serverSub = server.listen(
        (Socket client) {
          if (myEpoch != _epoch) {
            client.destroy();
            return;
          }
          _attachActiveSocket(
            socket: client,
            epoch: myEpoch,
            port: server.port,
            onSocketOpen: onSocketOpen,
            onLineReceived: onLineReceived,
            onSocketDisconnected: onSocketDisconnected,
            onSocketError: onSocketError,
          );
        },
        onError: (Object error) {
          if (myEpoch == _epoch) {
            onSocketError('SERVER_SOCKET_ERROR', error.toString());
          }
        },
      );
    } catch (e) {
      if (myEpoch == _epoch) {
        onSocketError('SERVER_BIND_FAILED', e.toString());
      }
    }
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
    final closing = close();
    final myEpoch = _epoch;
    await closing;
    if (myEpoch != _epoch) return;
    final cleanHost = host.trim();
    if (cleanHost.isEmpty || port <= 0) {
      onSocketError('INVALID_GROUP_OWNER_ENDPOINT', 'Indirizzo Group Owner o porta non validi');
      return;
    }

    Object? lastError;
    for (var attempt = 1; attempt <= clientMaxAttempts; attempt++) {
      if (myEpoch != _epoch) return;
      try {
        final socket = await Socket.connect(
          cleanHost,
          port,
          timeout: clientConnectTimeout,
        );
        if (myEpoch != _epoch) {
          socket.destroy();
          return;
        }
        _boundPort = port;
        _attachActiveSocket(
          socket: socket,
          epoch: myEpoch,
          port: port,
          onSocketOpen: onSocketOpen,
          onLineReceived: onLineReceived,
          onSocketDisconnected: onSocketDisconnected,
          onSocketError: onSocketError,
        );
        return;
      } catch (e) {
        lastError = e;
        if (attempt < clientMaxAttempts && myEpoch == _epoch) {
          await Future<void>.delayed(clientRetryDelay);
        }
      }
    }
    if (myEpoch == _epoch) {
      onSocketError(
        'CLIENT_CONNECT_FAILED',
        'Connessione socket TCP al Group Owner fallita dopo $clientMaxAttempts tentativi: ${lastError ?? "timeout"}',
      );
    }
  }

  void _attachActiveSocket({
    required Socket socket,
    required int epoch,
    required int port,
    required void Function(int port) onSocketOpen,
    required void Function(String line) onLineReceived,
    required void Function(String reason) onSocketDisconnected,
    required void Function(String code, String message) onSocketError,
  }) {
    _socketSub?.cancel();
    _activeSocket?.destroy();
    socket.setOption(SocketOption.tcpNoDelay, true);
    _activeSocket = socket;

    final buffer = StringBuffer();
    var notifiedDisconnect = false;

    void reportDisconnect(String reason) {
      if (notifiedDisconnect || epoch != _epoch) return;
      notifiedDisconnect = true;
      if (identical(_activeSocket, socket)) {
        _activeSocket = null;
      }
      onSocketDisconnected(reason);
    }

    _socketSub = socket.listen(
      (List<int> chunk) {
        if (epoch != _epoch) return;
        String decoded;
        try {
          decoded = utf8.decode(chunk, allowMalformed: false);
        } catch (_) {
          onSocketError('SOCKET_UTF8_INVALID', 'Dati non UTF-8 ricevuti sul socket');
          return;
        }
        buffer.write(decoded);
        if (buffer.length > WifiDirectSyntheticFrame.maxWireBytes * 8) {
          buffer.clear();
          onSocketError(
            'SOCKET_FRAME_TOO_LARGE',
            'Riga ricevuta oltre il limite massimo consentito',
          );
          return;
        }
        final current = buffer.toString();
        final lines = current.split('\n');
        buffer.clear();
        buffer.write(lines.removeLast());
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            onLineReceived(trimmed);
          }
        }
      },
      onError: (Object error) {
        if (epoch != _epoch) return;
        onSocketError('SOCKET_STREAM_ERROR', error.toString());
        reportDisconnect('socket_stream_error');
      },
      onDone: () {
        reportDisconnect('remote_socket_closed');
      },
      cancelOnError: false,
    );

    onSocketOpen(port);
  }

  @override
  Future<void> sendJsonLine(String jsonLine) async {
    final socket = _activeSocket;
    if (socket == null) {
      throw const SocketException('Socket TCP Wi-Fi Direct non aperto');
    }
    final normalized = jsonLine.endsWith('\n') ? jsonLine : '$jsonLine\n';
    socket.add(utf8.encode(normalized));
    await socket.flush();
  }

  @override
  Future<void> close() async {
    _epoch++;
    final sub = _socketSub;
    final sock = _activeSocket;
    final srvSub = _serverSub;
    final srv = _serverSocket;
    _socketSub = null;
    _activeSocket = null;
    _serverSub = null;
    _serverSocket = null;
    _boundPort = null;
    try {
      sock?.destroy();
    } catch (_) {}
    await sub?.cancel();
    await srvSub?.cancel();
    try {
      await srv?.close();
    } catch (_) {}
  }
}
