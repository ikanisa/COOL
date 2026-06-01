import 'package:flutter/material.dart';

class CollectTypography {
  const CollectTypography._();

  static const _family = <String>['Hanken Grotesk', 'Inter', 'Roboto'];
  static const _monoFamily = <String>['JetBrains Mono', 'Roboto Mono'];

  static const _tabular = <FontFeature>[FontFeature.tabularFigures()];

  static TextTheme textTheme(Color textPrimary, Color textSecondary) {
    return TextTheme(
      displaySmall: _style(48, 1.17, FontWeight.w700, textPrimary),
      headlineLarge: _style(32, 1.25, FontWeight.w600, textPrimary),
      headlineMedium: _style(24, 1.33, FontWeight.w600, textPrimary),
      headlineSmall: _style(20, 1.4, FontWeight.w600, textPrimary),
      titleLarge: _style(20, 1.4, FontWeight.w600, textPrimary),
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

  static TextStyle amountHero(Color color) =>
      _style(42, 1.02, FontWeight.w800, color).copyWith(fontFeatures: _tabular);

  static TextStyle amountDisplay(Color color) =>
      _style(48, 1.0, FontWeight.w800, color).copyWith(fontFeatures: _tabular);

  static TextStyle amountLarge(Color color) =>
      _style(28, 1.08, FontWeight.w800, color).copyWith(fontFeatures: _tabular);

  static TextStyle amountCompact(Color color) =>
      _style(15, 1.25, FontWeight.w800, color).copyWith(fontFeatures: _tabular);

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
      fontFamilyFallback: _family,
      fontSize: size,
      height: height,
      fontWeight: weight,
      color: color,
      letterSpacing: 0,
    );
  }
}
