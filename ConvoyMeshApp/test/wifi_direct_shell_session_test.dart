import 'dart:async';

import 'package:convoy_mesh/ble/ble_page.dart';
import 'package:convoy_mesh/main.dart';
import 'package:convoy_mesh/pages/map_page.dart';
import 'package:convoy_mesh/services/convoy_mesh_service.dart';
import 'package:convoy_mesh/services/diagnostic_capture_bridge.dart';
import 'package:convoy_mesh/services/location_fusion_service.dart';
import 'package:convoy_mesh/wifi_direct_lab/wifi_direct_lab_controller.dart';
import 'package:convoy_mesh/wifi_direct_lab/wifi_direct_lab_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wifi_direct_offline_lab_test.dart'
    show FakeWifiDirectPlatformBridge, PairedInMemorySocketTransport;

void main() {
  testWidgets('Outdoor shell retains the group across safe tabs and stops it on background', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    Timer? bridgeTimer;
    runZoned(
      () => DiagnosticCaptureBridge.instance.attach(),
      zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          final timer = parent.createPeriodicTimer(zone, duration, callback);
          bridgeTimer = timer;
          return timer;
        },
      ),
    );
    final bridge = FakeWifiDirectPlatformBridge();
    final (socket, _) = PairedInMemorySocketTransport.createPair();
    final controller = WifiDirectLabController(platform: bridge, socketTransport: socket);
    try {
      await tester.pumpWidget(MaterialApp(home: AppShell(
        wifiDirectIntegrated: true,
        wifiLabControllerFactory: () => controller,
      )));
      await tester.pumpAndSettle();
      tester.widget<NavigationBar>(find.byType(NavigationBar)).onDestinationSelected!(2);
      await tester.pumpAndSettle();
      final labButton = find.byKey(const Key('diag-open-wifi-lab-btn'));
      await tester.tap(labButton);
      for (var i = 0; i < 20 && find.byType(WifiDirectLabPage).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(find.byType(WifiDirectLabPage), findsOneWidget);
      expect(find.byKey(const Key('wfd_keep_group')), findsNothing);
      expect(await controller.requestDiscovery(), isTrue);
      bridge.emit({'type': 'group_formed', 'role': 'group_owner'});
      await tester.pumpAndSettle();
      expect(controller.isSocketOpen, isTrue);
      await tester.tap(find.byKey(const Key('wfd_keep_group')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wfd_retained_stop')), findsOneWidget);
      expect(bridge.stopCalls, 0);

      for (final tab in [0, 1, 2]) {
        tester.widget<NavigationBar>(find.byType(NavigationBar)).onDestinationSelected!(tab);
        await tester.pumpAndSettle();
        expect(find.byType(BlePage), findsNothing);
        expect(find.byType(MapPage), findsNothing);
        expect(find.byKey(const Key('wfd_retained_stop')), findsOneWidget);
        expect(controller.isSocketOpen, isTrue);
        expect(ConvoyMeshService.instance.isRunning, isFalse);
        expect(LocationFusionService.instance.last?.serviceEnabled, isFalse);
        expect(LocationFusionService.instance.isRecordingTrack, isFalse);
      }

      await tester.tap(find.byKey(const Key('diag-open-wifi-lab-btn')));
      await tester.pumpAndSettle();
      expect(controller.isSocketOpen, isTrue);
      await tester.tap(find.byKey(const Key('wfd_keep_group')));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(bridge.stopCalls, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(controller.isSocketOpen, isFalse);
      expect(bridge.lastStopReason, 'app_backgrounded_paused');
      // Flutter suppresses frames while paused; check the presented state on resume.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wfd_retained_stop')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      bridgeTimer?.cancel();
      await bridge.dispose();
    }
  });

}
