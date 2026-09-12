import 'package:flutter/material.dart';

import '../ble/ble_controller.dart';
import '../ble/ble_models.dart';

class BleScreen extends StatefulWidget {
  const BleScreen({super.key});

  @override
  State<BleScreen> createState() => _BleScreenState();
}

class _BleScreenState extends State<BleScreen> {
  final BleController _ble = BleController();

  @override
  void dispose() {
    _ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BleStatusUi>(
      stream: _ble.statusStream,
      initialData: _ble.statusNow,
      builder: (context, statusSnapshot) {
        final status = statusSnapshot.data ?? BleStatusUi.unknown;
        final bluetoothReady = status == BleStatusUi.ready;

        return Scaffold(
          appBar: AppBar(title: const Text('Convoy Mesh – BLE')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusRow('Bluetooth', _statusLabel(status), bluetoothReady),
                const SizedBox(height: 24),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: bluetoothReady
                        ? () async {
                            if (_ble.isScanning) {
                              await _ble.stopScan();
                            } else {
                              await _ble.startScan();
                            }
                            if (mounted) setState(() {});
                          }
                        : null,
                    icon: Icon(_ble.isScanning ? Icons.stop : Icons.search),
                    label: Text(_ble.isScanning ? 'Ferma scansione' : 'Scansiona dispositivi'),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: StreamBuilder<List<BleDeviceData>>(
                    stream: _ble.devicesStream,
                    initialData: const <BleDeviceData>[],
                    builder: (context, snapshot) {
                      final devices = snapshot.data ?? const <BleDeviceData>[];
                      if (devices.isEmpty) {
                        return const Center(child: Text('Nessun dispositivo ancora...'));
                      }

                      return ListView(
                        children: devices.map((d) {
                          return ListTile(
                            leading: const Icon(Icons.bluetooth),
                            title: Text(d.name),
                            subtitle: Text('ID: ${d.id}\nRSSI: ${d.rssi} dBm'),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _statusLabel(BleStatusUi status) {
    switch (status) {
      case BleStatusUi.ready:
        return 'Pronto';
      case BleStatusUi.poweredOff:
        return 'Spento';
      case BleStatusUi.unauthorized:
        return 'Permesso negato';
      case BleStatusUi.unknown:
        return 'Sconosciuto';
    }
  }

  Widget _buildStatusRow(String label, String value, bool ok) {
    return Row(
      children: [
        Text('$label: $value', style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 12),
        Icon(
          ok ? Icons.check_circle : Icons.cancel,
          color: ok ? Colors.green : Colors.red,
        ),
      ],
    );
  }
}
