import 'dart:async';

import 'package:convoy_mesh/services/diagnostic_recorder.dart';
import 'package:convoy_mesh/services/location_fusion_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Exercises the real service, estimator and track writer. Only the platform
/// input and wall clock are substituted. This does not validate Android GNSS,
/// sensors, foreground-service survival or physical walking.
class _LocationPlatform extends GeolocatorPlatform {
  final positions = StreamController<Position>.broadcast(sync: true);
  final statuses = StreamController<ServiceStatus>.broadcast(sync: true);
  final requestedSettings = <LocationSettings>[];

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Stream<ServiceStatus> getServiceStatusStream() => statuses.stream;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    requestedSettings.add(locationSettings!);
    return positions.stream;
  }
}

class _SilentSensors extends SensorsPlatform {
  final events = StreamController<UserAccelerometerEvent>.broadcast();

  @override
  Stream<UserAccelerometerEvent> userAccelerometerEventStream({
    Duration samplingPeriod = SensorInterval.normalInterval,
  }) => events.stream;
}

class _Harness {
  static final epoch = DateTime.utc(2026, 1, 1);
  DateTime now = epoch;
  final platform = _LocationPlatform();
  final sensors = _SilentSensors();
  late final LocationFusionService service = LocationFusionService.forTest(
    now: () => now,
  );

  void receive(int sourceSeconds, double eastMeters, {int? receivedSeconds}) {
    now = epoch.add(Duration(seconds: receivedSeconds ?? sourceSeconds));
    platform.positions.add(
      Position(
        latitude: 0,
        longitude: eastMeters / 111195,
        timestamp: epoch.add(Duration(seconds: sourceSeconds)),
        accuracy: 3,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ),
    );
  }

  void walk({required int from, required int until, double origin = 0}) {
    for (var second = from; second <= until; second += 5) {
      receive(second, origin + (second - from) * 1.4);
    }
  }

  Future<void> close() async {
    await service.disposeService();
    service.dispose();
    await platform.positions.close();
    await platform.statuses.close();
    await sensors.events.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const permissionChannel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );

  void contractTest(String name, Future<void> Function(_Harness harness) body) {
    test(name, () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final originalPlatform = GeolocatorPlatform.instance;
      final originalSensors = SensorsPlatform.instance;
      final harness = _Harness();
      GeolocatorPlatform.instance = harness.platform;
      SensorsPlatform.instance = harness.sensors;
      messenger.setMockMethodCallHandler(permissionChannel, (call) async {
        expect(call.method, 'checkPermissionStatus');
        return 1; // PermissionStatus.granted.
      });
      // The sensor stream supplies no IMU: actual GPS-only fallback is used.
      try {
        await body(harness);
      } finally {
        DiagnosticRecorder.instance.stop(reason: 'test_cleanup');
        await harness.close();
        GeolocatorPlatform.instance = originalPlatform;
        SensorsPlatform.instance = originalSensors;
        messenger.setMockMethodCallHandler(permissionChannel, null);
      }
    });
  }

  contractTest(
    'preview uses unchanged Android request and never writes a trail',
    (h) async {
      await h.service.startPreview();
      final settings = h.platform.requestedSettings.single as AndroidSettings;
      expect(settings.accuracy, LocationAccuracy.best);
      expect(settings.intervalDuration, const Duration(seconds: 5));
      expect(settings.distanceFilter, 0);
      expect(settings.forceLocationManager, isFalse);
      h.receive(0, 0);
      h.receive(5, 7);
      expect(
        h.service.last!.lat,
        isNull,
        reason: 'Unconfirmed input must not become a preview fix.',
      );
      h.walk(from: 10, until: 80, origin: 14);
      expect(h.service.last!.hasFreshFixAt(h.now), isTrue);
      expect(h.service.last!.lon, greaterThan(80 / 111195));
      expect(h.service.isRecordingTrack, isFalse);
      expect(h.service.trackPoints, isEmpty);
    },
  );

  contractTest('outing resets preview estimator and previous outing trail', (
    h,
  ) async {
    await h.service.startPreview();
    h.walk(from: 0, until: 60);
    await h.service.disposeService();
    await h.service.startOuting();
    expect(h.service.last!.lat, isNull);
    expect(h.service.isRecordingTrack, isTrue);
    h.receive(65, 1000);
    h.receive(70, 1007);
    expect(h.service.trackPoints, isEmpty);
    h.walk(from: 75, until: 145, origin: 1014);
    expect(h.service.trackPoints, isNotEmpty);
    expect(h.service.trackPoints.every((p) => p.lon > 1000 / 111195), isTrue);
    await h.service.disposeService();
    await h.service.startOuting();
    expect(h.service.trackPoints, isEmpty);
    expect(h.service.last!.lat, isNull);
  });

  contractTest(
    'UI age tick and delayed input cannot refresh source freshness',
    (h) async {
      await h.service.startOuting();
      h.receive(0, 0);
      h.receive(5, 0);
      h.receive(10, 0);
      expect(h.service.last!.hasFreshFixAt(h.now), isTrue);
      final coordinateAt = h.service.last!.coordinateAt;
      final measurementAt = h.service.last!.measurementAt;
      h.now = _Harness.epoch.add(const Duration(seconds: 30));
      await h.service.stream
          .firstWhere((fix) => fix.gpsDecision == 'waiting_for_fresh_fix')
          .timeout(const Duration(seconds: 5));
      expect(h.service.last!.gpsDecision, 'waiting_for_fresh_fix');
      expect(h.service.last!.ts, h.now);
      expect(h.service.last!.hasFreshFixAt(h.now), isFalse);
      expect(h.service.last!.measurementAt, measurementAt);
      expect(h.service.last!.coordinateAt, coordinateAt);
      h.receive(12, 50, receivedSeconds: 31);
      expect(h.service.last!.gpsDecision, 'stale_or_future_fix');
      expect(h.service.last!.hasFreshFixAt(h.now), isFalse);
      expect(h.service.last!.measurementAt, measurementAt);
      expect(h.service.trackPoints, isEmpty);
    },
  );

  contractTest('long-gap reacquisition starts a separate real track segment', (
    h,
  ) async {
    await h.service.startOuting();
    h.walk(from: 0, until: 45);
    expect(h.service.trackPoints, isNotEmpty);
    final before = h.service.trackPoints;
    final oldSegment = before.last.segment;
    h.receive(110, 1000);
    expect(h.service.last!.gpsDecision, 'reacquiring');
    h.receive(115, 1000);
    expect(h.service.last!.gpsDecision, 'reacquiring');
    h.receive(120, 1000);
    expect(h.service.last!.gpsDecision, 'reacquired');
    expect(
      h.service.trackPoints,
      hasLength(before.length),
      reason: 'The reacquisition itself must not add a connecting point.',
    );
    h.walk(from: 125, until: 180, origin: 1007);
    final after = h.service.trackPoints.skip(before.length).toList();
    expect(after, isNotEmpty);
    expect(after.every((p) => p.segment == oldSegment + 1), isTrue);
    expect(
      after.every(
        (p) => p.ts.isAfter(_Harness.epoch.add(const Duration(seconds: 120))),
      ),
      isTrue,
    );
  });

  contractTest('stopping location preserves an independently active Test log', (
    h,
  ) async {
    final recorder = DiagnosticRecorder.instance;
    recorder.start(deviceId: 123, deviceName: 'Synthetic service test');
    final sessionId = recorder.sessionId;
    await h.service.startOuting();
    h.walk(from: 0, until: 30);
    final lastMeasurement = h.service.last!.measurementAt;
    await h.service.disposeService();
    expect(recorder.isActive, isTrue);
    expect(recorder.sessionId, sessionId);
    expect(h.service.isRecordingTrack, isFalse);
    expect(h.service.last!.hasFreshFixAt(h.now), isFalse);
    h.receive(35, 1000);
    expect(
      h.service.last!.measurementAt,
      lastMeasurement,
      reason: 'A cancelled position stream must not deliver a late fix.',
    );
    await h.service.startPreview();
    expect(recorder.isActive, isTrue);
    recorder.addMarker('After stopping location');
    recorder.stop(reason: 'synthetic_complete');
    expect(recorder.lastContent, contains('After stopping location'));
  });
}
