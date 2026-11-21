import 'package:flutter/material.dart';

import 'design_presets.dart';
import 'design_tokens.dart';

/// Builds a complete Material 3 [ThemeData] from [ConvoyDesignTokens].
///
/// Applied app-wide whenever Outdoor Premium is active, ensuring every button,
/// input, checkbox, dropdown, card, dialog, bottom sheet and snackbar shares
/// consistent outdoor typography, borders, radii, spacing and touch targets.
ThemeData buildConvoyTheme(ConvoyDesignTokens t) {
  final dark = t.brightness == Brightness.dark;
  final onHighlight = DesignPresets.contrastingInkOn(t.highlight);
  final onPositive = DesignPresets.contrastingInkOn(t.positive);
  final onCritical = t.onCritical;

  final scheme = ColorScheme(
    brightness: t.brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    primaryContainer:
        Color.alphaBlend(t.accent.withValues(alpha: 0.14), t.surface),
    onPrimaryContainer: t.ink,
    secondary: t.highlight,
    onSecondary: onHighlight,
    secondaryContainer:
        Color.alphaBlend(t.highlight.withValues(alpha: 0.15), t.surface),
    onSecondaryContainer: t.ink,
    tertiary: t.positive,
    onTertiary: onPositive,
    error: t.critical,
    onError: onCritical,
    errorContainer:
        Color.alphaBlend(t.critical.withValues(alpha: 0.14), t.surface),
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
    outlineVariant: t.outline.withValues(alpha: 0.65),
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
  final shapeS =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSmall));
  final shapeM = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(t.radiusMedium));

  final buttonText = TextStyle(
    fontFamily: t.bodyFamily,
    fontWeight: ConvoyDesignTokens.resolveWeight(t.bodyFamily, FontWeight.w700),
    fontSize: t.sp(14.5),
    letterSpacing: t.uppercaseLabels ? 0.9 : 0.1,
  );
  final buttonMin = Size(48, t.minTouchTarget.clamp(48.0, 64.0).toDouble());

  return base.copyWith(
    scaffoldBackgroundColor: t.canvas,
    canvasColor: t.canvas,
    textTheme: text.copyWith(
      headlineMedium: t.display(26),
      headlineSmall: t.display(22),
      titleLarge: t.display(20),
      titleMedium: text.titleMedium?.copyWith(
        fontFamily: t.bodyFamily,
        fontSize: t.sp(16),
        fontWeight:
            ConvoyDesignTokens.resolveWeight(t.bodyFamily, FontWeight.w700),
        color: t.ink,
      ),
      bodyLarge: t.body(15),
      bodyMedium: t.body(14),
      bodySmall: t.body(12.5, color: t.inkMuted),
    ),
    extensions: [t],
    appBarTheme: AppBarTheme(
      backgroundColor: t.canvas,
      foregroundColor: t.inkOnCanvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: t.display(22, color: t.inkOnCanvas),
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
        disabledBackgroundColor: t.outline.withValues(alpha: 0.45),
        disabledForegroundColor: t.inkMuted,
        minimumSize: buttonMin,
        padding: EdgeInsets.symmetric(
            horizontal: t.space(4), vertical: t.space(2.5)),
        shape: shapeM,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.ink,
        backgroundColor: t.surfaceRaised,
        minimumSize: buttonMin,
        padding: EdgeInsets.symmetric(
            horizontal: t.space(3.5), vertical: t.space(2.5)),
        side: BorderSide(color: t.outline, width: t.borderWidth),
        shape: shapeM,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.accent,
        minimumSize: buttonMin,
        shape: shapeS,
        textStyle: buttonText,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.surfaceRaised,
      selectedColor: Color.alphaBlend(t.accent.withValues(alpha: 0.16), t.surface),
      side: BorderSide(color: t.outline, width: t.borderWidth),
      shape: shapeS,
      labelStyle: t.caption(color: t.ink),
      padding: EdgeInsets.symmetric(
          horizontal: t.space(2), vertical: t.space(1)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surfaceRaised,
      contentPadding: EdgeInsets.symmetric(
          horizontal: t.space(3.5), vertical: t.space(3)),
      hintStyle: t.body(14, color: t.inkMuted),
      labelStyle: t.body(14, color: t.inkMuted, weight: FontWeight.w600),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusSmall),
        borderSide: BorderSide(color: t.outline, width: t.borderWidth),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusSmall),
        borderSide: BorderSide(color: t.outline, width: t.borderWidth),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radiusSmall),
        borderSide: BorderSide(color: t.accent, width: t.borderWidth + 0.8),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular((t.radiusSmall * 0.45).clamp(4, 8))),
      side: WidgetStateBorderSide.resolveWith((states) => BorderSide(
            color: states.contains(WidgetState.disabled)
                ? t.outline.withValues(alpha: 0.55)
                : t.outline,
            width: t.borderWidth + 0.4,
          )),
      fillColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) {
          return s.contains(WidgetState.selected)
              ? t.accent.withValues(alpha: 0.45)
              : Colors.transparent;
        }
        return s.contains(WidgetState.selected) ? t.accent : Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll(t.onAccent),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.surfaceRaised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(shapeM),
      ),
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
      contentTextStyle: t.body(14,
          color: dark ? t.ink : t.surface, weight: FontWeight.w600),
      shape: shapeM,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radiusLarge),
        side: BorderSide(color: t.outline, width: t.borderWidth),
      ),
      titleTextStyle: t.display(21),
      contentTextStyle: t.body(14),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: t.inkMuted.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(t.radiusLarge)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? t.onAccent : t.inkMuted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? t.accent : t.outline),
      trackOutlineColor: WidgetStatePropertyAll(t.outline),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: t.accent,
      inactiveTrackColor: t.outline,
      thumbColor: t.accent,
      overlayColor: t.accent.withValues(alpha: 0.14),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: t.accent,
        selectedForegroundColor: t.onAccent,
        foregroundColor: t.ink,
        side: BorderSide(color: t.outline, width: t.borderWidth),
        shape: shapeS,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor:
          Color.alphaBlend(t.accent.withValues(alpha: 0.12), t.surface),
      indicatorShape: shapeM,
      height: 68,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
