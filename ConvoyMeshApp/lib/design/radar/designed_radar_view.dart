import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens.dart';
import 'radar_actions.dart';
import 'radar_components.dart';
import 'radar_scope.dart';
import 'radar_view_data.dart';

/// Redesigned Radar BLE screen.
///
/// Purely presentational: renders [data] and forwards taps to [actions].
/// It contains every capability of the original screen (status routing,
/// help, name edit, system settings, send name, restart scan, ID, remove
/// non-received peers, BLE diagnostics, regenerate ID) re-organised for
/// one-handed use: primary information at the top, tools grouped lower.
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

  static const radarCaption =
      'Anelli = qualità del segnale BLE, non distanza né direzione.';

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
            padding: EdgeInsets.fromLTRB(t.space(5), t.space(2), t.space(5), t.space(6)),
            children: [
              ...switch (t.layoutStyle) {
                RadarLayoutStyle.heroCard => _heroCardTop(context),
                RadarLayoutStyle.hud => _hudTop(context),
                RadarLayoutStyle.editorial => _editorialTop(context),
              },
              _modeBlock(),
              SectionHeader(
                tokens: t,
                title: t.layoutStyle == RadarLayoutStyle.hud ? 'Contatti' : 'Partecipanti',
                trailing: '${data.onlineCount} presenti · ${data.offlineCount} non ricevuti',
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
                    icon: Icon(Icons.cleaning_services_outlined, color: t.inkMuted, size: 18),
                    label: Text('Rimuovi dalla lista i peer non ricevuti',
                        style: t.body(14, color: t.ink, weight: FontWeight.w600)),
                  ),
                ),
              SectionHeader(tokens: t, title: 'Strumenti'),
              _tools(),
              SizedBox(height: t.space(4)),
              _identity(context),
              SizedBox(height: t.space(4)),
              DesignPanel(
                tokens: t,
                title: 'Diagnostica BLE',
                icon: Icons.monitor_heart_outlined,
                children: [
                  for (final line in data.diagnosticsLines)
                    Padding(
                      padding: EdgeInsets.only(bottom: t.space(1.5)),
                      child: Text(line,
                          style: t.layoutStyle == RadarLayoutStyle.hud
                              ? t.data(12, color: t.accent, weight: FontWeight.w500)
                              : t.body(13, color: t.inkMuted)),
                    ),
                ],
              ),
              DesignPanel(
                tokens: t,
                title: 'Avanzate',
                icon: Icons.tune,
                children: [
                  Text(
                    'Cambia ID solo in caso di collisione. Gli altri telefoni vedranno un nuovo partecipante.',
                    style: t.body(13.5, color: t.inkMuted),
                  ),
                  TextButton(onPressed: actions.onRegenerateId, child: const Text('Rigenera ID…')),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.palette_outlined, color: t.accent),
                    title: Text('Stile grafico e Design Studio',
                        style: t.body(15, weight: FontWeight.w700)),
                    subtitle: Text('Attivo: ${t.direction.label}',
                        style: t.body(13, color: t.inkMuted)),
                    onTap: actions.onChooseDesign,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared header row ───────────────────────────────────────────────────
  Widget _topBar(BuildContext context, {required String kicker, Color? ink}) {
    final t = tokens;
    final fg = ink ?? t.ink;
    return LayoutBuilder(builder: (context, constraints) {
      final maxChipW = (constraints.maxWidth * 0.42).clamp(96.0, 160.0);
      return Row(children: [
        Expanded(
          child: Text(
            t.label(kicker),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.caption(color: fg.withValues(alpha: 0.72)).copyWith(
                  fontSize: 11.5,
                  letterSpacing: 1.1,
                ),
          ),
        ),
        SizedBox(width: t.space(2)),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxChipW),
          child: _NameChip(tokens: t, name: data.myName, onTap: actions.onEditName),
        ),
        SizedBox(width: t.space(1.5)),
        _RoundIconButton(
          tokens: t,
          key: const Key('design-open-studio-btn'),
          icon: Icons.palette_outlined,
          tooltip: 'Stili UI e Design Studio',
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

  // ── A · Outdoor Premium: dark pine hero card with contour radar ─────────
  List<Widget> _heroCardTop(BuildContext context) {
    final t = tokens;
    return [
      _topBar(context, kicker: 'Convoy Mesh'),
      SizedBox(height: t.space(2.5)),
      Text('Radar BLE', style: t.display(31)),
      SizedBox(height: t.space(1)),
      Text('Chi del gruppo è nel raggio Bluetooth, anche senza rete.',
          style: t.body(14, color: t.inkMuted)),
      SizedBox(height: t.space(3.5)),
      Container(
        decoration: BoxDecoration(
          gradient: t.heroBackground,
          borderRadius: BorderRadius.circular(t.radiusLarge),
          boxShadow: t.shadow,
        ),
        padding: EdgeInsets.all(t.space(4)),
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
                LiveDot(active: data.scanning, color: t.radarSweep, size: 8),
                Flexible(
                  child: Text(data.scanning ? 'Ricerca attiva' : 'Ricerca ferma',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body(13, color: t.heroInk, weight: FontWeight.w600)),
                ),
              ]),
            ],
          ),
          SizedBox(height: t.space(2.5)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: t.space(5)),
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
            Container(width: 1, height: 40, color: t.heroInk.withValues(alpha: 0.2)),
            _heroStat(data.offlineCount, 'non ricevuti'),
            Container(width: 1, height: 40, color: t.heroInk.withValues(alpha: 0.2)),
            Expanded(
              child: Column(children: [
                Icon(data.advertising ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                    color: t.heroInk, size: 22),
                SizedBox(height: t.space(1)),
                Text(data.advertising ? 'Visibile' : 'Non visibile',
                    textAlign: TextAlign.center,
                    style: t.body(12.5, color: t.heroInk.withValues(alpha: 0.85))),
              ]),
            ),
          ]),
          SizedBox(height: t.space(2)),
          Text(DesignedRadarView.radarCaption,
              textAlign: TextAlign.center,
              style: t.body(11.5, color: t.heroInk.withValues(alpha: 0.7))),
        ]),
      ),
    ];
  }

  Widget _heroStat(int value, String label) => Expanded(
        child: Column(children: [
          Text('$value', style: tokens.display(30, color: tokens.heroInk)),
          Text(label,
              textAlign: TextAlign.center,
              style: tokens.body(12.5, color: tokens.heroInk.withValues(alpha: 0.85))),
        ]),
      );

  // ── B · Tactical Explorer: HUD telemetry + sweep scope ──────────────────
  List<Widget> _hudTop(BuildContext context) {
    final t = tokens;
    String two(int v) => v.toString().padLeft(2, '0');
    return [
      _topBar(context, kicker: 'Convoy · Radar'),
      SizedBox(height: t.space(4)),
      Row(children: [
        LiveDot(active: data.scanning, color: t.accent, size: 8),
        SizedBox(width: t.space(1)),
        Expanded(
          child: Text(data.scanning ? 'LIVE · SCANSIONE ATTIVA' : 'IDLE · SCANSIONE FERMA',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.data(12, color: data.scanning ? t.accent : t.inkMuted)),
        ),
      ]),
      SizedBox(height: t.space(3)),
      DesignBleStatusPill(
        tokens: t,
        label: data.bleLabel,
        ready: data.bleReady,
        onTap: actions.onStatusTap,
      ),
      SizedBox(height: t.space(3)),
      Row(children: [
        _hudCell('Scan', data.scanning ? 'ON' : 'OFF', data.scanning ? t.accent : t.inkMuted),
        SizedBox(width: t.space(2)),
        _hudCell('Adv', data.advertising ? 'ON' : 'OFF', data.advertising ? t.accent : t.inkMuted),
        SizedBox(width: t.space(2)),
        _hudCell('Presenti', two(data.onlineCount), t.ink),
        SizedBox(width: t.space(2)),
        _hudCell('Non ric.', two(data.offlineCount), data.offlineCount > 0 ? t.warning : t.ink),
      ]),
      SizedBox(height: t.space(4)),
      _Bracketed(
        tokens: t,
        child: Padding(
          padding: EdgeInsets.all(t.space(4)),
          child: Column(children: [
            RadarScope(
              tokens: t,
              peers: data.peers,
              scanning: data.scanning,
              showLabels: true,
              selectedPeerId: _selectedPeerId,
              onPeerTap: _togglePeerSelection,
            ),
            SizedBox(height: t.space(3)),
            Text(DesignedRadarView.radarCaption.toUpperCase(),
                textAlign: TextAlign.center,
                style: t.caption(color: t.inkMuted).copyWith(fontSize: 9.5, letterSpacing: 1.0)),
          ]),
        ),
      ),
    ];
  }

  Widget _hudCell(String label, String value, Color color) => Expanded(
        child: Container(
          padding: EdgeInsets.symmetric(vertical: tokens.space(2.5), horizontal: tokens.space(2)),
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border.all(color: tokens.outline, width: tokens.borderWidth),
            borderRadius: BorderRadius.circular(tokens.radiusSmall),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tokens.label(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.caption().copyWith(fontSize: 9.5, letterSpacing: 0.9)),
            SizedBox(height: tokens.space(1)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: tokens.data(20, color: color)),
            ),
          ]),
        ),
      );

  // ── C · Minimal Adventure: giant count + pulse rings ────────────────────
  List<Widget> _editorialTop(BuildContext context) {
    final t = tokens;
    return [
      _topBar(context, kicker: 'Radar BLE'),
      SizedBox(height: t.space(3)),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${data.onlineCount}', style: t.display(74).copyWith(height: 0.92)),
        SizedBox(width: t.space(3)),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: t.space(1)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data.onlineCount == 1 ? 'vicino presente' : 'vicini presenti',
                  style: t.display(21).copyWith(letterSpacing: -0.4)),
              Text('${data.offlineCount} non ricevuti', style: t.body(14.5, color: t.inkMuted)),
            ]),
          ),
        ),
      ]),
      SizedBox(height: t.space(3)),
      Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [
        DesignBleStatusPill(
          tokens: t,
          label: data.bleLabel,
          ready: data.bleReady,
          onTap: actions.onStatusTap,
        ),
        _plainPill(
          leading: LiveDot(active: data.scanning, color: t.highlight, size: 8),
          text: data.scanning ? 'Ricerca attiva' : 'Ricerca ferma',
        ),
        _plainPill(
          leading: Icon(data.advertising ? Icons.wifi_tethering : Icons.wifi_tethering_off,
              size: 18, color: t.ink),
          text: data.advertising ? 'Visibile agli altri' : 'Non visibile',
        ),
      ]),
      SizedBox(height: t.space(3)),
      Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.radiusLarge),
          border: Border.all(color: t.outline, width: t.borderWidth),
        ),
        padding: EdgeInsets.all(t.space(4)),
        child: Column(children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: t.space(3.5)),
            child: RadarScope(
              tokens: t,
              peers: data.peers,
              scanning: data.scanning,
              selectedPeerId: _selectedPeerId,
              onPeerTap: _togglePeerSelection,
            ),
          ),
          SizedBox(height: t.space(2)),
          Text(DesignedRadarView.radarCaption,
              textAlign: TextAlign.center, style: t.body(12, color: t.inkMuted)),
        ]),
      ),
    ];
  }

  Widget _plainPill({required Widget leading, required String text}) {
    final t = tokens;
    return Container(
      constraints: BoxConstraints(minHeight: t.minTouchTarget - 8),
      padding: EdgeInsets.only(left: t.space(2), right: t.space(3.5)),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.radiusLarge),
        border: Border.all(color: t.outline, width: t.borderWidth),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        leading,
        SizedBox(width: t.space(1.5)),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.body(14, weight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }

  // ── Mode / GPS freshness line (always visible, as in the original) ──────
  Widget _modeBlock() {
    final t = tokens;
    final icon = data.outingActive
        ? (data.gpsFresh ? Icons.gps_fixed : Icons.gps_not_fixed)
        : Icons.people_alt_outlined;
    final tone = data.outingActive ? (data.gpsFresh ? t.positive : t.warning) : t.accent;
    return Padding(
      padding: EdgeInsets.only(top: t.space(4)),
      child: Container(
        padding: EdgeInsets.all(t.space(4)),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(t.radiusMedium),
          border: Border.all(color: t.outline, width: t.borderWidth),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: t.brightness == Brightness.dark ? 0.16 : 0.12),
              borderRadius: BorderRadius.circular(t.radiusSmall),
            ),
            child: Icon(icon, color: tone, size: 22),
          ),
          SizedBox(width: t.space(3)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
    return Container(
      padding: EdgeInsets.all(t.space(5)),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.radiusMedium),
        border: Border.all(color: t.outline, width: t.borderWidth),
      ),
      child: Row(children: [
        Icon(Icons.travel_explore, color: t.inkMuted, size: 30),
        SizedBox(width: t.space(3)),
        Expanded(
          child: Text(
            'Nessun partecipante rilevato. Tocca ? per sapere come funziona la ricerca.',
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
      (Icons.admin_panel_settings_outlined, 'Permessi app', actions.onOpenAppPermissions),
      (Icons.campaign_outlined, 'Invia nome', actions.onSendName),
      (Icons.refresh, 'Riavvia scan', actions.onRestartScan),
    ];
    return LayoutBuilder(builder: (context, box) {
      final gap = t.space(2.5);
      final w = (box.maxWidth - gap) / 2;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final (icon, label, cb) in items)
          SizedBox(width: w, child: ToolButton(tokens: t, icon: icon, label: label, onTap: cb)),
      ]);
    });
  }

  Widget _identity(BuildContext context) {
    final t = tokens;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(3)),
      decoration: BoxDecoration(
        color: t.layoutStyle == RadarLayoutStyle.hud ? t.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(t.radiusMedium),
        border: Border.all(color: t.outline, width: t.borderWidth),
      ),
      child: Row(children: [
        Icon(Icons.badge_outlined, color: t.inkMuted, size: 20),
        SizedBox(width: t.space(3)),
        Expanded(
          child: SelectableText('Il mio ID: ${data.myId}',
              style: t.data(14, color: t.ink, weight: FontWeight.w600)),
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
    final hud = t.layoutStyle == RadarLayoutStyle.hud;
    final editorial = t.layoutStyle == RadarLayoutStyle.editorial;
    final tone = peer.online ? t.positive : t.inkMuted;
    final details = <String>[
      peer.gpsLine,
      if (peer.accuracyLine != null) peer.accuracyLine!,
      if (peer.historyLine != null) peer.historyLine!,
    ];

    final nameStyle = hud
        ? t.data(17, weight: FontWeight.w700)
        : editorial
            ? t.display(21).copyWith(letterSpacing: -0.5)
            : t.display(21);

    final borderColor = highlighted ? t.highlight : t.outline;
    final borderW = highlighted ? 2.0 : t.borderWidth;

    return AnimatedOpacity(
      duration: t.motionMedium,
      opacity: peer.online ? 1 : 0.78,
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.radiusMedium),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.radiusMedium),
          onTap: onTap,
          child: AnimatedContainer(
            duration: t.motionFast,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radiusMedium),
              border: hud
                  ? Border(
                      left: BorderSide(color: Color(peer.color), width: highlighted ? 5 : 3),
                      top: BorderSide(color: borderColor, width: borderW),
                      right: BorderSide(color: borderColor, width: borderW),
                      bottom: BorderSide(color: borderColor, width: borderW),
                    )
                  : Border.all(color: borderColor, width: borderW),
              boxShadow: t.elevated ? t.shadow : const [],
            ),
            padding: EdgeInsets.all(t.space(4)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                PeerAvatar(tokens: t, peer: peer, size: hud ? 40 : 48, square: hud),
                SizedBox(width: t.space(3)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.label(peer.name),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle),
                    SizedBox(height: t.space(1)),
                    Wrap(spacing: t.space(1.5), children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: 2),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: t.brightness == Brightness.dark ? 0.16 : 0.12),
                          borderRadius: BorderRadius.circular(t.radiusSmall),
                        ),
                        child: Text(t.label(peer.statusLabel),
                            style: t.caption(color: tone).copyWith(fontSize: 11.5)),
                      ),
                    ]),
                  ]),
                ),
                SizedBox(width: t.space(2)),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  SignalBars(
                    level: peer.online ? peer.signalLevel : 0,
                    color: hud ? t.accent : (editorial ? t.ink : t.accent),
                    track: t.outline,
                    height: 18,
                  ),
                  SizedBox(height: t.space(1)),
                  Text(peer.rssi < 0 ? '${peer.rssi} dBm' : '— dBm',
                      style: t.data(11.5, color: t.inkMuted, weight: FontWeight.w600)),
                ]),
              ]),
              SizedBox(height: t.space(3)),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                LocationGlyph(tokens: t, state: peer.locationState, size: 18),
                SizedBox(width: t.space(2)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final line in details)
                      Text(line, style: t.body(13.5, color: t.ink.withValues(alpha: 0.86))),
                  ]),
                ),
              ]),
              SizedBox(height: t.space(2)),
              Divider(height: t.space(3)),
              Text(peer.signalLine,
                  style: t.body(12.5, color: t.inkMuted, weight: FontWeight.w600)),
              Text(peer.lastPacketLine, style: t.body(12.5, color: t.inkMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NameChip extends StatelessWidget {
  const _NameChip({required this.tokens, required this.name, required this.onTap});
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
              constraints: BoxConstraints(minHeight: t.minTouchTarget - 8),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: t.space(2.5)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.person_outline, size: 16, color: t.accent),
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
                  Icon(Icons.edit, size: 13, color: t.inkMuted),
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
    final s = t.minTouchTarget - 8;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: t.surface,
        shape: CircleBorder(side: BorderSide(color: t.outline, width: t.borderWidth)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: s, height: s, child: Icon(icon, color: t.ink, size: 20)),
        ),
      ),
    );
  }
}

/// HUD frame with corner brackets (Tactical Explorer).
class _Bracketed extends StatelessWidget {
  const _Bracketed({required this.tokens, required this.child});
  final ConvoyDesignTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: tokens.heroBackground,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(color: tokens.outline, width: tokens.borderWidth),
        ),
        child: CustomPaint(
          foregroundPainter: _BracketPainter(tokens.accent),
          child: child,
        ),
      );
}

class _BracketPainter extends CustomPainter {
  _BracketPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const l = 18.0;
    const i = 6.0;
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final w = size.width, h = size.height;
    canvas.drawPath(Path()..moveTo(i, i + l)..lineTo(i, i)..lineTo(i + l, i), p);
    canvas.drawPath(Path()..moveTo(w - i - l, i)..lineTo(w - i, i)..lineTo(w - i, i + l), p);
    canvas.drawPath(Path()..moveTo(i, h - i - l)..lineTo(i, h - i)..lineTo(i + l, h - i), p);
    canvas.drawPath(Path()..moveTo(w - i - l, h - i)..lineTo(w - i, h - i)..lineTo(w - i, h - i - l), p);
  }

  @override
  bool shouldRepaint(covariant _BracketPainter old) => old.color != color;
}
