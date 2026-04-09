import 'package:flutter/material.dart';

import 'cool_foundations.dart';

/// Typography constants and [TextTheme] builder — ROUGEBLACK system.
///
/// Font stack:
/// - **Space Grotesk** — Display/Headline (bold geometric, w700–w900, unmistakable hierarchy)
/// - **Inter** — Title/Body/Label (readable, w400–w700)
/// - **DM Mono** — Values, IDs, aliases (via CoolTextStyles.mono/mobiLabel/mobiValue)
abstract final class AppThemeText {
  // ── Weight aliases ──────────────────────────────────────────────────
  static const black = FontWeight.w900;
  static const extraBold = FontWeight.w800;
  static const bold = FontWeight.w700;
  static const semibold = FontWeight.w700;
  static const medium = FontWeight.w600;
  static const regular = FontWeight.w400;

  // ── Named sizes (Space Grotesk × Inter scale) ──────────────────────────
  static const displayLarge = 60.0;   // Space Grotesk
  static const displayMedium = 52.0;  // Space Grotesk
  static const displaySmall = 44.0;   // Space Grotesk
  static const headlineLarge = 38.0;
  static const headlineMedium = 32.0;
  static const headlineSmall = 24.0;
  static const titleLarge = 18.0;
  static const titleMedium = 16.0;
  static const titleSmall = 14.0;
  static const bodyLarge = 16.0;
  static const bodyMedium = 14.0;
  static const bodySmall = 15.0;
  static const labelLarge = 14.0;
  static const labelMedium = 14.0;
  static const labelSmall = 14.0;

  /// Display/Headline → Space Grotesk (w700–w900, bold geometric authority)
  /// Title → Inter (w500–w600, structural)
  /// Body → Inter (w400–w500, readable)
  /// Label → Inter (w500–w600, compact)
  static TextTheme build({
    required Brightness brightness,
    required CoolSemanticColors semanticColors,
  }) {
    final base = ThemeData(brightness: brightness);
    final groteskText = GoogleFonts.spaceGroteskTextTheme(base.textTheme);
    final interText = GoogleFonts.interTextTheme(base.textTheme);

    return interText.copyWith(
      // ── Display (Space Grotesk — bold geometric hero) ───────────────
      displayLarge: groteskText.displayLarge?.copyWith(
        fontSize: AppThemeText.displayLarge,
        fontWeight: black,
        color: semanticColors.primaryText,
        letterSpacing: -2.5,
        height: 0.96,
      ),
      displayMedium: groteskText.displayMedium?.copyWith(
        fontSize: AppThemeText.displayMedium,
        fontWeight: black,
        color: semanticColors.primaryText,
        letterSpacing: -2.0,
        height: 1.0,
      ),
      displaySmall: groteskText.displaySmall?.copyWith(
        fontSize: AppThemeText.displaySmall,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -1.6,
        height: 1.05,
      ),

      // ── Headline (Space Grotesk — section authority) ─────────────────
      headlineLarge: groteskText.headlineLarge?.copyWith(
        fontSize: AppThemeText.headlineLarge,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -1.0,
        height: 1.08,
      ),
      headlineMedium: groteskText.headlineMedium?.copyWith(
        fontSize: AppThemeText.headlineMedium,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -0.8,
        height: 1.1,
      ),
      headlineSmall: groteskText.headlineSmall?.copyWith(
        fontSize: AppThemeText.headlineSmall,
        fontWeight: bold,
        color: semanticColors.primaryText,
        letterSpacing: -0.6,
        height: 1.15,
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
