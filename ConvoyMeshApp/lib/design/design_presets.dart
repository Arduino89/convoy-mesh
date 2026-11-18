import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'outdoor_config.dart';

/// Palette definitions and factory for **Outdoor Premium** + Classic reference.
///
/// Every bundled palette is verified for outdoor legibility in tests:
/// - Body ink vs. canvas / surface >= 7:1 (WCAG AAA)
/// - Muted ink, accents and status tones vs. surface >= 4.5:1 (WCAG AA/AAA)
/// - Hero ink vs. hero background >= 7:1 (WCAG AAA)
class DesignPresets {
  const DesignPresets._();

  /// Base palette values before applying custom overrides from [OutdoorCustomConfig].
  static ConvoyDesignTokens paletteOf(OutdoorPalettePreset preset) =>
      switch (preset) {
        OutdoorPalettePreset.pinoECarta => _pinoECarta,
        OutdoorPalettePreset.crestaAlba => _crestaAlba,
        OutdoorPalettePreset.terraERame => _terraERame,
        OutdoorPalettePreset.abeteNotturno => _abeteNotturno,
      };

  /// Default tokens for a given [DesignDirection].
  static ConvoyDesignTokens of(DesignDirection direction) =>
      direction == DesignDirection.classic ? classicReference : outdoorPremium;

  static const outdoorPremium = _pinoECarta;

  /// Resolves a complete [ConvoyDesignTokens] from [config], preserving safe
  /// contrast for customised accent or hero base colours.
  static ConvoyDesignTokens buildOutdoor(OutdoorCustomConfig config) {
    final base = paletteOf(config.palettePreset);
    final canvas =
        config.canvasArgb != null ? Color(config.canvasArgb!) : base.canvas;
    final surface =
        config.surfaceArgb != null ? Color(config.surfaceArgb!) : base.surface;
    final surfaceIsDark = surface.computeLuminance() < 0.25;
    final brightness = surfaceIsDark ? Brightness.dark : Brightness.light;
    final surfaceRaised = config.surfaceArgb != null
        ? Color.alphaBlend(
            (surfaceIsDark ? Colors.white : Colors.white)
                .withValues(alpha: surfaceIsDark ? 0.06 : 0.65),
            surface,
          )
        : base.surfaceRaised;
    final outline = config.surfaceArgb != null || config.canvasArgb != null
        ? Color.alphaBlend(
            (surfaceIsDark ? Colors.white : const Color(0xFF3A352A))
                .withValues(alpha: surfaceIsDark ? 0.16 : 0.14),
            surface,
          )
        : base.outline;

    final accent =
        config.accentArgb != null ? Color(config.accentArgb!) : base.accent;
    final onAccent = config.accentArgb != null
        ? contrastingInkOn(accent)
        : base.onAccent;
    final highlight = config.highlightArgb != null
        ? Color(config.highlightArgb!)
        : base.highlight;
    final positive = config.positiveArgb != null
        ? Color(config.positiveArgb!)
        : base.positive;
    final warning =
        config.warningArgb != null ? Color(config.warningArgb!) : base.warning;
    final critical = config.criticalArgb != null
        ? Color(config.criticalArgb!)
        : base.critical;

    final Gradient heroBg;
    final Color heroInk;
    if (config.heroBaseArgb != null) {
      final h0 = Color(config.heroBaseArgb!);
      final h1 = Color.lerp(h0, Colors.white, 0.12)!;
      final h2 = Color.lerp(h0, Colors.white, 0.20)!;
      heroBg = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [h0, h1, h2],
      );
      heroInk = contrastingInkOn(h0, preferWarm: true);
    } else {
      heroBg = base.heroBackground;
      heroInk = base.heroInk;
    }

