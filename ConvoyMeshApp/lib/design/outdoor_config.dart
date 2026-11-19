import 'dart:convert';

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
        OutdoorPalettePreset.crestaAlba =>
          'Pietra chiara ad altissimo contrasto solare',
        OutdoorPalettePreset.terraERame => 'Sentiero roccia, argilla e muschio',
        OutdoorPalettePreset.abeteNotturno =>
          'Crepuscolo nel bosco, abete scuro',
      };

  /// Default border thickness for this preset when not explicitly overridden.
  double get defaultBorderWidth => switch (this) {
        OutdoorPalettePreset.crestaAlba => 1.2,
        OutdoorPalettePreset.pinoECarta ||
        OutdoorPalettePreset.terraERame ||
        OutdoorPalettePreset.abeteNotturno =>
          1.0,
      };

  /// Default card elevation toggle for this preset when not explicitly overridden.
  bool get defaultElevated => switch (this) {
        OutdoorPalettePreset.abeteNotturno => false,
        OutdoorPalettePreset.pinoECarta ||
        OutdoorPalettePreset.crestaAlba ||
        OutdoorPalettePreset.terraERame =>
          true,
      };
}

/// Typed result for validated JSON configuration imports in Outdoor Studio.
@immutable
class OutdoorConfigImportResult {
  const OutdoorConfigImportResult.ok(this.config) : error = null;
  const OutdoorConfigImportResult.error(this.error) : config = null;

  final OutdoorCustomConfig? config;
  final String? error;

  bool get isOk => config != null && error == null;
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
    this.borderWidth,
    this.minTouchTarget = 52,
    this.avatarSize = 48,
    this.iconScale = 1.0,
    this.radarScopeScale = 0.90,
    this.elevated,
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

  static const int maxImportJsonBytes = 16384;

  static const _knownJsonKeys = <String>{
    'palettePreset',
    'canvasArgb',
    'surfaceArgb',
    'accentArgb',
    'highlightArgb',
    'heroBaseArgb',
    'positiveArgb',
    'warningArgb',
    'criticalArgb',
    'displayFamily',
    'bodyFamily',
    'dataFamily',
    'fontScale',
    'displayBold',
    'uppercaseLabels',
    'radiusSmall',
    'radiusMedium',
    'radiusLarge',
    'borderWidth',
    'minTouchTarget',
    'avatarSize',
    'iconScale',
    'radarScopeScale',
    'elevated',
    'spaceUnit',
    'screenPaddingScale',
    'cardPaddingScale',
    'sectionGapScale',
    'animationsEnabled',
    'radarRotationEnabled',
    'livePulseEnabled',
    'showTopoContours',
    'radarPeriodMs',
    'motionFastMs',
    'motionMediumMs',
    'copy',
  };

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

  /// Optional explicit override; `null` inherits [palettePreset.defaultBorderWidth].
  final double? borderWidth;
  final double minTouchTarget;
  final double avatarSize;
  final double iconScale;
  final double radarScopeScale;

  /// Optional explicit override; `null` inherits [palettePreset.defaultElevated].
  final bool? elevated;

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

  /// Effective border width respecting the active preset default.
  double get effectiveBorderWidth =>
      (borderWidth ?? palettePreset.defaultBorderWidth)
          .clamp(0.8, 2.5)
          .toDouble();

  /// Effective elevation toggle respecting the active preset default.
  bool get effectiveElevated => elevated ?? palettePreset.defaultElevated;

