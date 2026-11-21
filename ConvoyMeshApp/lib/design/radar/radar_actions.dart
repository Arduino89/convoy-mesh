import 'package:flutter/foundation.dart';

/// Callbacks from the redesigned Radar to the functional layer.
///
/// In the app they are wired by `BlePage` to exactly the same methods the
/// original buttons call; in the design studio they are simulated.
@immutable
class RadarActions {
  const RadarActions({
    required this.onStatusTap,
    required this.onHelp,
    required this.onEditName,
    required this.onOpenBluetooth,
    required this.onOpenLocation,
    required this.onOpenAppPermissions,
    required this.onSendName,
    required this.onRestartScan,
    required this.onClearOffline,
    required this.onRegenerateId,
    required this.onChooseDesign,
  });

  final VoidCallback onStatusTap;
  final VoidCallback onHelp;
  final VoidCallback onEditName;
  final VoidCallback onOpenBluetooth;
  final VoidCallback onOpenLocation;
  final VoidCallback onOpenAppPermissions;
  final VoidCallback onSendName;
  final VoidCallback onRestartScan;
  final VoidCallback onClearOffline;
  final VoidCallback onRegenerateId;
  final VoidCallback onChooseDesign;

  /// Every action records its id; handy for previews and tests.
  factory RadarActions.recording(void Function(String action) sink) => RadarActions(
        onStatusTap: () => sink('status'),
        onHelp: () => sink('help'),
        onEditName: () => sink('editName'),
        onOpenBluetooth: () => sink('bluetooth'),
        onOpenLocation: () => sink('location'),
        onOpenAppPermissions: () => sink('appPermissions'),
        onSendName: () => sink('sendName'),
        onRestartScan: () => sink('restartScan'),
        onClearOffline: () => sink('clearOffline'),
        onRegenerateId: () => sink('regenerateId'),
        onChooseDesign: () => sink('chooseDesign'),
      );
}
