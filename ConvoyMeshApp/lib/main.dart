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
import 'wifi_direct_lab/wifi_direct_lab_controller.dart';
import 'wifi_direct_lab/wifi_direct_lab_page.dart';

/// Compile-time flag isolating the Wi-Fi Direct Offline Lab from Outdoor +20.
/// When true, `AppShell._boot`, `ConvoyMeshService.startNearby()`, and
/// `BackgroundRuntimeService` are never mounted or started.
const bool kConvoyWifiDirectLab =
    bool.fromEnvironment('CONVOY_WIFI_DIRECT_LAB');

/// Integrate the synthetic-only LAB inside the existing Outdoor application.
/// This flag is enabled solely on the isolated Wi-Fi experiment branch.
const bool kConvoyWifiDirectIntegrated =
    bool.fromEnvironment('CONVOY_WIFI_DIRECT_LAB_INTEGRATED');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    kConvoyWifiDirectLab
        ? const WifiDirectOfflineLabApp()
        : const ConvoyMeshApp(),
  );
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
  const AppShell({
    super.key,
    this.wifiDirectIntegrated = kConvoyWifiDirectIntegrated,
    this.wifiLabControllerFactory,
  });

  final bool wifiDirectIntegrated;
  final WifiDirectLabController Function()? wifiLabControllerFactory;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  final _runtime = BackgroundRuntimeService.instance;
  final _mesh = ConvoyMeshService.instance;
  int _index = 0;
  bool _busy = false;
  bool _wifiLabActive = false;
  bool _wifiLabSwitching = false;
  bool _wifiLabRouteOpen = false;
  WifiDirectLabController? _wifiLab;
  Future<void>? _nearbyStartup;
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
    // Resume/permission callbacks must never restart BLE during a Wi-Fi LAB.
    if (_wifiLabActive || _wifiLabSwitching) return;
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

      if (!mounted || _wifiLabActive || _wifiLabSwitching ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      if (!_mesh.isRunning) {
        final startup = _nearbyStartup ??= _mesh.startNearby();
        try {
          await startup;
        } finally {
          if (identical(_nearbyStartup, startup)) _nearbyStartup = null;
        }
      }
      if (!mounted || _wifiLabActive || _wifiLabSwitching) return;
      await _mesh.refreshNow(reason: 'app_open_nearby');
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  // The shell owns the foreground session and the BLE/GPS exclusion, even
  // when the LAB route is popped and the user is browsing another tab.
  Future<void> _openWifiLab() async {
    if (!widget.wifiDirectIntegrated || _wifiLabRouteOpen || _wifiLabSwitching || _busy ||
        (_wifiLab == null && _index != 2)) {
      return;
    }
    if (_runtime.isRunning || DiagnosticRecorder.instance.isActive) {
      setState(() => _error =
          'Termina uscita e registrazione Test log prima del Wi-Fi Direct LAB.');
      return;
    }
    if (_wifiLab == null) {
      setState(() {
        _wifiLabSwitching = true;
        _error = null;
      });
      try {
        // A Nearby startup which has already passed its guard must settle
        // before releasing resources and arming the Wi-Fi session.
        await _nearbyStartup?.catchError((Object _) {});
        await _mesh.disposeService();
        await LocationFusionService.instance.disposeService();
        if (!mounted) return;
        if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
            _runtime.isRunning || DiagnosticRecorder.instance.isActive) {
          return;
        }
        _wifiLab = widget.wifiLabControllerFactory?.call() ?? WifiDirectLabController();
        _wifiLab!.addListener(_wifiLabChanged);
        _wifiLabActive = true;
      } catch (_) {
        if (mounted) setState(() => _error = 'Impossibile preparare il Wi-Fi Direct LAB.');
      } finally {
        if (mounted) {
          setState(() => _wifiLabSwitching = false);
          if (!_wifiLabActive && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
            unawaited(_ensureNearby());
          }
        }
      }
    }
    final controller = _wifiLab;
    if (!mounted || controller == null) return;
    _wifiLabRouteOpen = true;
    var retain = false;
    try {
      final route = MaterialPageRoute<bool>(
        builder: (_) => WifiDirectLabPage(
          controller: controller,
          integratedMode: true,
          shellOwnsSession: true,
        ),
        settings: const RouteSettings(name: '/wifi-direct-lab'),
      );
      retain = await Navigator.of(context).push(route) == true;
      // Release the controller only after the popped route has unmounted.
      await route.completed;
    } finally {
      _wifiLabRouteOpen = false;
      if (mounted && identical(_wifiLab, controller)) {
        if (retain && controller.isGroupFormed) {
          setState(() {});
        } else {
          await _endWifiLab('return_to_outdoor');
        }
      }
    }
  }

  void _wifiLabChanged() {
    if (!_wifiLabRouteOpen && !_wifiLabSwitching && _wifiLab?.isGroupFormed == false) {
      unawaited(_endWifiLab('retained_group_ended'));
    }
  }

  Future<void> _endWifiLab(String reason) async {
    final controller = _wifiLab;
    if (controller == null || _wifiLabSwitching) return;
    setState(() => _wifiLabSwitching = true);
    try {
      await controller.stopAll(reason: reason);
    } finally {
      if (mounted) {
        controller.removeListener(_wifiLabChanged);
        controller.dispose();
        setState(() {
          _wifiLab = null;
          _wifiLabActive = false;
          _wifiLabSwitching = false;
        });
        if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
          await _ensureNearby();
        }
      }
    }
  }

  Future<void> _startOuting() async {
    if (_busy || _wifiLabActive || _wifiLabSwitching || _runtime.isRunning) return;
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

      // Promote an existing foreground GPS preview without restarting its
      // provider/filter. LocationFusionService starts a new trail at promotion.
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
    if (_busy || _wifiLabActive || _wifiLabSwitching) return;
    setState(() => _busy = true);
    AppLifecycleCoordinator.instance.runtimeActive = false;
    // Do not stop an active diagnostic session when the outing ends.
    // The user owns the test session explicitly from the Test log page.
    await DiagnosticRecorder.instance.flush();
    // Only a visible, foreground map owns GPS preview after Outing.
    // Nearby and Test log never silently start continuous GPS tracking.
    final keepMapPreview = _index == 1 &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    await _mesh.stopOuting(keepGpsPreview: keepMapPreview);
    await _runtime.stop();
    // Deliberately keep foreground nearby discovery alive.
    await _ensureNearby();
    if (mounted) setState(() => _busy = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(AppLifecycleCoordinator.instance.onStateChanged(state));
    if (_wifiLabActive || _wifiLabSwitching) {
      final controller = _wifiLab;
      final background = state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused || state == AppLifecycleState.detached;
      if (controller != null && !_wifiLabSwitching) {
        if (background && !_wifiLabRouteOpen) {
          unawaited(_endWifiLab('app_backgrounded_${state.name}'));
        } else {
          unawaited(controller.onAppLifecycleStateChanged(state));
        }
      }
      if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
        unawaited(DiagnosticRecorder.instance.flush());
      }
      return;
    }
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
    _wifiLab?.removeListener(_wifiLabChanged);
    _wifiLab?.dispose();
    AppLifecycleCoordinator.instance.dispose();
    super.dispose();
  }

  Widget _pausedLiveTab(String title) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Per usare BLE o GPS, ferma il Wi-Fi Direct LAB.'),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = ConvoyDesignTokens.maybeOf(context);
    return Scaffold(
      body: Column(
        children: [
          if (_wifiLabActive && !_wifiLabRouteOpen)
            SafeArea(
              bottom: false,
              child: Material(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: ListTile(
                  title: const Text('Wi-Fi Direct LAB attivo'),
                  subtitle: const Text('BLE e GPS sospesi'),
                  onTap: _openWifiLab,
                  trailing: TextButton(
                    key: const Key('wfd_retained_stop'),
                    onPressed: _wifiLabSwitching ? null : () => _endWifiLab('manual_stop'),
                    child: const Text('Stop LAB'),
                  ),
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _index,
              // Keep available tabs mounted and mute their hidden animations.
              // During the LAB, replace the radio-owning tabs with placeholders.
              children: [
                TickerMode(
                  enabled: _index == 0,
                  child: _wifiLabActive || _wifiLabSwitching
                      ? _pausedLiveTab('Radar BLE')
                      : const BlePage(),
                ),
                TickerMode(
                  enabled: _index == 1,
                  child: _wifiLabActive || _wifiLabSwitching
                      ? _pausedLiveTab('Mappa')
                      : const MapPage(),
                ),
                TickerMode(
                  enabled: _index == 2,
                  child: DiagnosticPage(
                    onOpenWifiDirectLab:
                        widget.wifiDirectIntegrated ? _openWifiLab : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: tokens != null
          ? DesignedBottomDock(
              tokens: tokens,
              selectedIndex: _index,
              onSelectIndex: (i) => setState(() => _index = i),
              outingActive: _runtime.isRunning,
              busy: _busy || _wifiLabActive || _wifiLabSwitching,
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
                      onPressed: _busy || _wifiLabActive || _wifiLabSwitching
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
