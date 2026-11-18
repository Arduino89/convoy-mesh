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
    required this.accent,
    required this.onAccent,
    required this.highlight,
    required this.positive,
    required this.warning,
    required this.critical,
    required this.heroBackground,
    required this.heroInk,
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
  });

  final DesignDirection direction;
  final Brightness brightness;

  // ── 1. Palette ─────────────────────────────────────────────────────────
  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color outline;
  final Color ink;
  final Color inkMuted;
  final Color accent;
  final Color onAccent;
  final Color highlight;
  final Color positive;
  final Color warning;
  final Color critical;
  final Gradient heroBackground;
  final Color heroInk;
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

  TextStyle display(double size, {Color? color}) => TextStyle(
        fontFamily: displayFamily,
        fontSize: sp(size),
        fontWeight: displayWeight,
        letterSpacing: displayLetterSpacing,
        height: 1.10,
        color: color ?? ink,
      );

  TextStyle body(double size, {Color? color, FontWeight? weight}) => TextStyle(
        fontFamily: bodyFamily,
        fontSize: sp(size),
        fontWeight: weight ?? FontWeight.w400,
        height: 1.38,
        color: color ?? ink,
      );

  TextStyle caption({Color? color, double? size}) => TextStyle(
        fontFamily: dataFamily ?? bodyFamily,
        fontSize: sp(size ?? 11.5),
        fontWeight: FontWeight.w600,
        letterSpacing: labelLetterSpacing,
        color: color ?? inkMuted,
      );

  TextStyle data(double size, {Color? color, FontWeight? weight}) => TextStyle(
        fontFamily: dataFamily ?? bodyFamily,
        fontSize: sp(size),
        fontWeight: weight ?? FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color ?? ink,
      );

  List<BoxShadow> get shadow => elevated
      ? [
          BoxShadow(
            color: ink.withValues(
                alpha: brightness == Brightness.dark ? 0.45 : 0.07),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: ink.withValues(
                alpha: brightness == Brightness.dark ? 0.25 : 0.03),
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
    Color? accent,
    Color? onAccent,
    Color? highlight,
    Color? positive,
    Color? warning,
    Color? critical,
    Gradient? heroBackground,
    Color? heroInk,
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
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        highlight: highlight ?? this.highlight,
        positive: positive ?? this.positive,
        warning: warning ?? this.warning,
        critical: critical ?? this.critical,
        heroBackground: heroBackground ?? this.heroBackground,
        heroInk: heroInk ?? this.heroInk,
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
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      highlight: c(highlight, other.highlight),
      positive: c(positive, other.positive),
      warning: c(warning, other.warning),
      critical: c(critical, other.critical),
      heroBackground: Gradient.lerp(heroBackground, other.heroBackground, t)!,
      heroInk: c(heroInk, other.heroInk),
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
}
