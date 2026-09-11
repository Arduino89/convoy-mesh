import 'fused_location.dart';

enum GpsVisualMode { off, searching, stable, unstable }

class GpsVisualState {
  const GpsVisualState({
    required this.mode,
    required this.quality,
    required this.blinkPeriod,
    required this.label,
  });

  final GpsVisualMode mode;
  final int quality;
  final Duration? blinkPeriod;
  final String label;

  bool get isGreen => mode == GpsVisualMode.stable || mode == GpsVisualMode.unstable;
  bool get blinks => blinkPeriod != null;

  static GpsVisualState from(FusedLocation? fix, DateTime now) {
    if (fix == null || !fix.hasPermission || !fix.serviceEnabled) {
      return const GpsVisualState(
        mode: GpsVisualMode.off,
        quality: 0,
        blinkPeriod: null,
        label: 'Posizione non agganciata',
      );
    }

    if (!fix.hasFreshFixAt(now)) {
      return const GpsVisualState(
        mode: GpsVisualMode.searching,
        quality: 0,
        blinkPeriod: Duration(milliseconds: 1500),
        label: 'Ricerca posizione…',
      );
    }

    final quality = fix.gpsQuality.clamp(0, 100).toInt();
    final accuracy = fix.accuracyM ?? double.infinity;
    if (quality >= 80 && accuracy <= 15 && fix.gpsBars >= 3) {
      return GpsVisualState(
        mode: GpsVisualMode.stable,
        quality: quality,
        blinkPeriod: null,
        label: 'GPS agganciato • qualità $quality%',
      );
    }

    // Poorer lock => faster pulse. A marginal but usable fix pulses slowly;
    // very uncertain fixes become increasingly obvious without turning red,
    // because a real recent position still exists.
    final reliability = (quality / 80.0).clamp(0.0, 1.0);
    final milliseconds = (550 + reliability * 1250).round();
    return GpsVisualState(
      mode: GpsVisualMode.unstable,
      quality: quality,
      blinkPeriod: Duration(milliseconds: milliseconds),
      label: 'GPS agganciato ma instabile • qualità $quality%',
    );
  }
}
