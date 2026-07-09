import 'package:flutter/services.dart';

class SystemIntents {
  static const _ch = MethodChannel('convoy_mesh/system');

  static Future<void> openBluetoothSettings() async {
    try {
      await _ch.invokeMethod('openBluetoothSettings');
    } catch (_) {
      // fallback: niente (evitiamo crash)
    }
  }

  static Future<void> openLocationSettings() async {
    try {
      await _ch.invokeMethod('openLocationSettings');
    } catch (_) {
      // fallback: niente (evitiamo crash)
    }
  }
}
