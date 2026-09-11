import 'package:convoy_mesh/ble/convoy_ble_codec.dart';
import 'package:convoy_mesh/services/convoy_mesh_service.dart';
import 'package:convoy_mesh/services/location_fusion_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HISTORY BLE packet', () {
    test('round-trips a recovered trail point inside legacy advertising budget', () {
      final payload = ConvoyBleCodec.buildHistoryManufacturerData(
        userId: 42,
        seq: 9,
        lat: 45.1234567,
        lon: 10.7654321,
        accuracyM: 7.5,
        historyAgeSeconds: 321,
      );

      expect(payload.length, 22);
      final parsed = ConvoyBleCodec.parseManufacturerData(payload);
      expect(parsed.ok, isTrue);
      expect(parsed.packet!.kindLabel, 'HISTORY');
      expect(parsed.packet!.isHistory, isTrue);
      expect(parsed.packet!.historyAgeSeconds, 321);
      expect(parsed.packet!.lat, closeTo(45.1234567, 0.0000001));
      expect(parsed.packet!.lon, closeTo(10.7654321, 0.0000001));
      // 22 manufacturer bytes + normal BLE framing remains below 31 bytes.
      expect(payload.length + 7, lessThanOrEqualTo(31));
    });

    test('history cannot be encoded without a coordinate and age', () {
      expect(
        () => ConvoyBleCodec.buildManufacturerData(
          userId: 1,
          seq: 1,
          lat: null,
          lon: null,
          accuracyM: null,
          name: null,
          history: true,
          historyAgeSeconds: 10,
        ),
        throwsArgumentError,
      );
    });
  });

  group('recovered peer trail', () {
    test('history is stored as dashed/recovered evidence and never becomes current fix', () {
      // HISTORY carries age relative to the receiver's current clock. Keep the
      // fixture close to real wall time so the production retention gate (90m)
      // is exercised rather than accidentally rejecting a deliberately old
      // hard-coded calendar timestamp.
      final now = DateTime.now().toUtc();
      final service = ConvoyMeshService.forTest(now: () => now);
      service.ingestForTest(
        ConvoyBleCodec.buildHistoryManufacturerData(
          userId: 42,
          seq: 10,
          lat: 45,
          lon: 10,
          accuracyM: 6,
          historyAgeSeconds: 60,
        ),
      );

      final peer = service.peers[42]!;
      expect(peer.hasFix, isFalse,
          reason: 'A recovered point must not masquerade as the peer current position.');
      expect(peer.rxHistoryPackets, 1);
      expect(peer.trail, hasLength(1));
      expect(peer.trail.single.recovered, isTrue);
      expect(peer.trail.single.ts, now.subtract(const Duration(seconds: 60)));
      expect(service.rxValid, 1);
    });

    test('live position remains current when an older history point arrives later', () {
      var now = DateTime.now().toUtc();
      final service = ConvoyMeshService.forTest(now: () => now);
      service.ingestForTest(
        ConvoyBleCodec.buildPositionManufacturerData(
          userId: 42,
          seq: 1,
          lat: 45.001,
          lon: 10,
          accuracyM: 5,
          fixAgeSeconds: 0,
        ),
      );
      final liveLat = service.peers[42]!.lat;

      now = now.add(const Duration(seconds: 5));
      service.ingestForTest(
        ConvoyBleCodec.buildHistoryManufacturerData(
          userId: 42,
          seq: 2,
          lat: 45.0005,
          lon: 10,
          accuracyM: 5,
          historyAgeSeconds: 40,
        ),
      );

      final peer = service.peers[42]!;
      expect(peer.lat, liveLat);
      expect(peer.trail.any((p) => p.recovered), isTrue);
      expect(peer.trail.map((p) => p.ts).toList(), orderedEquals(
        [...peer.trail.map((p) => p.ts)]..sort(),
      ));
    });
  });

  group('catch-up selection', () {
    test('keeps first/last geometry while bounding radio backlog', () {
      final start = DateTime.utc(2026, 9, 9, 12);
      final track = List.generate(
        100,
        (i) => TrackPoint(
          lat: 45 + i / 100000,
          lon: 10,
          ts: start.add(Duration(seconds: i * 5)),
          accuracyM: 5,
          segment: 1,
        ),
      );

      final selected = ConvoyMeshService.selectHistoryCatchupPoints(
        track,
        since: start.subtract(const Duration(seconds: 1)),
        until: start.add(const Duration(minutes: 20)),
        maxPoints: 28,
      );

      expect(selected.length, lessThanOrEqualTo(28));
      expect(selected.first.ts, track.first.ts);
      expect(selected.last.ts, track.last.ts);
      for (var i = 1; i < selected.length; i++) {
        expect(selected[i].ts.isAfter(selected[i - 1].ts), isTrue);
      }
    });

    test('does not send points recorded before the peer disappeared', () {
      final start = DateTime.utc(2026, 9, 9, 12);
      final track = List.generate(
        10,
        (i) => TrackPoint(
          lat: 45 + i / 100000,
          lon: 10,
          ts: start.add(Duration(seconds: i * 10)),
          accuracyM: 5,
        ),
      );
      final selected = ConvoyMeshService.selectHistoryCatchupPoints(
        track,
        since: start.add(const Duration(seconds: 45)),
        until: start.add(const Duration(seconds: 95)),
      );
      expect(selected.every((p) => p.ts.isAfter(start.add(const Duration(seconds: 45)))), isTrue);
      expect(selected.first.ts, start.add(const Duration(seconds: 50)));
    });
  });

  group('HISTORY acknowledgement and retry bookkeeping', () {
    test('HISTORY_ACK round-trips inside legacy advertising budget', () {
      final payload = ConvoyBleCodec.buildHistoryAckManufacturerData(
        userId: 42,
        seq: 101,
        targetUserId: 99,
        historySeq: 77,
      );

      expect(payload.length, 16);
      expect(payload.length + 7, lessThanOrEqualTo(31));
      final parsed = ConvoyBleCodec.parseManufacturerData(payload);
      expect(parsed.ok, isTrue);
      expect(parsed.packet!.kindLabel, 'HISTORY_ACK');
      expect(parsed.packet!.isHistoryAck, isTrue);
      expect(parsed.packet!.ackTargetUserId, 99);
      expect(parsed.packet!.ackHistorySeq, 77);
    });

    test('receiver ACKs HISTORY transport once while still deduplicating trail data', () {
      final now = DateTime.now().toUtc();
      final service = ConvoyMeshService.forTest(now: () => now)..setIdentityForTest(99);
      final payload = ConvoyBleCodec.buildHistoryManufacturerData(
        userId: 42,
        seq: 77,
        lat: 45,
        lon: 10,
        accuracyM: 5,
        historyAgeSeconds: 20,
      );

      service.ingestForTest(payload);
      service.ingestForTest(payload);

      expect(service.pendingHistoryAcks, 1,
          reason: 'Duplicate radio receptions coalesce while an ACK is still pending.');
      expect(service.peers[42]!.rxHistoryPackets, 1,
          reason: 'Duplicate HISTORY must not duplicate the recovered trail point.');
    });

    test('ACK from intended peer clears only the matching transfer', () {
      final now = DateTime.now().toUtc();
      final service = ConvoyMeshService.forTest(now: () => now)..setIdentityForTest(99);
      service.queueHistoryForTest(
        TrackPoint(
          lat: 45,
          lon: 10,
          ts: now.subtract(const Duration(seconds: 30)),
          accuracyM: 5,
        ),
        peerId: 42,
        wireSeq: 77,
      );

      service.ingestForTest(ConvoyBleCodec.buildHistoryAckManufacturerData(
        userId: 43,
        seq: 1,
        targetUserId: 99,
        historySeq: 77,
      ));
      expect(service.pendingHistoryPoints, 1);
      expect(service.unackedHistoryPeersForTest(77), {42});

      service.ingestForTest(ConvoyBleCodec.buildHistoryAckManufacturerData(
        userId: 42,
        seq: 1,
        targetUserId: 99,
        historySeq: 77,
      ));
      expect(service.pendingHistoryPoints, 0);
      expect(service.rxHistoryAckPackets, 2);
    });
  });
}
