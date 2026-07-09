// lib/ble/convoy_ble_codec.dart
import 'dart:convert';
import 'dart:typed_data';

class ConvoyPacket {
  final int userId;
  final int seq;
  final double? lat;
  final double? lon;
  final double? accuracyM;
  final String? name;

  const ConvoyPacket({
    required this.userId,
    required this.seq,
    required this.lat,
    required this.lon,
    required this.accuracyM,
    required this.name,
  });

  bool get hasFix => lat != null && lon != null;
  bool get hasName => name != null && name!.trim().isNotEmpty;

  String get kindLabel {
    if (hasFix && hasName) return 'POS+NAME';
    if (hasFix) return 'POS';
    if (hasName) return 'NAME';
    return 'PING';
  }
}

class ConvoyParseResult {
  final ConvoyPacket? packet;
  final String reason;
  final int? magicOffset;
  final int inputLength;
  final String inputPreviewHex;

  const ConvoyParseResult({
    required this.packet,
    required this.reason,
    required this.magicOffset,
    required this.inputLength,
    required this.inputPreviewHex,
  });

  bool get ok => packet != null;
}

/// Payload super-snello in Manufacturer Data (BLE ADV).
///
/// Obiettivo di questa versione:
/// - NON dipendere dal serviceUuid nello scan/advertising.
/// - Tenere il payload abbastanza piccolo per BLE advertising classico.
/// - Separare pacchetto posizione e pacchetto nome.
/// - Accettare in RX sia payload "CM..." puro, sia manufacturerData con
///   manufacturerId prefissato, es. "0A 0C CM...".
///
/// Layout payload little endian, senza eventuale manufacturerId esterno:
/// [0]      : magic0 = 0x43 ('C')
/// [1]      : magic1 = 0x4D ('M') => "CM" = Convoy Mesh
/// [2]      : version = 0x02
/// [3]      : flags (bit0 hasFix, bit1 hasName)
/// [4..7]   : userId (uint32)
/// [8..9]   : seq (uint16)
/// [10..13] : latE7 (int32)  solo se hasFix
/// [14..17] : lonE7 (int32)  solo se hasFix
/// [18..19] : accDm (uint16) solo se hasFix, decimetri
/// [..]     : nameLen (uint8) + UTF-8 bytes solo se hasName
class ConvoyBleCodec {
  /// Lo teniamo come costante progetto/debug, ma nella patch BLE Stability
  /// NON viene più inserito nell'advertising per risparmiare bytes.
  static const String serviceUuid = '0000FEED-0000-1000-8000-00805F9B34FB';

  static const int manufacturerId = 0x0C0A; // arbitrario, stabile

  static const int version = 0x02;
  static const int _magic0 = 0x43; // C
  static const int _magic1 = 0x4D; // M

  // Payload dati, esclusi overhead BLE/manufacturerId.
  // Posizione: 10 header + 10 fix = 20 bytes.
  // Nome: 10 header + 1 len + max 12 = 23 bytes.
  static const int maxNameBytes = 12;

  // Accettiamo fino a 20 in RX per compatibilità con eventuali pacchetti v0.1.
  static const int _maxAcceptedNameBytes = 20;

  static Uint8List buildPositionManufacturerData({
    required int userId,
    required int seq,
    required double? lat,
    required double? lon,
    required double? accuracyM,
  }) {
    return buildManufacturerData(
      userId: userId,
      seq: seq,
      lat: lat,
      lon: lon,
      accuracyM: accuracyM,
      name: null,
    );
  }

  static Uint8List buildNameManufacturerData({
    required int userId,
    required int seq,
    required String name,
  }) {
    return buildManufacturerData(
      userId: userId,
      seq: seq,
      lat: null,
      lon: null,
      accuracyM: null,
      name: name,
    );
  }

  static Uint8List buildPingManufacturerData({
    required int userId,
    required int seq,
  }) {
    return buildManufacturerData(
      userId: userId,
      seq: seq,
      lat: null,
      lon: null,
      accuracyM: null,
      name: null,
    );
  }

  /// Metodo generico mantenuto per compatibilità interna.
  /// Nel servizio BLE preferiamo usare i builder dedicati per evitare
  /// pacchetti POS+NAME troppo grandi.
  static Uint8List buildManufacturerData({
    required int userId,
    required int seq,
    required double? lat,
    required double? lon,
    required double? accuracyM,
    required String? name,
  }) {
    final hasFix = lat != null && lon != null;
    final cleanedName = _cleanName(name);
    final hasName = cleanedName != null;

    final flags = (hasFix ? 0x01 : 0) | (hasName ? 0x02 : 0);

    final bytes = <int>[
      _magic0,
      _magic1,
      version,
      flags,
      ..._u32le(userId),
      ..._u16le(seq),
    ];

    if (hasFix) {
      final latE7 = (lat * 1e7).round();
      final lonE7 = (lon * 1e7).round();

      final acc = (accuracyM ?? 9999).clamp(0.0, 6553.5);
      final accDm = (acc * 10).round();

      bytes.addAll(_i32le(latE7));
      bytes.addAll(_i32le(lonE7));
      bytes.addAll(_u16le(accDm));
    }

    if (hasName) {
      final nameBytes = _utf8Capped(cleanedName, maxNameBytes);
      bytes.add(nameBytes.length);
      bytes.addAll(nameBytes);
    }

    return Uint8List.fromList(bytes);
  }

  static ConvoyPacket? tryParseManufacturerData(Uint8List data) {
    return parseManufacturerData(data).packet;
  }

