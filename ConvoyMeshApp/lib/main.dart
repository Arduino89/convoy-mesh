import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'ble/ble_page.dart';
import 'pages/diagnostic_page.dart';
import 'pages/map_page.dart';
import 'services/app_lifecycle_coordinator.dart';
import 'services/background_runtime_service.dart';
import 'services/convoy_mesh_service.dart';
import 'services/diagnostic_capture_bridge.dart';
import 'services/diagnostic_recorder.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const ConvoyMeshApp()); }
class ConvoyMeshApp extends StatelessWidget {
  const ConvoyMeshApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(title: 'Convoy Mesh', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey), useMaterial3: true),
    home: const AppShell());
}
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}
class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  final _runtime = BackgroundRuntimeService.instance;
  int _index = 0;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DiagnosticCaptureBridge.instance.attach();
    _runtime.addListener(_changed);
    _runtime.onUnlock = () => ConvoyMeshService.instance.refreshNow(reason: 'screen_unlocked');
    _runtime.onStopped = () async {
      AppLifecycleCoordinator.instance.runtimeActive = false;
      await ConvoyMeshService.instance.disposeService();
      DiagnosticRecorder.instance.stop(reason: 'outing_stopped');
      await DiagnosticRecorder.instance.flush();
      if (mounted) setState(() => _error = _runtime.lastError);
    };
    unawaited(_boot());
  }
  void _changed() { if (mounted) setState(() {}); }
  Future<void> _boot() async {
    await DiagnosticRecorder.instance.initialize();
    if (mounted) await _startOuting();
  }
  Future<void> _startOuting() async {
    if (_busy || _runtime.isRunning) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _runtime.refreshCapabilities();
      final location = await ph.Permission.locationWhenInUse.request();
      if (!location.isGranted) throw StateError('Concedi il permesso Posizione nelle impostazioni app.');
      if ((_runtime.sdkInt ?? 31) >= 31) {
        final permissions = await [ph.Permission.bluetoothScan, ph.Permission.bluetoothConnect,
          ph.Permission.bluetoothAdvertise].request();
        if (permissions.values.any((v) => !v.isGranted)) throw StateError('Concedi il permesso Dispositivi vicini.');
      }
      if ((_runtime.sdkInt ?? 33) >= 33) await ph.Permission.notification.request();
      if (!mounted) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        throw StateError('Torna in Convoy Mesh e premi Avvia uscita.');
      }
      await ConvoyMeshService.instance.start();
      await _runtime.start();
      if (!_runtime.isRunning) throw StateError(_runtime.lastError ?? 'Runtime non attivo');
      AppLifecycleCoordinator.instance.runtimeActive = true;
      await ConvoyMeshService.instance.refreshNow(reason: 'outing_started');
    } catch (e) {
      AppLifecycleCoordinator.instance.runtimeActive = false;
      await ConvoyMeshService.instance.disposeService();
      await _runtime.stop();
      _error = e.toString();
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _stopOuting() async {
    if (_busy) return;
    setState(() => _busy = true);
    AppLifecycleCoordinator.instance.runtimeActive = false;
    DiagnosticRecorder.instance.stop(reason: 'outing_stopped');
    await DiagnosticRecorder.instance.flush();
    await ConvoyMeshService.instance.disposeService();
    await _runtime.stop();
    if (mounted) setState(() => _busy = false);
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(AppLifecycleCoordinator.instance.onStateChanged(state));
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(DiagnosticRecorder.instance.flush());
    }
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _runtime.removeListener(_changed);
    _runtime.onUnlock = null; _runtime.onStopped = null;
    AppLifecycleCoordinator.instance.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _index, children: const [BlePage(), MapPage(), DiagnosticPage()]),
    bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
      if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(_error!, style: const TextStyle(color: Colors.red), maxLines: 3, overflow: TextOverflow.ellipsis)),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: SizedBox(width: double.infinity,
        child: OutlinedButton.icon(onPressed: _busy ? null : _runtime.isRunning ? _stopOuting : _startOuting,
          icon: Icon(_runtime.isRunning ? Icons.stop_circle_outlined : Icons.play_circle_outline),
          label: Text(_busy ? 'Preparazione…' : _runtime.isRunning ? 'Uscita attiva • Termina uscita' : 'Avvia uscita')))),
      NavigationBar(selectedIndex: _index, onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [NavigationDestination(icon: Icon(Icons.radar), label: 'Radar BLE'),
          NavigationDestination(icon: Icon(Icons.map), label: 'Mappa'),
          NavigationDestination(icon: Icon(Icons.bug_report_outlined), label: 'Test log')]),
    ]));
}
