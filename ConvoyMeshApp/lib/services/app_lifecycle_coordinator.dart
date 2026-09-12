import 'package:flutter/widgets.dart';
import 'convoy_mesh_service.dart';
import 'diagnostic_recorder.dart';

class AppLifecycleCoordinator {
  AppLifecycleCoordinator._();
  static final instance = AppLifecycleCoordinator._();
  AppLifecycleState _lastState = AppLifecycleState.resumed;
  bool runtimeActive = false;
  AppLifecycleState get lastState => _lastState;
  bool get isForeground => _lastState == AppLifecycleState.resumed;

  Future<void> onStateChanged(AppLifecycleState state) async {
    if (_lastState == state) return;
    _lastState = state;
    DiagnosticRecorder.instance.record('lifecycle', 'state', data: {'state': state.name});
    // The mesh scheduler owns periodic POS/NAME/PING in every lifecycle state.
    // Permission dialogs must not create additional timers or force NAME bursts.
    if (state == AppLifecycleState.resumed && runtimeActive) {
      await ConvoyMeshService.instance.refreshNow(reason: 'app_resumed');
    }
  }
  void dispose() { runtimeActive = false; }
}
