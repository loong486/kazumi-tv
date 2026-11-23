import 'package:flutter/material.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/theme.dart';

class TvLayout {
  TvLayout._();

  static const EdgeInsets overscanPadding = EdgeInsets.symmetric(
    horizontal: 36,
    vertical: 24,
  );

  static const double railCollapsedWidth = 76;
  static const double railExpandedWidth = 216;
  static const double gridSpacing = 18;
  static const double focusBorderWidth = 2.5;
  static const double focusGlowBlur = 10.0;
  static const double focusGlowSpread = 0.5;
  static const double focusScale = 1.03;
  static const Duration focusAnimationDuration = Duration(milliseconds: 140);
  static const double cardBorderRadius = 14;
}

class TvTheme {
  TvTheme._();

  static SwitchThemeData _buildSwitchTheme(
    ColorScheme colorScheme, {
    required bool isDark,
  }) {
    return SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onSurface.withValues(alpha: 0.12);
          }
          return colorScheme.surfaceContainerHighest.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary;
        }
        return isDark
            ? const Color(0xFF2B3245)
            : colorScheme.surfaceContainerHighest;
      }),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.surface;
          }
          return colorScheme.onSurface.withValues(alpha: 0.38);
        }
        if (states.contains(WidgetState.selected)) {
          return colorScheme.onPrimary;
        }
        return colorScheme.onSurfaceVariant;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.transparent;
        }
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.onSurface.withValues(alpha: 0.12);
        }
        return colorScheme.outline;
      }),
    );
  }

  static ThemeData buildTheme({
    required Brightness brightness,
    Color? seedColor,
    ColorScheme? colorScheme,
    String? fontFamily,
    bool oledEnhance = false,
  }) {
    final effectiveColorScheme = colorScheme ??
        ColorScheme.fromSeed(
          seedColor: seedColor ?? Colors.green,
          brightness: brightness,
        );

    final isDark = brightness == Brightness.dark;
    final scaffoldColor = isDark
        ? (oledEnhance ? Colors.black : const Color(0xFF0D1017))
        : effectiveColorScheme.surface;
    final surfaceColor = isDark
        ? (oledEnhance ? Colors.black : const Color(0xFF151924))
        : effectiveColorScheme.surface;
    final containerHigh = isDark
        ? (oledEnhance ? const Color(0xFF10131A) : const Color(0xFF1E2433))
        : effectiveColorScheme.surfaceContainerHigh;

    final adjustedScheme = isDark
        ? effectiveColorScheme.copyWith(
            surface: surfaceColor,
            surfaceContainer: const Color(0xFF181D29),
            surfaceContainerHigh: containerHigh,
            surfaceContainerHighest: const Color(0xFF262D40),
          )
        : effectiveColorScheme;

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      colorScheme: adjustedScheme,
      scaffoldBackgroundColor: scaffoldColor,
      focusColor: adjustedScheme.primary.withValues(alpha: 0.24),
      hoverColor: adjustedScheme.primary.withValues(alpha: 0.12),
      progressIndicatorTheme: progressIndicatorTheme2024,
      sliderTheme: sliderTheme2024,
      pageTransitionsTheme: pageTransitionsTheme2024,
      switchTheme: _buildSwitchTheme(adjustedScheme, isDark: isDark),
      dialogTheme: DialogThemeData(
        backgroundColor: containerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF23293A),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );

    if (isDark && oledEnhance) {
      final oled = oledDarkTheme(base);
      return oled.copyWith(
        focusColor: base.focusColor,
        dialogTheme: base.dialogTheme,
        snackBarTheme: base.snackBarTheme,
        switchTheme: _buildSwitchTheme(oled.colorScheme, isDark: true),
      );
    }
    return base;
  }
}
