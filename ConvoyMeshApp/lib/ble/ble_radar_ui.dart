import 'dart:math' as math;

import 'package:flutter/material.dart';

/// User-facing BLE state. "Unknown" is a red, unresolved condition, not a
/// diagnosed hardware fault. Scan activity remains a separate source signal.
enum BleStatusAction { readyInfo, bluetoothSettings, appPermissions, locationSettings, explain }

class BleStatePresentation {
  const BleStatePresentation(this.label, this.explanation, this.action, this.ready);

  final String label;
  final String explanation;
  final BleStatusAction action;
  final bool ready;
}

BleStatePresentation describeBleStatus(String statusName) {
  switch (statusName) {
    case 'ready':
      return const BleStatePresentation(
        'Bluetooth pronto',
        'Il Bluetooth è acceso e pronto. La scansione dei vicini ha un '
            'indicatore separato: Bluetooth pronto non significa che il GPS '
            'sia disponibile o che un altro telefono sia stato ricevuto.',
        BleStatusAction.readyInfo, true);
    case 'poweredOff':
      return const BleStatePresentation(
        'Bluetooth spento',
        'Il Bluetooth risulta spento. Apri le impostazioni Bluetooth per '
            'abilitarlo e riprendere la ricerca dei vicini.',
        BleStatusAction.bluetoothSettings, false);
    case 'unauthorized':
      return const BleStatePresentation(
        'Permessi Bluetooth negati',
        'Convoy non dispone delle autorizzazioni necessarie. Apri '
            'le impostazioni dell’app e controlla «Dispositivi vicini» '
            'e, se richiesta, «Posizione».',
        BleStatusAction.appPermissions, false);
    case 'unsupported':
      return const BleStatePresentation(
        'Bluetooth non supportato',
        'Il servizio Bluetooth Low Energy risulta non supportato da questo '
            'dispositivo o ambiente. Le impostazioni potrebbero non '
            'risolvere il problema.',
        BleStatusAction.explain, false);
    case 'locationServicesDisabled':
      return const BleStatePresentation(
        'Posizione del telefono disattivata',
        'I servizi di localizzazione Android risultano disattivati e '
            'possono impedire la ricerca Bluetooth. Abilitali nelle '
            'impostazioni del telefono.',
        BleStatusAction.locationSettings, false);
    case 'unknown':
    default:
      return const BleStatePresentation(
        'Bluetooth da verificare',
        'Lo stato del Bluetooth non è ancora determinato. Potrebbe '
            'essere una fase di avvio, un permesso mancante o un problema '
            'del sistema: la causa non è ancora accertata.',
        BleStatusAction.explain, false);
  }
}

/// Compact replacement for the raw "Bluetooth: ready/unknown" text.
/// The palette uses a light tint and dark text for readability outdoors.
class BleStatusBanner extends StatelessWidget {
  const BleStatusBanner({
    super.key,
    required this.statusName,
    required this.onTap,
  });

  final String statusName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final view = describeBleStatus(statusName);
    const green = Color(0xFF245B45);
    const red = Color(0xFF932F3B);
    final color = view.ready ? green : red;
    final gradient = view.ready
        ? const [Color(0xFFDFEFE5), Color(0xFFF6FBF8)]
        : const [Color(0xFFF9E4E5), Color(0xFFFFF7F7)];
    return Semantics(
      button: true,
      label: view.label,
      hint: view.ready ? 'Tocca per conferma dello stato' : 'Tocca per capire come risolvere',
      child: InkWell(
        key: const Key('ble-status-tap'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(colors: gradient),
            border: Border.all(color: color.withOpacity(0.24)),
          ),
          child: Row(children: [
            Icon(view.ready ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: color, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(view.label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color, fontWeight: FontWeight.w700))),
            Icon(Icons.info_outline, color: color, size: 19),
          ]),
        ),
      ),
    );
  }
}

/// Animated option #4 chosen by the tester: soft concentric BLE scan waves.
/// An OFF scanner uses the standard static chip and never animates.
class ScanStatusChip extends StatelessWidget {
  const ScanStatusChip({super.key, required this.scanning});
  final bool scanning;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: scanning
        ? const ScanPulseIcon()
        : const Icon(Icons.radar, size: 18),
    label: Text(scanning ? 'Scan ON' : 'Scan OFF'),
  );
}

class ScanPulseIcon extends StatefulWidget {
  const ScanPulseIcon({super.key});
  @override
  State<ScanPulseIcon> createState() => _ScanPulseIconState();
}

class _ScanPulseIconState extends State<ScanPulseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1700),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      label: 'Scansione Bluetooth attiva',
      child: SizedBox(
        width: 20, height: 20,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) => CustomPaint(
              painter: _ScanPulsePainter(disabled ? 0.15 : _pulse.value),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanPulsePainter extends CustomPainter {
  const _ScanPulsePainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const green = Color(0xFF356956);
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2 - 1.0;
    canvas.drawCircle(center, 2.0, Paint()..color = green);
    for (var i = 0; i < 3; i++) {
      final phase = (progress + i / 3) % 1.0;
      final alpha = (1.0 - phase) * 0.7;
      final paint = Paint()
        ..color = green.withOpacity(alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(center, 2.3 + phase * (maxRadius - 2.3), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanPulsePainter old) =>
      progress != old.progress;
}
