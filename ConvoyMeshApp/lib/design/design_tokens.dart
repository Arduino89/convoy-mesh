import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'outdoor_copy.dart';

/// Supported UI modes.
///
/// The chosen visual direction is [outdoorPremium]. [classic] preserves the
/// pre-redesign Material 3 UI (`LAB +15`) so testers can switch back anytime.
/// Previous exploratory variants (Tactical Explorer, Minimal Adventure) are
/// preserved untouched in GitHub checkpoint `5dbdedf`.
enum DesignDirection { classic, outdoorPremium }

extension DesignDirectionLabels on DesignDirection {
  String get label => switch (this) {
        DesignDirection.classic => 'Originale (LAB +15)',
        DesignDirection.outdoorPremium => 'Outdoor Premium',
      };

  String get tagline => switch (this) {
        DesignDirection.classic => 'Interfaccia diagnostica classica',
        DesignDirection.outdoorPremium =>
          'Carta calda, pino alpino e curve di livello personalizzabili',
      };

  /// Stable storage id (never localised).
  String get storageId => name;
}

/// Single source of truth for every customisable visual value across
/// Convoy Mesh when **Outdoor Premium** is active.
///
/// Built by `DesignPresets.buildOutdoor(OutdoorCustomConfig)` from user/team
/// customisation settings so colours, typography, dimensions, spacing,
/// animations and visual copy remain completely separate from business logic.
@immutable
class ConvoyDesignTokens extends ThemeExtension<ConvoyDesignTokens> {
  const ConvoyDesignTokens({
    required this.direction,
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.outline,
    required this.ink,
    required this.inkMuted,
    Color? inkOnCanvas,
    Color? inkMutedOnCanvas,
    required this.accent,
    required this.onAccent,
    required this.highlight,
    required this.positive,
    required this.warning,
    required this.critical,
    Color? onCritical,
    required this.heroBackground,
    required this.heroInk,
    Color? heroOfflineInk,
    required this.radarGrid,
    required this.radarSweep,
    required this.displayFamily,
    required this.bodyFamily,
    required this.dataFamily,
    required this.displayWeight,
    required this.displayLetterSpacing,
    required this.labelLetterSpacing,
    required this.fontScale,
    required this.uppercaseLabels,
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.borderWidth,
    required this.spaceUnit,
    required this.screenPaddingScale,
    required this.cardPaddingScale,
    required this.sectionGapScale,
    required this.minTouchTarget,
    required this.avatarSize,
    required this.iconScale,
    required this.radarScopeScale,
    required this.elevated,
    required this.animationsEnabled,
    required this.radarRotationEnabled,
    required this.livePulseEnabled,
    required this.showTopoContours,
    required this.motionFast,
    required this.motionMedium,
    required this.radarPeriod,
    required this.motionCurve,
    this.copy = OutdoorCopyTokens.defaults,
  })  : inkOnCanvas = inkOnCanvas ?? ink,
        inkMutedOnCanvas = inkMutedOnCanvas ?? inkMuted,
        onCritical = onCritical ?? Colors.white,
        heroOfflineInk = heroOfflineInk ?? const Color(0xFFF3CA7E);

  final DesignDirection direction;
  final Brightness brightness;

  // ── 1. Palette ─────────────────────────────────────────────────────────
  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color outline;
  final Color ink;
  final Color inkMuted;

  /// Foreground ink guaranteed to contrast with [canvas] even when [canvas]
  /// and [surface] have opposite luminance.
  final Color inkOnCanvas;
  final Color inkMutedOnCanvas;
  final Color accent;
  final Color onAccent;
  final Color highlight;
  final Color positive;
  final Color warning;
  final Color critical;

  /// Foreground ink guaranteed to contrast with [critical] fills.
  final Color onCritical;
  final Gradient heroBackground;
  final Color heroInk;

  /// High-contrast offline peer label ink over [heroBackground].
  final Color heroOfflineInk;
  final Color radarGrid;
  final Color radarSweep;

  // ── 2. Typography ──────────────────────────────────────────────────────
  final String? displayFamily;
  final String? bodyFamily;
  final String? dataFamily;
  final FontWeight displayWeight;
  final double displayLetterSpacing;
  final double labelLetterSpacing;
  final double fontScale;
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

  // ── 5. Motion ──────────────────────────────────────────────────────────
  final bool animationsEnabled;
  final bool radarRotationEnabled;
  final bool livePulseEnabled;
  final bool showTopoContours;
  final Duration motionFast;
  final Duration motionMedium;
  final Duration radarPeriod;
  final Curve motionCurve;

  // ── 6. Copy ────────────────────────────────────────────────────────────
  final OutdoorCopyTokens copy;

