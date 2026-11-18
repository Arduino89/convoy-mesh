import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../outdoor_components.dart';
import '../radar/radar_components.dart';

/// Bottom controls (Outing action + navigation bar) styled for Outdoor Premium.
///
/// Preserves the exact navigation destinations and accessibility / smoke-test
/// semantics labels (`Radar BLE`, `Mappa`, `Test log`, `Avvia uscita`,
/// `Uscita attiva • Termina uscita`).
class DesignedBottomDock extends StatelessWidget {
  const DesignedBottomDock({
    super.key,
    required this.tokens,
    required this.selectedIndex,
    required this.onSelectIndex,
    required this.outingActive,
    required this.busy,
    required this.error,
    required this.onToggleOuting,
  });

  final ConvoyDesignTokens tokens;
  final int selectedIndex;
  final ValueChanged<int> onSelectIndex;
  final bool outingActive;
  final bool busy;
  final String? error;
  final VoidCallback onToggleOuting;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final outingBg = outingActive ? t.critical : t.accent;
    final outingFg = outingActive ? Colors.white : t.onAccent;

    final buttonLabel = busy
        ? 'Preparazione…'
        : outingActive
            ? 'Uscita attiva • Termina uscita'
            : 'Avvia uscita';

    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: t.elevated
            ? [
                BoxShadow(
                  color: t.ink.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                )
              ]
            : const [],
      ),
      child: Material(
        color: t.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Divider(
              height: t.borderWidth,
              thickness: t.borderWidth,
              color: t.outline,
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  t.space(3.5) * t.screenPaddingScale,
                  t.space(2.25),
                  t.space(3.5) * t.screenPaddingScale,
                  t.space(1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
              if (error != null) ...[
                OutdoorCallout(
                  tokens: t,
                  icon: Icons.error_outline,
                  text: error!,
                  tone: OutdoorTone.critical,
                  padding: EdgeInsets.symmetric(
                    horizontal: t.space(3),
                    vertical: t.space(1.75),
                  ),
                ),
                SizedBox(height: t.space(2)),
              ],
              Semantics(
                container: true,
                excludeSemantics: true,
                button: true,
                label: buttonLabel,
                child: Material(
                  color: busy ? t.outline : outingBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(t.radiusMedium),
                  ),
                  child: InkWell(
                    key: const Key('designed-outing-toggle'),
                    borderRadius: BorderRadius.circular(t.radiusMedium),
                    onTap: busy ? null : onToggleOuting,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: t.minTouchTarget),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: t.space(4), vertical: t.space(2)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (outingActive && !busy) ...[
                              LiveDot(
                                active: true,
                                pulseEnabled: t.shouldPulseLive,
                                color: outingFg,
                                size: 7,
                              ),
                              SizedBox(width: t.space(1.5)),
                            ] else
                              Padding(
                                padding: EdgeInsets.only(right: t.space(2)),
                                child: Icon(
                                  busy
                                      ? Icons.hourglass_top_rounded
                                      : outingActive
                                          ? Icons.stop_circle_outlined
                                          : Icons.play_circle_outline,
                                  color: busy ? t.inkMuted : outingFg,
                                  size: t.iconSize(21),
                                ),
                              ),
                            Flexible(
                              child: Text(
                                t.label(buttonLabel),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t
                                    .body(
                                      14.5,
                                      color: busy ? t.inkMuted : outingFg,
                                      weight: FontWeight.w800,
                                    )
                                    .copyWith(
                                        letterSpacing:
                                            t.uppercaseLabels ? 0.9 : 0),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: t.space(1.75)),
              Row(children: [
                _navItem(
                  index: 0,
                  icon: Icons.radar,
                  label: 'Radar BLE',
                  selected: selectedIndex == 0,
                ),
                _navItem(
                  index: 1,
                  icon: Icons.map_outlined,
                  activeIcon: Icons.map,
                  label: 'Mappa',
                  selected: selectedIndex == 1,
                ),
                _navItem(
                  index: 2,
                  icon: Icons.bug_report_outlined,
                  activeIcon: Icons.bug_report,
                  label: 'Test log',
                  selected: selectedIndex == 2,
                ),
              ]),
            ],
          ),
        ),
      ),
          ],
        ),
      ),
    );
  }

  Widget _navItem({
    required int index,
    required IconData icon,
    IconData? activeIcon,
    required String label,
    required bool selected,
  }) {
    final t = tokens;
    final activeBg = t.accent.withValues(alpha: 0.12);
    return Expanded(
      child: Semantics(
        container: true,
        excludeSemantics: true,
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(t.radiusMedium),
          onTap: () => onSelectIndex(index),
          child: AnimatedContainer(
            duration: t.effectiveMotionFast,
            curve: t.motionCurve,
            padding: EdgeInsets.symmetric(
              vertical: t.space(1.75),
              horizontal: t.space(1.5),
            ),
            decoration: BoxDecoration(
              color: selected ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(t.radiusMedium),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? (activeIcon ?? icon) : icon,
                  size: t.iconSize(22),
                  color: selected ? t.accent : t.inkMuted,
                ),
                SizedBox(height: t.space(0.75)),
                Text(
                  t.label(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: t.sp(11.5),
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    letterSpacing: t.uppercaseLabels ? 0.8 : 0,
                    color: selected ? t.ink : t.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
