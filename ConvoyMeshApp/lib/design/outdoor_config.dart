import 'package:flutter/foundation.dart';

import 'outdoor_copy.dart';

/// Curated Outdoor Premium sub-palettes (all WCAG AAA body / AA accent & status).
enum OutdoorPalettePreset {
  pinoECarta,
  crestaAlba,
  terraERame,
  abeteNotturno,
}

extension OutdoorPalettePresetMeta on OutdoorPalettePreset {
  String get label => switch (this) {
        OutdoorPalettePreset.pinoECarta => 'Pino & Carta',
        OutdoorPalettePreset.crestaAlba => 'Cresta Alba',
        OutdoorPalettePreset.terraERame => 'Terra & Rame',
        OutdoorPalettePreset.abeteNotturno => 'Abete Notturno',
      };

  String get subtitle => switch (this) {
        OutdoorPalettePreset.pinoECarta => 'Carta calda, pino e ocra alpina',
        OutdoorPalettePreset.crestaAlba => 'Pietra chiara ad altissimo contrasto solare',
        OutdoorPalettePreset.terraERame => 'Sentiero roccia, argilla e muschio',
        OutdoorPalettePreset.abeteNotturno => 'Crepuscolo nel bosco, abete scuro',
      };
}

/// Complete, serialisable customisation config for **Outdoor Premium**.
///
/// Covers all six customisable design axes:
/// 1. Colors ([palettePreset] + individual ARGB overrides)
/// 2. Typography ([displayFamily], [bodyFamily], [dataFamily], [fontScale],
///    [displayBold], [uppercaseLabels])
/// 3. Dimensions ([radiusSmall], [radiusMedium], [radiusLarge], [borderWidth],
///    [minTouchTarget], [avatarSize], [iconScale], [radarScopeScale], [elevated])
/// 4. Spacing ([spaceUnit], [screenPaddingScale], [cardPaddingScale],
///    [sectionGapScale])
/// 5. Animations ([animationsEnabled], [radarRotationEnabled],
///    [livePulseEnabled], [showTopoContours], [radarPeriodMs], [motionFastMs],
///    [motionMediumMs])
/// 6. Copy ([copy])
@immutable
class OutdoorCustomConfig {
  const OutdoorCustomConfig({
    this.palettePreset = OutdoorPalettePreset.pinoECarta,
    this.canvasArgb,
    this.surfaceArgb,
    this.accentArgb,
    this.highlightArgb,
    this.heroBaseArgb,
    this.positiveArgb,
    this.warningArgb,
    this.criticalArgb,
    this.displayFamily = 'Fraunces',
    this.bodyFamily = 'Manrope',
    this.dataFamily = 'Manrope',
    this.fontScale = 1.0,
    this.displayBold = true,
    this.uppercaseLabels = false,
    this.radiusSmall = 12,
    this.radiusMedium = 20,
    this.radiusLarge = 30,
    this.borderWidth = 1.0,
    this.minTouchTarget = 52,
    this.avatarSize = 48,
    this.iconScale = 1.0,
    this.radarScopeScale = 0.90,
    this.elevated = true,
    this.spaceUnit = 4.0,
    this.screenPaddingScale = 1.0,
    this.cardPaddingScale = 1.0,
    this.sectionGapScale = 1.0,
    this.animationsEnabled = true,
    this.radarRotationEnabled = true,
    this.livePulseEnabled = true,
    this.showTopoContours = true,
    this.radarPeriodMs = 5200,
    this.motionFastMs = 220,
    this.motionMediumMs = 420,
    this.copy = OutdoorCopyTokens.defaults,
  });

  static const defaults = OutdoorCustomConfig();

  /// Special sentinel strings for dropdowns/JSON (`"system"` -> `null` system font).
  static const systemFontSentinel = 'system';
  static const availableFonts = <String?>[
    'Fraunces',
    'Manrope',
    'JetBrainsMono',
    null,
  ];

