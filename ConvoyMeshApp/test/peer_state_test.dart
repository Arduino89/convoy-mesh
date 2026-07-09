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
}
