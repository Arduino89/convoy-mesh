import 'package:flutter/material.dart';

import '../../services/diagnostic_recorder.dart';
import '../design_tokens.dart';
import '../radar/radar_components.dart';

/// Visual enhancement for the active/idle diagnostic recording card when one of
/// the redesigned directions is active. Adds a 4-minute progress bar and
/// tabular counters while leaving all underlying strings and controls intact.
class DesignedDiagnosticStatusStrip extends StatelessWidget {
  const DesignedDiagnosticStatusStrip({
    super.key,
    required this.tokens,
    required this.active,
    required this.ready,
    required this.persistent,
    required this.elapsed,
    required this.remaining,
    required this.eventCount,
    required this.droppedEvents,
  });

  final ConvoyDesignTokens tokens;
  final bool active;
  final bool ready;
  final bool persistent;
  final Duration elapsed;
  final Duration remaining;
  final int eventCount;
  final int droppedEvents;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final totalMs = DiagnosticRecorder.maxDuration.inMilliseconds;
    final fraction = totalMs <= 0 ? 0.0 : (elapsed.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final statusColor = active
        ? t.highlight
        : ready
            ? t.positive
            : t.warning;

    return Container(
      margin: EdgeInsets.only(bottom: t.space(3)),
      padding: EdgeInsets.all(t.space(3)),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(t.radiusSmall),
        border: Border.all(color: active ? statusColor.withValues(alpha: 0.6) : t.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            LiveDot(active: active, color: statusColor, size: 8),
            SizedBox(width: t.space(1.5)),
            Expanded(
              child: Text(
                t.label(
                  active
                      ? 'Acquisizione locale attiva'
                      : ready
                          ? 'Pronto per registrare'
                          : 'In attesa di modalità Vicini',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.caption(color: statusColor),
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: 2),
              decoration: BoxDecoration(
                color: persistent
                    ? t.positive.withValues(alpha: 0.14)
                    : t.warning.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(t.radiusSmall),
              ),
              child: Text(
                t.label(persistent ? 'File locale' : 'Solo memoria'),
                style: t.caption(color: persistent ? t.positive : t.warning).copyWith(fontSize: 10.5),
              ),
            ),
          ]),
          if (active) ...[
            SizedBox(height: t.space(2.5)),
            ClipRRect(
              borderRadius: BorderRadius.circular(t.radiusSmall),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 7,
                backgroundColor: t.outline.withValues(alpha: 0.4),
                valueColor: AlwaysStoppedAnimation<Color>(t.highlight),
              ),
            ),
            SizedBox(height: t.space(2.5)),
            Row(children: [
              _stat('Trascorso', DiagnosticRecorder.formatDuration(elapsed)),
              _stat('Restante', DiagnosticRecorder.formatDuration(remaining)),
              _stat('Eventi', '$eventCount'),
              _stat('Scartati', '$droppedEvents'),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    final t = tokens;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.label(label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.caption().copyWith(fontSize: 10)),
        SizedBox(height: t.space(0.5)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: t.data(15, weight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