  // ── 1. Colors ──────────────────────────────────────────────────────────
  final OutdoorPalettePreset palettePreset;
  final int? canvasArgb;
  final int? surfaceArgb;
  final int? accentArgb;
  final int? highlightArgb;
  final int? heroBaseArgb;
  final int? positiveArgb;
  final int? warningArgb;
  final int? criticalArgb;

  // ── 2. Typography ──────────────────────────────────────────────────────
  final String? displayFamily;
  final String? bodyFamily;
  final String? dataFamily;
  final double fontScale;
  final bool displayBold;
  final bool uppercaseLabels;

  // ── 3. Dimensions ──────────────────────────────────────────────────────
  final double radiusSmall;
  final double radiusMedium;
  final double radiusLarge;
  final double borderWidth;
  final double minTouchTarget;
  final double avatarSize;
  final double iconScale;
  final double radarScopeScale;
  final bool elevated;

  // ── 4. Spacing ─────────────────────────────────────────────────────────
  final double spaceUnit;
  final double screenPaddingScale;
  final double cardPaddingScale;
  final double sectionGapScale;

  // ── 5. Animations ──────────────────────────────────────────────────────
  final bool animationsEnabled;
  final bool radarRotationEnabled;
  final bool livePulseEnabled;
  final bool showTopoContours;
  final int radarPeriodMs;
  final int motionFastMs;
  final int motionMediumMs;

  // ── 6. Copy ────────────────────────────────────────────────────────────
  final OutdoorCopyTokens copy;

  static const _keep = Object();

