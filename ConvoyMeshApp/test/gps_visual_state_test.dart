import 'package:convoy_mesh/location/fused_location.dart';
import 'package:convoy_mesh/location/gps_visual_state.dart';
import 'package:flutter_test/flutter_test.dart';

FusedLocation fix({
  required DateTime now,
  required bool permission,
  required bool enabled,
  required int quality,
  required int bars,
  required double accuracy,
  DateTime? measured,
}) => FusedLocation(
      lat: measured == null ? null : 45.0,
      lon: measured == null ? null : 10.0,
      accuracyM: measured == null ? null : accuracy,
      rawLat: measured == null ? null : 45.0,
      rawLon: measured == null ? null : 10.0,
      rawAccuracyM: measured == null ? null : accuracy,
      hasPermission: permission,
      serviceEnabled: enabled,
      gpsState: measured == null ? GpsUiState.searching : GpsUiState.ok,
      gpsBars: bars,
      gpsQuality: quality,
      ts: now,
      measurementAt: measured,
      coordinateAt: measured,
      isMoving: false,
      motionReliable: true,
      motionScore: 0,
      gpsDecision: measured == null ? 'acquiring' : 'anchored',
      gpsReason: measured == null ? 'acquiring' : 'anchored',
    );

void main() {
  final now = DateTime.utc(2026, 9, 11, 12);

  test('not started or unavailable is steady red/off', () {
    expect(GpsVisualState.from(null, now).mode, GpsVisualMode.off);
    final state = GpsVisualState.from(
      fix(now: now, permission: true, enabled: false, quality: 0, bars: 0, accuracy: 999),
      now,
    );
    expect(state.mode, GpsVisualMode.off);
    expect(state.blinks, isFalse);
  });

  test('active acquisition is slow red/searching pulse', () {
    final state = GpsVisualState.from(
      fix(now: now, permission: true, enabled: true, quality: 0, bars: 0, accuracy: 999),
      now,
    );
    expect(state.mode, GpsVisualMode.searching);
    expect(state.blinkPeriod, const Duration(milliseconds: 1500));
  });

  test('good recent fix is steady green', () {
    final state = GpsVisualState.from(
      fix(
        now: now,
        permission: true,
        enabled: true,
        quality: 90,
        bars: 3,
        accuracy: 9,
        measured: now.subtract(const Duration(seconds: 2)),
      ),
      now,
    );
    expect(state.mode, GpsVisualMode.stable);
    expect(state.isGreen, isTrue);
    expect(state.blinks, isFalse);
  });

  test('recent but weak fix stays green and pulses faster as quality worsens', () {
    final medium = GpsVisualState.from(
      fix(
        now: now,
        permission: true,
        enabled: true,
        quality: 65,
        bars: 2,
        accuracy: 24,
        measured: now.subtract(const Duration(seconds: 2)),
      ),
      now,
    );
    final weak = GpsVisualState.from(
      fix(
        now: now,
        permission: true,
        enabled: true,
        quality: 25,
        bars: 1,
        accuracy: 70,
        measured: now.subtract(const Duration(seconds: 2)),
      ),
      now,
    );
    expect(medium.mode, GpsVisualMode.unstable);
    expect(weak.mode, GpsVisualMode.unstable);
    expect(weak.blinkPeriod!.inMilliseconds, lessThan(medium.blinkPeriod!.inMilliseconds));
  });

  test('stale measurement becomes searching even if old coordinates remain', () {
    final state = GpsVisualState.from(
      fix(
        now: now,
        permission: true,
        enabled: true,
        quality: 90,
        bars: 4,
        accuracy: 5,
        measured: now.subtract(const Duration(seconds: 20)),
      ),
      now,
    );
    expect(state.mode, GpsVisualMode.searching);
  });
}
