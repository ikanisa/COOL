import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'cool_palette.dart';

/// Typography constants and [TextTheme] builder for the Cool design system.
///
/// Uses a larger, heavier Manrope scale with short-copy hierarchy.
abstract final class AppThemeText {
  // ── Weight aliases ──────────────────────────────────────────────────
  static const black = FontWeight.w800;
  static const extraBold = FontWeight.w800;
  static const bold = FontWeight.w700;
  static const semibold = FontWeight.w700;
  static const medium = FontWeight.w600;
  static const regular = FontWeight.w600;

  // ── Named sizes ─────────────────────────────────────────────────────
  static const displayLarge = 56.0;
  static const displayMedium = 48.0;
  static const displaySmall = 40.0;
  static const headlineLarge = 36.0;
  static const headlineMedium = 30.0;
  static const headlineSmall = 26.0;
  static const titleLarge = 24.0;
  static const titleMedium = 22.0;
  static const titleSmall = 20.0;
  static const bodyLarge = 18.0;
  static const bodyMedium = 17.0;
  static const bodySmall = 15.0;
  static const labelLarge = 16.0;
  static const labelMedium = 15.0;
  static const labelSmall = 14.0;

  /// Builds the full [TextTheme] for the given [brightness] and [palette].
  static TextTheme build({
    required Brightness brightness,
    required CoolPalette palette,
  }) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark()
        : ThemeData.light();
    final baseText = GoogleFonts.manropeTextTheme(base.textTheme);

    return baseText.copyWith(
      displayLarge: baseText.displayLarge?.copyWith(
        fontSize: AppThemeText.displayLarge,
        fontWeight: black,
        color: palette.text,
        letterSpacing: -2.0,
        height: 1.1,
      ),
      displayMedium: baseText.displayMedium?.copyWith(
        fontSize: AppThemeText.displayMedium,
        fontWeight: extraBold,
        color: palette.text,
        letterSpacing: -1.6,
        height: 1.1,
      ),
      displaySmall: baseText.displaySmall?.copyWith(
        fontSize: AppThemeText.displaySmall,
        fontWeight: extraBold,
        color: palette.text,
        letterSpacing: -1.2,
        height: 1.12,
      ),
      headlineLarge: baseText.headlineLarge?.copyWith(
        fontSize: AppThemeText.headlineLarge,
        fontWeight: extraBold,
        color: palette.text,
        letterSpacing: -1.0,
        height: 1.15,
      ),
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontSize: AppThemeText.headlineMedium,
        fontWeight: extraBold,
        color: palette.text,
        letterSpacing: -0.8,
        height: 1.18,
      ),
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontSize: AppThemeText.headlineSmall,
        fontWeight: extraBold,
        color: palette.text,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontSize: AppThemeText.titleLarge,
        fontWeight: bold,
        color: palette.text,
        letterSpacing: -0.4,
        height: 1.22,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontSize: AppThemeText.titleMedium,
        fontWeight: bold,
        color: palette.text,
        letterSpacing: -0.3,
        height: 1.24,
      ),
      titleSmall: baseText.titleSmall?.copyWith(
        fontSize: AppThemeText.titleSmall,
        fontWeight: semibold,
        color: palette.text,
        height: 1.26,
      ),
      bodyLarge: baseText.bodyLarge?.copyWith(
        fontSize: AppThemeText.bodyLarge,
        fontWeight: semibold,
        color: palette.text,
        letterSpacing: -0.2,
        height: 1.38,
      ),
      bodyMedium: baseText.bodyMedium?.copyWith(
        fontSize: AppThemeText.bodyMedium,
        fontWeight: semibold,
        color: palette.text,
        letterSpacing: -0.1,
        height: 1.42,
      ),
      bodySmall: baseText.bodySmall?.copyWith(
        fontSize: AppThemeText.bodySmall,
        fontWeight: medium,
        color: palette.text2,
        letterSpacing: -0.1,
        height: 1.4,
      ),
      labelLarge: baseText.labelLarge?.copyWith(
        fontSize: AppThemeText.labelLarge,
        fontWeight: bold,
        color: palette.text,
        height: 1.2,
      ),
      labelMedium: baseText.labelMedium?.copyWith(
        fontSize: AppThemeText.labelMedium,
        fontWeight: bold,
        color: palette.text,
        height: 1.2,
      ),
      labelSmall: baseText.labelSmall?.copyWith(
        fontSize: AppThemeText.labelSmall,
        fontWeight: medium,
        color: palette.text2,
        letterSpacing: 0.15,
        height: 1.2,
      ),
    );
  }
}
