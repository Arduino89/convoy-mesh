import 'package:flutter/material.dart';

import 'design_controller.dart';
import 'design_presets.dart';
import 'design_tokens.dart';
import 'outdoor_components.dart';
import 'outdoor_config.dart';
import 'studio/frontend_design_studio_page.dart';

/// Bottom sheet to switch between **Outdoor Premium** and **Originale (LAB +15)**
/// or launch the live **Outdoor Studio** customiser.
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
        builder: (context, _) {
          final activeTokens = ConvoyDesignTokens.maybeOf(context);
          final pad = activeTokens?.hPad ?? 16.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (activeTokens != null)
                  OutdoorCardHeader(
                    tokens: activeTokens,
                    icon: Icons.palette_outlined,
                    title: 'Stile Outdoor Premium',
                    subtitle:
                        'Cambia aspetto o torna alla grafica originale senza modificare radio, GPS, tracce o diagnostica.',
                  )
                else ...[
                  Text(
                    'Stile grafico',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Scegli Outdoor Premium o torna alla grafica originale. Bluetooth, GPS, tracce e diagnostica restano identici.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 14),
                DesignDirectionTile(
                  direction: DesignDirection.outdoorPremium,
                  tokens: ctrl.outdoorTokens,
                  subtitleOverride:
                      '${ctrl.config.palettePreset.label} · ${ctrl.config.displayFamily ?? 'Sistema'} + ${ctrl.config.bodyFamily ?? 'Sistema'}',
                  selected: ctrl.direction == DesignDirection.outdoorPremium,
                  onTap: () async {
                    await ctrl.select(DesignDirection.outdoorPremium);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
                DesignDirectionTile(
                  direction: DesignDirection.classic,
                  tokens: DesignPresets.classicReference,
                  selected: ctrl.direction == DesignDirection.classic,
                  onTap: () async {
                    await ctrl.select(DesignDirection.classic);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const Key('open-design-studio-sheet-btn'),
                  onPressed: () {
                    final nav = Navigator.of(context);
                    Navigator.pop(sheetContext);
                    nav.push(
                      MaterialPageRoute<void>(
                        builder: (_) => FrontendDesignStudioPage(
                          controller: ctrl,
                          initialCustomizeTab: true,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.tune),
                  label: const Text('Personalizza Outdoor Premium'),
                ),
              ],
            ),
          );
        },
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
    this.tokens,
    this.subtitleOverride,
  });

  final DesignDirection direction;
  final bool selected;
  final VoidCallback onTap;
  final ConvoyDesignTokens? tokens;
  final String? subtitleOverride;

  @override
  Widget build(BuildContext context) {
    final activeTokens = ConvoyDesignTokens.maybeOf(context);
    final t = tokens ?? DesignPresets.of(direction);
    final swatches = direction == DesignDirection.classic
        ? const [Color(0xFF607D8B), Color(0xFFECEFF1), Color(0xFF245B45)]
        : [t.canvas, t.accent, t.highlight];
    final radius = activeTokens?.radiusMedium ?? 16.0;
    final subtitle = subtitleOverride ?? direction.tagline;
    final scheme = Theme.of(context).colorScheme;
    final titleColor = selected
        ? scheme.onPrimaryContainer
        : (activeTokens?.ink ?? scheme.onSurface);
    final subtitleColor = selected
        ? scheme.onPrimaryContainer.withValues(alpha: 0.82)
        : (activeTokens?.inkMuted ?? Theme.of(context).textTheme.bodySmall?.color);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: selected
            ? scheme.primaryContainer
            : (activeTokens?.surfaceRaised ?? scheme.surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : (activeTokens?.borderWidth ?? 1),
          ),
        ),
        child: InkWell(
          key: Key('design-direction-${direction.storageId}'),
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: activeTokens?.minTouchTarget ?? 64,
            ),
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
                            border: Border.all(color: Colors.black26),
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
                      Text(
                        direction.label,
                        style: TextStyle(
                          fontFamily: t.displayFamily,
                          fontWeight: ConvoyDesignTokens.resolveWeight(
                            t.displayFamily,
                            FontWeight.w700,
                          ),
                          fontSize: 16,
                          color: titleColor,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: subtitleColor),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle,
                    color: scheme.primary,
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
