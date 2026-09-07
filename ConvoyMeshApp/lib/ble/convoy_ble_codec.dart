import 'dart:convert';
import 'dart:typed_data';

class ConvoyPacket {
  final int userId, seq;
  final double? lat, lon, accuracyM;
  final String? name;
  /// Null for legacy packets: source measurement age is unknown.
  final int? fixAgeSeconds;
  const ConvoyPacket({required this.userId, required this.seq, required this.lat,
    required this.lon, required this.accuracyM, required this.name, this.fixAgeSeconds});
  bool get hasFix => lat != null && lon != null;
  bool get hasName => name != null && name!.trim().isNotEmpty;
  String get kindLabel => hasFix ? (hasName ? 'POS+NAME' : 'POS') : hasName ? 'NAME' : 'PING';
}
class ConvoyParseResult {
  final ConvoyPacket? packet;
  final String reason;
  final int? magicOffset;
  final int inputLength;
  final String inputPreviewHex;
  const ConvoyParseResult({required this.packet, required this.reason, required this.magicOffset,
    required this.inputLength, required this.inputPreviewHex});
  bool get ok => packet != null;
}

/// Existing v2 little-endian layout: CM, version, flags, uint32 ID, uint16 seq;
/// optional int32 latE7, int32 lonE7, uint16 accuracyDm; optional UTF-8 name.
/// New POS-only trailer: A3 + source-age seconds. Legacy parsers ignore it.
/// POS 22B + manufacturer framing 4B + BLE flags 3B = 29B (limit 31B).
class ConvoyBleCodec {
  static const serviceUuid = '0000FEED-0000-1000-8000-00805F9B34FB';
  static const manufacturerId = 0x0C0A;
  static const version = 0x02;
  static const maxNameBytes = 12;
  static const _maxAcceptedNameBytes = 20;

  static Uint8List buildPositionManufacturerData({required int userId, required int seq,
    required double? lat, required double? lon, required double? accuracyM, int? fixAgeSeconds}) {
    final bytes = buildManufacturerData(userId: userId, seq: seq, lat: lat, lon: lon,
        accuracyM: accuracyM, name: null);
    if (lat != null && lon != null && fixAgeSeconds != null) {
      return Uint8List.fromList([...bytes, 0xA3, fixAgeSeconds.clamp(0, 254).toInt()]);
    }
    return bytes;
  }
  static Uint8List buildNameManufacturerData({required int userId, required int seq, required String name}) =>
      buildManufacturerData(userId: userId, seq: seq, lat: null, lon: null, accuracyM: null, name: name);
  static Uint8List buildPingManufacturerData({required int userId, required int seq}) =>
      buildManufacturerData(userId: userId, seq: seq, lat: null, lon: null, accuracyM: null, name: null);
  static Uint8List buildManufacturerData({required int userId, required int seq, required double? lat,
    required double? lon, required double? accuracyM, required String? name}) {
    final hasFix = lat != null && lon != null;
    final cleaned = name?.trim();
    final hasName = cleaned != null && cleaned.isNotEmpty;
    if (hasFix && (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180)) {
      throw ArgumentError('Invalid position');
    }
    final bytes = <int>[0x43, 0x4D, version, (hasFix ? 1 : 0) | (hasName ? 2 : 0),
      ..._u32(userId), ..._u16(seq)];
    if (hasFix) {
      final accuracy = accuracyM != null && accuracyM.isFinite && accuracyM >= 0 ? accuracyM : 6553.5;
      bytes.addAll([..._u32((lat * 1e7).round()), ..._u32((lon * 1e7).round()),
        ..._u16((accuracy.clamp(0.0, 6553.5) * 10).round())]);
    }
    if (hasName) {
      final data = <int>[];
      for (final rune in cleaned.runes) {
        final part = utf8.encode(String.fromCharCode(rune));
        if (data.length + part.length > maxNameBytes) break;
        data.addAll(part);
      }
      bytes.addAll([data.length, ...data]);
    }
    return Uint8List.fromList(bytes);
  }
  static ConvoyPacket? tryParseManufacturerData(Uint8List data) => parseManufacturerData(data).packet;
  static ConvoyParseResult parseManufacturerData(Uint8List data) {
    final offset = findPayloadOffset(data);
    ConvoyParseResult error(String reason) => ConvoyParseResult(packet: null, reason: reason,
        magicOffset: offset, inputLength: data.length, inputPreviewHex: previewHex(data));
    if (offset == null) return error('no_magic');
    if (data.length < offset + 10) return error('short_after_magic');
    final flags = data[offset + 3];
    final hasFix = flags & 1 != 0;
    final hasName = flags & 2 != 0;
    final userId = _readU32(data, offset + 4);
    final seq = _readU16(data, offset + 8);
    var idx = offset + 10;
    double? lat, lon, accuracy;
    String? name;
    if (hasFix) {
      if (data.length < idx + 10) return error('short_fix');
      lat = _readI32(data, idx) / 1e7;
      lon = _readI32(data, idx + 4) / 1e7;
      accuracy = _readU16(data, idx + 8) / 10;
      if (lat.abs() > 90 || lon.abs() > 180) return error('bad_coordinates');
      idx += 10;
    }
    if (hasName) {
      if (data.length < idx + 1) return error('short_name_len');
      final len = data[idx++];
      if (len > _maxAcceptedNameBytes) return error('bad_name_len_$len');
      if (data.length < idx + len) return error('short_name');
      name = utf8.decode(data.sublist(idx, idx + len), allowMalformed: true).trim();
      if (name.isEmpty) name = null;
      idx += len;
    }
    final int? age = hasFix && !hasName && data.length == idx + 2 && data[idx] == 0xA3 ? data[idx + 1] : null;
    return ConvoyParseResult(packet: ConvoyPacket(userId: userId, seq: seq, lat: lat, lon: lon,
      accuracyM: accuracy, name: name, fixAgeSeconds: age), reason: 'ok', magicOffset: offset,
      inputLength: data.length, inputPreviewHex: previewHex(data));
  }
  static int? findPayloadOffset(Uint8List data) {
    bool valid(int p) => p >= 0 && data.length >= p + 4 && data[p] == 0x43 && data[p + 1] == 0x4D &&
        (data[p + 2] == 1 || data[p + 2] == version) && data[p + 3] & ~3 == 0;
    if (valid(0)) return 0;
    if (valid(2)) return 2;
    for (var i = 1; i <= (data.length - 4).clamp(0, 8); i++) { if (valid(i)) return i; }
    return null;
  }
  static String previewHex(Uint8List data, {int maxBytes = 24}) {
    if (data.isEmpty) return '-';
    final parts = data.take(maxBytes).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).toList();
    if (data.length > maxBytes) parts.add('...');
    return parts.join(' ');
  }
  static List<int> _u16(int n) => [n & 255, (n >> 8) & 255];
  static List<int> _u32(int n) => [n & 255, (n >> 8) & 255, (n >> 16) & 255, (n >> 24) & 255];
  static int _readU16(Uint8List b, int p) => b[p] | (b[p + 1] << 8);
  static int _readU32(Uint8List b, int p) => b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24);
  static int _readI32(Uint8List b, int p) { final n = _readU32(b, p); return n & 0x80000000 != 0 ? n - 0x100000000 : n; }
}
