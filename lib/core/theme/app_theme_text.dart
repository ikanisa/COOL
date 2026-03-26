import 'package:flutter/material.dart';

import 'cool_foundations.dart';

/// Typography constants and [TextTheme] builder for the Cool design system.
///
/// Dual-font strategy inspired by Mobio's "Claymorphic Utility":
/// - **BarlowCondensed** for display/headline — impact & brand authority
/// - **Barlow** for title — structural hierarchy
/// - **Inter** for body/label — optimised for dense reading (Groups, Admin, MoMo)
abstract final class AppThemeText {
  // ── Weight aliases ──────────────────────────────────────────────────
  static const black = FontWeight.w900;
  static const extraBold = FontWeight.w800;
  static const bold = FontWeight.w800;
  static const semibold = FontWeight.w700;
  static const medium = FontWeight.w600;
  static const regular = FontWeight.w500;

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

  /// Builds the full [TextTheme] for the given [brightness] and [semanticColors].
  ///
  /// Display/Headline → BarlowCondensed (impact)
  /// Title → Barlow (structural)
  /// Body/Label → Inter (readable, lighter weights for dense content)
  static TextTheme build({
    required Brightness brightness,
    required CoolSemanticColors semanticColors,
  }) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark()
        : ThemeData.light();
    final barlowText = GoogleFonts.barlowTextTheme(base.textTheme);
    final condensedText = GoogleFonts.barlowCondensedTextTheme(base.textTheme);
    final interText = GoogleFonts.interTextTheme(base.textTheme);

    return barlowText.copyWith(
      // ── Display (BarlowCondensed — hero impact) ─────────────────────
      displayLarge: condensedText.displayLarge?.copyWith(
        fontSize: AppThemeText.displayLarge,
        fontWeight: black,
        color: semanticColors.primaryText,
        letterSpacing: -2.0,
        height: 1.1,
      ),
      displayMedium: condensedText.displayMedium?.copyWith(
        fontSize: AppThemeText.displayMedium,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -1.6,
        height: 1.1,
      ),
      displaySmall: condensedText.displaySmall?.copyWith(
        fontSize: AppThemeText.displaySmall,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -1.2,
        height: 1.12,
      ),

      // ── Headline (BarlowCondensed — section authority) ──────────────
      headlineLarge: condensedText.headlineLarge?.copyWith(
        fontSize: AppThemeText.headlineLarge,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -1.0,
        height: 1.15,
      ),
      headlineMedium: condensedText.headlineMedium?.copyWith(
        fontSize: AppThemeText.headlineMedium,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -0.8,
        height: 1.18,
      ),
      headlineSmall: condensedText.headlineSmall?.copyWith(
        fontSize: AppThemeText.headlineSmall,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -0.6,
        height: 1.2,
      ),

      // ── Title (Barlow — structural hierarchy) ──────────────────────
      titleLarge: barlowText.titleLarge?.copyWith(
        fontSize: AppThemeText.titleLarge,
        fontWeight: bold,
        color: semanticColors.primaryText,
        letterSpacing: -0.4,
        height: 1.22,
      ),
      titleMedium: barlowText.titleMedium?.copyWith(
        fontSize: AppThemeText.titleMedium,
        fontWeight: bold,
        color: semanticColors.primaryText,
        letterSpacing: -0.3,
        height: 1.24,
      ),
      titleSmall: barlowText.titleSmall?.copyWith(
        fontSize: AppThemeText.titleSmall,
        fontWeight: semibold,
        color: semanticColors.primaryText,
        letterSpacing: -0.2,
        height: 1.25,
      ),

      // ── Body (Inter — optimised for dense reading) ─────────────────
      bodyLarge: interText.bodyLarge?.copyWith(
        fontSize: AppThemeText.bodyLarge,
        fontWeight: regular,
        color: semanticColors.primaryText,
        height: 1.5,
      ),
      bodyMedium: interText.bodyMedium?.copyWith(
        fontSize: AppThemeText.bodyMedium,
        fontWeight: FontWeight.w400,
        color: semanticColors.primaryText,
        height: 1.5,
      ),
      bodySmall: interText.bodySmall?.copyWith(
        fontSize: AppThemeText.bodySmall,
        fontWeight: FontWeight.w400,
        color: semanticColors.secondaryText,
        height: 1.5,
      ),

      // ── Label (Inter — metadata & captions) ────────────────────────
      labelLarge: interText.labelLarge?.copyWith(
        fontSize: AppThemeText.labelLarge,
        fontWeight: semibold,
        color: semanticColors.primaryText,
        height: 1.2,
      ),
      labelMedium: interText.labelMedium?.copyWith(
        fontSize: AppThemeText.labelMedium,
        fontWeight: semibold,
        color: semanticColors.primaryText,
        height: 1.2,
      ),
      labelSmall: interText.labelSmall?.copyWith(
        fontSize: AppThemeText.labelSmall,
        fontWeight: medium,
        color: semanticColors.secondaryText,
        letterSpacing: 0.5,
        height: 1.2,
      ),
    );
  }
}
