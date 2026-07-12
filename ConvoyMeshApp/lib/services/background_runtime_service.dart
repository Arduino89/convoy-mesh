import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'diagnostic_recorder.dart';

class BackgroundRuntimeService extends ChangeNotifier {
  BackgroundRuntimeService._();

  static final BackgroundRuntimeService instance = BackgroundRuntimeService._();
  static const MethodChannel _channel = MethodChannel('convoy_mesh/system');

  bool _running = false;
  bool get isRunning => _running;

  int? _sdkInt;
  int? get sdkInt => _sdkInt;

  bool _uwbSupported = false;
  bool get uwbSupported => _uwbSupported;

  bool _wifiRttSupported = false;
  bool get wifiRttSupported => _wifiRttSupported;

  bool _bleExtendedAdvertisingSupported = false;
  bool get bleExtendedAdvertisingSupported => _bleExtendedAdvertisingSupported;

  bool _bleMultipleAdvertisingSupported = false;
  bool get bleMultipleAdvertisingSupported => _bleMultipleAdvertisingSupported;

  String? _lastError;
  String? get lastError => _lastError;

  Future<void> initializeAndStart() async {
    await refreshCapabilities();
    await start();
  }

  Future<void> start() async {
    try {
      final result = await _channel.invokeMethod<bool>('startForegroundRuntime');
      _running = result ?? false;
      _lastError = null;
      DiagnosticRecorder.instance.record(
        'runtime',
        'foreground_service_start',
        data: <String, Object?>{'ok': _running},
      );
    } catch (error) {
      _running = false;
      _lastError = error.toString();
      DiagnosticRecorder.instance.record(
        'runtime',
        'foreground_service_error',
        data: <String, Object?>{'error': _lastError},
      );
    }
    notifyListeners();
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stopForegroundRuntime');
      _running = false;
      _lastError = null;
    } catch (error) {
      _lastError = error.toString();
    }
    notifyListeners();
  }

  Future<void> refreshCapabilities() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('getDeviceCapabilities');
      final map = raw ?? const <String, dynamic>{};
      _sdkInt = map['sdkInt'] as int?;
      _uwbSupported = map['uwbSupported'] == true;
      _wifiRttSupported = map['wifiRttSupported'] == true;
      _bleExtendedAdvertisingSupported = map['bleExtendedAdvertisingSupported'] == true;
      _bleMultipleAdvertisingSupported = map['bleMultipleAdvertisingSupported'] == true;
      _running = map['foregroundRuntimeRunning'] == true;
      _lastError = null;

      DiagnosticRecorder.instance.record(
        'capability',
        'device',
        data: <String, Object?>{
          'sdk_int': _sdkInt,
          'uwb': _uwbSupported,
          'wifi_rtt': _wifiRttSupported,
          'ble_extended_advertising': _bleExtendedAdvertisingSupported,
          'ble_multiple_advertising': _bleMultipleAdvertisingSupported,
        },
      );
    } catch (error) {
      _lastError = error.toString();
    }
    notifyListeners();
  }
}