  OutdoorCustomConfig copyWith({
    OutdoorPalettePreset? palettePreset,
    Object? canvasArgb = _keep,
    Object? surfaceArgb = _keep,
    Object? accentArgb = _keep,
    Object? highlightArgb = _keep,
    Object? heroBaseArgb = _keep,
    Object? positiveArgb = _keep,
    Object? warningArgb = _keep,
    Object? criticalArgb = _keep,
    Object? displayFamily = _keep,
    Object? bodyFamily = _keep,
    Object? dataFamily = _keep,
    double? fontScale,
    bool? displayBold,
    bool? uppercaseLabels,
    double? radiusSmall,
    double? radiusMedium,
    double? radiusLarge,
    double? borderWidth,
    double? minTouchTarget,
    double? avatarSize,
    double? iconScale,
    double? radarScopeScale,
    bool? elevated,
    double? spaceUnit,
    double? screenPaddingScale,
    double? cardPaddingScale,
    double? sectionGapScale,
    bool? animationsEnabled,
    bool? radarRotationEnabled,
    bool? livePulseEnabled,
    bool? showTopoContours,
    int? radarPeriodMs,
    int? motionFastMs,
    int? motionMediumMs,
    OutdoorCopyTokens? copy,
  }) =>
      OutdoorCustomConfig(
        palettePreset: palettePreset ?? this.palettePreset,
        canvasArgb:
            identical(canvasArgb, _keep) ? this.canvasArgb : canvasArgb as int?,
        surfaceArgb: identical(surfaceArgb, _keep)
            ? this.surfaceArgb
            : surfaceArgb as int?,
        accentArgb:
            identical(accentArgb, _keep) ? this.accentArgb : accentArgb as int?,
        highlightArgb: identical(highlightArgb, _keep)
            ? this.highlightArgb
            : highlightArgb as int?,
        heroBaseArgb: identical(heroBaseArgb, _keep)
            ? this.heroBaseArgb
            : heroBaseArgb as int?,
        positiveArgb: identical(positiveArgb, _keep)
            ? this.positiveArgb
            : positiveArgb as int?,
        warningArgb: identical(warningArgb, _keep)
            ? this.warningArgb
            : warningArgb as int?,
        criticalArgb: identical(criticalArgb, _keep)
            ? this.criticalArgb
            : criticalArgb as int?,
        displayFamily: identical(displayFamily, _keep)
            ? this.displayFamily
            : displayFamily as String?,
        bodyFamily: identical(bodyFamily, _keep)
            ? this.bodyFamily
            : bodyFamily as String?,
        dataFamily: identical(dataFamily, _keep)
            ? this.dataFamily
            : dataFamily as String?,
        fontScale: (fontScale ?? this.fontScale).clamp(0.88, 1.24).toDouble(),
        displayBold: displayBold ?? this.displayBold,
        uppercaseLabels: uppercaseLabels ?? this.uppercaseLabels,
        radiusSmall: (radiusSmall ?? this.radiusSmall).clamp(4.0, 20.0).toDouble(),
        radiusMedium:
            (radiusMedium ?? this.radiusMedium).clamp(8.0, 30.0).toDouble(),
        radiusLarge: (radiusLarge ?? this.radiusLarge).clamp(12.0, 38.0).toDouble(),
        borderWidth:
            (borderWidth ?? this.borderWidth).clamp(0.8, 2.5).toDouble(),
        minTouchTarget:
            (minTouchTarget ?? this.minTouchTarget).clamp(48.0, 64.0).toDouble(),
        avatarSize: (avatarSize ?? this.avatarSize).clamp(38.0, 60.0).toDouble(),
        iconScale: (iconScale ?? this.iconScale).clamp(0.85, 1.25).toDouble(),
        radarScopeScale:
            (radarScopeScale ?? this.radarScopeScale).clamp(0.75, 1.0).toDouble(),
        elevated: elevated ?? this.elevated,
        spaceUnit: (spaceUnit ?? this.spaceUnit).clamp(3.0, 5.5).toDouble(),
        screenPaddingScale:
            (screenPaddingScale ?? this.screenPaddingScale).clamp(0.8, 1.35).toDouble(),
        cardPaddingScale:
            (cardPaddingScale ?? this.cardPaddingScale).clamp(0.8, 1.35).toDouble(),
        sectionGapScale:
            (sectionGapScale ?? this.sectionGapScale).clamp(0.8, 1.4).toDouble(),
        animationsEnabled: animationsEnabled ?? this.animationsEnabled,
        radarRotationEnabled:
            radarRotationEnabled ?? this.radarRotationEnabled,
        livePulseEnabled: livePulseEnabled ?? this.livePulseEnabled,
        showTopoContours: showTopoContours ?? this.showTopoContours,
        radarPeriodMs:
            (radarPeriodMs ?? this.radarPeriodMs).clamp(2400, 9500).toInt(),
        motionFastMs:
            (motionFastMs ?? this.motionFastMs).clamp(80, 450).toInt(),
        motionMediumMs:
            (motionMediumMs ?? this.motionMediumMs).clamp(140, 750).toInt(),
        copy: copy ?? this.copy,
      );

  /// Clears per-color overrides while keeping typography, sizing, spacing, motion, copy.
  OutdoorCustomConfig withPalettePreset(OutdoorPalettePreset preset) => copyWith(
        palettePreset: preset,
        canvasArgb: null,
        surfaceArgb: null,
        accentArgb: null,
        highlightArgb: null,
        heroBaseArgb: null,
        positiveArgb: null,
        warningArgb: null,
        criticalArgb: null,
      );

  static double _num(Map<String, dynamic> m, String k, double fallback,
      double min, double max) {
    final v = m[k];
    if (v is num && v.isFinite) return v.toDouble().clamp(min, max).toDouble();
    return fallback;
  }

  static int _int(
      Map<String, dynamic> m, String k, int fallback, int min, int max) {
    final v = m[k];
    if (v is num && v.isFinite) return v.round().clamp(min, max);
    return fallback;
  }

  static int? _argb(Map<String, dynamic> m, String k) {
    final v = m[k];
    return v is int ? v : null;
  }

  static String? _font(Map<String, dynamic> m, String k, String? fallback) {
    if (!m.containsKey(k)) return fallback;
    final v = m[k];
    if (v == null || v == systemFontSentinel) return null;
    if (v is String && availableFonts.contains(v)) return v;
    return fallback;
  }