  double space(double multiplier) => spaceUnit * multiplier;
  double get hPad => space(4.5) * screenPaddingScale;
  double get cardPad => space(4) * cardPaddingScale;
  double get sectionTop => space(5.5) * sectionGapScale;
  double iconSize(double base) => (base * iconScale).clamp(12.0, 48.0);
  double sp(double base) => base * fontScale;

  Duration get effectiveMotionFast =>
      animationsEnabled ? motionFast : Duration.zero;
  Duration get effectiveMotionMedium =>
      animationsEnabled ? motionMedium : Duration.zero;
  bool get shouldRotateRadar => animationsEnabled && radarRotationEnabled;
  bool get shouldPulseLive => animationsEnabled && livePulseEnabled;

  String label(String text) => uppercaseLabels ? text.toUpperCase() : text;

  /// Maps requested weights onto the exact weights bundled in `assets/fonts/`
  /// (`Manrope`: 400/600/800, `Fraunces` & `JetBrainsMono`: 500/700) so Android
  /// never falls back to inconsistent synthetic font synthesis.
  static FontWeight resolveWeight(String? family, FontWeight requested) {
    if (family == 'Manrope') {
      if (requested.value <= 450) return FontWeight.w400;
      if (requested.value <= 650) return FontWeight.w600;
      return FontWeight.w800;
    }
    if (family == 'Fraunces' || family == 'JetBrainsMono') {
      return requested.value <= 550 ? FontWeight.w500 : FontWeight.w700;
    }
    return requested;
  }

  TextStyle display(double size, {Color? color}) => TextStyle(
        fontFamily: displayFamily,
        fontSize: sp(size),
        fontWeight: resolveWeight(displayFamily, displayWeight),
        letterSpacing: displayLetterSpacing,
        height: 1.10,
        color: color ?? ink,
      );

  TextStyle body(double size, {Color? color, FontWeight? weight}) => TextStyle(
        fontFamily: bodyFamily,
        fontSize: sp(size),
        fontWeight: resolveWeight(bodyFamily, weight ?? FontWeight.w400),
        height: 1.38,
        color: color ?? ink,
      );

  TextStyle caption({Color? color, double? size}) {
    final fam = dataFamily ?? bodyFamily;
    return TextStyle(
      fontFamily: fam,
      fontSize: sp(size ?? 11.5),
      fontWeight: resolveWeight(fam, FontWeight.w600),
      letterSpacing: labelLetterSpacing,
      color: color ?? inkMuted,
    );
  }

  TextStyle data(double size, {Color? color, FontWeight? weight}) {
    final fam = dataFamily ?? bodyFamily;
    return TextStyle(
      fontFamily: fam,
      fontSize: sp(size),
      fontWeight: resolveWeight(fam, weight ?? FontWeight.w700),
      fontFeatures: const [FontFeature.tabularFigures()],
      color: color ?? ink,
    );
  }

