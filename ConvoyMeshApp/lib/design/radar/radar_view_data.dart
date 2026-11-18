import 'package:flutter/foundation.dart';

/// Presentation-only snapshot of the Radar BLE screen.
///
/// Built either from the live services (`radar_live_adapter.dart`) or from
/// synthetic fixtures (design studio / tests). Widgets consume only this
/// object, which keeps the graphic layer independent from BLE/GPS logic.
@immutable
class RadarViewData {
  const RadarViewData({
    required this.bleStatusName,
    required this.bleLabel,
    required this.bleReady,
    required this.scanning,
    required this.advertising,
    required this.onlineCount,
    required this.offlineCount,
    required this.modeText,
    required this.outingActive,
    required this.gpsFresh,
    required this.filterLine,
    required this.myName,
    required this.myId,
    required this.peers,
    required this.diagnosticsLines,
  });

  final String bleStatusName;
  final String bleLabel;
  final bool bleReady;
  final bool scanning;
  final bool advertising;
  final int onlineCount;
  final int offlineCount;

  /// Same sentence as the original screen's mode line.
  final String modeText;
  final bool outingActive;
  final bool gpsFresh;

  /// "Filtro: … • sensore movimento …" (only during an outing with a fix).
  final String? filterLine;
  final String myName;
  final int myId;

  /// Already ordered by most recent valid packet first.
  final List<RadarPeerView> peers;

  /// Lines of the "Diagnostica BLE" panel, verbatim from the original.
  final List<String> diagnosticsLines;
}

enum PeerLocationState { fresh, searching, off }

@immutable
class RadarPeerView {
  const RadarPeerView({
    required this.userId,
    required this.name,
    required this.color,
    required this.online,
    required this.gpsLine,
    required this.accuracyLine,
    required this.historyLine,
    required this.signalQuality,
    required this.rssi,
    required this.lastPacketLine,
    required this.locationState,
  });

  final int userId;
  final String name;

  /// ARGB colour assigned to the user by the existing service palette.
  final int color;
  final bool online;
  final String gpsLine;
  final String? accuracyLine;
  final String? historyLine;

  /// "Ottimo" / "Buono" / "Medio" / "Scarso" / "non disponibile".
  final String signalQuality;
  final int rssi;
  final String lastPacketLine;
  final PeerLocationState locationState;

  String get statusLabel => online ? 'presente' : 'segnale non ricevuto';

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts.first;
      return (p.length >= 2 ? p.substring(0, 2) : p).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  /// 0 = unavailable, 1..4 mirrors the thresholds of
  /// `ConvoyMeshService.rssiQuality` (Scarso, Medio, Buono, Ottimo).
  /// It is a signal-quality bucket, NOT a distance.
  int get signalLevel => signalLevelForRssi(rssi);

  static int signalLevelForRssi(int rssi) {
    if (rssi >= 0 || rssi < -127) return 0;
    if (rssi >= -60) return 4;
    if (rssi >= -70) return 3;
    if (rssi >= -80) return 2;
    return 1;
  }

  String get signalLine =>
      'Segnale BLE: $signalQuality • mediana $rssi dBm';
}
