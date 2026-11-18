import 'package:flutter/foundation.dart';

/// Customisable visual copy tokens for the **Outdoor Premium** experience.
///
/// Only visual chrome headers, subtitles and non-critical CTA texts live here;
/// functional/diagnostic protocol labels and CI-verified navigation labels
/// remain untouched in their widgets.
@immutable
class OutdoorCopyTokens {
  const OutdoorCopyTokens({
    this.appKicker = defaultAppKicker,
    this.radarTitle = defaultRadarTitle,
    this.radarSubtitle = defaultRadarSubtitle,
    this.radarCaption = defaultRadarCaption,
    this.peersSectionTitle = defaultPeersSectionTitle,
    this.toolsSectionTitle = defaultToolsSectionTitle,
    this.bleDiagSectionTitle = defaultBleDiagSectionTitle,
    this.advancedSectionTitle = defaultAdvancedSectionTitle,
    this.emptyPeersMessage = defaultEmptyPeersMessage,
    this.mapSearchCta = defaultMapSearchCta,
    this.mapRecenterCta = defaultMapRecenterCta,
    this.diagnosticTitle = defaultDiagnosticTitle,
    this.diagnosticStartTitle = defaultDiagnosticStartTitle,
    this.diagnosticActiveTitle = defaultDiagnosticActiveTitle,
    this.diagnosticContextTitle = defaultDiagnosticContextTitle,
    this.diagnosticRuntimeTitle = defaultDiagnosticRuntimeTitle,
    this.diagnosticGuideTitle = defaultDiagnosticGuideTitle,
  });

  static const defaults = OutdoorCopyTokens();

  static const defaultAppKicker = 'Convoy Mesh';
  static const defaultRadarTitle = 'Radar BLE';
  static const defaultRadarSubtitle =
      'Chi del gruppo è nel raggio Bluetooth, anche senza rete.';
  static const defaultRadarCaption =
      'Anelli = qualità del segnale BLE, non distanza né direzione.';
  static const defaultPeersSectionTitle = 'Partecipanti';
  static const defaultToolsSectionTitle = 'Strumenti';
  static const defaultBleDiagSectionTitle = 'Diagnostica BLE';
  static const defaultAdvancedSectionTitle = 'Avanzate';
  static const defaultEmptyPeersMessage =
      'Nessun partecipante rilevato. Tocca ? per sapere come funziona la ricerca.';
  static const defaultMapSearchCta = 'Cerca GPS';
  static const defaultMapRecenterCta = 'Centra su di me';
  static const defaultDiagnosticTitle = 'Test diagnostico';
  static const defaultDiagnosticStartTitle = 'Registrazione diagnostica locale';
  static const defaultDiagnosticActiveTitle = 'Registrazione locale in corso';
  static const defaultDiagnosticContextTitle = 'Condizioni reali della prova';
  static const defaultDiagnosticRuntimeTitle = 'Runtime e capacità hardware';
  static const defaultDiagnosticGuideTitle = 'Lettura dei log';

  final String appKicker;
  final String radarTitle;
  final String radarSubtitle;
  final String radarCaption;
  final String peersSectionTitle;
  final String toolsSectionTitle;
  final String bleDiagSectionTitle;
  final String advancedSectionTitle;
  final String emptyPeersMessage;
  final String mapSearchCta;
  final String mapRecenterCta;
  final String diagnosticTitle;
  final String diagnosticStartTitle;
  final String diagnosticActiveTitle;
  final String diagnosticContextTitle;
  final String diagnosticRuntimeTitle;
  final String diagnosticGuideTitle;

  OutdoorCopyTokens copyWith({
    String? appKicker,
    String? radarTitle,
    String? radarSubtitle,
    String? radarCaption,
    String? peersSectionTitle,
    String? toolsSectionTitle,
    String? bleDiagSectionTitle,
    String? advancedSectionTitle,
    String? emptyPeersMessage,
    String? mapSearchCta,
    String? mapRecenterCta,
    String? diagnosticTitle,
    String? diagnosticStartTitle,
    String? diagnosticActiveTitle,
    String? diagnosticContextTitle,
    String? diagnosticRuntimeTitle,
    String? diagnosticGuideTitle,
  }) =>
      OutdoorCopyTokens(
        appKicker: appKicker ?? this.appKicker,
        radarTitle: radarTitle ?? this.radarTitle,
        radarSubtitle: radarSubtitle ?? this.radarSubtitle,
        radarCaption: radarCaption ?? this.radarCaption,
        peersSectionTitle: peersSectionTitle ?? this.peersSectionTitle,
        toolsSectionTitle: toolsSectionTitle ?? this.toolsSectionTitle,
        bleDiagSectionTitle: bleDiagSectionTitle ?? this.bleDiagSectionTitle,
        advancedSectionTitle: advancedSectionTitle ?? this.advancedSectionTitle,
        emptyPeersMessage: emptyPeersMessage ?? this.emptyPeersMessage,
        mapSearchCta: mapSearchCta ?? this.mapSearchCta,
        mapRecenterCta: mapRecenterCta ?? this.mapRecenterCta,
        diagnosticTitle: diagnosticTitle ?? this.diagnosticTitle,
        diagnosticStartTitle: diagnosticStartTitle ?? this.diagnosticStartTitle,
        diagnosticActiveTitle:
            diagnosticActiveTitle ?? this.diagnosticActiveTitle,
        diagnosticContextTitle:
            diagnosticContextTitle ?? this.diagnosticContextTitle,
        diagnosticRuntimeTitle:
            diagnosticRuntimeTitle ?? this.diagnosticRuntimeTitle,
        diagnosticGuideTitle:
            diagnosticGuideTitle ?? this.diagnosticGuideTitle,
      );

