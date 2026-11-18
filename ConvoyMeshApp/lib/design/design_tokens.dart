import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Visual directions explored by the Frontend Design Studio.
///
/// [classic] is the original, unmodified Convoy Mesh look and remains the
/// default: selecting it renders exactly the pre-existing widgets.
enum DesignDirection { classic, outdoorPremium, tacticalExplorer, minimalAdventure }

extension DesignDirectionLabels on DesignDirection {
  String get label => switch (this) {
        DesignDirection.classic => 'Originale',
        DesignDirection.outdoorPremium => 'Outdoor Premium',
        DesignDirection.tacticalExplorer => 'Tactical Explorer',
        DesignDirection.minimalAdventure => 'Minimal Adventure',
      };

  String get tagline => switch (this) {
        DesignDirection.classic => 'Interfaccia attuale (LAB +15)',
        DesignDirection.outdoorPremium => 'Carta, pino e curve di livello',
        DesignDirection.tacticalExplorer => 'HUD notturno, dati in monospazio',
        DesignDirection.minimalAdventure => 'Bianco, nero e arancio sicurezza',
      };

  /// Stable storage id (never localised).
  String get storageId => name;
}

/// How the radar hero is drawn. Purely decorative; it never changes which
/// peers are shown or how their state is computed.
enum RadarScopeStyle {
  /// Irregular topographic contour rings with a soft rotating light.
  contour,

  /// Rotating sweep wedge with bezel ticks and blip afterglow.
  sweep,

  /// Thin concentric rings with outward pulse waves (tester-chosen #4 motif).
  pulse,
}

/// Layout composition of the redesigned Radar screen.
enum RadarLayoutStyle { heroCard, hud, editorial }

/// Single source of truth for every customisable visual value.
///
/// Changing a preset in `design_presets.dart` (or calling [copyWith]) is the
/// only step needed to restyle colours, type, shapes, spacing and motion.
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
    required this.uppercaseLabels,
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.borderWidth,
    required this.spaceUnit,
    required this.minTouchTarget,
    required this.elevated,
    required this.motionFast,
    required this.motionMedium,
    required this.radarPeriod,
    required this.motionCurve,
    required this.radarStyle,
    required this.layoutStyle,
  });

  final DesignDirection direction;
  final Brightness brightness;

  // ── Palette ────────────────────────────────────────────────────────────
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

  // ── Typography ─────────────────────────────────────────────────────────
  /// Bundled font family names (see pubspec `fonts:`). Null = platform font.
  final String? displayFamily;
  final String? bodyFamily;
  final String? dataFamily;
  final FontWeight displayWeight;
  final double displayLetterSpacing;
  final double labelLetterSpacing;
  final bool uppercaseLabels;

  // ── Shape & spacing ────────────────────────────────────────────────────
  final double radiusSmall;
  final double radiusMedium;
  final double radiusLarge;
  final double borderWidth;
  final double spaceUnit;

  /// Minimum interactive height; outdoor presets use ≥ 52 dp for gloves.
  final double minTouchTarget;
  final bool elevated;

  // ── Motion ─────────────────────────────────────────────────────────────
  final Duration motionFast;
  final Duration motionMedium;
  final Duration radarPeriod;
  final Curve motionCurve;
  final RadarScopeStyle radarStyle;
  final RadarLayoutStyle layoutStyle;

  double space(double multiplier) => spaceUnit * multiplier;

  String label(String text) => uppercaseLabels ? text.toUpperCase() : text;

  TextStyle display(double size, {Color? color}) => TextStyle(
        fontFamily: displayFamily,
        fontSize: size,
        fontWeight: displayWeight,
        letterSpacing: displayLetterSpacing,
        height: 1.08,
        color: color ?? ink,
      );

  TextStyle body(double size, {Color? color, FontWeight? weight}) => TextStyle(
        fontFamily: bodyFamily,
        fontSize: size,
        fontWeight: weight ?? FontWeight.w400,
        height: 1.35,
        color: color ?? ink,
      );

  TextStyle caption({Color? color}) => TextStyle(
        fontFamily: dataFamily ?? bodyFamily,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: labelLetterSpacing,
        color: color ?? inkMuted,
      );

  TextStyle data(double size, {Color? color, FontWeight? weight}) => TextStyle(
        fontFamily: dataFamily ?? bodyFamily,
        fontSize: size,
        fontWeight: weight ?? FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color ?? ink,
      );

  List<BoxShadow> get shadow => elevated
      ? [
          BoxShadow(
            color: ink.withValues(alpha: brightness == Brightness.dark ? 0.5 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: ink.withValues(alpha: brightness == Brightness.dark ? 0.3 : 0.04),
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
    bool? uppercaseLabels,
    double? radiusSmall,
    double? radiusMedium,
    double? radiusLarge,
    double? borderWidth,
    double? spaceUnit,
    double? minTouchTarget,
    bool? elevated,
    Duration? motionFast,
    Duration? motionMedium,
    Duration? radarPeriod,
    Curve? motionCurve,
    RadarScopeStyle? radarStyle,
    RadarLayoutStyle? layoutStyle,
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
        displayLetterSpacing: displayLetterSpacing ?? this.displayLetterSpacing,
        labelLetterSpacing: labelLetterSpacing ?? this.labelLetterSpacing,
        uppercaseLabels: uppercaseLabels ?? this.uppercaseLabels,
        radiusSmall: radiusSmall ?? this.radiusSmall,
        radiusMedium: radiusMedium ?? this.radiusMedium,
        radiusLarge: radiusLarge ?? this.radiusLarge,
        borderWidth: borderWidth ?? this.borderWidth,
        spaceUnit: spaceUnit ?? this.spaceUnit,
        minTouchTarget: minTouchTarget ?? this.minTouchTarget,
        elevated: elevated ?? this.elevated,
        motionFast: motionFast ?? this.motionFast,
        motionMedium: motionMedium ?? this.motionMedium,
        radarPeriod: radarPeriod ?? this.radarPeriod,
        motionCurve: motionCurve ?? this.motionCurve,
        radarStyle: radarStyle ?? this.radarStyle,
        layoutStyle: layoutStyle ?? this.layoutStyle,
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
      displayLetterSpacing: d(displayLetterSpacing, other.displayLetterSpacing),
      labelLetterSpacing: d(labelLetterSpacing, other.labelLetterSpacing),
      uppercaseLabels: discrete.uppercaseLabels,
      radiusSmall: d(radiusSmall, other.radiusSmall),
      radiusMedium: d(radiusMedium, other.radiusMedium),
      radiusLarge: d(radiusLarge, other.radiusLarge),
      borderWidth: d(borderWidth, other.borderWidth),
      spaceUnit: d(spaceUnit, other.spaceUnit),
      minTouchTarget: d(minTouchTarget, other.minTouchTarget),
      elevated: discrete.elevated,
      motionFast: discrete.motionFast,
      motionMedium: discrete.motionMedium,
      radarPeriod: discrete.radarPeriod,
      motionCurve: discrete.motionCurve,
      radarStyle: discrete.radarStyle,
      layoutStyle: discrete.layoutStyle,
    );
  }
}
