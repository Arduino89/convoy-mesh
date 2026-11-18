import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Builds a complete Material 3 [ThemeData] from [ConvoyDesignTokens].
///
/// Applied app-wide when a non-classic direction is selected, so Map and
/// Test log inherit colours, type, shapes and touch targets without any change
/// to their functional code.
ThemeData buildConvoyTheme(ConvoyDesignTokens t) {
  final dark = t.brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: t.brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    primaryContainer: Color.alphaBlend(t.accent.withValues(alpha: 0.14), t.surface),
    onPrimaryContainer: t.ink,
    secondary: t.highlight,
    onSecondary: dark ? t.canvas : Colors.white,
    secondaryContainer: Color.alphaBlend(t.highlight.withValues(alpha: 0.16), t.surface),
    onSecondaryContainer: t.ink,
    tertiary: t.positive,
    onTertiary: dark ? t.canvas : Colors.white,
    error: t.critical,
    onError: dark ? t.canvas : Colors.white,
    errorContainer: Color.alphaBlend(t.critical.withValues(alpha: 0.14), t.surface),
    onErrorContainer: t.ink,
    surface: t.surface,
    onSurface: t.ink,
    onSurfaceVariant: t.inkMuted,
    surfaceContainerLowest: t.canvas,
    surfaceContainerLow: t.canvas,
    surfaceContainer: t.surface,
    surfaceContainerHigh: t.surfaceRaised,
    surfaceContainerHighest: t.surfaceRaised,
    outline: t.outline,
    outlineVariant: t.outline.withValues(alpha: 0.6),
    shadow: Colors.black,
    inverseSurface: t.ink,
    onInverseSurface: t.surface,
    inversePrimary: t.highlight,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: t.brightness,
    fontFamily: t.bodyFamily,
  );
  final text = base.textTheme.apply(
    bodyColor: t.ink,
    displayColor: t.ink,
    fontFamily: t.bodyFamily,
  );
  final shapeM = RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusMedium));
  final shapeS = RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSmall));
  final buttonText = TextStyle(
    fontFamily: t.bodyFamily,
    fontWeight: FontWeight.w700,
    fontSize: 15,
    letterSpacing: t.uppercaseLabels ? 1.0 : 0.1,
  );
  final buttonMin = Size(48, t.minTouchTarget - 8);

  return base.copyWith(
    scaffoldBackgroundColor: t.canvas,
    canvasColor: t.canvas,
    textTheme: text.copyWith(
      headlineMedium: t.display(28),
      headlineSmall: t.display(24),
      titleLarge: t.display(21),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
    extensions: [t],
    appBarTheme: AppBarTheme(
      backgroundColor: t.canvas,
      foregroundColor: t.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: t.display(22),
    ),
    cardTheme: CardThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: t.space(1.5)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusMedium),
        side: BorderSide(color: t.outline, width: t.borderWidth),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        minimumSize: buttonMin,
        shape: shapeM,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        minimumSize: buttonMin,
        side: BorderSide(color: t.outline, width: t.borderWidth),
        shape: shapeM,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? t.accent : t.accent,
        minimumSize: buttonMin,
        shape: shapeS,
        textStyle: buttonText,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.surfaceRaised,
      side: BorderSide(color: t.outline, width: t.borderWidth),
      shape: shapeS,
      labelStyle: t.caption(color: t.ink),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: dark
          ? t.accent.withValues(alpha: 0.18)
          : Color.alphaBlend(t.accent.withValues(alpha: 0.12), t.surface),
      indicatorShape: shapeM,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: states.contains(WidgetState.selected) ? t.ink : t.inkMuted,
            letterSpacing: t.uppercaseLabels ? 0.8 : 0,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? (dark ? t.accent : t.accent) : t.inkMuted,
          )),
    ),
    dividerTheme: DividerThemeData(color: t.outline, thickness: t.borderWidth),
    expansionTileTheme: ExpansionTileThemeData(
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: t.inkMuted,
      collapsedIconColor: t.inkMuted,
      textColor: t.ink,
      collapsedTextColor: t.ink,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? t.surfaceRaised : t.ink,
      contentTextStyle: t.body(14, color: dark ? t.ink : t.surface, weight: FontWeight.w600),
      shape: shapeM,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusLarge)),
      titleTextStyle: t.display(22),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? t.onAccent : t.inkMuted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? t.accent : t.outline),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
