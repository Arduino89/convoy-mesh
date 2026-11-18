import 'package:flutter/material.dart';

import 'design_controller.dart';
import 'design_presets.dart';
import 'design_tokens.dart';
import 'studio/frontend_design_studio_page.dart';

/// Bottom sheet to switch the visual direction on the device or open the
/// interactive comparison studio.
Future<void> showDesignDirectionPicker(
  BuildContext context, {
  DesignDirectionController? controller,
}) {
  final ctrl = controller ?? DesignDirectionController.instance;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Stile grafico (anteprima)', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Cambia solo l’aspetto. Bluetooth, GPS, tracce e diagnostica '
                'restano identici. La scelta resta solo su questo telefono.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              for (final d in DesignDirection.values)
                DesignDirectionTile(
                  direction: d,
                  selected: ctrl.direction == d,
                  onTap: () async {
                    await ctrl.select(d);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('open-design-studio-sheet-btn'),
                onPressed: () {
                  final nav = Navigator.of(context);
                  Navigator.pop(sheetContext);
                  nav.push(
                    MaterialPageRoute<void>(
                      builder: (_) => FrontendDesignStudioPage(controller: ctrl),
                    ),
                  );
                },
                icon: const Icon(Icons.compare),
                label: const Text('Confronta varianti nel Design Studio'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class DesignDirectionTile extends StatelessWidget {
  const DesignDirectionTile({
    super.key,
    required this.direction,
    required this.selected,
    required this.onTap,
  });

  final DesignDirection direction;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignPresets.of(direction);
    final swatches = direction == DesignDirection.classic
        ? const [Color(0xFF607D8B), Color(0xFFECEFF1), Color(0xFF245B45)]
        : [t.canvas, t.accent, t.highlight];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          key: Key('design-direction-${direction.storageId}'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                SizedBox(
                  width: 54,
                  height: 30,
                  child: Stack(children: [
                    for (var i = 0; i < swatches.length; i++)
                      Positioned(
                        left: i * 12.0,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: swatches[i],
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black12),
                          ),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(direction.label,
                          style: TextStyle(
                            fontFamily: t.displayFamily,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          )),
                      Text(direction.tagline, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
