import 'dart:typed_data';

import 'package:convoy_mesh/ble/convoy_ble_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConvoyBleCodec', () {
    test('round-trips position manufacturer data', () {
      final payload = ConvoyBleCodec.buildPositionManufacturerData(
        userId: 0x12345678,
        seq: 42,
        lat: 45.1567,
        lon: 10.7912,
        accuracyM: 12.3,
      );

      expect(payload.length, 20);

      final parsed = ConvoyBleCodec.parseManufacturerData(payload);
      expect(parsed.ok, isTrue);
      expect(parsed.reason, 'ok');
      expect(parsed.magicOffset, 0);

      final packet = parsed.packet!;
      expect(packet.userId, 0x12345678);
      expect(packet.seq, 42);
      expect(packet.hasFix, isTrue);
      expect(packet.hasName, isFalse);
      expect(packet.kindLabel, 'POS');
      expect(packet.lat!, closeTo(45.1567, 0.0000001));
      expect(packet.lon!, closeTo(10.7912, 0.0000001));
      expect(packet.accuracyM!, closeTo(12.3, 0.05));
    });

    test('parses payload when manufacturer id is prefixed by BLE stack', () {
      final payload = ConvoyBleCodec.buildPingManufacturerData(
        userId: 77,
        seq: 9,
      );
      final withManufacturerId = Uint8List.fromList(<int>[
        0x0A,
        0x0C,
        ...payload,
      ]);

      final parsed = ConvoyBleCodec.parseManufacturerData(withManufacturerId);
      expect(parsed.ok, isTrue);
      expect(parsed.magicOffset, 2);
      expect(parsed.packet!.userId, 77);
      expect(parsed.packet!.seq, 9);
      expect(parsed.packet!.kindLabel, 'PING');
    });

    test('round-trips name packet and caps payload size for legacy advertising', () {
      final payload = ConvoyBleCodec.buildNameManufacturerData(
        userId: 99,
        seq: 65535,
        name: '  CamaEnterpriseVeryLongName  ',
      );

      expect(payload.length, lessThanOrEqualTo(23));

      final parsed = ConvoyBleCodec.parseManufacturerData(payload);
      expect(parsed.ok, isTrue);
      expect(parsed.packet!.userId, 99);
      expect(parsed.packet!.seq, 65535);
      expect(parsed.packet!.hasName, isTrue);
      expect(parsed.packet!.hasFix, isFalse);
      expect(parsed.packet!.kindLabel, 'NAME');
      expect(parsed.packet!.name, startsWith('Cama'));
      expect(parsed.packet!.name!.length, lessThanOrEqualTo('CamaEnterprise'.length));
    });

    test('rejects random data without Convoy magic', () {
      final parsed = ConvoyBleCodec.parseManufacturerData(
        Uint8List.fromList(<int>[0x01, 0x02, 0x03, 0x04, 0x05]),
      );

      expect(parsed.ok, isFalse);
      expect(parsed.reason, 'no_magic');
      expect(parsed.magicOffset, isNull);
    });

    test('rejects unsupported version', () {
      final payload = ConvoyBleCodec.buildPingManufacturerData(userId: 1, seq: 1);
      final corrupted = Uint8List.fromList(payload);
      corrupted[2] = 0x7F;

      final parsed = ConvoyBleCodec.parseManufacturerData(corrupted);
      expect(parsed.ok, isFalse);
      expect(parsed.reason, 'no_magic');
    });

    test('rejects truncated fix packets', () {
      final payload = ConvoyBleCodec.buildPositionManufacturerData(
        userId: 1,
        seq: 1,
        lat: 45.0,
        lon: 10.0,
        accuracyM: 5,
      );
      final truncated = Uint8List.fromList(payload.sublist(0, 12));

      final parsed = ConvoyBleCodec.parseManufacturerData(truncated);
      expect(parsed.ok, isFalse);
      expect(parsed.reason, 'short_fix');
    });

    test('rejects coordinates outside valid ranges', () {
      final payload = ConvoyBleCodec.buildPositionManufacturerData(
        userId: 1,
        seq: 1,
        lat: 45.0,
        lon: 10.0,
        accuracyM: 5,
      );
      final corrupted = Uint8List.fromList(payload);

      // latE7 starts at byte 10. 100.0 degrees => 1,000,000,000 => invalid latitude.
      corrupted[10] = 0x00;
      corrupted[11] = 0xCA;
      corrupted[12] = 0x9A;
      corrupted[13] = 0x3B;

      final parsed = ConvoyBleCodec.parseManufacturerData(corrupted);
      expect(parsed.ok, isFalse);
      expect(parsed.reason, 'bad_coordinates');
    });
  });
}
