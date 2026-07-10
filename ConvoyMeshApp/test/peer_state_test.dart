import 'package:convoy_mesh/services/convoy_mesh_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PeerState', () {
    test('markHeard updates raw activity without making peer online', () {
      final peer = PeerState(userId: 123);
      final heardAt = DateTime.now();

      peer.markHeard(now: heardAt, rssi: -67, address: 'AA:BB:CC');

      expect(peer.lastHeardAt, heardAt);
      expect(peer.rssi, -67);
      expect(peer.lastAddress, 'AA:BB:CC');
      expect(peer.lastSeen, DateTime.fromMillisecondsSinceEpoch(0));
      expect(ConvoyMeshService.isPeerOnline(peer), isFalse);
    });

    test('online status is based on last valid packet only', () {
      final peer = PeerState(userId: 123);

      peer.lastSeen = DateTime.now().subtract(
        ConvoyMeshService.peerOnlineTtl - const Duration(seconds: 1),
      );
      expect(ConvoyMeshService.isPeerOnline(peer), isTrue);

      peer.lastSeen = DateTime.now().subtract(
        ConvoyMeshService.peerOnlineTtl + const Duration(seconds: 1),
      );
      expect(ConvoyMeshService.isPeerOnline(peer), isFalse);
    });

    test('fresh fix requires coordinates and recent valid fix timestamp', () {
      final peer = PeerState(userId: 123)
        ..lat = 45.0
        ..lon = 10.0
        ..lastFixSeen = DateTime.now();

      expect(peer.hasFix, isTrue);
      expect(peer.hasFreshFix, isTrue);

      peer.lastFixSeen = DateTime.now().subtract(
        ConvoyMeshService.peerOnlineTtl + const Duration(seconds: 1),
      );
      expect(peer.hasFreshFix, isFalse);

      peer.lat = null;
      expect(peer.hasFix, isFalse);
      expect(peer.hasFreshFix, isFalse);
    });

    test('trail ignores low accuracy and tiny jitter but records real movement', () {
      final peer = PeerState(userId: 123)
        ..lat = 45.000000
        ..lon = 10.000000
        ..accuracyM = 5;

      peer.addPointIfValid(retention: const Duration(minutes: 90));
      expect(peer.trail, hasLength(1));

      // About 1.1 m north: below max(3m, accuracy * 0.35).
      peer
        ..lat = 45.000010
        ..lon = 10.000000
        ..accuracyM = 5;
      peer.addPointIfValid(retention: const Duration(minutes: 90));
      expect(peer.trail, hasLength(1));

      // About 11 m north: should be recorded.
      peer
        ..lat = 45.000100
        ..lon = 10.000000
        ..accuracyM = 5;
      peer.addPointIfValid(retention: const Duration(minutes: 90));
      expect(peer.trail, hasLength(2));

      // Bad accuracy should not add a point even if coordinates changed.
      peer
        ..lat = 45.001000
        ..lon = 10.000000
        ..accuracyM = 120;
      peer.addPointIfValid(retention: const Duration(minutes: 90));
      expect(peer.trail, hasLength(2));
    });

    test('distanceMeters is approximately correct for latitude deltas', () {
      final distance = PeerState.distanceMeters(45.0, 10.0, 45.001, 10.0);
      expect(distance, closeTo(111.2, 1.0));
    });
  });

  group('pedestrian peer movement validation', () {
    final start = DateTime(2026, 7, 10, 9);

    test('accepts normal walking movement', () {
      final plausible = ConvoyMeshService.isPeerMovementPlausible(
        previousLat: 45.000000,
        previousLon: 10.000000,
        previousAccuracyM: 8,
        previousAt: start,
        nextLat: 45.000100,
        nextLon: 10.000000,
        nextAccuracyM: 8,
        nextAt: start.add(const Duration(seconds: 10)),
      );

      expect(plausible, isTrue);
    });

    test('rejects a teleport even when both fixes claim good accuracy', () {
      final plausible = ConvoyMeshService.isPeerMovementPlausible(
        previousLat: 45.000000,
        previousLon: 10.000000,
        previousAccuracyM: 5,
        previousAt: start,
        nextLat: 45.010000,
        nextLon: 10.000000,
        nextAccuracyM: 5,
        nextAt: start.add(const Duration(seconds: 5)),
      );

      expect(plausible, isFalse);
    });

    test('allows movement that fits the uncertainty of weak outdoor fixes', () {
      final plausible = ConvoyMeshService.isPeerMovementPlausible(
        previousLat: 45.000000,
        previousLon: 10.000000,
        previousAccuracyM: 40,
        previousAt: start,
        nextLat: 45.000270,
        nextLon: 10.000000,
        nextAccuracyM: 50,
        nextAt: start.add(const Duration(seconds: 10)),
      );

      expect(plausible, isTrue);
    });

    test('rejects a large weak-accuracy jump beyond uncertainty margin', () {
      final plausible = ConvoyMeshService.isPeerMovementPlausible(
        previousLat: 45.000000,
        previousLon: 10.000000,
        previousAccuracyM: 35,
        previousAt: start,
        nextLat: 45.003000,
        nextLon: 10.000000,
        nextAccuracyM: 45,
        nextAt: start.add(const Duration(seconds: 10)),
      );

      expect(plausible, isFalse);
    });
  });
}
