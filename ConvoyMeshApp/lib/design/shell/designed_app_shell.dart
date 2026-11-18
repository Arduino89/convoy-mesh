import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../radar/radar_components.dart';

/// Token-driven bottom controls (Outing action + navigation bar) used when
/// a non-classic direction is active. Preserves the exact action labels and
/// destination semantics of `AppShell`.
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
    final hud = t.layoutStyle == RadarLayoutStyle.hud;
    final editorial = t.layoutStyle == RadarLayoutStyle.editorial;

    final outingBg = outingActive
        ? (hud ? t.critical.withValues(alpha: 0.16) : t.critical)
        : t.accent;
    final outingFg = outingActive
        ? (hud ? t.critical : Colors.white)
        : t.onAccent;
    final outingBorder = outingActive && hud
        ? BorderSide(color: t.critical, width: 1.5)
        : BorderSide.none;

    final buttonLabel = busy
        ? 'Preparazione…'
        : outingActive
            ? 'Uscita attiva • Termina uscita'
            : 'Avvia uscita';

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.outline, width: t.borderWidth)),
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
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(t.space(3.5), t.space(2.5), t.space(3.5), t.space(1.5)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null)
                Container(
                  margin: EdgeInsets.only(bottom: t.space(2)),
                  padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
                  decoration: BoxDecoration(
                    color: t.critical.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(t.radiusSmall),
                    border: Border.all(color: t.critical.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    error!,
                    style: t.body(12.5, color: t.critical, weight: FontWeight.w600),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Material(
                color: busy ? t.outline : outingBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(editorial ? t.radiusLarge : t.radiusMedium),
                  side: outingBorder,
                ),
                child: InkWell(
                  key: const Key('designed-outing-toggle'),
                  borderRadius: BorderRadius.circular(editorial ? t.radiusLarge : t.radiusMedium),
                  onTap: busy ? null : onToggleOuting,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: t.minTouchTarget),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (outingActive && !busy) ...[
                            LiveDot(active: true, color: outingFg, size: 7),
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
                                size: 22,
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
                                  .copyWith(letterSpacing: t.uppercaseLabels ? 0.9 : 0),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: t.space(2)),
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
    final hud = t.layoutStyle == RadarLayoutStyle.hud;
    final editorial = t.layoutStyle == RadarLayoutStyle.editorial;
    final activeBg = hud
        ? t.accent.withValues(alpha: 0.14)
        : editorial
            ? t.highlight.withValues(alpha: 0.12)
            : t.accent.withValues(alpha: 0.12);
    final activeColor = hud ? t.accent : (editorial ? t.highlight : t.accent);

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(t.radiusMedium),
          onTap: () => onSelectIndex(index),
          child: AnimatedContainer(
            duration: t.motionFast,
            curve: t.motionCurve,
            padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(1.5)),
            decoration: BoxDecoration(
              color: selected ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(t.radiusMedium),
              border: hud && selected
                  ? Border(top: BorderSide(color: t.accent, width: 2))
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? (activeIcon ?? icon) : icon,
                  size: 22,
                  color: selected ? activeColor : t.inkMuted,
                ),
                SizedBox(height: t.space(0.75)),
                Text(
                  t.label(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 11.5,
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
