import 'dart:typed_data';
import 'package:flutter/services.dart';

class BleAdvertisement {
  const BleAdvertisement({required this.id, required this.rssi,
    required this.manufacturerData, this.observedElapsedNanos});
  final String id;
  final int rssi;
  final Uint8List manufacturerData;
  final int? observedElapsedNanos;
}

/// Native Android manufacturer-data filter. No unfiltered fallback on error.
class NativeBleScan {
  static const _channel = EventChannel('convoy_mesh/filtered_scan');
  static Stream<BleAdvertisement> scan() => _channel.receiveBroadcastStream().map((raw) {
    final event = Map<Object?, Object?>.from(raw as Map);
    return BleAdvertisement(id: event['id'] as String,
      rssi: event['rssi'] as int,
      manufacturerData: event['data'] as Uint8List,
      observedElapsedNanos: event['observed_elapsed_nanos'] as int?);
  });
}