    return ConvoyDesignTokens(
      direction: DesignDirection.outdoorPremium,
      brightness: brightness,
      canvas: canvas,
      surface: surface,
      surfaceRaised: surfaceRaised,
      outline: outline,
      ink: config.canvasArgb != null || config.surfaceArgb != null
          ? (surfaceIsDark ? const Color(0xFFECE7DB) : const Color(0xFF17201B))
          : base.ink,
      inkMuted: config.canvasArgb != null || config.surfaceArgb != null
          ? (surfaceIsDark ? const Color(0xFFA0B1A5) : const Color(0xFF4F5B53))
          : base.inkMuted,
      accent: accent,
      onAccent: onAccent,
      highlight: highlight,
      positive: positive,
      warning: warning,
      critical: critical,
      heroBackground: heroBg,
      heroInk: heroInk,
      radarGrid: heroInk.withValues(alpha: 0.40),
      radarSweep: config.highlightArgb != null ? highlight : base.radarSweep,
      displayFamily: config.displayFamily,
      bodyFamily: config.bodyFamily,
      dataFamily: config.dataFamily,
      displayWeight: config.displayBold ? FontWeight.w700 : FontWeight.w500,
      displayLetterSpacing:
          config.displayFamily == 'Fraunces' ? -0.4 : -0.2,
      labelLetterSpacing: config.uppercaseLabels ? 1.0 : 0.5,
      fontScale: config.fontScale,
      uppercaseLabels: config.uppercaseLabels,
      radiusSmall: config.radiusSmall,
      radiusMedium: config.radiusMedium,
      radiusLarge: config.radiusLarge,
      borderWidth: config.borderWidth,
      spaceUnit: config.spaceUnit,
      screenPaddingScale: config.screenPaddingScale,
      cardPaddingScale: config.cardPaddingScale,
      sectionGapScale: config.sectionGapScale,
      minTouchTarget: config.minTouchTarget,
      avatarSize: config.avatarSize,
      iconScale: config.iconScale,
      radarScopeScale: config.radarScopeScale,
      elevated: config.elevated,
      animationsEnabled: config.animationsEnabled,
      radarRotationEnabled: config.radarRotationEnabled,
      livePulseEnabled: config.livePulseEnabled,
      showTopoContours: config.showTopoContours,
      motionFast: Duration(
          milliseconds: config.animationsEnabled ? config.motionFastMs : 0),
      motionMedium: Duration(
          milliseconds: config.animationsEnabled ? config.motionMediumMs : 0),
      radarPeriod: Duration(milliseconds: config.radarPeriodMs),
      motionCurve: Curves.easeOutCubic,
      copy: config.copy,
    );
  }

  static Color contrastingInkOn(Color bg, {bool preferWarm = false}) {
    const darkInk = Color(0xFF101914);
    final lightInk =
        preferWarm ? const Color(0xFFF6EFDD) : const Color(0xFFFFFFFF);
    final lBg = bg.computeLuminance();
    final crDark = (lBg + 0.05) / (darkInk.computeLuminance() + 0.05);
    final crLight = (lightInk.computeLuminance() + 0.05) / (lBg + 0.05);
    return crDark >= crLight ? darkInk : lightInk;
  }

  /// Default curated swatch grids offered in the Outdoor customiser.
  static const customCanvasSwatches = <Color>[
    Color(0xFFF2EEE4), // Carta calda (default)
    Color(0xFFEFECE4), // Pietra alpina
    Color(0xFFF3ECE3), // Sabbia calda
    Color(0xFFF7F7F4), // Neve morbida
    Color(0xFF0D1511), // Bosco notturno
  ];

  static const customAccentSwatches = <Color>[
    Color(0xFF24503F), // Pino profondo (default)
    Color(0xFF1B4234), // Abete intenso
    Color(0xFF683722), // Terra & cuoio
    Color(0xFF234B6E), // Lago alpino
    Color(0xFF76D1A1), // Pino chiaro (dark mode)
  ];

  static const customHighlightSwatches = <Color>[
    Color(0xFFB06C14), // Ocra ambra (default)
    Color(0xFFA35D0A), // Rame carico
    Color(0xFF265743), // Salvia alpina
    Color(0xFFD06024), // Segnale sentiero
    Color(0xFFEAB056), // Luce crepuscolo
  ];

  static const customHeroSwatches = <Color>[
    Color(0xFF173428), // Pino scuro (default)
    Color(0xFF0F281E), // Abete profondo
    Color(0xFF3A2015), // Corteccia roccia
    Color(0xFF162C40), // Ardesia notte
    Color(0xFF09130E), // Bosco notte
  ];

  // ── 1. Pino & Carta (default Outdoor Premium) ──────────────────────────
  static const _pinoECarta = ConvoyDesignTokens(
    direction: DesignDirection.outdoorPremium,
    brightness: Brightness.light,
    canvas: Color(0xFFF2EEE4),
    surface: Color(0xFFFFFCF5),
    surfaceRaised: Color(0xFFFFFFFF),
    outline: Color(0xFFDCD5C5),
    ink: Color(0xFF1C2620),
    inkMuted: Color(0xFF525E56),
    accent: Color(0xFF24503F),
    onAccent: Color(0xFFFFF8EA),
    highlight: Color(0xFFB06C14),
    positive: Color(0xFF265E42),
    warning: Color(0xFF854E08),
    critical: Color(0xFF9A2D24),
    heroBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF173428), Color(0xFF2B5A47), Color(0xFF3C6B52)],
    ),
    heroInk: Color(0xFFF6EFDD),
    radarGrid: Color(0x66F6EFDD),
    radarSweep: Color(0xFFE9B85C),
    displayFamily: 'Fraunces',
    bodyFamily: 'Manrope',
    dataFamily: 'Manrope',
    displayWeight: FontWeight.w700,
    displayLetterSpacing: -0.4,
    labelLetterSpacing: 0.5,
    fontScale: 1.0,
    uppercaseLabels: false,
    radiusSmall: 12,
    radiusMedium: 20,
    radiusLarge: 30,
    borderWidth: 1,
    spaceUnit: 4,
    screenPaddingScale: 1.0,
    cardPaddingScale: 1.0,
    sectionGapScale: 1.0,
    minTouchTarget: 52,
    avatarSize: 48,
    iconScale: 1.0,
    radarScopeScale: 0.90,
    elevated: true,
    animationsEnabled: true,
    radarRotationEnabled: true,
    livePulseEnabled: true,
    showTopoContours: true,
    motionFast: Duration(milliseconds: 220),
    motionMedium: Duration(milliseconds: 420),
    radarPeriod: Duration(milliseconds: 5200),
    motionCurve: Curves.easeOutCubic,
  );

  // ── 2. Cresta Alba (alta leggibilità al sole diretto) ──────────────────
  static const _crestaAlba = ConvoyDesignTokens(
    direction: DesignDirection.outdoorPremium,
    brightness: Brightness.light,
    canvas: Color(0xFFEFECE4),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    outline: Color(0xFFC7C2B4),
    ink: Color(0xFF101713),
    inkMuted: Color(0xFF49544C),
    accent: Color(0xFF1B4234),
    onAccent: Color(0xFFFFFFFF),
    highlight: Color(0xFFA35D0A),
    positive: Color(0xFF1E5B3B),
    warning: Color(0xFF854B04),
    critical: Color(0xFF932720),
    heroBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0F281E), Color(0xFF1D4536), Color(0xFF2B5946)],
    ),
    heroInk: Color(0xFFFFFFFF),
    radarGrid: Color(0x66FFFFFF),
    radarSweep: Color(0xFFF0B955),
    displayFamily: 'Fraunces',
    bodyFamily: 'Manrope',
    dataFamily: 'Manrope',
    displayWeight: FontWeight.w700,
    displayLetterSpacing: -0.4,
    labelLetterSpacing: 0.5,
    fontScale: 1.0,
    uppercaseLabels: false,
    radiusSmall: 12,
    radiusMedium: 20,
    radiusLarge: 30,
    borderWidth: 1.2,
    spaceUnit: 4,
    screenPaddingScale: 1.0,
    cardPaddingScale: 1.0,
    sectionGapScale: 1.0,
    minTouchTarget: 52,
    avatarSize: 48,
    iconScale: 1.0,
    radarScopeScale: 0.90,
    elevated: true,
    animationsEnabled: true,
    radarRotationEnabled: true,
    livePulseEnabled: true,
    showTopoContours: true,
    motionFast: Duration(milliseconds: 220),
    motionMedium: Duration(milliseconds: 420),
    radarPeriod: Duration(milliseconds: 5200),
    motionCurve: Curves.easeOutCubic,
  );

  // ── 3. Terra & Rame (sentieri roccia e bosco caldo) ────────────────────
  static const _terraERame = ConvoyDesignTokens(
    direction: DesignDirection.outdoorPremium,
    brightness: Brightness.light,
    canvas: Color(0xFFF3ECE3),
    surface: Color(0xFFFFFDF8),
    surfaceRaised: Color(0xFFFFFFFF),
    outline: Color(0xFFD8CBBF),
    ink: Color(0xFF211A16),
    inkMuted: Color(0xFF5B4D44),
    accent: Color(0xFF683722),
    onAccent: Color(0xFFFFF9F2),
    highlight: Color(0xFF265743),
    positive: Color(0xFF245C3F),
    warning: Color(0xFF854D07),
    critical: Color(0xFF9E2A21),
    heroBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF3A2015), Color(0xFF563222), Color(0xFF6E422E)],
    ),
    heroInk: Color(0xFFFCF2E6),
    radarGrid: Color(0x66FCF2E6),
    radarSweep: Color(0xFF8FD1AE),
    displayFamily: 'Fraunces',
    bodyFamily: 'Manrope',
    dataFamily: 'Manrope',
    displayWeight: FontWeight.w700,
    displayLetterSpacing: -0.4,
    labelLetterSpacing: 0.5,
    fontScale: 1.0,
    uppercaseLabels: false,
    radiusSmall: 12,
    radiusMedium: 20,
    radiusLarge: 30,
    borderWidth: 1,
    spaceUnit: 4,
    screenPaddingScale: 1.0,
    cardPaddingScale: 1.0,
    sectionGapScale: 1.0,
    minTouchTarget: 52,
    avatarSize: 48,
    iconScale: 1.0,
    radarScopeScale: 0.90,
    elevated: true,
    animationsEnabled: true,
    radarRotationEnabled: true,
    livePulseEnabled: true,
    showTopoContours: true,
    motionFast: Duration(milliseconds: 220),
    motionMedium: Duration(milliseconds: 420),
    radarPeriod: Duration(milliseconds: 5200),
    motionCurve: Curves.easeOutCubic,
  );

  // ── 4. Abete Notturno (crepuscolo nel bosco, alto contrasto dark) ──────
  static const _abeteNotturno = ConvoyDesignTokens(
    direction: DesignDirection.outdoorPremium,
    brightness: Brightness.dark,
    canvas: Color(0xFF0D1511),
    surface: Color(0xFF14201A),
    surfaceRaised: Color(0xFF1B2B23),
    outline: Color(0xFF2C4237),
    ink: Color(0xFFECE7DB),
    inkMuted: Color(0xFF9EB0A4),
    accent: Color(0xFF76D1A1),
    onAccent: Color(0xFF071910),
    highlight: Color(0xFFEAB056),
    positive: Color(0xFF7ED8A6),
    warning: Color(0xFFF0B556),
    critical: Color(0xFFF28579),
    heroBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF09130E), Color(0xFF13251D), Color(0xFF1C3529)],
    ),
    heroInk: Color(0xFFF5EFE0),
    radarGrid: Color(0x55ECE7DB),
    radarSweep: Color(0xFFEAB056),
    displayFamily: 'Fraunces',
    bodyFamily: 'Manrope',
    dataFamily: 'Manrope',
    displayWeight: FontWeight.w700,
    displayLetterSpacing: -0.4,
    labelLetterSpacing: 0.5,
    fontScale: 1.0,
    uppercaseLabels: false,
    radiusSmall: 12,
    radiusMedium: 20,
    radiusLarge: 30,
    borderWidth: 1,
    spaceUnit: 4,
    screenPaddingScale: 1.0,
    cardPaddingScale: 1.0,
    sectionGapScale: 1.0,
    minTouchTarget: 52,
    avatarSize: 48,
    iconScale: 1.0,
    radarScopeScale: 0.90,
    elevated: false,
    animationsEnabled: true,
    radarRotationEnabled: true,
    livePulseEnabled: true,
    showTopoContours: true,
    motionFast: Duration(milliseconds: 220),
    motionMedium: Duration(milliseconds: 420),
    radarPeriod: Duration(milliseconds: 5200),
    motionCurve: Curves.easeOutCubic,
  );

  /// Neutral values approximating the original seed theme (`LAB +15`) for
  /// picker swatches and rollback comparisons.
  static const classicReference = ConvoyDesignTokens(
    direction: DesignDirection.classic,
    brightness: Brightness.light,
    canvas: Color(0xFFF8F9FB),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    outline: Color(0xFFD5DADF),
    ink: Color(0xFF191C1E),
    inkMuted: Color(0xFF5A6166),
    accent: Color(0xFF3F5F70),
    onAccent: Color(0xFFFFFFFF),
    highlight: Color(0xFF3F5F70),
    positive: Color(0xFF245B45),
    warning: Color(0xFF8F5A0E),
    critical: Color(0xFF932F3B),
    heroBackground: LinearGradient(
      colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
    ),
    heroInk: Color(0xFF191C1E),
    radarGrid: Color(0x33191C1E),
    radarSweep: Color(0xFF356956),
    displayFamily: null,
    bodyFamily: null,
    dataFamily: null,
    displayWeight: FontWeight.w600,
    displayLetterSpacing: 0,
    labelLetterSpacing: 0.4,
    fontScale: 1.0,
    uppercaseLabels: false,
    radiusSmall: 8,
    radiusMedium: 12,
    radiusLarge: 16,
    borderWidth: 1,
    spaceUnit: 4,
    screenPaddingScale: 1.0,
    cardPaddingScale: 1.0,
    sectionGapScale: 1.0,
    minTouchTarget: 48,
    avatarSize: 44,
    iconScale: 1.0,
    radarScopeScale: 0.9,
    elevated: false,
    animationsEnabled: true,
    radarRotationEnabled: true,
    livePulseEnabled: true,
    showTopoContours: false,
    motionFast: Duration(milliseconds: 200),
    motionMedium: Duration(milliseconds: 300),
    radarPeriod: Duration(milliseconds: 1700),
    motionCurve: Curves.easeInOut,
  );
}
