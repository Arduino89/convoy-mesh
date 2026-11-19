import 'package:flutter/widgets.dart';

/// Customisable visual copy tokens for the **Outdoor Premium** experience.
///
/// Only visual chrome headers, subtitles and non-critical CTA texts live here;
/// functional/diagnostic protocol labels, data-interpretation warnings (such as
/// [radarCaption]), and CI-verified navigation labels remain protected.
@immutable
class OutdoorCopyTokens {
  const OutdoorCopyTokens({
    this.appKicker = defaultAppKicker,
    this.radarTitle = defaultRadarTitle,
    this.radarSubtitle = defaultRadarSubtitle,
    String? radarCaption,
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
  }) : _ignoredRadarCaption = radarCaption;

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

  /// Bounded character limits per editable visual copy field so UI chrome
  /// stays legible and never overflows on compact phones.
  static const maxLengths = <String, int>{
    'appKicker': 28,
    'radarTitle': 40,
    'radarSubtitle': 120,
    'peersSectionTitle': 36,
    'toolsSectionTitle': 36,
    'bleDiagSectionTitle': 40,
    'advancedSectionTitle': 36,
    'emptyPeersMessage': 140,
    'mapSearchCta': 28,
    'mapRecenterCta': 28,
    'diagnosticTitle': 40,
    'diagnosticStartTitle': 48,
    'diagnosticActiveTitle': 48,
    'diagnosticContextTitle': 48,
    'diagnosticRuntimeTitle': 48,
    'diagnosticGuideTitle': 48,
  };

  static int maxLengthFor(String key) => maxLengths[key] ?? 48;

  static final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]+');
  static final RegExp _multiSpace = RegExp(r'\s{2,}');

  /// Strips newlines/control characters, collapses repeated spaces, clamps
  /// length by grapheme cluster, and falls back to [fallback] if empty.
  static String sanitize(
    String raw, {
    required String fallback,
    required int maxLength,
  }) {
    final normalized =
        raw.replaceAll(_controlChars, ' ').replaceAll(_multiSpace, ' ').trim();
    if (normalized.isEmpty) return fallback;
    final chars = normalized.characters;
    if (chars.length <= maxLength) return normalized;
    final clipped = chars.take(maxLength).toString().trimRight();
    return clipped.isEmpty ? fallback : clipped;
  }

  final String appKicker;
  final String radarTitle;
  final String radarSubtitle;
  // Kept strictly for const-constructor backwards compatibility; the warning
  // getter below always returns [defaultRadarCaption].
  // ignore: unused_field
  final String? _ignoredRadarCaption;
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

  /// Protected data-interpretation notice: always truthful, never editable.
  String get radarCaption => defaultRadarCaption;

  OutdoorCopyTokens copyWith({
    String? appKicker,
    String? radarTitle,
    String? radarSubtitle,
    String? radarCaption, // Intentionally ignored: protected notice.
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
        appKicker: appKicker != null
            ? sanitize(appKicker,
                fallback: defaultAppKicker,
                maxLength: maxLengthFor('appKicker'))
            : this.appKicker,
        radarTitle: radarTitle != null
            ? sanitize(radarTitle,
                fallback: defaultRadarTitle,
                maxLength: maxLengthFor('radarTitle'))
            : this.radarTitle,
        radarSubtitle: radarSubtitle != null
            ? sanitize(radarSubtitle,
                fallback: defaultRadarSubtitle,
                maxLength: maxLengthFor('radarSubtitle'))
            : this.radarSubtitle,
        peersSectionTitle: peersSectionTitle != null
            ? sanitize(peersSectionTitle,
                fallback: defaultPeersSectionTitle,
                maxLength: maxLengthFor('peersSectionTitle'))
            : this.peersSectionTitle,
        toolsSectionTitle: toolsSectionTitle != null
            ? sanitize(toolsSectionTitle,
                fallback: defaultToolsSectionTitle,
                maxLength: maxLengthFor('toolsSectionTitle'))
            : this.toolsSectionTitle,
        bleDiagSectionTitle: bleDiagSectionTitle != null
            ? sanitize(bleDiagSectionTitle,
                fallback: defaultBleDiagSectionTitle,
                maxLength: maxLengthFor('bleDiagSectionTitle'))
            : this.bleDiagSectionTitle,
        advancedSectionTitle: advancedSectionTitle != null
            ? sanitize(advancedSectionTitle,
                fallback: defaultAdvancedSectionTitle,
                maxLength: maxLengthFor('advancedSectionTitle'))
            : this.advancedSectionTitle,
        emptyPeersMessage: emptyPeersMessage != null
            ? sanitize(emptyPeersMessage,
                fallback: defaultEmptyPeersMessage,
                maxLength: maxLengthFor('emptyPeersMessage'))
            : this.emptyPeersMessage,
        mapSearchCta: mapSearchCta != null
            ? sanitize(mapSearchCta,
                fallback: defaultMapSearchCta,
                maxLength: maxLengthFor('mapSearchCta'))
            : this.mapSearchCta,
        mapRecenterCta: mapRecenterCta != null
            ? sanitize(mapRecenterCta,
                fallback: defaultMapRecenterCta,
                maxLength: maxLengthFor('mapRecenterCta'))
            : this.mapRecenterCta,
        diagnosticTitle: diagnosticTitle != null
            ? sanitize(diagnosticTitle,
                fallback: defaultDiagnosticTitle,
                maxLength: maxLengthFor('diagnosticTitle'))
            : this.diagnosticTitle,
        diagnosticStartTitle: diagnosticStartTitle != null
            ? sanitize(diagnosticStartTitle,
                fallback: defaultDiagnosticStartTitle,
                maxLength: maxLengthFor('diagnosticStartTitle'))
            : this.diagnosticStartTitle,
        diagnosticActiveTitle: diagnosticActiveTitle != null
            ? sanitize(diagnosticActiveTitle,
                fallback: defaultDiagnosticActiveTitle,
                maxLength: maxLengthFor('diagnosticActiveTitle'))
            : this.diagnosticActiveTitle,
        diagnosticContextTitle: diagnosticContextTitle != null
            ? sanitize(diagnosticContextTitle,
                fallback: defaultDiagnosticContextTitle,
                maxLength: maxLengthFor('diagnosticContextTitle'))
            : this.diagnosticContextTitle,
        diagnosticRuntimeTitle: diagnosticRuntimeTitle != null
            ? sanitize(diagnosticRuntimeTitle,
                fallback: defaultDiagnosticRuntimeTitle,
                maxLength: maxLengthFor('diagnosticRuntimeTitle'))
            : this.diagnosticRuntimeTitle,
        diagnosticGuideTitle: diagnosticGuideTitle != null
            ? sanitize(diagnosticGuideTitle,
                fallback: defaultDiagnosticGuideTitle,
                maxLength: maxLengthFor('diagnosticGuideTitle'))
            : this.diagnosticGuideTitle,
      );

  static String _pick(Map<String, dynamic> map, String key, String fallback) {
    final raw = map[key];
    if (raw is String) {
      return sanitize(raw, fallback: fallback, maxLength: maxLengthFor(key));
    }
    return fallback;
  }

  factory OutdoorCopyTokens.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    return OutdoorCopyTokens(
      appKicker: _pick(json, 'appKicker', defaultAppKicker),
      radarTitle: _pick(json, 'radarTitle', defaultRadarTitle),
      radarSubtitle: _pick(json, 'radarSubtitle', defaultRadarSubtitle),
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
