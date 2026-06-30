import 'package:flutter/material.dart';

import 'collect_runtime_typography.dart';

class CollectTypography {
  const CollectTypography._();

  static const _family = CollectRuntimeTypography.fontFamilyFallback;
  static const _displayFamily =
      CollectRuntimeTypography.displayFontFamilyFallback;
  static const _monoFamily = CollectRuntimeTypography.monoFontFamilyFallback;

  static const _tabular = <FontFeature>[FontFeature.tabularFigures()];

  static TextTheme textTheme(Color textPrimary, Color textSecondary) {
    return TextTheme(
      displaySmall: _displayStyle(48, 1.17, FontWeight.w700, textPrimary),
      headlineLarge: _displayStyle(32, 1.25, FontWeight.w600, textPrimary),
      headlineMedium: _displayStyle(24, 1.33, FontWeight.w600, textPrimary),
      headlineSmall: _displayStyle(20, 1.4, FontWeight.w600, textPrimary),
      titleLarge: _displayStyle(20, 1.4, FontWeight.w600, textPrimary),
      titleMedium: _style(16, 1.5, FontWeight.w600, textPrimary),
      titleSmall: _style(14, 1.45, FontWeight.w600, textPrimary),
      bodyLarge: _style(18, 1.56, FontWeight.w400, textPrimary),
      bodyMedium: _style(16, 1.5, FontWeight.w400, textSecondary),
      bodySmall: _style(14, 1.45, FontWeight.w400, textSecondary),
      labelLarge: _style(14, 1.3, FontWeight.w600, textPrimary),
      labelMedium: _label(12, 1.33, textSecondary),
      labelSmall: _label(11, 1.3, textSecondary),
    );
  }

  static TextStyle amountHero(Color color) => _displayStyle(
    42,
    1.02,
    FontWeight.w700,
    color,
  ).copyWith(fontFeatures: _tabular);

  static TextStyle amountDisplay(Color color) => _displayStyle(
    48,
    1.0,
    FontWeight.w700,
    color,
  ).copyWith(fontFeatures: _tabular);

  static TextStyle amountLarge(Color color) => _displayStyle(
    28,
    1.08,
    FontWeight.w700,
    color,
  ).copyWith(fontFeatures: _tabular);

  static TextStyle amountCompact(Color color) =>
      _style(15, 1.25, FontWeight.w700, color).copyWith(fontFeatures: _tabular);

  static TextStyle mono(Color color) =>
      _style(12, 1.33, FontWeight.w500, color).copyWith(
        fontFamilyFallback: _monoFamily,
        fontFeatures: _tabular,
        letterSpacing: 0.6,
      );

  static TextStyle collectIdDisplay(Color color) =>
      _style(28, 1.12, FontWeight.w700, color).copyWith(
        fontFamilyFallback: _monoFamily,
        fontFeatures: _tabular,
        letterSpacing: 2,
      );

  static TextStyle transactionMeta(Color color) =>
      _style(12, 1.35, FontWeight.w500, color).copyWith(
        fontFamilyFallback: _monoFamily,
        fontFeatures: _tabular,
        letterSpacing: 0.5,
      );

  static TextStyle eyebrowLabel(Color color) => _style(
    11,
    1.3,
    FontWeight.w700,
    color,
  ).copyWith(fontFamilyFallback: _monoFamily, letterSpacing: 0.8);

  static TextStyle _label(double size, double height, Color color) {
    return _style(
      size,
      height,
      FontWeight.w500,
      color,
    ).copyWith(fontFamilyFallback: _monoFamily, letterSpacing: 0.6);
  }

  static TextStyle _style(
    double size,
    double height,
    FontWeight weight,
    Color color,
  ) {
    return TextStyle(
      fontFamily: CollectRuntimeTypography.fontFamily,
      fontFamilyFallback: _family,
      fontSize: size,
      height: height,
      fontWeight: weight,
      color: color,
      letterSpacing: 0,
    );
  }

  static TextStyle _displayStyle(
    double size,
    double height,
    FontWeight weight,
    Color color,
  ) {
    return TextStyle(
      fontFamily: CollectRuntimeTypography.displayFontFamily,
      fontFamilyFallback: _displayFamily,
      fontSize: size,
      height: height,
      fontWeight: weight,
      color: color,
      letterSpacing: 0,
    );
  }
}