  static bool _flag(Map<String, dynamic> m, String k, bool fallback) {
    final v = m[k];
    return v is bool ? v : fallback;
  }

  factory OutdoorCustomConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    final presetName = json['palettePreset'];
    final preset = OutdoorPalettePreset.values.firstWhere(
      (p) => p.name == presetName,
      orElse: () => OutdoorPalettePreset.pinoECarta,
    );
    return OutdoorCustomConfig(
      palettePreset: preset,
      canvasArgb: _argb(json, 'canvasArgb'),
      surfaceArgb: _argb(json, 'surfaceArgb'),
      accentArgb: _argb(json, 'accentArgb'),
      highlightArgb: _argb(json, 'highlightArgb'),
      heroBaseArgb: _argb(json, 'heroBaseArgb'),
      positiveArgb: _argb(json, 'positiveArgb'),
      warningArgb: _argb(json, 'warningArgb'),
      criticalArgb: _argb(json, 'criticalArgb'),
      displayFamily: _font(json, 'displayFamily', defaults.displayFamily),
      bodyFamily: _font(json, 'bodyFamily', defaults.bodyFamily),
      dataFamily: _font(json, 'dataFamily', defaults.dataFamily),
      fontScale: _num(json, 'fontScale', 1.0, 0.88, 1.24),
      displayBold: _flag(json, 'displayBold', true),
      uppercaseLabels: _flag(json, 'uppercaseLabels', false),
      radiusSmall: _num(json, 'radiusSmall', 12, 4, 20),
      radiusMedium: _num(json, 'radiusMedium', 20, 8, 30),
      radiusLarge: _num(json, 'radiusLarge', 30, 12, 38),
      borderWidth: _num(json, 'borderWidth', 1.0, 0.8, 2.5),
      minTouchTarget: _num(json, 'minTouchTarget', 52, 48, 64),
      avatarSize: _num(json, 'avatarSize', 48, 38, 60),
      iconScale: _num(json, 'iconScale', 1.0, 0.85, 1.25),
      radarScopeScale: _num(json, 'radarScopeScale', 0.90, 0.75, 1.0),
      elevated: _flag(json, 'elevated', true),
      spaceUnit: _num(json, 'spaceUnit', 4.0, 3.0, 5.5),
      screenPaddingScale: _num(json, 'screenPaddingScale', 1.0, 0.8, 1.35),
      cardPaddingScale: _num(json, 'cardPaddingScale', 1.0, 0.8, 1.35),
      sectionGapScale: _num(json, 'sectionGapScale', 1.0, 0.8, 1.4),
      animationsEnabled: _flag(json, 'animationsEnabled', true),
      radarRotationEnabled: _flag(json, 'radarRotationEnabled', true),
      livePulseEnabled: _flag(json, 'livePulseEnabled', true),
      showTopoContours: _flag(json, 'showTopoContours', true),
      radarPeriodMs: _int(json, 'radarPeriodMs', 5200, 2400, 9500),
      motionFastMs: _int(json, 'motionFastMs', 220, 80, 450),
      motionMediumMs: _int(json, 'motionMediumMs', 420, 140, 750),
      copy: OutdoorCopyTokens.fromJson(
        json['copy'] is Map<String, dynamic>
            ? json['copy'] as Map<String, dynamic>
            : null,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'palettePreset': palettePreset.name,
        if (canvasArgb != null) 'canvasArgb': canvasArgb,
        if (surfaceArgb != null) 'surfaceArgb': surfaceArgb,
        if (accentArgb != null) 'accentArgb': accentArgb,
        if (highlightArgb != null) 'highlightArgb': highlightArgb,
        if (heroBaseArgb != null) 'heroBaseArgb': heroBaseArgb,
        if (positiveArgb != null) 'positiveArgb': positiveArgb,
        if (warningArgb != null) 'warningArgb': warningArgb,
        if (criticalArgb != null) 'criticalArgb': criticalArgb,
        'displayFamily': displayFamily ?? systemFontSentinel,
        'bodyFamily': bodyFamily ?? systemFontSentinel,
        'dataFamily': dataFamily ?? systemFontSentinel,
        'fontScale': fontScale,
        'displayBold': displayBold,
        'uppercaseLabels': uppercaseLabels,
        'radiusSmall': radiusSmall,
        'radiusMedium': radiusMedium,
        'radiusLarge': radiusLarge,
        'borderWidth': borderWidth,
        'minTouchTarget': minTouchTarget,
        'avatarSize': avatarSize,
        'iconScale': iconScale,
        'radarScopeScale': radarScopeScale,
        'elevated': elevated,
        'spaceUnit': spaceUnit,
        'screenPaddingScale': screenPaddingScale,
        'cardPaddingScale': cardPaddingScale,
        'sectionGapScale': sectionGapScale,
        'animationsEnabled': animationsEnabled,
        'radarRotationEnabled': radarRotationEnabled,
        'livePulseEnabled': livePulseEnabled,
        'showTopoContours': showTopoContours,
        'radarPeriodMs': radarPeriodMs,
        'motionFastMs': motionFastMs,
        'motionMediumMs': motionMediumMs,
        'copy': copy.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is OutdoorCustomConfig &&
      other.palettePreset == palettePreset &&
      other.canvasArgb == canvasArgb &&
      other.surfaceArgb == surfaceArgb &&
      other.accentArgb == accentArgb &&
      other.highlightArgb == highlightArgb &&
      other.heroBaseArgb == heroBaseArgb &&
      other.positiveArgb == positiveArgb &&
      other.warningArgb == warningArgb &&
      other.criticalArgb == criticalArgb &&
      other.displayFamily == displayFamily &&
      other.bodyFamily == bodyFamily &&
      other.dataFamily == dataFamily &&
      other.fontScale == fontScale &&
      other.displayBold == displayBold &&
      other.uppercaseLabels == uppercaseLabels &&
      other.radiusSmall == radiusSmall &&
      other.radiusMedium == radiusMedium &&
      other.radiusLarge == radiusLarge &&
      other.borderWidth == borderWidth &&
      other.minTouchTarget == minTouchTarget &&
      other.avatarSize == avatarSize &&
      other.iconScale == iconScale &&
      other.radarScopeScale == radarScopeScale &&
      other.elevated == elevated &&
      other.spaceUnit == spaceUnit &&
      other.screenPaddingScale == screenPaddingScale &&
      other.cardPaddingScale == cardPaddingScale &&
      other.sectionGapScale == sectionGapScale &&
      other.animationsEnabled == animationsEnabled &&
      other.radarRotationEnabled == radarRotationEnabled &&
      other.livePulseEnabled == livePulseEnabled &&
      other.showTopoContours == showTopoContours &&
      other.radarPeriodMs == radarPeriodMs &&
      other.motionFastMs == motionFastMs &&
      other.motionMediumMs == motionMediumMs &&
      other.copy == copy;

  @override
  int get hashCode => Object.hashAll([
        palettePreset,
        canvasArgb,
        surfaceArgb,
        accentArgb,
        highlightArgb,
        heroBaseArgb,
        positiveArgb,
        warningArgb,
        criticalArgb,
        displayFamily,
        bodyFamily,
        dataFamily,
        fontScale,
        displayBold,
        uppercaseLabels,
        radiusSmall,
        radiusMedium,
        radiusLarge,
        borderWidth,
        minTouchTarget,
        avatarSize,
        iconScale,
        radarScopeScale,
        elevated,
        spaceUnit,
        screenPaddingScale,
        cardPaddingScale,
        sectionGapScale,
        animationsEnabled,
        radarRotationEnabled,
        livePulseEnabled,
        showTopoContours,
        radarPeriodMs,
        motionFastMs,
        motionMediumMs,
        copy,
      ]);
}