  /// Shadows always use dark alpha (never [ink], which becomes cream in dark
  /// mode and would otherwise produce milky halos).
  List<BoxShadow> get shadow => elevated
      ? [
          BoxShadow(
            color: Colors.black
                .withValues(alpha: brightness == Brightness.dark ? 0.38 : 0.08),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black
                .withValues(alpha: brightness == Brightness.dark ? 0.22 : 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ]
      : const [];

  static ConvoyDesignTokens? maybeOf(BuildContext context) =>
      Theme.of(context).extension<ConvoyDesignTokens>();

  @override
  ConvoyDesignTokens copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? outline,
    Color? ink,
    Color? inkMuted,
    Color? inkOnCanvas,
    Color? inkMutedOnCanvas,
    Color? accent,
    Color? onAccent,
    Color? highlight,
    Color? positive,
    Color? warning,
    Color? critical,
    Color? onCritical,
    Gradient? heroBackground,
    Color? heroInk,
    Color? heroOfflineInk,
    Color? radarGrid,
    Color? radarSweep,
    String? displayFamily,
    String? bodyFamily,
    String? dataFamily,
    FontWeight? displayWeight,
    double? displayLetterSpacing,
    double? labelLetterSpacing,
    double? fontScale,
    bool? uppercaseLabels,
    double? radiusSmall,
    double? radiusMedium,
    double? radiusLarge,
    double? borderWidth,
    double? spaceUnit,
    double? screenPaddingScale,
    double? cardPaddingScale,
    double? sectionGapScale,
    double? minTouchTarget,
    double? avatarSize,
    double? iconScale,
    double? radarScopeScale,
    bool? elevated,
    bool? animationsEnabled,
    bool? radarRotationEnabled,
    bool? livePulseEnabled,
    bool? showTopoContours,
    Duration? motionFast,
    Duration? motionMedium,
    Duration? radarPeriod,
    Curve? motionCurve,
    OutdoorCopyTokens? copy,
  }) =>
      ConvoyDesignTokens(
        direction: direction,
        brightness: brightness,
        canvas: canvas ?? this.canvas,
        surface: surface ?? this.surface,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        outline: outline ?? this.outline,
        ink: ink ?? this.ink,
        inkMuted: inkMuted ?? this.inkMuted,
        inkOnCanvas: inkOnCanvas ?? this.inkOnCanvas,
        inkMutedOnCanvas: inkMutedOnCanvas ?? this.inkMutedOnCanvas,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        highlight: highlight ?? this.highlight,
        positive: positive ?? this.positive,
        warning: warning ?? this.warning,
        critical: critical ?? this.critical,
        onCritical: onCritical ?? this.onCritical,
        heroBackground: heroBackground ?? this.heroBackground,
        heroInk: heroInk ?? this.heroInk,
        heroOfflineInk: heroOfflineInk ?? this.heroOfflineInk,
        radarGrid: radarGrid ?? this.radarGrid,
        radarSweep: radarSweep ?? this.radarSweep,
        displayFamily: displayFamily ?? this.displayFamily,
        bodyFamily: bodyFamily ?? this.bodyFamily,
        dataFamily: dataFamily ?? this.dataFamily,
        displayWeight: displayWeight ?? this.displayWeight,
        displayLetterSpacing:
            displayLetterSpacing ?? this.displayLetterSpacing,
        labelLetterSpacing: labelLetterSpacing ?? this.labelLetterSpacing,
        fontScale: fontScale ?? this.fontScale,
        uppercaseLabels: uppercaseLabels ?? this.uppercaseLabels,
        radiusSmall: radiusSmall ?? this.radiusSmall,
        radiusMedium: radiusMedium ?? this.radiusMedium,
        radiusLarge: radiusLarge ?? this.radiusLarge,
        borderWidth: borderWidth ?? this.borderWidth,
        spaceUnit: spaceUnit ?? this.spaceUnit,
        screenPaddingScale: screenPaddingScale ?? this.screenPaddingScale,
        cardPaddingScale: cardPaddingScale ?? this.cardPaddingScale,
        sectionGapScale: sectionGapScale ?? this.sectionGapScale,
        minTouchTarget: minTouchTarget ?? this.minTouchTarget,
        avatarSize: avatarSize ?? this.avatarSize,
        iconScale: iconScale ?? this.iconScale,
        radarScopeScale: radarScopeScale ?? this.radarScopeScale,
        elevated: elevated ?? this.elevated,
        animationsEnabled: animationsEnabled ?? this.animationsEnabled,
        radarRotationEnabled:
            radarRotationEnabled ?? this.radarRotationEnabled,
        livePulseEnabled: livePulseEnabled ?? this.livePulseEnabled,
        showTopoContours: showTopoContours ?? this.showTopoContours,
        motionFast: motionFast ?? this.motionFast,
        motionMedium: motionMedium ?? this.motionMedium,
        radarPeriod: radarPeriod ?? this.radarPeriod,
        motionCurve: motionCurve ?? this.motionCurve,
        copy: copy ?? this.copy,
      );

