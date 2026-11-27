import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'wifi_direct_lab_models.dart';

/// In-memory proof of possession for one explicitly shared LAB code.
/// This authenticates synthetic traffic. It is not a confidential channel.
class WifiDirectLabPairing {
  WifiDirectLabPairing(
    String code, {
    required this.owner,
    required this.localNode,
    this.initiated = false,
  }) : _mac = Hmac(sha256, ascii.encode(code)),
       _local = newCode();

  static final _hex128 = RegExp(r'^[0-9a-f]{32}$');
  static bool isCode(String value) => _hex128.hasMatch(value);
  static String newCode() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  final bool owner;
  final String localNode;
  final bool initiated;
  String? remoteNode;
  bool remoteInitiated = false;
  final Hmac _mac;
  final String _local;
  String? _remote;
  bool verified = false;
  int _sent = 0;
  int _received = 0;

  String get hello => 'L1H:$_local:$localNode:${initiated ? 1 : 0}';
  String _tag(String body) => _mac.convert(utf8.encode(body)).toString();
  String _direction(bool outgoing) => owner == outgoing ? 'G' : 'C';
  String _transcript(bool outgoing) =>
      'LAB27:${_direction(outgoing)}:'
      '${outgoing ? _local : _remote}:${outgoing ? _remote : _local}:'
      '${outgoing ? localNode : remoteNode}:${outgoing ? remoteNode : localNode}:'
      '${outgoing ? initiated : remoteInitiated}:${outgoing ? remoteInitiated : initiated}';

  bool _matches(String supplied, String expected) {
    if (supplied.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < supplied.length; i++) {
      difference |= supplied.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }

  /// Returns a reply to send, a verified payload to process, or neither
  /// on acceptance of the peer proof. A malformed line is fatal to this socket.
  ({String? reply, String? payload}) receive(String line) {
    if (!verified && _remote == null && line.startsWith('L1H:')) {
      final parts = line.substring(4).split(':');
      if (parts.length != 3 ||
          !const {'0', '1'}.contains(parts[2]) ||
          !_hex128.hasMatch(parts[0]) ||
          parts[0] == _local ||
          !WifiDirectSyntheticFrame.validSyntheticNodeId(parts[1]) ||
          parts[1] == localNode) {
        throw const FormatException('LAB hello non valido');
      }
      _remote = parts[0];
      remoteNode = parts[1];
      remoteInitiated = parts[2] == '1';
      return (reply: 'L1A:${_tag(_transcript(true))}', payload: null);
    }
    if (!verified &&
        _remote != null &&
        line.startsWith('L1A:') &&
        _matches(line.substring(4), _tag(_transcript(false)))) {
      verified = true;
      return (reply: null, payload: null);
    }
    if (verified && line.startsWith('L1D:') && line.length > 69) {
      final suppliedTag = line.substring(4, 68);
      final payload = line.substring(69);
      if (line[68] == ':' &&
          _matches(
            suppliedTag,
            _tag('${_transcript(false)}:${_received + 1}:$payload'),
          )) {
        _received++;
        return (reply: null, payload: payload);
      }
    }
    throw const FormatException('Prova LAB non valida');
  }

  String seal(String payload) {
    if (!verified) throw StateError('Peer LAB non autorizzato');
    final tag = _tag('${_transcript(true)}:${++_sent}:$payload');
    return 'L1D:$tag:$payload';
  }
}
