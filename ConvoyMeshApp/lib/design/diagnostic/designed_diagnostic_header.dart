import 'package:flutter/material.dart';

import '../../services/diagnostic_recorder.dart';
import '../design_tokens.dart';
import '../outdoor_components.dart';
import '../radar/radar_components.dart';

/// Visual status header for the diagnostic recording card when Outdoor Premium
/// is active. Keeps idle height compact so the Start CTA remains above the fold.
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
    final fraction =
        totalMs <= 0 ? 0.0 : (elapsed.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final statusColor = active
        ? t.highlight
        : ready
            ? t.positive
            : t.warning;

    return Container(
      margin: EdgeInsets.only(bottom: t.space(1.75)),
      padding: EdgeInsets.symmetric(
        horizontal: t.space(2.75),
        vertical: active ? t.space(2) : t.space(1.4),
      ),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: BorderRadius.circular(t.radiusSmall),
        border: Border.all(
          color: active ? statusColor.withValues(alpha: 0.65) : t.outline,
          width: t.borderWidth,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 250;
          final statusLine = Row(
            mainAxisSize: narrow ? MainAxisSize.min : MainAxisSize.max,
            children: [
              LiveDot(
                active: active,
                pulseEnabled: t.shouldPulseLive,
                color: statusColor,
                size: 7.5,
              ),
              SizedBox(width: t.space(1.5)),
              Flexible(
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
                  style: t.caption(color: statusColor, size: 11),
                ),
              ),
            ],
          );
          final storageBadge = OutdoorStatusBadge(
            tokens: t,
            label: persistent ? 'File locale' : 'Solo memoria',
            tone: persistent ? OutdoorTone.positive : OutdoorTone.warning,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (narrow) ...[
                statusLine,
                SizedBox(height: t.space(1)),
                storageBadge,
              ] else
                Row(children: [
                  Expanded(child: statusLine),
                  SizedBox(width: t.space(1.5)),
                  Flexible(flex: 0, child: storageBadge),
                ]),
              if (active) ...[
                SizedBox(height: t.space(2.25)),
                ClipRRect(
                  borderRadius: BorderRadius.circular(t.radiusSmall),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 7,
                    backgroundColor: t.outline.withValues(alpha: 0.4),
                    valueColor: AlwaysStoppedAnimation<Color>(t.highlight),
                  ),
                ),
                SizedBox(height: t.space(2.25)),
                if (narrow) ...[
                  Row(children: [
                    _stat(
                        'Trascorso', DiagnosticRecorder.formatDuration(elapsed)),
                    SizedBox(width: t.space(2)),
                    _stat('Restante',
                        DiagnosticRecorder.formatDuration(remaining)),
                  ]),
                  SizedBox(height: t.space(1.5)),
                  Row(children: [
                    _stat('Eventi', '$eventCount'),
                    SizedBox(width: t.space(2)),
                    _stat('Scartati', '$droppedEvents'),
                  ]),
                ] else
                  Row(children: [
                    _stat(
                        'Trascorso', DiagnosticRecorder.formatDuration(elapsed)),
                    SizedBox(width: t.space(1.5)),
                    _stat('Restante',
                        DiagnosticRecorder.formatDuration(remaining)),
                    SizedBox(width: t.space(1.5)),
                    _stat('Eventi', '$eventCount'),
                    SizedBox(width: t.space(1.5)),
                    _stat('Scartati', '$droppedEvents'),
                  ]),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value) {
    final t = tokens;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          t.label(label),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.caption(size: 10),
        ),
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
