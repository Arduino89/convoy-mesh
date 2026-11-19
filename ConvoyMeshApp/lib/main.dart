import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'ble/ble_page.dart';
import 'design/design_controller.dart';
import 'design/design_theme.dart';
import 'design/design_tokens.dart';
import 'design/shell/designed_app_shell.dart';
import 'pages/diagnostic_page.dart';
import 'pages/map_page.dart';
import 'services/app_lifecycle_coordinator.dart';
import 'services/background_runtime_service.dart';
import 'services/convoy_mesh_service.dart';
import 'services/diagnostic_capture_bridge.dart';
import 'services/diagnostic_recorder.dart';
import 'services/location_fusion_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ConvoyMeshApp());
}

class ConvoyMeshApp extends StatelessWidget {
  const ConvoyMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    final design = DesignDirectionController.instance;
    return AnimatedBuilder(
      animation: design,
      builder: (context, _) {
        final tokens = design.activeTokens;
        final theme = tokens == null
            ? ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
                useMaterial3: true,
              )
            : buildConvoyTheme(tokens);
        return MaterialApp(
          title: 'Convoy Mesh',
          debugShowCheckedModeBanner: false,
          theme: theme,
          themeAnimationDuration: Duration.zero,
          home: const AppShell(),
        );
      },
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  final _runtime = BackgroundRuntimeService.instance;
  final _mesh = ConvoyMeshService.instance;
  int _index = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DiagnosticCaptureBridge.instance.attach();
    _runtime.addListener(_changed);
    _runtime.onUnlock = () => _mesh.refreshNow(reason: 'screen_unlocked');
    _runtime.onStopped = () async {
      AppLifecycleCoordinator.instance.runtimeActive = false;
      await _mesh.stopOuting();
      // Diagnostic recording is independent from outing lifetime. Keep it
      // running so one test can span Nearby -> Outing -> Nearby transitions.
      await DiagnosticRecorder.instance.flush();
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        await _ensureNearby();
      } else {
        await _mesh.disposeService();
      }
      if (mounted) setState(() => _error = _runtime.lastError);
    };
    unawaited(_boot());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _boot() async {
    unawaited(DesignDirectionController.instance.load());
    await DiagnosticRecorder.instance.initialize();
    if (mounted) await _ensureNearby();
  }

  /// Foreground lobby: nearby people are visible as soon as both apps are open.
  /// It advertises identity/presence only; GPS/background begin with an outing.
  Future<void> _ensureNearby() async {
    try {
      await _runtime.refreshCapabilities();
      final sdk = _runtime.sdkInt ?? 31;
      if (sdk >= 31) {
        final permissions = await [
          ph.Permission.bluetoothScan,
          ph.Permission.bluetoothConnect,
          ph.Permission.bluetoothAdvertise,
        ].request();
        if (permissions.values.any((v) => !v.isGranted)) {
          throw StateError('Concedi il permesso Dispositivi vicini.');
        }
      }

      // Convoy deliberately uses BLE observations as proximity/location
      // evidence, so the manifest does not claim neverForLocation. Request the
      // matching location permission even in Nearby; this does NOT start GPS
      // tracking or the foreground service. It also makes clean installs behave
      // like devices that previously granted location through an outing.
      final location = await ph.Permission.locationWhenInUse.request();
      if (!location.isGranted) {
        throw StateError(
          'Concedi il permesso Posizione per trovare dispositivi Convoy vicini. '
          'In modalità Vicini non viene avviato il tracking GPS continuo.',
        );
      }

      if (!mounted || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
      if (!_mesh.isRunning) {
        await _mesh.startNearby();
      }
      await _mesh.refreshNow(reason: 'app_open_nearby');
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _startOuting() async {
    if (_busy || _runtime.isRunning) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _ensureNearby();
      final location = await ph.Permission.locationWhenInUse.request();
      if (!location.isGranted) {
        throw StateError('Concedi il permesso Posizione nelle impostazioni app.');
      }
      final sdk = _runtime.sdkInt ?? 31;
      if (sdk >= 31) {
        final permissions = await [
          ph.Permission.bluetoothScan,
          ph.Permission.bluetoothConnect,
          ph.Permission.bluetoothAdvertise,
        ].request();
        if (permissions.values.any((v) => !v.isGranted)) {
          throw StateError('Concedi il permesso Dispositivi vicini.');
        }
      }
      if (sdk >= 33) await ph.Permission.notification.request();
      if (!mounted || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        throw StateError('Torna in Convoy Mesh e premi Avvia uscita.');
      }

      // The map may have started a foreground-only GPS preview. An outing owns
      // a fresh estimator/track, so preview observations never become outing history.
      await LocationFusionService.instance.disposeService();
      await _mesh.startOuting();
      await _runtime.start();
      if (!_runtime.isRunning) {
        throw StateError(_runtime.lastError ?? 'Runtime non attivo');
      }
      AppLifecycleCoordinator.instance.runtimeActive = true;
      await _mesh.refreshNow(reason: 'outing_started');
    } catch (e) {
      AppLifecycleCoordinator.instance.runtimeActive = false;
      await _mesh.stopOuting();
      await _runtime.stop();
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopOuting() async {
    if (_busy) return;
    setState(() => _busy = true);
    AppLifecycleCoordinator.instance.runtimeActive = false;
    // Do not stop an active diagnostic session when the outing ends.
    // The user owns the test session explicitly from the Test log page.
    await DiagnosticRecorder.instance.flush();
    await _mesh.stopOuting();
    await _runtime.stop();
    // Deliberately keep foreground nearby discovery alive.
    await _ensureNearby();
    if (mounted) setState(() => _busy = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(AppLifecycleCoordinator.instance.onStateChanged(state));
    if (state == AppLifecycleState.resumed && !_runtime.isRunning) {
      unawaited(_ensureNearby());
    }
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.detached) &&
        !_runtime.isRunning) {
      // Nearby + map GPS preview are foreground-only. No outing means no
      // background BLE/GPS cost and no foreground service.
      unawaited(LocationFusionService.instance.disposeService());
      unawaited(_mesh.disposeService());
    }
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(DiagnosticRecorder.instance.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _runtime.removeListener(_changed);
    _runtime.onUnlock = null;
    _runtime.onStopped = null;
    AppLifecycleCoordinator.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ConvoyDesignTokens.maybeOf(context);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        // Keep page state mounted, but mute tickers in the two hidden tabs.
        // This affects visual animations only, never BLE/GPS/outing services.
        children: [
          TickerMode(enabled: _index == 0, child: const BlePage()),
          TickerMode(enabled: _index == 1, child: const MapPage()),
          TickerMode(enabled: _index == 2, child: const DiagnosticPage()),
        ],
      ),
      bottomNavigationBar: tokens != null
          ? DesignedBottomDock(
              tokens: tokens,
              selectedIndex: _index,
              onSelectIndex: (i) => setState(() => _index = i),
              outingActive: _runtime.isRunning,
              busy: _busy,
              error: _error,
              onToggleOuting: _runtime.isRunning ? _stopOuting : _startOuting,
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : _runtime.isRunning
                              ? _stopOuting
                              : _startOuting,
                      icon: Icon(
                        _runtime.isRunning
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline,
                      ),
                      label: Text(
                        _busy
                            ? 'Preparazione…'
                            : _runtime.isRunning
                                ? 'Uscita attiva • Termina uscita'
                                : 'Avvia uscita',
                      ),
                    ),
                  ),
                ),
                NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.radar), label: 'Radar BLE'),
                    NavigationDestination(icon: Icon(Icons.map), label: 'Mappa'),
                    NavigationDestination(icon: Icon(Icons.bug_report_outlined), label: 'Test log'),
                  ],
                ),
              ],
            ),
    );
  }
}