  /// Forces opaque alpha (`0xFF......`) so translucent/invisible custom ARGB
  /// values can never break outdoor contrast.
  static int? sanitizeOpaqueArgb(int? value) =>
      value == null ? null : ((value & 0x00FFFFFF) | 0xFF000000);

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
    Object? borderWidth = _keep,
    double? minTouchTarget,
    double? avatarSize,
    double? iconScale,
    double? radarScopeScale,
    Object? elevated = _keep,
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
  }) {
    var rs = (radiusSmall ?? this.radiusSmall).clamp(4.0, 20.0).toDouble();
    var rm = (radiusMedium ?? this.radiusMedium).clamp(8.0, 30.0).toDouble();
    var rl = (radiusLarge ?? this.radiusLarge).clamp(12.0, 38.0).toDouble();
    if (radiusSmall != null && radiusMedium == null && radiusLarge == null) {
      if (rm < rs) rm = rs;
      if (rl < rm) rl = rm;
    } else if (radiusLarge != null &&
        radiusMedium == null &&
        radiusSmall == null) {
      if (rm > rl) rm = rl;
      if (rs > rm) rs = rm;
    } else {
      if (rm < rs) rs = rm;
      if (rl < rm) rl = rm;
    }

    var mf = (motionFastMs ?? this.motionFastMs).clamp(80, 450).toInt();
    var mm = (motionMediumMs ?? this.motionMediumMs).clamp(140, 750).toInt();
    if (motionFastMs != null && motionMediumMs == null) {
      if (mm < mf) mm = mf;
    } else if (mm < mf) {
      mf = mm;
    }

    final resolvedBorderWidth = identical(borderWidth, _keep)
        ? this.borderWidth
        : (borderWidth as double?)?.clamp(0.8, 2.5).toDouble();
    final resolvedElevated =
        identical(elevated, _keep) ? this.elevated : elevated as bool?;

    return OutdoorCustomConfig(
      palettePreset: palettePreset ?? this.palettePreset,
      canvasArgb: sanitizeOpaqueArgb(
          identical(canvasArgb, _keep) ? this.canvasArgb : canvasArgb as int?),
      surfaceArgb: sanitizeOpaqueArgb(identical(surfaceArgb, _keep)
          ? this.surfaceArgb
          : surfaceArgb as int?),
      accentArgb: sanitizeOpaqueArgb(
          identical(accentArgb, _keep) ? this.accentArgb : accentArgb as int?),
      highlightArgb: sanitizeOpaqueArgb(identical(highlightArgb, _keep)
          ? this.highlightArgb
          : highlightArgb as int?),
      heroBaseArgb: sanitizeOpaqueArgb(identical(heroBaseArgb, _keep)
          ? this.heroBaseArgb
          : heroBaseArgb as int?),
      positiveArgb: sanitizeOpaqueArgb(identical(positiveArgb, _keep)
          ? this.positiveArgb
          : positiveArgb as int?),
      warningArgb: sanitizeOpaqueArgb(identical(warningArgb, _keep)
          ? this.warningArgb
          : warningArgb as int?),
      criticalArgb: sanitizeOpaqueArgb(identical(criticalArgb, _keep)
          ? this.criticalArgb
          : criticalArgb as int?),
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
      radiusSmall: rs,
      radiusMedium: rm,
      radiusLarge: rl,
      borderWidth: resolvedBorderWidth,
      minTouchTarget:
          (minTouchTarget ?? this.minTouchTarget).clamp(48.0, 64.0).toDouble(),
      avatarSize: (avatarSize ?? this.avatarSize).clamp(38.0, 60.0).toDouble(),
      iconScale: (iconScale ?? this.iconScale).clamp(0.85, 1.25).toDouble(),
      radarScopeScale:
          (radarScopeScale ?? this.radarScopeScale).clamp(0.75, 1.0).toDouble(),
      elevated: resolvedElevated,
      spaceUnit: (spaceUnit ?? this.spaceUnit).clamp(3.0, 5.5).toDouble(),
      screenPaddingScale: (screenPaddingScale ?? this.screenPaddingScale)
          .clamp(0.8, 1.35)
          .toDouble(),
      cardPaddingScale: (cardPaddingScale ?? this.cardPaddingScale)
          .clamp(0.8, 1.35)
          .toDouble(),
      sectionGapScale:
          (sectionGapScale ?? this.sectionGapScale).clamp(0.8, 1.4).toDouble(),
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      radarRotationEnabled: radarRotationEnabled ?? this.radarRotationEnabled,
      livePulseEnabled: livePulseEnabled ?? this.livePulseEnabled,
      showTopoContours: showTopoContours ?? this.showTopoContours,
      radarPeriodMs:
          (radarPeriodMs ?? this.radarPeriodMs).clamp(2400, 9500).toInt(),
      motionFastMs: mf,
      motionMediumMs: mm,
      copy: copy ?? this.copy,
    );
  }

  /// Clears per-color, border, and elevation overrides so the chosen preset's
  /// complete visual personality applies cleanly while keeping typography,
  /// spacing, sizing, motion, and visual copy.
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
        borderWidth: null,
        elevated: null,
      );

  static double _num(Map<String, dynamic> m, String k, double fallback,
      double min, double max) {
    final v = m[k];
    if (v is num && v.isFinite) return v.toDouble().clamp(min, max).toDouble();
    return fallback;
  }

  static double? _optionalNum(
      Map<String, dynamic> m, String k, double min, double max) {
    final v = m[k];
    if (v is num && v.isFinite) return v.toDouble().clamp(min, max).toDouble();
    return null;
  }

  static int _int(
      Map<String, dynamic> m, String k, int fallback, int min, int max) {
    final v = m[k];
    if (v is num && v.isFinite) return v.round().clamp(min, max);
    return fallback;
  }

  static int? _argb(Map<String, dynamic> m, String k) {
    final v = m[k];
    return v is int ? sanitizeOpaqueArgb(v) : null;
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

  static bool? _optionalFlag(Map<String, dynamic> m, String k) {
    final v = m[k];
    return v is bool ? v : null;
  }

  /// Safely validates and parses an exported Outdoor Studio JSON string.
  /// Never throws; returns a human-readable Italian error when invalid.
  static OutdoorConfigImportResult tryParseJsonString(
    String raw, {
    int maxBytes = maxImportJsonBytes,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const OutdoorConfigImportResult.error(
        'Incolla prima un blocco JSON di configurazione.',
      );
    }
    if (utf8.encode(trimmed).length > maxBytes) {
      return OutdoorConfigImportResult.error(
        'Configurazione troppo grande (limite $maxBytes byte).',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      return const OutdoorConfigImportResult.error(
        'JSON non valido: controlla parentesi, virgolette e virgole.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      return const OutdoorConfigImportResult.error(
        'Il JSON deve contenere un oggetto di configurazione { ... }.',
      );
    }
    final hasKnownKey = decoded.keys.any(_knownJsonKeys.contains);
    if (!hasKnownKey) {
      return const OutdoorConfigImportResult.error(
        'Nessun parametro Outdoor riconosciuto nel JSON incollato.',
      );
    }
    return OutdoorConfigImportResult.ok(OutdoorCustomConfig.fromJson(decoded));
  }

  factory OutdoorCustomConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    final presetName = json['palettePreset'];
    final preset = OutdoorPalettePreset.values.firstWhere(
      (p) => p.name == presetName,
      orElse: () => OutdoorPalettePreset.pinoECarta,
    );
    final rs = _num(json, 'radiusSmall', 12, 4, 20);
    var rm = _num(json, 'radiusMedium', 20, 8, 30);
    var rl = _num(json, 'radiusLarge', 30, 12, 38);
    if (rm < rs) rm = rs;
    if (rl < rm) rl = rm;

    final mf = _int(json, 'motionFastMs', 220, 80, 450);
    var mm = _int(json, 'motionMediumMs', 420, 140, 750);
    if (mm < mf) mm = mf;

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
      radiusSmall: rs,
      radiusMedium: rm,
      radiusLarge: rl,
      borderWidth: _optionalNum(json, 'borderWidth', 0.8, 2.5),
      minTouchTarget: _num(json, 'minTouchTarget', 52, 48, 64),
      avatarSize: _num(json, 'avatarSize', 48, 38, 60),
      iconScale: _num(json, 'iconScale', 1.0, 0.85, 1.25),
      radarScopeScale: _num(json, 'radarScopeScale', 0.90, 0.75, 1.0),
      elevated: _optionalFlag(json, 'elevated'),
      spaceUnit: _num(json, 'spaceUnit', 4.0, 3.0, 5.5),
      screenPaddingScale: _num(json, 'screenPaddingScale', 1.0, 0.8, 1.35),
      cardPaddingScale: _num(json, 'cardPaddingScale', 1.0, 0.8, 1.35),
      sectionGapScale: _num(json, 'sectionGapScale', 1.0, 0.8, 1.4),
      animationsEnabled: _flag(json, 'animationsEnabled', true),
      radarRotationEnabled: _flag(json, 'radarRotationEnabled', true),
      livePulseEnabled: _flag(json, 'livePulseEnabled', true),
      showTopoContours: _flag(json, 'showTopoContours', true),
      radarPeriodMs: _int(json, 'radarPeriodMs', 5200, 2400, 9500),
      motionFastMs: mf,
      motionMediumMs: mm,
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
        if (borderWidth != null) 'borderWidth': borderWidth,
        'minTouchTarget': minTouchTarget,
        'avatarSize': avatarSize,
        'iconScale': iconScale,
        'radarScopeScale': radarScopeScale,
        if (elevated != null) 'elevated': elevated,
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
