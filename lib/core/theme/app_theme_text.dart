import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';

import 'cool_foundations.dart';

/// Typography constants and [TextTheme] builder for the minimalist mobile UI.
///
/// Font stack:
/// - **Manrope** — Display, headings, titles, and body copy
/// - **Inter** — Labels, utility text, and controls
/// - **DM Mono** — Numeric/technical values when a fixed-width rhythm helps
abstract final class AppThemeText {
  static final String displayFontFamily =
      GoogleFonts.manrope().fontFamily ?? 'Manrope';
  static final String bodyFontFamily =
      GoogleFonts.manrope().fontFamily ?? 'Manrope';
  static final String labelFontFamily =
      GoogleFonts.inter().fontFamily ?? 'Inter';
  static final String monoFontFamily =
      GoogleFonts.dmMono().fontFamily ?? 'DM Mono';

  static const black = FontWeight.w700;
  static const extraBold = FontWeight.w700;
  static const bold = FontWeight.w700;
  static const semibold = FontWeight.w600;
  static const medium = FontWeight.w500;
  static const regular = FontWeight.w500;

  static const displayLarge = 40.0;
  static const displayMedium = 34.0;
  static const displaySmall = 28.0;
  static const headlineLarge = 24.0;
  static const headlineMedium = 20.0;
  static const headlineSmall = 18.0;
  static const titleLarge = 18.0;
  static const titleMedium = 16.0;
  static const titleSmall = 14.0;
  static const bodyLarge = 16.0;
  static const bodyMedium = 14.0;
  static const bodySmall = 14.0;
  static const labelLarge = 14.0;
  static const labelMedium = 14.0;
  static const labelSmall = 14.0;

  static TextTheme build({
    required Brightness brightness,
    required CoolSemanticColors semanticColors,
  }) {
    final base = ThemeData(brightness: brightness);
    final baseText = base.textTheme;
    final displayText = GoogleFonts.manropeTextTheme(baseText);
    final bodyText = GoogleFonts.manropeTextTheme(baseText);
    final labelText = GoogleFonts.interTextTheme(baseText);

    return baseText.copyWith(
      displayLarge: displayText.displayLarge?.copyWith(
        fontSize: AppThemeText.displayLarge,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -1.2,
        height: 1.0,
      ),
      displayMedium: displayText.displayMedium?.copyWith(
        fontSize: AppThemeText.displayMedium,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -0.9,
        height: 1.02,
      ),
      displaySmall: displayText.displaySmall?.copyWith(
        fontSize: AppThemeText.displaySmall,
        fontWeight: bold,
        color: semanticColors.primaryText,
        letterSpacing: -0.6,
        height: 1.05,
      ),

      headlineLarge: displayText.headlineLarge?.copyWith(
        fontSize: AppThemeText.headlineLarge,
        fontWeight: bold,
        color: semanticColors.primaryText,
        letterSpacing: -0.4,
        height: 1.12,
      ),
      headlineMedium: displayText.headlineMedium?.copyWith(
        fontSize: AppThemeText.headlineMedium,
        fontWeight: semibold,
        color: semanticColors.primaryText,
        letterSpacing: -0.2,
        height: 1.2,
      ),
      headlineSmall: displayText.headlineSmall?.copyWith(
        fontSize: AppThemeText.headlineSmall,
        fontWeight: semibold,
        color: semanticColors.primaryText,
        letterSpacing: -0.1,
        height: 1.22,
      ),

      titleLarge: bodyText.titleLarge?.copyWith(
        fontSize: AppThemeText.titleLarge,
        fontWeight: semibold,
        color: semanticColors.primaryText,
        letterSpacing: -0.1,
        height: 1.28,
      ),
      titleMedium: bodyText.titleMedium?.copyWith(
        fontSize: AppThemeText.titleMedium,
        fontWeight: semibold,
        color: semanticColors.primaryText,
        height: 1.3,
      ),
      titleSmall: bodyText.titleSmall?.copyWith(
        fontSize: AppThemeText.titleSmall,
        fontWeight: medium,
        color: semanticColors.primaryText,
        height: 1.3,
      ),

      bodyLarge: bodyText.bodyLarge?.copyWith(
        fontSize: AppThemeText.bodyLarge,
        fontWeight: regular,
        color: semanticColors.primaryText,
        height: 1.45,
      ),
      bodyMedium: bodyText.bodyMedium?.copyWith(
        fontSize: AppThemeText.bodyMedium,
        fontWeight: medium,
        color: semanticColors.primaryText,
        height: 1.45,
      ),
      bodySmall: bodyText.bodySmall?.copyWith(
        fontSize: AppThemeText.bodySmall,
        fontWeight: regular,
        color: semanticColors.secondaryText,
        height: 1.4,
      ),

      labelLarge: labelText.labelLarge?.copyWith(
        fontSize: AppThemeText.labelLarge,
        fontWeight: semibold,
        color: semanticColors.primaryText,
        height: 1.2,
      ),
      labelMedium: labelText.labelMedium?.copyWith(
        fontSize: AppThemeText.labelMedium,
        fontWeight: semibold,
        color: semanticColors.primaryText,
        height: 1.2,
      ),
      labelSmall: labelText.labelSmall?.copyWith(
        fontSize: AppThemeText.labelSmall,
        fontWeight: medium,
        color: semanticColors.secondaryText,
        letterSpacing: 0.0,
        height: 1.2,
      ),
    );
  }
}
