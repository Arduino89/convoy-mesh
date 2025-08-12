import 'dart:async';
import 'dart:math';
import 'package:uuid/uuid.dart';

// MVP stub: This simulates BLE mesh updates for local testing.
// On device, replace with flutter_reactive_ble advertising/scanning.
// We'll expose a simple API: joinRoom, leaveRoom, broadcast(position), stream of peer positions.

class PeerPosition {
  final String nodeId;
  final double lat;
  final double lon;
  final DateTime seenAt;
  final int hops; // number of relays
  PeerPosition(this.nodeId, this.lat, this.lon, this.seenAt, this.hops);
}

class BleMeshService {
  final _uuid = const Uuid();
  final _peersController = StreamController<List<PeerPosition>>.broadcast();
  Stream<List<PeerPosition>> get peersStream => _peersController.stream;

  String? _roomCode;
  String? _nodeId;
  Timer? _simTimer;

  // Local cache of peers (would be fed by BLE in real app)
  final Map<String, PeerPosition> _peers = {};

  Future<String> joinRoom(String roomCode, {String? nodeId}) async {
    _roomCode = roomCode;
    _nodeId = nodeId ?? _uuid.v4().substring(0, 8);
    // Start simulation for now
    _startSimulation();
    return _nodeId!;
  }

  Future<void> leaveRoom() async {
    _roomCode = null;
    _peers.clear();
    _peersController.add([]);
    _simTimer?.cancel();
    _simTimer = null;
  }

  void broadcastSelf(double lat, double lon) {
    if (_roomCode == null || _nodeId == null) return;
    // In real BLE mode, advertise encrypted payload here.
    // For now, inject self into peers list (hops=0) so the UI shows your marker too.
    _peers[_nodeId!] = PeerPosition(_nodeId!, lat, lon, DateTime.now(), 0);
    _peersController.add(_peers.values.toList());
  }

  void _startSimulation() {
    _simTimer?.cancel();
    final rnd = Random();
    _simTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_roomCode == null) return;
      // Generate 2 fake peers around (0,0) for demo; UI will reposition once GPS arrives.
      final now = DateTime.now();
      final peers = List.generate(2, (i) {
        final nid = 'peer${i+1}';
        final lat = 45.1 + rnd.nextDouble()/100; // Mantova-ish, for fun
        final lon = 10.7 + rnd.nextDouble()/100;
        return PeerPosition(nid, lat, lon, now, 1 + i);
      });
      for (final p in peers) {
        _peers[p.nodeId] = p;
      }
      _peersController.add(_peers.values.toList());
    });
  }

  void dispose() {
    _peersController.close();
    _simTimer?.cancel();
  }
}
