import 'package:flutter/material.dart';

import 'cool_foundations.dart';

/// Typography constants and [TextTheme] builder — Mobi × Rayon system.
///
/// Font stack:
/// - **Barlow Condensed** — Display/Headline (uppercase, w800–w900, condensed impact)
/// - **Inter** — Title/Body/Label (readable, w400–w700)
/// - **JetBrains Mono** — Values, IDs, labels (via CoolTextStyles.mono/mobiLabel/mobiValue)
abstract final class AppThemeText {
  // ── Weight aliases ──────────────────────────────────────────────────
  static const black = FontWeight.w900;
  static const extraBold = FontWeight.w800;
  static const bold = FontWeight.w700;
  static const semibold = FontWeight.w700;
  static const medium = FontWeight.w600;
  static const regular = FontWeight.w400;

  // ── Named sizes (Mobi × Rayon scale) ────────────────────────────────
  static const displayLarge = 56.0;
  static const displayMedium = 48.0;
  static const displaySmall = 40.0;
  static const headlineLarge = 36.0;
  static const headlineMedium = 30.0;
  static const headlineSmall = 20.0;
  static const titleLarge = 18.0;
  static const titleMedium = 16.0;
  static const titleSmall = 14.0;
  static const bodyLarge = 16.0;
  static const bodyMedium = 14.0;
  static const bodySmall = 15.0;
  static const labelLarge = 14.0;
  static const labelMedium = 14.0;
  static const labelSmall = 14.0;

  /// Display/Headline → Barlow Condensed (w800, uppercase intent)
  /// Title → Inter (w500–w600, structural)
  /// Body → Inter (w400–w500, readable)
  /// Label → Inter (w500–w600, compact)
  static TextTheme build({
    required Brightness brightness,
    required CoolSemanticColors semanticColors,
  }) {
    final base = ThemeData(brightness: brightness);
    final condensedText = GoogleFonts.barlowCondensedTextTheme(base.textTheme);
    final interText = GoogleFonts.interTextTheme(base.textTheme);

    return interText.copyWith(
      // ── Display (Barlow Condensed — uppercase hero impact) ───────────
      displayLarge: condensedText.displayLarge?.copyWith(
        fontSize: AppThemeText.displayLarge,
        fontWeight: black,
        color: semanticColors.primaryText,
        letterSpacing: -2.0,
        height: 1.0,
      ),
      displayMedium: condensedText.displayMedium?.copyWith(
        fontSize: AppThemeText.displayMedium,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -1.6,
        height: 1.05,
      ),
      displaySmall: condensedText.displaySmall?.copyWith(
        fontSize: AppThemeText.displaySmall,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -1.2,
        height: 1.1,
      ),

      // ── Headline (Barlow Condensed — section authority) ──────────────
      headlineLarge: condensedText.headlineLarge?.copyWith(
        fontSize: AppThemeText.headlineLarge,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -0.6,
        height: 1.1,
      ),
      headlineMedium: condensedText.headlineMedium?.copyWith(
        fontSize: AppThemeText.headlineMedium,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -0.48,
        height: 1.15,
      ),
      headlineSmall: condensedText.headlineSmall?.copyWith(
        fontSize: AppThemeText.headlineSmall,
        fontWeight: bold,
        color: semanticColors.primaryText,
        letterSpacing: -0.4,
        height: 1.2,
      ),

      // ── Title (Inter — structural hierarchy) ────────────────────────
      titleLarge: interText.titleLarge?.copyWith(
        fontSize: AppThemeText.titleLarge,
        fontWeight: semibold,
        color: semanticColors.primaryText,
        letterSpacing: -0.2,
        height: 1.3,
      ),
      titleMedium: interText.titleMedium?.copyWith(
        fontSize: AppThemeText.titleMedium,
        fontWeight: semibold,
        color: semanticColors.primaryText,
        height: 1.3,
      ),
      titleSmall: interText.titleSmall?.copyWith(
        fontSize: AppThemeText.titleSmall,
        fontWeight: medium,
        color: semanticColors.primaryText,
        height: 1.3,
      ),

      // ── Body (Inter — readable content) ─────────────────────────────
      bodyLarge: interText.bodyLarge?.copyWith(
        fontSize: AppThemeText.bodyLarge,
        fontWeight: regular,
        color: semanticColors.primaryText,
        height: 1.5,
      ),
      bodyMedium: interText.bodyMedium?.copyWith(
        fontSize: AppThemeText.bodyMedium,
        fontWeight: medium,
        color: semanticColors.primaryText,
        height: 1.5,
      ),
      bodySmall: interText.bodySmall?.copyWith(
        fontSize: AppThemeText.bodySmall,
        fontWeight: regular,
        color: semanticColors.secondaryText,
        height: 1.5,
      ),

      // ── Label (Inter — compact metadata) ────────────────────────────
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
        fontWeight: semibold,
        color: semanticColors.secondaryText,
        letterSpacing: 1.0, // wide tracking for mobi-label
        height: 1.2,
      ),
    );
  }
}