  /// Parser diagnostico.
  ///
  /// Nota importante: alcuni stack/plugin BLE espongono manufacturerData già
  /// senza manufacturerId, quindi il payload inizia da "CM". Altri lo espongono
  /// con i 2 byte manufacturerId davanti. Per questo cerchiamo "CM" a offset 0,
  /// offset 2, e infine nei primi byte del buffer.
  static ConvoyParseResult parseManufacturerData(Uint8List data) {
    final preview = previewHex(data);
    final offset = findPayloadOffset(data);

    if (offset == null) {
      return ConvoyParseResult(
        packet: null,
        reason: 'no_magic',
        magicOffset: null,
        inputLength: data.length,
        inputPreviewHex: preview,
      );
    }

    if (data.length < offset + 10) {
      return ConvoyParseResult(
        packet: null,
        reason: 'short_after_magic',
        magicOffset: offset,
        inputLength: data.length,
        inputPreviewHex: preview,
      );
    }

    final ver = data[offset + 2];
    if (ver != 0x01 && ver != version) {
      return ConvoyParseResult(
        packet: null,
        reason: 'bad_version_$ver',
        magicOffset: offset,
        inputLength: data.length,
        inputPreviewHex: preview,
      );
    }

    final flags = data[offset + 3];
    if ((flags & ~0x03) != 0) {
      return ConvoyParseResult(
        packet: null,
        reason: 'bad_flags_$flags',
        magicOffset: offset,
        inputLength: data.length,
        inputPreviewHex: preview,
      );
    }

    final hasFix = (flags & 0x01) != 0;
    final hasName = (flags & 0x02) != 0;

    final userId = _readU32le(data, offset + 4);
    final seq = _readU16le(data, offset + 8);

    var idx = offset + 10;

    double? lat;
    double? lon;
    double? acc;

    if (hasFix) {
      if (data.length < idx + 10) {
        return ConvoyParseResult(
          packet: null,
          reason: 'short_fix',
          magicOffset: offset,
          inputLength: data.length,
          inputPreviewHex: preview,
        );
      }

      final latE7 = _readI32le(data, idx);
      final lonE7 = _readI32le(data, idx + 4);
      final accDm = _readU16le(data, idx + 8);

      lat = latE7 / 1e7;
      lon = lonE7 / 1e7;
      acc = accDm / 10.0;

      if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
        return ConvoyParseResult(
          packet: null,
          reason: 'bad_coordinates',
          magicOffset: offset,
          inputLength: data.length,
          inputPreviewHex: preview,
        );
      }

      idx += 10;
    }

    String? name;
    if (hasName) {
      if (data.length < idx + 1) {
        return ConvoyParseResult(
          packet: null,
          reason: 'short_name_len',
          magicOffset: offset,
          inputLength: data.length,
          inputPreviewHex: preview,
        );
      }

      final len = data[idx];
      idx += 1;

      if (len > _maxAcceptedNameBytes) {
        return ConvoyParseResult(
          packet: null,
          reason: 'bad_name_len_$len',
          magicOffset: offset,
          inputLength: data.length,
          inputPreviewHex: preview,
        );
      }

      if (data.length < idx + len) {
        return ConvoyParseResult(
          packet: null,
          reason: 'short_name',
          magicOffset: offset,
          inputLength: data.length,
          inputPreviewHex: preview,
        );
      }

      name = utf8.decode(data.sublist(idx, idx + len), allowMalformed: true).trim();
      if (name.isEmpty) name = null;
      idx += len;
    }

    return ConvoyParseResult(
      packet: ConvoyPacket(
        userId: userId,
        seq: seq,
        lat: lat,
        lon: lon,
        accuracyM: acc,
        name: name,
      ),
      reason: 'ok',
      magicOffset: offset,
      inputLength: data.length,
      inputPreviewHex: preview,
    );
  }

  static int? findPayloadOffset(Uint8List data) {
    bool looksLikePacketAt(int o) {
      if (o < 0 || data.length < o + 4) return false;
      if (data[o] != _magic0 || data[o + 1] != _magic1) return false;
      final ver = data[o + 2];
      if (ver != 0x01 && ver != version) return false;
      final flags = data[o + 3];
      return (flags & ~0x03) == 0;
    }

    // Caso A: plugin consegna solo payload manufacturer-specific: CM...
    if (looksLikePacketAt(0)) return 0;

    // Caso B: plugin consegna manufacturerId + payload: 0A 0C CM...
    if (looksLikePacketAt(2)) return 2;

    // Caso C: fallback diagnostico, cerchiamo nei primi byte senza essere troppo
    // aggressivi per evitare falsi positivi in manufacturerData casuali.
    final maxStart = (data.length - 4).clamp(0, 8);
    for (var i = 1; i <= maxStart; i++) {
      if (looksLikePacketAt(i)) return i;
    }

    return null;
  }

  static String previewHex(Uint8List data, {int maxBytes = 24}) {
    if (data.isEmpty) return '-';
    final n = data.length < maxBytes ? data.length : maxBytes;
    final parts = <String>[];
    for (var i = 0; i < n; i++) {
      parts.add(data[i].toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    if (data.length > n) parts.add('...');
    return parts.join(' ');
  }

  static String? _cleanName(String? s) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  static List<int> _utf8Capped(String s, int maxBytes) {
    final out = <int>[];
    for (final rune in s.runes) {
      final part = utf8.encode(String.fromCharCode(rune));
      if (out.length + part.length > maxBytes) break;
      out.addAll(part);
    }
    return out;
  }

  static List<int> _u16le(int v) => [v & 0xFF, (v >> 8) & 0xFF];

  static List<int> _u32le(int v) => [
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF,
      ];

  static List<int> _i32le(int v) => _u32le(v);

  static int _readU16le(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

  static int _readU32le(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  static int _readI32le(Uint8List b, int o) {
    final u = _readU32le(b, o);
    return (u & 0x80000000) != 0 ? (u - 0x100000000) : u;
  }
}
