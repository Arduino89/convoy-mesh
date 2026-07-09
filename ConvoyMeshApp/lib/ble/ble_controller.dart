import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'ble_models.dart';

enum BleStatusUi {
  unknown,
  poweredOff,
  unauthorized,
  ready,
}

class BleController {
  final FlutterReactiveBle _ble = FlutterReactiveBle();

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<BleStatus>? _statusSub;

  final Map<String, BleDeviceData> _devices = {};
  final _devicesCtrl = StreamController<List<BleDeviceData>>.broadcast();

  BleStatusUi _statusUi = BleStatusUi.unknown;
  final _statusCtrl = StreamController<BleStatusUi>.broadcast();

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  Stream<List<BleDeviceData>> get devicesStream => _devicesCtrl.stream;
  Stream<BleStatusUi> get statusStream => _statusCtrl.stream;
  BleStatusUi get statusNow => _statusUi;

  BleController() {
    _statusSub = _ble.statusStream.listen((s) {
      _statusUi = _mapStatus(s);
      _statusCtrl.add(_statusUi);

      // Se torna "ready" e stavi scansionando, non fare nulla:
      // lo scan lo gestiamo esplicitamente dai bottoni.
    }, onError: (_) {
      _statusUi = BleStatusUi.unknown;
      _statusCtrl.add(_statusUi);
    });
  }

  BleStatusUi _mapStatus(BleStatus s) {
    switch (s) {
      case BleStatus.ready:
        return BleStatusUi.ready;
      case BleStatus.poweredOff:
        return BleStatusUi.poweredOff;
      case BleStatus.unauthorized:
        return BleStatusUi.unauthorized;
      case BleStatus.unknown:
      default:
        return BleStatusUi.unknown;
    }
  }

  void clearDevices() {
    _devices.clear();
    _pushDevices();
  }

  Future<void> startScan() async {
    if (_isScanning) return;
    _isScanning = true;

    // Scan di "tutti" (withServices: [])
    _scanSub = _ble
        .scanForDevices(
      withServices: const [],
      scanMode: ScanMode.lowLatency,
    )
        .listen((d) {
      final now = DateTime.now();
      final name = (d.name.isNotEmpty) ? d.name : "Sconosciuto";
      final id = d.id;

      final prev = _devices[id];
      _devices[id] = (prev == null)
          ? BleDeviceData(id: id, name: name, rssi: d.rssi, lastSeen: now)
          : prev.copyWith(name: name, rssi: d.rssi, lastSeen: now);

      _pushDevices();
    }, onError: (e) {
      debugPrint("Errore scan BLE: $e");
      _isScanning = false;
      _pushDevices();
    });
  }

  Future<void> stopScan() async {
    if (!_isScanning) return;
    _isScanning = false;
    await _scanSub?.cancel();
    _scanSub = null;
    _pushDevices();
  }

  void _pushDevices() {
    final list = _devices.values.toList()
      ..sort((a, b) {
        // più “recenti” sopra, poi RSSI migliore
        final t = b.lastSeen.compareTo(a.lastSeen);
        if (t != 0) return t;
        return b.rssi.compareTo(a.rssi);
      });
    _devicesCtrl.add(list);
  }

  Future<void> dispose() async {
    await stopScan();
    await _statusSub?.cancel();
    await _devicesCtrl.close();
    await _statusCtrl.close();
  }
}
