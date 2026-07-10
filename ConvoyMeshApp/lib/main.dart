import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'ble/ble_page.dart';
import 'pages/diagnostic_page.dart';
import 'pages/map_page.dart';
import 'services/convoy_mesh_service.dart';
import 'services/diagnostic_capture_bridge.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ConvoyMeshApp());
}

class ConvoyMeshApp extends StatelessWidget {
  const ConvoyMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Convoy Mesh',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    DiagnosticCaptureBridge.instance.attach();
    _boot();
  }

  Future<void> _boot() async {
    await ph.Permission.locationWhenInUse.request();
    await ph.Permission.bluetoothScan.request();
    await ph.Permission.bluetoothConnect.request();
    await ph.Permission.bluetoothAdvertise.request();

    await ConvoyMeshService.instance.start();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const BlePage(),
      const MapPage(),
      const DiagnosticPage(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.radar), label: 'Radar BLE'),
          NavigationDestination(icon: Icon(Icons.map), label: 'Mappa'),
          NavigationDestination(icon: Icon(Icons.bug_report_outlined), label: 'Test log'),
        ],
      ),
    );
  }
}
