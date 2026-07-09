import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class PeerTrack {
  final String id;
  final Color color;
  final List<LatLng> points = [];
  DateTime? lastTs;

  PeerTrack({required this.id, required this.color});
}

class PeersStore extends ChangeNotifier {
  final Map<String, PeerTrack> _peers = {};
  Map<String, PeerTrack> get peers => _peers;

  // palette semplice
  static const _palette = <Color>[
    Colors.cyan,
    Colors.orange,
    Colors.pink,
    Colors.lime,
    Colors.purple,
    Colors.teal,
    Colors.amber,
    Colors.indigo,
  ];

  Color _colorFor(String id) {
    final h = id.codeUnits.fold<int>(0, (a, b) => a + b);
    return _palette[h % _palette.length];
  }

  void upsertPeerFix({
    required String peerId,
    required LatLng latLng,
    required DateTime ts,
    double minDeltaM = 6,
  }) {
    final peer = _peers.putIfAbsent(
      peerId,
          () => PeerTrack(id: peerId, color: _colorFor(peerId)),
    );

    if (peer.points.isNotEmpty) {
      final last = peer.points.last;
      final dist = const Distance().as(LengthUnit.Meter, last, latLng);
      if (dist < minDeltaM) return; // anti-jitter anche per peer
    }

    peer.points.add(latLng);
    peer.lastTs = ts;
    notifyListeners();
  }

  /// Solo per test: genera 1-2 peer finti attorno a te.
  void demoFromMyPosition(LatLng me) {
    final now = DateTime.now();
    final r = Random();

    for (final id in ["FRAN", "PEER2"]) {
      final dx = (r.nextDouble() - 0.5) * 0.001; // ~100m
      final dy = (r.nextDouble() - 0.5) * 0.001;
      upsertPeerFix(
        peerId: id,
        latLng: LatLng(me.latitude + dx, me.longitude + dy),
        ts: now,
      );
    }
  }

  void clear() {
    _peers.clear();
    notifyListeners();
  }
}
