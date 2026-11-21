import 'package:flutter/material.dart';

import '../design/design_tokens.dart';
import '../design/outdoor_components.dart';
import '../services/manual_ping_service.dart';

/// Pressing the only button authorizes one synthetic diagnostic event.
class ManualPingCard extends StatefulWidget {
  const ManualPingCard({
    super.key,
    this.pingSenderOverride,
    this.configuredOverride,
    this.temporarilyDisabledOverride,
    this.attemptTrackerOverride,
  });

  // Test-only injection points. Production uses the default service.
  final Future<int> Function(String pingId)? pingSenderOverride;
  final bool? configuredOverride;
  final bool? temporarilyDisabledOverride;
  final ManualPingAttemptTracker? attemptTrackerOverride;

  @override
  State<ManualPingCard> createState() => _ManualPingCardState();
}

class _ManualPingCardState extends State<ManualPingCard>
    with AutomaticKeepAliveClientMixin<ManualPingCard> {
  static const _title = 'Ping PostHog — laboratorio';
  static const _introText =
      'Premendo «Invia ping di prova» autorizzi UN SOLO invio '
      'sintetico a PostHog EU. Non vengono trasmessi nome, coordinate GPS, '
      'percorso, ID Bluetooth o file diagnostici. '
      'Il servizio tratta i dati tecnici della connessione. '
      'Nessun invio automatico.';
  static const _temporarilyDisabledText =
      'Invio a PostHog temporaneamente disattivato in questa build Outdoor LAB: '
      'nessun evento viene trasmesso. La registrazione locale e la condivisione '
      'manuale restano attive.';
  static const _unconfiguredText =
      'Invio non configurato in questa build: nessun evento può essere trasmesso.';

  late ManualPingAttemptTracker _tracker;

  @override
  bool get wantKeepAlive => true;

  bool get _temporarilyDisabled =>
      widget.temporarilyDisabledOverride ??
      (widget.configuredOverride != null
          ? false
          : ManualPingService.temporarilyDisabled);

  bool get _configured =>
      !_temporarilyDisabled &&
      (widget.configuredOverride ?? ManualPingService.isConfigured);

  @override
  void initState() {
    super.initState();
    _tracker = widget.attemptTrackerOverride ?? ManualPingService.attemptTracker;
    _tracker.addListener(_onTrackerChanged);
  }

  @override
  void didUpdateWidget(ManualPingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next =
        widget.attemptTrackerOverride ?? ManualPingService.attemptTracker;
    if (!identical(next, _tracker)) {
      _tracker.removeListener(_onTrackerChanged);
      _tracker = next;
      _tracker.addListener(_onTrackerChanged);
    }
  }

  @override
  void dispose() {
    _tracker.removeListener(_onTrackerChanged);
    super.dispose();
  }

  void _onTrackerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    if (!_configured) return;
    final tracker = _tracker;
    final id = ManualPingService.newPingId();
    // Atomic launch-scoped lock: at most one request, even if the widget
    // unmounts mid-flight or the transport times out ambiguously.
    if (!tracker.beginAttempt(id)) return;
    try {
      final http = await (widget.pingSenderOverride?.call(id) ??
          ManualPingService.sendOnce(pingId: id));
      tracker.completeAttempt(
        http >= 200 && http < 300
            ? 'HTTP $http: richiesta accettata. Verifica il ping_id su PostHog: il salvataggio non è ancora confermato.'
            : 'HTTP $http: evento NON confermato. Nessun ritentativo automatico.',
      );
    } catch (_) {
      tracker.completeAttempt(
        'Connessione fallita o incerta. Nessun ritentativo automatico.',
      );
    }
  }

  Widget _classicInfoNotice(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = ConvoyDesignTokens.maybeOf(context);
    final state = _tracker.state;
    final temporarilyDisabled = _temporarilyDisabled;
    final configured = _configured;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (t == null) ...const [
          Text(_title, style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text(_introText),
          SizedBox(height: 8),
        ] else ...[
          OutdoorCardHeader(
            tokens: t,
            icon: Icons.wifi_tethering,
            title: _title,
          ),
          SizedBox(height: t.space(2)),
          Text(_introText, style: t.body(13, color: t.inkMuted)),
          SizedBox(height: t.space(2)),
        ],
        if (temporarilyDisabled) ...[
          if (t == null)
            _classicInfoNotice(context, _temporarilyDisabledText)
          else ...[
            OutdoorCallout(
              tokens: t,
              icon: Icons.info_outline,
              text: _temporarilyDisabledText,
              tone: OutdoorTone.neutral,
            ),
            SizedBox(height: t.space(2)),
          ],
        ] else if (!configured) ...[
          if (t == null)
            const Text(_unconfiguredText, style: TextStyle(color: Colors.red))
          else ...[
            OutdoorCallout(
              tokens: t,
              icon: Icons.cloud_off_outlined,
              text: _unconfiguredText,
              tone: OutdoorTone.critical,
            ),
            SizedBox(height: t.space(2)),
          ],
        ],
        FilledButton.icon(
          onPressed: configured && !state.attempted && !state.inFlight
              ? _send
              : null,
          icon: const Icon(Icons.wifi_tethering),
          label: const Text('Invia ping di prova'),
        ),
        if (state.pingId != null) ...[
          if (t != null) SizedBox(height: t.space(2)),
          if (t == null)
            SelectableText('ping_id: ${state.pingId}')
          else
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: t.space(2.75),
                vertical: t.space(1.5),
              ),
              decoration: BoxDecoration(
                color: t.surfaceRaised,
                borderRadius: BorderRadius.circular(t.radiusSmall),
                border: Border.all(color: t.outline, width: t.borderWidth),
              ),
              child: SelectableText(
                'ping_id: ${state.pingId}',
                style: t.data(12, color: t.ink),
              ),
            ),
        ],
        if (state.status != null) ...[
          if (t != null) SizedBox(height: t.space(1.75)),
          if (t == null)
            Text(state.status!)
          else
            OutdoorCallout(
              tokens: t,
              icon: state.status!.startsWith('HTTP 2')
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_rounded,
              text: state.status!,
              tone: state.status!.startsWith('HTTP 2')
                  ? OutdoorTone.positive
                  : OutdoorTone.warning,
            ),
        ],
        if (state.attempted) ...[
          if (t != null) SizedBox(height: t.space(1.5)),
          Text(
            'Per ripetere il test, chiudi e riapri l’app.',
            style: t?.body(12.5, color: t.inkMuted),
          ),
        ],
      ],
    );

    if (t != null) return OutdoorCard(tokens: t, child: content);
    return Card(
      child: Padding(padding: const EdgeInsets.all(14), child: content),
    );
  }
}