  static String _pick(Map<String, dynamic> map, String key, String fallback) {
    final raw = map[key];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return fallback;
  }

  factory OutdoorCopyTokens.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    return OutdoorCopyTokens(
      appKicker: _pick(json, 'appKicker', defaultAppKicker),
      radarTitle: _pick(json, 'radarTitle', defaultRadarTitle),
      radarSubtitle: _pick(json, 'radarSubtitle', defaultRadarSubtitle),
      radarCaption: _pick(json, 'radarCaption', defaultRadarCaption),
      peersSectionTitle:
          _pick(json, 'peersSectionTitle', defaultPeersSectionTitle),
      toolsSectionTitle:
          _pick(json, 'toolsSectionTitle', defaultToolsSectionTitle),
      bleDiagSectionTitle:
          _pick(json, 'bleDiagSectionTitle', defaultBleDiagSectionTitle),
      advancedSectionTitle:
          _pick(json, 'advancedSectionTitle', defaultAdvancedSectionTitle),
      emptyPeersMessage:
          _pick(json, 'emptyPeersMessage', defaultEmptyPeersMessage),
      mapSearchCta: _pick(json, 'mapSearchCta', defaultMapSearchCta),
      mapRecenterCta: _pick(json, 'mapRecenterCta', defaultMapRecenterCta),
      diagnosticTitle: _pick(json, 'diagnosticTitle', defaultDiagnosticTitle),
      diagnosticStartTitle:
          _pick(json, 'diagnosticStartTitle', defaultDiagnosticStartTitle),
      diagnosticActiveTitle:
          _pick(json, 'diagnosticActiveTitle', defaultDiagnosticActiveTitle),
      diagnosticContextTitle:
          _pick(json, 'diagnosticContextTitle', defaultDiagnosticContextTitle),
      diagnosticRuntimeTitle:
          _pick(json, 'diagnosticRuntimeTitle', defaultDiagnosticRuntimeTitle),
      diagnosticGuideTitle:
          _pick(json, 'diagnosticGuideTitle', defaultDiagnosticGuideTitle),
    );
  }

  Map<String, String> toJson() => {
        'appKicker': appKicker,
        'radarTitle': radarTitle,
        'radarSubtitle': radarSubtitle,
        'radarCaption': radarCaption,
        'peersSectionTitle': peersSectionTitle,
        'toolsSectionTitle': toolsSectionTitle,
        'bleDiagSectionTitle': bleDiagSectionTitle,
        'advancedSectionTitle': advancedSectionTitle,
        'emptyPeersMessage': emptyPeersMessage,
        'mapSearchCta': mapSearchCta,
        'mapRecenterCta': mapRecenterCta,
        'diagnosticTitle': diagnosticTitle,
        'diagnosticStartTitle': diagnosticStartTitle,
        'diagnosticActiveTitle': diagnosticActiveTitle,
        'diagnosticContextTitle': diagnosticContextTitle,
        'diagnosticRuntimeTitle': diagnosticRuntimeTitle,
        'diagnosticGuideTitle': diagnosticGuideTitle,
      };

  @override
  bool operator ==(Object other) =>
      other is OutdoorCopyTokens &&
      other.appKicker == appKicker &&
      other.radarTitle == radarTitle &&
      other.radarSubtitle == radarSubtitle &&
      other.radarCaption == radarCaption &&
      other.peersSectionTitle == peersSectionTitle &&
      other.toolsSectionTitle == toolsSectionTitle &&
      other.bleDiagSectionTitle == bleDiagSectionTitle &&
      other.advancedSectionTitle == advancedSectionTitle &&
      other.emptyPeersMessage == emptyPeersMessage &&
      other.mapSearchCta == mapSearchCta &&
      other.mapRecenterCta == mapRecenterCta &&
      other.diagnosticTitle == diagnosticTitle &&
      other.diagnosticStartTitle == diagnosticStartTitle &&
      other.diagnosticActiveTitle == diagnosticActiveTitle &&
      other.diagnosticContextTitle == diagnosticContextTitle &&
      other.diagnosticRuntimeTitle == diagnosticRuntimeTitle &&
      other.diagnosticGuideTitle == diagnosticGuideTitle;

  @override
  int get hashCode => Object.hash(
        appKicker,
        radarTitle,
        radarSubtitle,
        radarCaption,
        peersSectionTitle,
        toolsSectionTitle,
        bleDiagSectionTitle,
        advancedSectionTitle,
        emptyPeersMessage,
        mapSearchCta,
        mapRecenterCta,
        diagnosticTitle,
        diagnosticStartTitle,
        diagnosticActiveTitle,
        diagnosticContextTitle,
        diagnosticRuntimeTitle,
        diagnosticGuideTitle,
      );
}
