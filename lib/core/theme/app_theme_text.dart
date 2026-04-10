import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';

import 'cool_foundations.dart';

/// Typography constants and [TextTheme] builder — Tactile Monolith system.
///
/// Font stack:
/// - **Space Grotesk** — Display/Headline (bold geometric, w700–w900, stamped authority)
/// - **Manrope** — Title/Body (premium editorial, geometric, w400–w700)
/// - **Inter** — Label (utility clarity, w500–w600)
/// - **DM Mono** — Values, IDs, aliases (via CoolTextStyles.mono/mobiLabel/mobiValue)
abstract final class AppThemeText {
  static final String displayFontFamily =
      GoogleFonts.spaceGrotesk().fontFamily ?? 'Space Grotesk';
  static final String bodyFontFamily =
      GoogleFonts.manrope().fontFamily ?? 'Manrope';
  static final String labelFontFamily =
      GoogleFonts.inter().fontFamily ?? 'Inter';
  static final String monoFontFamily =
      GoogleFonts.dmMono().fontFamily ?? 'DM Mono';

  // ── Weight aliases ──────────────────────────────────────────────────
  static const black = FontWeight.w900;
  static const extraBold = FontWeight.w800;
  static const bold = FontWeight.w700;
  static const semibold = FontWeight.w700;
  static const medium = FontWeight.w600;
  static const regular = FontWeight.w400;

  // ── Named sizes (Space Grotesk × Inter scale) ──────────────────────────
  static const displayLarge = 60.0; // Space Grotesk
  static const displayMedium = 52.0; // Space Grotesk
  static const displaySmall = 44.0; // Space Grotesk
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
  /// Title → Manrope (w600–w700, premium editorial)
  /// Body → Manrope (w400–w500, readable geometric)
  /// Label → Inter (w500–w600, compact utility)
  static TextTheme build({
    required Brightness brightness,
    required CoolSemanticColors semanticColors,
  }) {
    final base = ThemeData(brightness: brightness);
    final baseText = base.textTheme;
    final displayText = GoogleFonts.spaceGroteskTextTheme(baseText);
    final bodyText = GoogleFonts.manropeTextTheme(baseText);
    final labelText = GoogleFonts.interTextTheme(baseText);

    return baseText.copyWith(
      // ── Display (Space Grotesk — bold geometric hero) ───────────────
      displayLarge: displayText.displayLarge?.copyWith(
        fontSize: AppThemeText.displayLarge,
        fontWeight: black,
        color: semanticColors.primaryText,
        letterSpacing: -2.4, // -0.04em at 60px
        height: 0.96,
      ),
      displayMedium: displayText.displayMedium?.copyWith(
        fontSize: AppThemeText.displayMedium,
        fontWeight: black,
        color: semanticColors.primaryText,
        letterSpacing: -2.1, // -0.04em at 52px
        height: 1.0,
      ),
      displaySmall: displayText.displaySmall?.copyWith(
        fontSize: AppThemeText.displaySmall,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -1.76, // -0.04em at 44px
        height: 1.05,
      ),

      // ── Headline (Space Grotesk — section authority) ─────────────────
      headlineLarge: displayText.headlineLarge?.copyWith(
        fontSize: AppThemeText.headlineLarge,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -1.52, // -0.04em at 38px
        height: 1.08,
      ),
      headlineMedium: displayText.headlineMedium?.copyWith(
        fontSize: AppThemeText.headlineMedium,
        fontWeight: extraBold,
        color: semanticColors.primaryText,
        letterSpacing: -1.28, // -0.04em at 32px
        height: 1.1,
      ),
      headlineSmall: displayText.headlineSmall?.copyWith(
        fontSize: AppThemeText.headlineSmall,
        fontWeight: bold,
        color: semanticColors.primaryText,
        letterSpacing: -1.2, // -0.05em at 24px
        height: 1.15,
      ),

      // ── Title (Manrope — premium editorial hierarchy) ──────────────
      titleLarge: bodyText.titleLarge?.copyWith(
        fontSize: AppThemeText.titleLarge,
        fontWeight: semibold,
        color: semanticColors.primaryText,
        letterSpacing: -0.2,
        height: 1.3,
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

      // ── Body (Manrope — readable geometric content) ─────────────────
      bodyLarge: bodyText.bodyLarge?.copyWith(
        fontSize: AppThemeText.bodyLarge,
        fontWeight: regular,
        color: semanticColors.primaryText,
        height: 1.5,
      ),
      bodyMedium: bodyText.bodyMedium?.copyWith(
        fontSize: AppThemeText.bodyMedium,
        fontWeight: medium,
        color: semanticColors.primaryText,
        height: 1.5,
      ),
      bodySmall: bodyText.bodySmall?.copyWith(
        fontSize: AppThemeText.bodySmall,
        fontWeight: regular,
        color: semanticColors.secondaryText,
        height: 1.5,
      ),

      // ── Label (Inter — compact metadata) ────────────────────────────
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
        fontWeight: semibold,
        color: semanticColors.secondaryText,
        letterSpacing: 1.0, // wide tracking for mobi-label
        height: 1.2,
      ),
    );
  }
}
