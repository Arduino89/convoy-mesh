import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_mesh/ble/ble_tx_scheduler.dart';
import 'package:convoy_mesh/ble/convoy_ble_codec.dart';
import 'package:convoy_mesh/location/pedestrian_position_estimator.dart';
import 'package:convoy_mesh/location/fused_location.dart';
import 'package:convoy_mesh/services/convoy_mesh_service.dart';

void main() {
  group('single-owner BLE scheduler', () {
    test('30-minute name flood cannot starve fresh positions', () {
      final scheduler = BleTxScheduler();
      final positions = <int>[];
      for (var s = 0; s < 1800; s++) {
        scheduler.requestName();
        final now = Duration(seconds: s);
        final kind = scheduler.choose(now: now, hasFreshPosition: true);
        if (kind != null) {
          scheduler.didSend(kind, now);
          if (kind == BleTxKind.position) positions.add(s);
        }
      }
      expect(positions.length, greaterThanOrEqualTo(180));
      for (var i = 1; i < positions.length; i++) { expect(positions[i] - positions[i - 1], lessThanOrEqualTo(10)); }
    });
    test('presence continues without GPS and never invents POS', () {
      final scheduler = BleTxScheduler();
      final kinds = <BleTxKind>[];
      for (var s = 0; s <= 60; s += 5) {
        final now = Duration(seconds: s);
        final kind = scheduler.choose(now: now, hasFreshPosition: false)!;
        kinds.add(kind); scheduler.didSend(kind, now);
      }
      expect(kinds, isNot(contains(BleTxKind.position)));
      expect(kinds, contains(BleTxKind.ping));
      expect(kinds, contains(BleTxKind.name));
    });
    test('failure does not consume a name request or heartbeat deadline', () {
      final scheduler = BleTxScheduler();
      expect(scheduler.choose(now: Duration.zero, hasFreshPosition: false), BleTxKind.name);
      expect(scheduler.choose(now: const Duration(seconds: 1), hasFreshPosition: false), BleTxKind.name);
    });
    test('resume prioritises fresh POS but throttles repeated resume events', () {
      final scheduler = BleTxScheduler();
      scheduler.didSend(BleTxKind.name, Duration.zero);
      expect(scheduler.choose(now: const Duration(milliseconds: 100), hasFreshPosition: true, refresh: true), isNull);
      expect(scheduler.choose(now: const Duration(seconds: 1), hasFreshPosition: true, refresh: true), BleTxKind.position);
    });
    test('normal name cadence leaves position slots available', () {
      final scheduler = BleTxScheduler();
      scheduler.didSend(BleTxKind.name, Duration.zero);
      expect(scheduler.choose(now: const Duration(seconds: 5), hasFreshPosition: true), BleTxKind.position);
      scheduler.didSend(BleTxKind.position, const Duration(seconds: 5));
      expect(scheduler.choose(now: const Duration(seconds: 10), hasFreshPosition: true), BleTxKind.position);
      expect(scheduler.choose(now: const Duration(seconds: 30), hasFreshPosition: true), BleTxKind.name);
    });
  });

  group('stateful pedestrian estimate', () {
    final start = DateTime.utc(2026, 1, 1);
    PositionEstimate feed(PedestrianPositionEstimator e, double metres, int seconds,
        {double accuracy = 5, bool moving = false, bool reliable = true}) {
      final t = start.add(Duration(seconds: seconds));
      return e.add(GpsObservation(45 + metres / 111195, 10, accuracy, t),
          receivedAt: t, moving: moving, motionReliable: reliable);
    }
    PedestrianPositionEstimator acquired({double metres = 0, double accuracy = 5}) {
      final e = PedestrianPositionEstimator();
      for (final t in [0, 5, 10]) { feed(e, metres, t, accuracy: accuracy); }
      return e;
    }
    double metres(PositionEstimate p) => (p.lat! - 45) * 111195;
    test('first inaccurate fix remains provisional until majority consensus', () {
      final e = PedestrianPositionEstimator();
      expect(feed(e, 30, 0, accuracy: 40).lat, isNull);
      feed(e, 0, 5); feed(e, 1, 10);
      final result = feed(e, -1, 15);
      expect(result.decision, 'acquired');
      expect(metres(result).abs(), lessThan(2));
    });
    test('30 minutes stationary: jitter and single outliers do not create movement', () {
      final e = acquired(); final random = Random(71);
      for (var t = 15; t < 1800; t += 5) {
        final p = feed(e, t % 100 == 0 ? 30 : random.nextDouble() * 4 - 2, t);
        expect(metres(p).abs(), lessThan(0.01), reason: 't=$t');
        expect(p.addToTrack, isFalse, reason: 't=$t');
      }
    });
    test('a coherent better cluster corrects the anchor without a fake trail', () {
      final e = acquired(metres: 20, accuracy: 30);
      PositionEstimate? p;
      for (var t = 15; t <= 50; t += 5) { p = feed(e, 0, t, accuracy: 4); expect(p.addToTrack, isFalse); }
      expect(metres(p!).abs(), lessThan(2));
    });
    test('held coordinates never borrow raw accuracy from a different point', () {
      final e = acquired(accuracy: 15);
      final p = feed(e, 8, 15, accuracy: 1);
      expect(metres(p).abs(), lessThan(0.01));
      expect(p.accuracyM, greaterThanOrEqualTo(9));
      expect(p.coordinateAt, start.add(const Duration(seconds: 10)));
    });
    test('rejected poor fixes do not refresh the supported timestamp', () {
      final e = acquired(); final p = feed(e, 100, 50, accuracy: 500);
      expect(p.supportedAt, start.add(const Duration(seconds: 10)));
      expect(p.isFreshAt(start.add(const Duration(seconds: 50))), isFalse);
    });
    test('delayed and future observations are rejected', () {
      final e = acquired();
      final p = e.add(GpsObservation(46, 10, 5, start.add(const Duration(seconds: 15))),
          receivedAt: start.add(const Duration(seconds: 60)), moving: true, motionReliable: true);
      expect(p.decision, 'stale_or_future_fix');
      final future = e.add(GpsObservation(46, 10, 5, start.add(const Duration(seconds: 100))),
          receivedAt: start.add(const Duration(seconds: 60)), moving: true, motionReliable: true);
      expect(future.decision, 'stale_or_future_fix');
    });
    test('duplicate and out-of-order fixes cannot move the anchor', () {
      final e = acquired();
      expect(feed(e, 20, 10).decision, 'out_of_order_fix');
      expect(feed(e, 20, 5).decision, 'out_of_order_fix');
    });
    test('invalid numeric inputs do not enter the estimator', () {
      final e = acquired();
      for (final accuracy in [double.nan, double.infinity, -1.0, 0.0]) {
        expect(feed(e, 0, 15, accuracy: accuracy).decision, 'invalid_fix');
      }
      expect(feed(e, double.nan, 15).decision, 'invalid_fix');
    });
    test('normal walking follows without excessive filter lag', () {
      final e = acquired();
      for (var t = 15; t <= 120; t += 5) {
        final distance = (t - 10).toDouble();
        final p = feed(e, distance, t, moving: true);
        expect((metres(p) - distance).abs(), lessThan(3));
        expect(p.addToTrack, isTrue);
      }
    });
    test('claimed high accuracy cannot legitimise a kilometre teleport', () {
      expect(feed(acquired(), 1000, 15, accuracy: 2, moving: true).decision, 'rejected_jump');
    });
    test('long gaps require a new cluster and do not draw a connecting trail', () {
      final e = acquired();
      expect(feed(e, 1000, 100).decision, 'reacquiring');
      expect(feed(e, 1001, 105).decision, 'reacquiring');
      final p = feed(e, 999, 110);
      expect(p.decision, 'reacquired');
      expect((metres(p) - 1000).abs(), lessThan(2));
      expect(p.addToTrack, isFalse);
    });
    test('coherent GPS motion eventually overrides an IMU falsely reporting still', () {
      final e = acquired(); PositionEstimate? p;
      for (var t = 15; t <= 80; t += 5) { p = feed(e, (t - 10).toDouble(), t); }
      expect(metres(p!), greaterThan(65));
    });
    test('missing IMU does not manufacture a stationary trail', () {
      final e = acquired();
      for (var t = 15; t <= 300; t += 5) {
        final p = feed(e, t % 20 == 0 ? 2 : -2, t, reliable: false);
        expect(p.addToTrack, isFalse);
        expect(metres(p).abs(), lessThan(0.01));
      }
    });
  });

  group('wire age and actual receive handler', () {
    test('POS source age round-trips inside legacy BLE payload budget', () {
      final bytes = ConvoyBleCodec.buildPositionManufacturerData(userId: 42, seq: 8,
          lat: 45, lon: 10, accuracyM: 5, fixAgeSeconds: 14);
      expect(bytes.length + 7, lessThanOrEqualTo(31));
      expect(ConvoyBleCodec.parseManufacturerData(bytes).packet!.fixAgeSeconds, 14);
    });
    test('legacy POS remains readable but source age is unknown', () {
      final bytes = ConvoyBleCodec.buildPositionManufacturerData(userId: 42, seq: 8,
          lat: 45, lon: 10, accuracyM: 5);
      expect(bytes.length, 20);
      expect(ConvoyBleCodec.parseManufacturerData(bytes).packet!.fixAgeSeconds, isNull);
    });
    test('poor/stale position does not falsely mean radio offline', () {
      final now = DateTime.now();
      final service = ConvoyMeshService.forTest(now: () => now);
      service.ingestForTest(ConvoyBleCodec.buildPositionManufacturerData(userId: 42, seq: 1,
          lat: 45, lon: 10, accuracyM: 5, fixAgeSeconds: 50));
      final peer = service.peers[42]!;
      expect(peer.lastSeen, now);
      expect(ConvoyMeshService.isPeerOnline(peer), isTrue);
      expect(peer.hasFix, isFalse);
      expect(service.rxValid, 1);
      expect(service.rxFixPackets, 0);
    });
    test('duplicate packets cannot advance accepted presence time', () {
      var now = DateTime.now();
      final service = ConvoyMeshService.forTest(now: () => now);
      final bytes = ConvoyBleCodec.buildPingManufacturerData(userId: 42, seq: 1);
      service.ingestForTest(bytes); final accepted = now;
      now = now.add(const Duration(seconds: 5)); service.ingestForTest(bytes);
      expect(service.peers[42]!.lastSeen, accepted);
      expect(service.peers[42]!.lastHeardAt, now);
      expect(service.rxStale, 1);
    });
    test('wrapped sequence advances and unrelated packet types do not starve each other', () {
      final service = ConvoyMeshService.forTest();
      service.ingestForTest(ConvoyBleCodec.buildPingManufacturerData(userId: 42, seq: 65535));
      service.ingestForTest(ConvoyBleCodec.buildPingManufacturerData(userId: 42, seq: 0));
      service.ingestForTest(ConvoyBleCodec.buildNameManufacturerData(userId: 42, seq: 1, name: 'Fra'));
      expect(service.rxValid, 3);
      expect(service.peers[42]!.name, 'Fra');
    });
    test('malformed noise and zero peer ID do not create peers', () {
      final service = ConvoyMeshService.forTest();
      service.ingestForTest(Uint8List.fromList([0, 1, 2]));
      service.ingestForTest(ConvoyBleCodec.buildPingManufacturerData(userId: 0, seq: 1));
      expect(service.peers, isEmpty);
    });
    test('median signal resists one outlier and is not a distance claim', () {
      final peer = PeerState(userId: 42);
      for (final rssi in [-71, -70, -69, -70, -25]) { peer.markHeard(now: DateTime.now(), rssi: rssi, address: 'test'); }
      expect(peer.medianRssi, -70);
      expect(ConvoyMeshService.rssiQuality(0), 'non disponibile');
    });
    test('new UI timestamp alone cannot refresh a stale local fix', () {
      final now = DateTime.now();
      final f = FusedLocation(lat: 45, lon: 10, accuracyM: 5, rawLat: 45, rawLon: 10,
        hasPermission: true, serviceEnabled: true, gpsState: GpsUiState.ok, gpsBars: 4, gpsQuality: 100,
        ts: now, measurementAt: now.subtract(const Duration(seconds: 30)),
        isMoving: false, motionReliable: true, motionScore: 0, gpsDecision: 'held', gpsReason: 'held');
      expect(f.hasFreshFixAt(now), isFalse);
    });
  });
}
