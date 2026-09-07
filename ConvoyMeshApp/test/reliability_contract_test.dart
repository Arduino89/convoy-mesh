import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_mesh/ble/convoy_ble_codec.dart';
import 'package:convoy_mesh/location/fused_location.dart';
import 'package:convoy_mesh/services/convoy_mesh_service.dart';

void main() {
  group('BLE transport bounds', () {
    test('valid coordinate and sequence extremes survive the existing wire format', () {
      for (final point in <List<double>>[[90, 180], [-90, -180], [0, 0]]) {
        final payload = ConvoyBleCodec.buildPositionManufacturerData(
          userId: 0xffffffff, seq: 0xffff, lat: point[0], lon: point[1],
          accuracyM: 120, fixAgeSeconds: 0,
        );
        final decoded = ConvoyBleCodec.parseManufacturerData(payload).packet!;
        expect(decoded.userId, 0xffffffff);
        expect(decoded.seq, 0xffff);
        expect(decoded.lat, point[0]);
        expect(decoded.lon, point[1]);
        expect(payload.length + 7, lessThanOrEqualTo(31));
      }
    });
    test('UTF-8 names are capped without splitting a character', () {
      final payload = ConvoyBleCodec.buildNameManufacturerData(
        userId: 42, seq: 1, name: '🥾🥾🥾🥾 montagna',
      );
      final packet = ConvoyBleCodec.parseManufacturerData(payload).packet!;
      expect(packet.name, '🥾🥾🥾');
      expect(utf8.encode(packet.name!).length, ConvoyBleCodec.maxNameBytes);
      expect(payload.length + 7, lessThanOrEqualTo(31));
    });
    test('nonfinite coordinates cannot be transmitted as valid positions', () {
      for (final invalid in [double.nan, double.infinity, -double.infinity, 91.0]) {
        expect(() => ConvoyBleCodec.buildPositionManufacturerData(
          userId: 42, seq: 1, lat: invalid, lon: 10, accuracyM: 5,
        ), throwsArgumentError);
      }
    });
    test('bounded arbitrary advertisements never crash the parser', () {
      final random = Random(1907);
      for (var i = 0; i < 3000; i++) {
        final bytes = Uint8List.fromList(List.generate(random.nextInt(40), (_) => random.nextInt(256)));
        expect(() => ConvoyBleCodec.parseManufacturerData(bytes), returnsNormally);
      }
    });
  });

  group('freshness is not the UI refresh clock', () {
    FusedLocation fix(DateTime eventAt, DateTime? sourceAt, {
      bool permission = true, bool enabled = true,
    }) => FusedLocation(
      lat: 45, lon: 10, accuracyM: 5, rawLat: 45, rawLon: 10,
      hasPermission: permission, serviceEnabled: enabled,
      gpsState: GpsUiState.ok, gpsBars: 4, gpsQuality: 100,
      ts: eventAt, measurementAt: sourceAt, coordinateAt: sourceAt,
      isMoving: false, motionReliable: true, motionScore: 0,
      gpsDecision: 'test', gpsReason: 'synthetic',
    );
    test('unknown, future and stale measurement times remain nonfresh', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      expect(fix(now, null).hasFreshFixAt(now), isFalse);
      expect(fix(now, now.add(const Duration(seconds: 1))).hasFreshFixAt(now), isFalse);
      expect(fix(now, now.subtract(const Duration(seconds: 16))).hasFreshFixAt(now), isFalse);
      expect(fix(now, now.subtract(const Duration(seconds: 15))).hasFreshFixAt(now), isTrue);
    });
    test('revoked permission or disabled location blocks fresh-position advertising', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      expect(fix(now, now, permission: false).hasFreshFixAt(now), isFalse);
      expect(fix(now, now, enabled: false).hasFreshFixAt(now), isFalse);
    });
    test('a heartbeat does not alter a previously accepted source fix', () {
      var now = DateTime.now();
      final service = ConvoyMeshService.forTest(now: () => now);
      service.ingestForTest(ConvoyBleCodec.buildPositionManufacturerData(
        userId: 42, seq: 1, lat: 45, lon: 10, accuracyM: 5, fixAgeSeconds: 8,
      ));
      final measured = service.peers[42]!.lastFixMeasuredAt;
      now = now.add(const Duration(seconds: 20));
      service.ingestForTest(ConvoyBleCodec.buildPingManufacturerData(userId: 42, seq: 2));
      expect(service.peers[42]!.lastSeen, now);
      expect(service.peers[42]!.lastFixMeasuredAt, measured);
      expect(service.peers[42]!.lat, 45);
      expect(service.rxFixPackets, 1);
    });
  });
}
