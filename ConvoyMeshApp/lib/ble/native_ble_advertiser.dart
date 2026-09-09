import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Android-native Convoy advertiser.
///
/// Scanning is already native. Keeping advertising native as well removes the
/// plugin/native contract ambiguity that real-device logs exposed: both phones
/// reported successful plugin TX while neither native scanner saw a radio event.
class NativeBleAdvertiser {
  static const MethodChannel _channel = MethodChannel('convoy_mesh/system');

  static Future<void> replace(Uint8List manufacturerPayload) async {
    final ok = await _channel.invokeMethod<bool>(
      'replaceNativeAdvertising',
      <String, Object?>{'payload': manufacturerPayload},
    );
    if (ok != true) {
      throw StateError('Advertising BLE nativo non avviato');
    }
  }

  static Future<void> stop() async {
    await _channel.invokeMethod<bool>('stopNativeAdvertising');
  }
}
