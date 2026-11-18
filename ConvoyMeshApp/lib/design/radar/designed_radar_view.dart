import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens.dart';
import '../outdoor_components.dart';
import 'radar_actions.dart';
import 'radar_components.dart';
import 'radar_scope.dart';
import 'radar_view_data.dart';

/// Outdoor Premium **Radar BLE** screen.
///
/// Purely presentational: renders [data] and forwards taps to [actions],
/// consuming palette, typography, spacing, dimensions, motion and editable
/// visual copy from [tokens].
class DesignedRadarView extends StatefulWidget {
  const DesignedRadarView({
    super.key,
    required this.tokens,
    required this.data,
    required this.actions,
  });

  final ConvoyDesignTokens tokens;
  final RadarViewData data;
  final RadarActions actions;

  @override
  State<DesignedRadarView> createState() => _DesignedRadarViewState();
}

class _DesignedRadarViewState extends State<DesignedRadarView> {
  int? _selectedPeerId;

  ConvoyDesignTokens get tokens => widget.tokens;
  RadarViewData get data => widget.data;
  RadarActions get actions => widget.actions;

  void _togglePeerSelection(RadarPeerView peer) {
    setState(() {
      _selectedPeerId = _selectedPeerId == peer.userId ? null : peer.userId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final copy = t.copy;
    final overlay = t.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay.copyWith(statusBarColor: Colors.transparent),
      child: Material(
        color: t.canvas,
        child: SafeArea(
          bottom: false,
          child: ListView(
            key: const Key('designed-radar-list'),
            padding:
                EdgeInsets.fromLTRB(t.hPad, t.space(2), t.hPad, t.space(6)),
            children: [
              ..._heroCardTop(context),
              _modeBlock(),
              SectionHeader(
                tokens: t,
                title: copy.peersSectionTitle,
                trailing:
                    '${data.onlineCount} presenti · ${data.offlineCount} non ricevuti',
              ),
              if (data.peers.isEmpty) _emptyState(),
              for (final p in data.peers)
                Padding(
                  padding: EdgeInsets.only(bottom: t.space(3)),
                  child: _PeerEntry(
                    tokens: t,
                    peer: p,
                    highlighted: _selectedPeerId == p.userId,
                    onTap: () => _togglePeerSelection(p),
                  ),
                ),
              if (data.offlineCount > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: actions.onClearOffline,
                    icon: Icon(
                      Icons.cleaning_services_outlined,
                      color: t.inkMuted,
                      size: t.iconSize(18),
                    ),
                    label: Text(
                      'Rimuovi dalla lista i peer non ricevuti',
                      style: t.body(14, color: t.ink, weight: FontWeight.w600),
                    ),
                  ),
                ),
              SectionHeader(tokens: t, title: copy.toolsSectionTitle),
              _tools(),
              SizedBox(height: t.space(4)),
              _identity(context),
              SizedBox(height: t.space(4)),
              DesignPanel(
                tokens: t,
                title: copy.bleDiagSectionTitle,
                icon: Icons.monitor_heart_outlined,
                children: [
                  for (final line in data.diagnosticsLines)
                    Padding(
                      padding: EdgeInsets.only(bottom: t.space(1.5)),
                      child: Text(line, style: t.body(13, color: t.inkMuted)),
                    ),
                ],
              ),
              DesignPanel(
                tokens: t,
                title: copy.advancedSectionTitle,
                icon: Icons.tune,
                children: [
                  Text(
                    'Cambia ID solo in caso di collisione. Gli altri telefoni vedranno un nuovo partecipante.',
                    style: t.body(13.5, color: t.inkMuted),
                  ),
                  SizedBox(height: t.space(2)),
                  OutlinedButton.icon(
                    onPressed: actions.onRegenerateId,
                    icon: Icon(Icons.fingerprint, size: t.iconSize(18)),
                    label: const Text('Rigenera ID…'),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: t.space(3)),
                    child: const Divider(height: 1),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(t.radiusSmall),
                    onTap: actions.onChooseDesign,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: t.space(1.5)),
                      child: Row(children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: t.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(t.radiusSmall),
                          ),
                          child: Icon(
                            Icons.palette_outlined,
                            color: t.accent,
                            size: t.iconSize(20),
                          ),
                        ),
                        SizedBox(width: t.space(3)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Personalizza Outdoor Premium',
                                style: t.body(15, weight: FontWeight.w700),
                              ),
                              Text(
                                'Colori, font, spaziature, animazioni o ritorno a Originale',
                                style: t.body(12.5, color: t.inkMuted),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            color: t.inkMuted, size: t.iconSize(20)),
                      ]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, {required String kicker}) {
    final t = tokens;
    return LayoutBuilder(builder: (context, constraints) {
      final maxChipW = (constraints.maxWidth * 0.42).clamp(96.0, 160.0);
      return Row(children: [
        Expanded(
          child: Text(
            t.label(kicker),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.caption(color: t.ink.withValues(alpha: 0.72)).copyWith(
                  letterSpacing: 1.1,
                ),
          ),
        ),
        SizedBox(width: t.space(2)),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxChipW),
          child: _NameChip(
            tokens: t,
            name: data.myName,
            onTap: actions.onEditName,
          ),
        ),
        SizedBox(width: t.space(1.5)),
        _RoundIconButton(
          tokens: t,
          key: const Key('design-open-studio-btn'),
          icon: Icons.palette_outlined,
          tooltip: 'Personalizza Outdoor Premium o torna a Originale',
          onTap: actions.onChooseDesign,
        ),
        SizedBox(width: t.space(1.5)),
        _RoundIconButton(
          tokens: t,
          icon: Icons.help_outline,
          tooltip: 'Come funzionano Vicini, GPS e segnale BLE',
          onTap: actions.onHelp,
        ),
      ]);
    });
  }

  List<Widget> _heroCardTop(BuildContext context) {
    final t = tokens;
    final copy = t.copy;
    return [
      _topBar(context, kicker: copy.appKicker),
      SizedBox(height: t.space(2.5)),
      Text(copy.radarTitle, style: t.display(31)),
      SizedBox(height: t.space(1)),
      Text(copy.radarSubtitle, style: t.body(14, color: t.inkMuted)),
      SizedBox(height: t.space(3.5)),
      Container(
        decoration: BoxDecoration(
          gradient: t.heroBackground,
          borderRadius: BorderRadius.circular(t.radiusLarge),
          boxShadow: t.shadow,
        ),
        padding: EdgeInsets.all(t.cardPad),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(
            spacing: t.space(2),
            runSpacing: t.space(2),
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DesignBleStatusPill(
                tokens: t,
                label: data.bleLabel,
                ready: data.bleReady,
                onTap: actions.onStatusTap,
                onHero: true,
              ),
              Row(mainAxisSize: MainAxisSize.min, children: [
                LiveDot(
                  active: data.scanning,
                  pulseEnabled: t.shouldPulseLive,
                  color: t.radarSweep,
                  size: 8,
                ),
                Flexible(
                  child: Text(
                    data.scanning ? 'Ricerca attiva' : 'Ricerca ferma',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body(13, color: t.heroInk, weight: FontWeight.w600),
                  ),
                ),
              ]),
            ],
          ),
          SizedBox(height: t.space(2.5)),
          Center(
            child: RadarScope(
              tokens: t,
              peers: data.peers,
              scanning: data.scanning,
              selectedPeerId: _selectedPeerId,
              onPeerTap: _togglePeerSelection,
            ),
          ),
          SizedBox(height: t.space(2)),
          Row(children: [
            _heroStat(data.onlineCount, 'presenti'),
            Container(
              width: 1,
              height: 40,
              color: t.heroInk.withValues(alpha: 0.2),
            ),
            _heroStat(data.offlineCount, 'non ricevuti'),
            Container(
              width: 1,
              height: 40,
              color: t.heroInk.withValues(alpha: 0.2),
            ),
            Expanded(
              child: Column(children: [
                Icon(
                  data.advertising
                      ? Icons.wifi_tethering
                      : Icons.wifi_tethering_off,
                  color: t.heroInk,
                  size: t.iconSize(22),
                ),
                SizedBox(height: t.space(1)),
                Text(
                  data.advertising ? 'Visibile' : 'Non visibile',
                  textAlign: TextAlign.center,
                  style: t.body(12.5, color: t.heroInk.withValues(alpha: 0.85)),
                ),
              ]),
            ),
          ]),
          SizedBox(height: t.space(2)),
          Text(
            copy.radarCaption,
            textAlign: TextAlign.center,
            style: t.body(11.5, color: t.heroInk.withValues(alpha: 0.72)),
          ),
        ]),
      ),
    ];
  }

  Widget _heroStat(int value, String label) => Expanded(
        child: Column(children: [
          Text('$value', style: tokens.display(30, color: tokens.heroInk)),
          Text(
            label,
            textAlign: TextAlign.center,
            style: tokens.body(12.5,
                color: tokens.heroInk.withValues(alpha: 0.85)),
          ),
        ]),
      );

  Widget _modeBlock() {
    final t = tokens;
    final icon = data.outingActive
        ? (data.gpsFresh ? Icons.gps_fixed : Icons.gps_not_fixed)
        : Icons.people_alt_outlined;
    final tone =
        data.outingActive ? (data.gpsFresh ? t.positive : t.warning) : t.accent;
    return Padding(
      padding: EdgeInsets.only(top: t.space(4)),
      child: OutdoorCard(
        tokens: t,
        margin: EdgeInsets.zero,
        elevated: false,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tone.withValues(
                  alpha: t.brightness == Brightness.dark ? 0.16 : 0.12),
              borderRadius: BorderRadius.circular(t.radiusSmall),
            ),
            child: Icon(icon, color: tone, size: t.iconSize(22)),
          ),
          SizedBox(width: t.space(3)),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data.modeText, style: t.body(15, weight: FontWeight.w700)),
              if (data.filterLine != null) ...[
                SizedBox(height: t.space(1)),
                Text(data.filterLine!, style: t.body(12.5, color: t.inkMuted)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _emptyState() {
    final t = tokens;
    return OutdoorCard(
      tokens: t,
      margin: EdgeInsets.zero,
      elevated: false,
      padding: EdgeInsets.all(t.cardPad * 1.1),
      child: Row(children: [
        Icon(Icons.travel_explore, color: t.inkMuted, size: t.iconSize(30)),
        SizedBox(width: t.space(3)),
        Expanded(
          child: Text(
            t.copy.emptyPeersMessage,
            style: t.body(14.5, color: t.inkMuted),
          ),
        ),
      ]),
    );
  }

  Widget _tools() {
    final t = tokens;
    final items = <(IconData, String, VoidCallback)>[
      (Icons.settings_bluetooth, 'Bluetooth', actions.onOpenBluetooth),
      (Icons.location_on_outlined, 'Posizione', actions.onOpenLocation),
      (
        Icons.admin_panel_settings_outlined,
        'Permessi app',
        actions.onOpenAppPermissions
      ),
      (Icons.campaign_outlined, 'Invia nome', actions.onSendName),
      (Icons.refresh, 'Riavvia scan', actions.onRestartScan),
    ];
    return LayoutBuilder(builder: (context, box) {
      final gap = t.space(2.5);
      final w = (box.maxWidth - gap) / 2;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final (icon, label, cb) in items)
          SizedBox(
            width: w,
            child: ToolButton(tokens: t, icon: icon, label: label, onTap: cb),
          ),
      ]);
    });
  }

  Widget _identity(BuildContext context) {
    final t = tokens;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: t.cardPad, vertical: t.space(3)),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.radiusMedium),
        border: Border.all(color: t.outline, width: t.borderWidth),
      ),
      child: Row(children: [
        Icon(Icons.badge_outlined, color: t.inkMuted, size: t.iconSize(20)),
        SizedBox(width: t.space(3)),
        Expanded(
          child: SelectableText(
            'Il mio ID: ${data.myId}',
            style: t.data(14, color: t.ink, weight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

class _PeerEntry extends StatelessWidget {
  const _PeerEntry({
    required this.tokens,
    required this.peer,
    required this.highlighted,
    required this.onTap,
  });

  final ConvoyDesignTokens tokens;
  final RadarPeerView peer;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final tone = peer.online ? t.positive : t.inkMuted;
    final details = <String>[
      peer.gpsLine,
      if (peer.accuracyLine != null) peer.accuracyLine!,
      if (peer.historyLine != null) peer.historyLine!,
    ];

    final borderColor = highlighted ? t.highlight : t.outline;
    final borderW = highlighted ? (t.borderWidth + 1.0) : t.borderWidth;

    return AnimatedOpacity(
      duration: t.effectiveMotionMedium,
      opacity: peer.online ? 1 : 0.78,
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.radiusMedium),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.radiusMedium),
          onTap: onTap,
          child: AnimatedContainer(
            duration: t.effectiveMotionFast,
            curve: t.motionCurve,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radiusMedium),
              border: Border.all(color: borderColor, width: borderW),
              boxShadow: t.elevated ? t.shadow : const [],
            ),
            padding: EdgeInsets.all(t.cardPad),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                PeerAvatar(tokens: t, peer: peer),
                SizedBox(width: t.space(3)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.label(peer.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.display(20.5),
                      ),
                      SizedBox(height: t.space(1)),
                      Wrap(spacing: t.space(1.5), children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: t.space(2), vertical: 2),
                          decoration: BoxDecoration(
                            color: tone.withValues(
                                alpha: t.brightness == Brightness.dark
                                    ? 0.16
                                    : 0.12),
                            borderRadius: BorderRadius.circular(t.radiusSmall),
                          ),
                          child: Text(
                            t.label(peer.statusLabel),
                            style: t.caption(color: tone),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
                SizedBox(width: t.space(2)),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  SignalBars(
                    level: peer.online ? peer.signalLevel : 0,
                    color: t.accent,
                    track: t.outline,
                    height: 18,
                  ),
                  SizedBox(height: t.space(1)),
                  Text(
                    peer.rssi < 0 ? '${peer.rssi} dBm' : '— dBm',
                    style: t.data(11.5, color: t.inkMuted, weight: FontWeight.w600),
                  ),
                ]),
              ]),
              SizedBox(height: t.space(3)),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                LocationGlyph(tokens: t, state: peer.locationState, size: 18),
                SizedBox(width: t.space(2)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in details)
                        Text(
                          line,
                          style: t.body(13.5,
                              color: t.ink.withValues(alpha: 0.86)),
                        ),
                    ],
                  ),
                ),
              ]),
              SizedBox(height: t.space(2)),
              Divider(height: t.space(3)),
              Text(
                peer.signalLine,
                style: t.body(12.5, color: t.inkMuted, weight: FontWeight.w600),
              ),
              Text(peer.lastPacketLine,
                  style: t.body(12.5, color: t.inkMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NameChip extends StatelessWidget {
  const _NameChip({
    required this.tokens,
    required this.name,
    required this.onTap,
  });

  final ConvoyDesignTokens tokens;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Semantics(
      button: true,
      label: 'Modifica nome: $name',
      child: Tooltip(
        message: 'Modifica il tuo nome ($name)',
        child: Material(
          color: t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.radiusLarge),
            side: BorderSide(color: t.outline, width: t.borderWidth),
          ),
          child: InkWell(
            key: const Key('design-edit-name'),
            borderRadius: BorderRadius.circular(t.radiusLarge),
            onTap: onTap,
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: (t.minTouchTarget - 8).clamp(40, 60)),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: t.space(2.5)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.person_outline,
                      size: t.iconSize(16), color: t.accent),
                  SizedBox(width: t.space(1.25)),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body(13.5, weight: FontWeight.w800),
                    ),
                  ),
                  SizedBox(width: t.space(1)),
                  Icon(Icons.edit, size: t.iconSize(13), color: t.inkMuted),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    super.key,
    required this.tokens,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final ConvoyDesignTokens tokens;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final s = (t.minTouchTarget - 6).clamp(42.0, 60.0);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: t.surface,
        shape: CircleBorder(
          side: BorderSide(color: t.outline, width: t.borderWidth),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: s,
            height: s,
            child: Icon(icon, color: t.ink, size: t.iconSize(20)),
          ),
        ),
      ),
    );
  }
}
