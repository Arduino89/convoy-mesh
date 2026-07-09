import 'package:flutter/material.dart';
import '../ble/ble_controller.dart';

class BleScreen extends StatefulWidget {
  const BleScreen({super.key});

  @override
  State<BleScreen> createState() => _BleScreenState();
}

class _BleScreenState extends State<BleScreen> {
  final BleController _ble = BleController();
  bool permissionsOk = false;
  bool bluetoothOn = false;

  @override
  void initState() {
    super.initState();
    initBle();
  }

  Future<void> initBle() async {
    permissionsOk = await _ble.checkPermissions();
    bluetoothOn = await _ble.isBluetoothOn();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Convoy Mesh – BLE")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusRow(
              "Permessi",
              permissionsOk,
            ),
            _buildStatusRow(
              "Bluetooth",
              bluetoothOn,
            ),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                onPressed: permissionsOk && bluetoothOn && !_ble.isScanning
                    ? () {
                  _ble.startScan();
                  setState(() {});
                }
                    : null,
                icon: const Icon(Icons.search),
                label: Text(_ble.isScanning ? "Scansione in corso..." : "Scansiona dispositivi"),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder(
                stream: _ble.scanResultsStream,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: Text("Nessun dispositivo ancora..."));
                  }

                  final devices = snapshot.data!;

                  return ListView(
                    children: devices.map((d) {
                      return ListTile(
                        leading: const Icon(Icons.bluetooth),
                        title: Text(d.name ?? "Sconosciuto"),
                        subtitle: Text("ID: ${d.id}\nRSSI: ${d.rssi} dBm"),
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
  }

  Widget _buildStatusRow(String label, bool ok) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 12),
        Icon(
          ok ? Icons.check_circle : Icons.cancel,
          color: ok ? Colors.green : Colors.red,
        )
      ],
    );
  }
}
