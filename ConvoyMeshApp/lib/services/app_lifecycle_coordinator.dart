import 'dart:async';

import 'package:flutter/widgets.dart';

import 'convoy_mesh_service.dart';
import 'diagnostic_recorder.dart';

class AppLifecycleCoordinator {
  AppLifecycleCoordinator._();

  static final AppLifecycleCoordinator instance = AppLifecycleCoordinator._();

  // Deve restare sotto peerOnlineTtl (15 s), altrimenti il ricevente mostra
  // falsi offline tra un heartbeat e il successivo.
  static const Duration backgroundHeartbeatEvery = Duration(seconds: 10);

  Timer? _backgroundHeartbeat;
  AppLifecycleState _lastState = AppLifecycleState.resumed;

  AppLifecycleState get lastState => _lastState;
  bool get isForeground => _lastState == AppLifecycleState.resumed;

  Future<void> onStateChanged(AppLifecycleState state) async {
    if (_lastState == state) return;
    _lastState = state;

    DiagnosticRecorder.instance.record(
      'lifecycle',
      'state',
      data: <String, Object?>{'state': state.name},
    );

    if (state == AppLifecycleState.resumed) {
      _backgroundHeartbeat?.cancel();
      _backgroundHeartbeat = null;

      // App/schermo di nuovo attivi: annuncio immediato e scan ripulito.
      ConvoyMeshService.instance.spamMyNameNow();
      await ConvoyMeshService.instance.restartScanForDebug(reason: 'app_resumed');

      DiagnosticRecorder.instance.record(
        'lifecycle',
        'instant_refresh',
        data: const <String, Object?>{'reason': 'app_resumed'},
      );
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _startBackgroundHeartbeat();
    }
  }

  void _startBackgroundHeartbeat() {
    if (_backgroundHeartbeat != null) return;

    // Un primo segnale subito, poi heartbeat leggero ogni 10 secondi.
    ConvoyMeshService.instance.spamMyNameNow();
    DiagnosticRecorder.instance.record(
      'lifecycle',
      'background_heartbeat',
      data: const <String, Object?>{'phase': 'immediate'},
    );

    _backgroundHeartbeat = Timer.periodic(backgroundHeartbeatEvery, (_) {
      ConvoyMeshService.instance.spamMyNameNow();
      DiagnosticRecorder.instance.record(
        'lifecycle',
        'background_heartbeat',
        data: <String, Object?>{
          'phase': 'periodic',
          'interval_seconds': backgroundHeartbeatEvery.inSeconds,
        },
      );
    });
  }

  void dispose() {
    _backgroundHeartbeat?.cancel();
    _backgroundHeartbeat = null;
  }
}
