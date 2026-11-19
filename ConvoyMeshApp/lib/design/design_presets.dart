import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'outdoor_config.dart';

/// Single WCAG contrast evaluation entry for a foreground/background pair.
@immutable
class OutdoorContrastCheck {
  const OutdoorContrastCheck({
    required this.label,
    required this.ratio,
    required this.minAa,
  });

  final String label;
  final double ratio;
  final double minAa;

  bool get passesAa => ratio >= minAa;
  bool get passesAaa => ratio >= 7.0;
}

/// Complete WCAG contrast report across every active UI surface pair.
@immutable
class OutdoorContrastReport {
  const OutdoorContrastReport({required this.checks});

  final List<OutdoorContrastCheck> checks;

  double get minRatio =>
      checks.isEmpty ? 21.0 : checks.map((c) => c.ratio).reduce(math.min);

  List<OutdoorContrastCheck> get failures =>
      checks.where((c) => !c.passesAa).toList(growable: false);

  bool get allPassAa => failures.isEmpty;

  bool get bodyIsAaa => checks
      .where((c) =>
          c.label == 'Testo su card' ||
          c.label == 'Testo su sfondo' ||
          c.label == 'Hero radar')
      .every((c) => c.passesAaa);
}

/// Palette definitions and factory for **Outdoor Premium** + Classic reference.
///
/// Every bundled palette is verified for outdoor legibility in tests:
/// - Body ink vs. canvas / surface >= 7:1 (WCAG AAA)
/// - Muted ink, accents and status tones vs. surface >= 4.5:1 (WCAG AA/AAA)
/// - Hero ink vs. all hero background stops >= 7:1 (WCAG AAA)
/// - Critical button foreground vs. critical fill >= 4.5:1 (WCAG AA/AAA)
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

  static Color _opaque(int argb) =>
      Color(OutdoorCustomConfig.sanitizeOpaqueArgb(argb)!);

  /// WCAG 2.1 contrast ratio between [fg] (composited over [bg] if translucent)
  /// and opaque [bg].
  static double contrastRatio(Color fg, Color bg) {
    final opaqueBg = bg.withValues(alpha: 1.0);
    final opaqueFg = Color.alphaBlend(fg, opaqueBg);
    final l1 = opaqueFg.computeLuminance();
    final l2 = opaqueBg.computeLuminance();
    final light = math.max(l1, l2);
    final dark = math.min(l1, l2);
    return (light + 0.05) / (dark + 0.05);
  }

  /// Resolves a complete [ConvoyDesignTokens] from [config], preserving safe
  /// contrast independently on [canvas], [surface], [accent], [critical], and
  /// [heroBackground], and preserving preset defaults for [borderWidth] and
  /// [elevated] unless explicitly overridden.
  static ConvoyDesignTokens buildOutdoor(OutdoorCustomConfig config) {
    final base = paletteOf(config.palettePreset);
    final canvas =
        config.canvasArgb != null ? _opaque(config.canvasArgb!) : base.canvas;
    final surface =
        config.surfaceArgb != null ? _opaque(config.surfaceArgb!) : base.surface;
    final surfaceIsDark = surface.computeLuminance() < 0.25;
    final canvasIsDark = canvas.computeLuminance() < 0.25;
    final brightness = surfaceIsDark ? Brightness.dark : Brightness.light;

    final surfaceRaised = config.surfaceArgb != null
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: surfaceIsDark ? 0.06 : 0.65),
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

    final ink = config.surfaceArgb != null
        ? (surfaceIsDark ? const Color(0xFFECE7DB) : const Color(0xFF17201B))
        : base.ink;
    final inkMuted = config.surfaceArgb != null
        ? (surfaceIsDark ? const Color(0xFFA0B1A5) : const Color(0xFF4F5B53))
        : base.inkMuted;
    final inkOnCanvas = config.canvasArgb != null
        ? (canvasIsDark ? const Color(0xFFECE7DB) : const Color(0xFF17201B))
        : base.inkOnCanvas;
    final inkMutedOnCanvas = config.canvasArgb != null
        ? (canvasIsDark ? const Color(0xFFA0B1A5) : const Color(0xFF4F5B53))
        : base.inkMutedOnCanvas;

    final accent =
        config.accentArgb != null ? _opaque(config.accentArgb!) : base.accent;
    final onAccent =
        config.accentArgb != null ? contrastingInkOn(accent) : base.onAccent;
    final highlight = config.highlightArgb != null
        ? _opaque(config.highlightArgb!)
        : base.highlight;
    final positive = config.positiveArgb != null
        ? _opaque(config.positiveArgb!)
        : base.positive;
    final warning = config.warningArgb != null
        ? _opaque(config.warningArgb!)
        : base.warning;
    final critical = config.criticalArgb != null
        ? _opaque(config.criticalArgb!)
        : base.critical;
    final onCritical = config.criticalArgb != null
        ? contrastingInkOn(critical)
        : base.onCritical;

    final Gradient heroBg;
    final Color heroInk;
    final Color heroOfflineInk;
    if (config.heroBaseArgb != null) {
      final h0 = _opaque(config.heroBaseArgb!);
      final h0IsDark = h0.computeLuminance() < 0.30;
      final shiftTarget = h0IsDark ? Colors.white : const Color(0xFF101914);
      final h1 = Color.lerp(h0, shiftTarget, 0.08)!;
      final h2 = Color.lerp(h0, shiftTarget, 0.14)!;
      final stops = [h0, h1, h2];
      heroBg = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: stops,
      );
      heroInk = _bestInkForGradient(stops, preferWarm: true);
      heroOfflineInk = _offlineInkForGradient(stops);
    } else {
      heroBg = base.heroBackground;
      heroInk = base.heroInk;
      heroOfflineInk = base.heroOfflineInk;
    }

    final displayWeight = config.displayFamily == 'Manrope'
        ? (config.displayBold ? FontWeight.w800 : FontWeight.w400)
        : (config.displayBold ? FontWeight.w700 : FontWeight.w500);

    return ConvoyDesignTokens(
      direction: DesignDirection.outdoorPremium,
      brightness: brightness,
      canvas: canvas,
      surface: surface,
      surfaceRaised: surfaceRaised,
      outline: outline,
      ink: ink,
      inkMuted: inkMuted,
      inkOnCanvas: inkOnCanvas,
      inkMutedOnCanvas: inkMutedOnCanvas,
      accent: accent,
      onAccent: onAccent,
      highlight: highlight,
      positive: positive,
      warning: warning,
      critical: critical,
      onCritical: onCritical,
      heroBackground: heroBg,
      heroInk: heroInk,
      heroOfflineInk: heroOfflineInk,
      radarGrid: heroInk.withValues(alpha: 0.40),
      radarSweep: config.highlightArgb != null ? highlight : base.radarSweep,
      displayFamily: config.displayFamily,
      bodyFamily: config.bodyFamily,
      dataFamily: config.dataFamily,
      displayWeight: displayWeight,
      displayLetterSpacing:
          config.displayFamily == 'Fraunces' ? -0.4 : -0.2,
      labelLetterSpacing: config.uppercaseLabels ? 1.0 : 0.5,
      fontScale: config.fontScale,
      uppercaseLabels: config.uppercaseLabels,
      radiusSmall: config.radiusSmall,
      radiusMedium: config.radiusMedium,
      radiusLarge: config.radiusLarge,
      borderWidth: config.borderWidth ?? base.borderWidth,
      spaceUnit: config.spaceUnit,
      screenPaddingScale: config.screenPaddingScale,
      cardPaddingScale: config.cardPaddingScale,
      sectionGapScale: config.sectionGapScale,
      minTouchTarget: config.minTouchTarget,
      avatarSize: config.avatarSize,
      iconScale: config.iconScale,
      radarScopeScale: config.radarScopeScale,
      elevated: config.elevated ?? base.elevated,
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

  static Color _bestInkForGradient(List<Color> stops,
      {bool preferWarm = false}) {
    const darkInk = Color(0xFF101914);
    final lightInk =
        preferWarm ? const Color(0xFFF6EFDD) : const Color(0xFFFFFFFF);
    final worstDark =
        stops.map((s) => contrastRatio(darkInk, s)).reduce(math.min);
    final worstLight =
        stops.map((s) => contrastRatio(lightInk, s)).reduce(math.min);
    return worstDark >= worstLight ? darkInk : lightInk;
  }

  static Color _offlineInkForGradient(List<Color> stops) {
    const lightAmber = Color(0xFFFFE7A8);
    const darkAmber = Color(0xFF6B3A00);
    final worstLight =
        stops.map((s) => contrastRatio(lightAmber, s)).reduce(math.min);
    final worstDark =
        stops.map((s) => contrastRatio(darkAmber, s)).reduce(math.min);
    final bestAmber = worstLight >= worstDark ? lightAmber : darkAmber;
    final bestRatio = math.max(worstLight, worstDark);
    if (bestRatio >= 4.5) return bestAmber;
    return _bestInkForGradient(stops, preferWarm: true);
  }

  /// Evaluates WCAG contrast across every live foreground/background pair in [t].
  static OutdoorContrastReport evaluateContrast(ConvoyDesignTokens t) {
    final heroStops = t.heroBackground.colors;
    final worstHeroInk =
        heroStops.map((s) => contrastRatio(t.heroInk, s)).reduce(math.min);
    final worstHeroOffline = heroStops
        .map((s) => contrastRatio(t.heroOfflineInk, s))
        .reduce(math.min);
    return OutdoorContrastReport(checks: [
      OutdoorContrastCheck(
        label: 'Testo su card',
        ratio: contrastRatio(t.ink, t.surface),
        minAa: 4.5,
      ),
      OutdoorContrastCheck(
        label: 'Testo secondario',
        ratio: contrastRatio(t.inkMuted, t.surface),
        minAa: 4.5,
      ),
      OutdoorContrastCheck(
        label: 'Testo su sfondo',
        ratio: contrastRatio(t.inkOnCanvas, t.canvas),
        minAa: 4.5,
      ),
      OutdoorContrastCheck(
        label: 'Secondario sfondo',
        ratio: contrastRatio(t.inkMutedOnCanvas, t.canvas),
        minAa: 4.5,
      ),
      OutdoorContrastCheck(
        label: 'Pulsante primario',
        ratio: contrastRatio(t.onAccent, t.accent),
        minAa: 4.5,
      ),
      OutdoorContrastCheck(
        label: 'Accento su card',
        ratio: contrastRatio(t.accent, t.surface),
        minAa: 4.5,
      ),
      OutdoorContrastCheck(
        label: 'Pulsante critico',
        ratio: contrastRatio(t.onCritical, t.critical),
        minAa: 4.5,
      ),
      OutdoorContrastCheck(
        label: 'Stato positivo',
        ratio: contrastRatio(t.positive, t.surface),
        minAa: 4.5,
      ),
      OutdoorContrastCheck(
        label: 'Stato avviso',
        ratio: contrastRatio(t.warning, t.surface),
        minAa: 4.5,
      ),
      OutdoorContrastCheck(
        label: 'Stato critico',
        ratio: contrastRatio(t.critical, t.surface),
        minAa: 4.5,
      ),
      OutdoorContrastCheck(
        label: 'Hero radar',
        ratio: worstHeroInk,
        minAa: 4.5,
      ),
      OutdoorContrastCheck(
        label: 'Offline su hero',
        ratio: worstHeroOffline,
        minAa: 4.5,
      ),
    ]);
  }

  static Color contrastingInkOn(Color bg, {bool preferWarm = false}) {
    const darkInk = Color(0xFF101914);
    final lightInk =
        preferWarm ? const Color(0xFFF6EFDD) : const Color(0xFFFFFFFF);
    final crDark = contrastRatio(darkInk, bg);
    final crLight = contrastRatio(lightInk, bg);
    return crDark >= crLight ? darkInk : lightInk;
  }

  /// Default curated swatch grids offered in the Outdoor customiser across all
  /// eight semantic colour roles (including light and dark mode options).
  static const customCanvasSwatches = <Color>[
    Color(0xFFF2EEE4), // Carta calda (default)
    Color(0xFFEFECE4), // Pietra alpina
    Color(0xFFF3ECE3), // Sabbia calda
    Color(0xFFF7F7F4), // Neve morbida
    Color(0xFF0D1511), // Bosco notturno
  ];

  static const customSurfaceSwatches = <Color>[
    Color(0xFFFFFCF5), // Pergamena chiara
    Color(0xFFFFFFFF), // Bianco alpino
    Color(0xFFFFFDF8), // Avorio caldo
    Color(0xFF14201A), // Abete scuro (dark)
    Color(0xFF18222A), // Ardesia notte (dark)
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

  static const customPositiveSwatches = <Color>[
    Color(0xFF265E42), // Pino segnale (default)
    Color(0xFF1E5B3B), // Muschio intenso
    Color(0xFF1C5E54), // Lago smeraldo
    Color(0xFF7ED8A6), // Felce chiara (dark mode)
    Color(0xFF8BE2C3), // Menta chiara (dark mode)
  ];

  static const customWarningSwatches = <Color>[
    Color(0xFF854E08), // Ocra segnale (default)
    Color(0xFF854B04), // Ambra profonda
    Color(0xFF7E4612), // Bronzo sentiero
    Color(0xFFF0B556), // Sole crepuscolo (dark mode)
    Color(0xFFF3C66E), // Oro chiaro (dark mode)
  ];

  static const customCriticalSwatches = <Color>[
    Color(0xFF9A2D24), // Rosso segnale (default)
    Color(0xFF932720), // Cremisi rifugio
    Color(0xFF9E2A21), // Argilla rossa
    Color(0xFFF28579), // Corallo notte (dark mode)
    Color(0xFFFF9B8E), // Rosa segnale (dark mode)
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
    inkOnCanvas: Color(0xFF1C2620),
    inkMutedOnCanvas: Color(0xFF4B574F),
    accent: Color(0xFF24503F),
    onAccent: Color(0xFFFFF8EA),
    highlight: Color(0xFFB06C14),
    positive: Color(0xFF265E42),
    warning: Color(0xFF854E08),
    critical: Color(0xFF9A2D24),
    onCritical: Color(0xFFFFFFFF),
    heroBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF173428), Color(0xFF214838), Color(0xFF2B5644)],
    ),
    heroInk: Color(0xFFF6EFDD),
    heroOfflineInk: Color(0xFFFFE7A8),
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
    inkOnCanvas: Color(0xFF101713),
    inkMutedOnCanvas: Color(0xFF434E46),
    accent: Color(0xFF1B4234),
    onAccent: Color(0xFFFFFFFF),
    highlight: Color(0xFFA35D0A),
    positive: Color(0xFF1E5B3B),
    warning: Color(0xFF854B04),
    critical: Color(0xFF932720),
    onCritical: Color(0xFFFFFFFF),
    heroBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0F281E), Color(0xFF1D4536), Color(0xFF2B5946)],
    ),
    heroInk: Color(0xFFFFFFFF),
    heroOfflineInk: Color(0xFFF6D28B),
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
    inkOnCanvas: Color(0xFF211A16),
    inkMutedOnCanvas: Color(0xFF52453D),
    accent: Color(0xFF683722),
    onAccent: Color(0xFFFFF9F2),
    highlight: Color(0xFF265743),
    positive: Color(0xFF245C3F),
    warning: Color(0xFF854D07),
    critical: Color(0xFF9E2A21),
    onCritical: Color(0xFFFFFFFF),
    heroBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF3A2015), Color(0xFF563222), Color(0xFF6E422E)],
    ),
    heroInk: Color(0xFFFCF2E6),
    heroOfflineInk: Color(0xFFF6D59B),
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
    inkOnCanvas: Color(0xFFECE7DB),
    inkMutedOnCanvas: Color(0xFF9EB0A4),
    accent: Color(0xFF76D1A1),
    onAccent: Color(0xFF071910),
    highlight: Color(0xFFEAB056),
    positive: Color(0xFF7ED8A6),
    warning: Color(0xFFF0B556),
    critical: Color(0xFFF28579),
    onCritical: Color(0xFF101914),
    heroBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF09130E), Color(0xFF13251D), Color(0xFF1C3529)],
    ),
    heroInk: Color(0xFFF5EFE0),
    heroOfflineInk: Color(0xFFF3C46C),
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
    inkOnCanvas: Color(0xFF191C1E),
    inkMutedOnCanvas: Color(0xFF5A6166),
    accent: Color(0xFF3F5F70),
    onAccent: Color(0xFFFFFFFF),
    highlight: Color(0xFF3F5F70),
    positive: Color(0xFF245B45),
    warning: Color(0xFF8F5A0E),
    critical: Color(0xFF932F3B),
    onCritical: Color(0xFFFFFFFF),
    heroBackground: LinearGradient(
      colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
    ),
    heroInk: Color(0xFF191C1E),
    heroOfflineInk: Color(0xFF8F5A0E),
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