  @override
  ConvoyDesignTokens lerp(covariant ConvoyDesignTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    double d(double a, double b) => lerpDouble(a, b, t)!;
    final discrete = t < 0.5 ? this : other;
    return ConvoyDesignTokens(
      direction: discrete.direction,
      brightness: discrete.brightness,
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surfaceRaised: c(surfaceRaised, other.surfaceRaised),
      outline: c(outline, other.outline),
      ink: c(ink, other.ink),
      inkMuted: c(inkMuted, other.inkMuted),
      inkOnCanvas: c(inkOnCanvas, other.inkOnCanvas),
      inkMutedOnCanvas: c(inkMutedOnCanvas, other.inkMutedOnCanvas),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      highlight: c(highlight, other.highlight),
      positive: c(positive, other.positive),
      warning: c(warning, other.warning),
      critical: c(critical, other.critical),
      onCritical: c(onCritical, other.onCritical),
      heroBackground: Gradient.lerp(heroBackground, other.heroBackground, t)!,
      heroInk: c(heroInk, other.heroInk),
      heroOfflineInk: c(heroOfflineInk, other.heroOfflineInk),
      radarGrid: c(radarGrid, other.radarGrid),
      radarSweep: c(radarSweep, other.radarSweep),
      displayFamily: discrete.displayFamily,
      bodyFamily: discrete.bodyFamily,
      dataFamily: discrete.dataFamily,
      displayWeight: FontWeight.lerp(displayWeight, other.displayWeight, t)!,
      displayLetterSpacing:
          d(displayLetterSpacing, other.displayLetterSpacing),
      labelLetterSpacing: d(labelLetterSpacing, other.labelLetterSpacing),
      fontScale: d(fontScale, other.fontScale),
      uppercaseLabels: discrete.uppercaseLabels,
      radiusSmall: d(radiusSmall, other.radiusSmall),
      radiusMedium: d(radiusMedium, other.radiusMedium),
      radiusLarge: d(radiusLarge, other.radiusLarge),
      borderWidth: d(borderWidth, other.borderWidth),
      spaceUnit: d(spaceUnit, other.spaceUnit),
      screenPaddingScale: d(screenPaddingScale, other.screenPaddingScale),
      cardPaddingScale: d(cardPaddingScale, other.cardPaddingScale),
      sectionGapScale: d(sectionGapScale, other.sectionGapScale),
      minTouchTarget: d(minTouchTarget, other.minTouchTarget),
      avatarSize: d(avatarSize, other.avatarSize),
      iconScale: d(iconScale, other.iconScale),
      radarScopeScale: d(radarScopeScale, other.radarScopeScale),
      elevated: discrete.elevated,
      animationsEnabled: discrete.animationsEnabled,
      radarRotationEnabled: discrete.radarRotationEnabled,
      livePulseEnabled: discrete.livePulseEnabled,
      showTopoContours: discrete.showTopoContours,
      motionFast: discrete.motionFast,
      motionMedium: discrete.motionMedium,
      radarPeriod: discrete.radarPeriod,
      motionCurve: discrete.motionCurve,
      copy: discrete.copy,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConvoyDesignTokens &&
          other.direction == direction &&
          other.brightness == brightness &&
          other.canvas == canvas &&
          other.surface == surface &&
          other.surfaceRaised == surfaceRaised &&
          other.outline == outline &&
          other.ink == ink &&
          other.inkMuted == inkMuted &&
          other.inkOnCanvas == inkOnCanvas &&
          other.inkMutedOnCanvas == inkMutedOnCanvas &&
          other.accent == accent &&
          other.onAccent == onAccent &&
          other.highlight == highlight &&
          other.positive == positive &&
          other.warning == warning &&
          other.critical == critical &&
          other.onCritical == onCritical &&
          other.heroBackground == heroBackground &&
          other.heroInk == heroInk &&
          other.heroOfflineInk == heroOfflineInk &&
          other.radarGrid == radarGrid &&
          other.radarSweep == radarSweep &&
          other.displayFamily == displayFamily &&
          other.bodyFamily == bodyFamily &&
          other.dataFamily == dataFamily &&
          other.displayWeight == displayWeight &&
          other.displayLetterSpacing == displayLetterSpacing &&
          other.labelLetterSpacing == labelLetterSpacing &&
          other.fontScale == fontScale &&
          other.uppercaseLabels == uppercaseLabels &&
          other.radiusSmall == radiusSmall &&
          other.radiusMedium == radiusMedium &&
          other.radiusLarge == radiusLarge &&
          other.borderWidth == borderWidth &&
          other.spaceUnit == spaceUnit &&
          other.screenPaddingScale == screenPaddingScale &&
          other.cardPaddingScale == cardPaddingScale &&
          other.sectionGapScale == sectionGapScale &&
          other.minTouchTarget == minTouchTarget &&
          other.avatarSize == avatarSize &&
          other.iconScale == iconScale &&
          other.radarScopeScale == radarScopeScale &&
          other.elevated == elevated &&
          other.animationsEnabled == animationsEnabled &&
          other.radarRotationEnabled == radarRotationEnabled &&
          other.livePulseEnabled == livePulseEnabled &&
          other.showTopoContours == showTopoContours &&
          other.motionFast == motionFast &&
          other.motionMedium == motionMedium &&
          other.radarPeriod == radarPeriod &&
          other.motionCurve == motionCurve &&
          other.copy == copy);

  @override
  int get hashCode => Object.hashAll([
        direction,
        brightness,
        canvas,
        surface,
        surfaceRaised,
        outline,
        ink,
        inkMuted,
        inkOnCanvas,
        inkMutedOnCanvas,
        accent,
        onAccent,
        highlight,
        positive,
        warning,
        critical,
        onCritical,
        heroBackground,
        heroInk,
        heroOfflineInk,
        radarGrid,
        radarSweep,
        displayFamily,
        bodyFamily,
        dataFamily,
        displayWeight,
        displayLetterSpacing,
        labelLetterSpacing,
        fontScale,
        uppercaseLabels,
        radiusSmall,
        radiusMedium,
        radiusLarge,
        borderWidth,
        spaceUnit,
        screenPaddingScale,
        cardPaddingScale,
        sectionGapScale,
        minTouchTarget,
        avatarSize,
        iconScale,
        radarScopeScale,
        elevated,
        animationsEnabled,
        radarRotationEnabled,
        livePulseEnabled,
        showTopoContours,
        motionFast,
        motionMedium,
        radarPeriod,
        motionCurve,
        copy,
      ]);
}
