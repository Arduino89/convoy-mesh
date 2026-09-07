import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'diagnostic_recorder.dart';

class BackgroundRuntimeService extends ChangeNotifier {
  BackgroundRuntimeService._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'runtimeUserPresent') {
        DiagnosticRecorder.instance.record('lifecycle', 'screen_unlocked');
        if (_running) await onUnlock?.call();
      } else if (call.method == 'runtimeStopped') {
        await _onStopped(call.arguments?.toString());
      }
    });
  }
  static final instance = BackgroundRuntimeService._();
  static const _channel = MethodChannel('convoy_mesh/system');
  bool _running = false;
  bool get isRunning => _running;
  int? _sdkInt;
  int? get sdkInt => _sdkInt;
  String? model;
  bool _uwbSupported = false, _wifiRttSupported = false;
  bool _bleExtendedAdvertisingSupported = false, _bleMultipleAdvertisingSupported = false;
  bool get uwbSupported => _uwbSupported;
  bool get wifiRttSupported => _wifiRttSupported;
  bool get bleExtendedAdvertisingSupported => _bleExtendedAdvertisingSupported;
  bool get bleMultipleAdvertisingSupported => _bleMultipleAdvertisingSupported;
  String? _lastError;
  String? get lastError => _lastError;
  Future<void> Function()? onUnlock, onStopped;

  Future<void> initializeAndStart() async { await refreshCapabilities(); await start(); }
  Future<void> start() async {
    try {
      _lastError = null;
      final accepted = await _channel.invokeMethod<bool>('startForegroundRuntime');
      if (accepted != true) throw StateError('Richiesta runtime rifiutata');
      // Native startService acknowledgement is not proof of foreground promotion.
      _running = false;
      for (var i = 0; i < 20; i++) {
        if (await _channel.invokeMethod<bool>('isForegroundRuntimeRunning') == true) {
          _running = true; break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (!_running) {
        await refreshCapabilities();
        throw StateError(_lastError ?? 'Servizio foreground non avviato');
      }
      DiagnosticRecorder.instance.record('runtime', 'foreground_service_started', data: {'verified_running': true});
    } catch (e) {
      _running = false; _lastError = e.toString();
      DiagnosticRecorder.instance.record('runtime', 'foreground_service_error', data: {'error': _lastError});
    }
    notifyListeners();
  }
  Future<void> pulse() async {
    if (!_running) return;
    try {
      if (await _channel.invokeMethod<bool>('runtimePulse') != true) {
        await _onStopped('Runtime nativo non più attivo');
      }
    } catch (e) { await _onStopped(e.toString()); }
  }
  Future<void> _onStopped(String? error) async {
    final wasRunning = _running;
    _running = false; _lastError = error;
    DiagnosticRecorder.instance.record('runtime', 'foreground_service_stopped', data: {'error': error});
    notifyListeners();
    if (wasRunning) await onStopped?.call();
  }
  Future<void> stop() async {
    _running = false;
    try { await _channel.invokeMethod<bool>('stopForegroundRuntime'); _lastError = null; }
    catch (e) { _lastError = e.toString(); }
    notifyListeners();
  }
  Future<void> refreshCapabilities() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('getDeviceCapabilities') ?? {};
      _sdkInt = map['sdkInt'] as int?; model = map['model'] as String?;
      _uwbSupported = map['uwbSupported'] == true;
      _wifiRttSupported = map['wifiRttSupported'] == true;
      _bleExtendedAdvertisingSupported = map['bleExtendedAdvertisingSupported'] == true;
      _bleMultipleAdvertisingSupported = map['bleMultipleAdvertisingSupported'] == true;
      _running = map['foregroundRuntimeRunning'] == true;
      _lastError = map['runtimeError'] as String?;
      DiagnosticRecorder.instance.record('capability', 'device', data: {
        'sdk_int': _sdkInt, 'model': model, 'uwb': _uwbSupported, 'wifi_rtt': _wifiRttSupported,
        'ble_extended_advertising': _bleExtendedAdvertisingSupported,
        'ble_multiple_advertising': _bleMultipleAdvertisingSupported, 'ranging_active': false,
        'foreground_runtime_running': _running,
      });
    } catch (e) { _lastError = e.toString(); }
    notifyListeners();
  }
}
