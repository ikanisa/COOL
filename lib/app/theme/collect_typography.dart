import 'package:flutter/material.dart';

class CollectTypography {
  const CollectTypography._();

  static const _family = <String>[
    'Inter',
    'Plus Jakarta Sans',
    'Manrope',
    'Roboto',
  ];

  static const _tabular = <FontFeature>[FontFeature.tabularFigures()];

  static TextTheme textTheme(Color textPrimary, Color textSecondary) {
    return TextTheme(
      displaySmall: _style(42, 1.04, FontWeight.w800, textPrimary),
      headlineLarge: _style(34, 1.1, FontWeight.w800, textPrimary),
      headlineMedium: _style(29, 1.14, FontWeight.w800, textPrimary),
      headlineSmall: _style(24, 1.18, FontWeight.w700, textPrimary),
      titleLarge: _style(20, 1.24, FontWeight.w700, textPrimary),
      titleMedium: _style(17, 1.35, FontWeight.w700, textPrimary),
      titleSmall: _style(15, 1.35, FontWeight.w700, textPrimary),
      bodyLarge: _style(16, 1.5, FontWeight.w500, textPrimary),
      bodyMedium: _style(14, 1.48, FontWeight.w500, textSecondary),
      bodySmall: _style(13, 1.42, FontWeight.w500, textSecondary),
      labelLarge: _style(14, 1.3, FontWeight.w700, textPrimary),
      labelMedium: _style(12, 1.25, FontWeight.w700, textSecondary),
      labelSmall: _style(11, 1.2, FontWeight.w700, textSecondary),
    );
  }

  static TextStyle amountHero(Color color) =>
      _style(42, 1.02, FontWeight.w800, color).copyWith(fontFeatures: _tabular);

  static TextStyle amountLarge(Color color) =>
      _style(28, 1.08, FontWeight.w800, color).copyWith(fontFeatures: _tabular);

  static TextStyle amountCompact(Color color) =>
      _style(15, 1.25, FontWeight.w800, color).copyWith(fontFeatures: _tabular);

  static TextStyle mono(Color color) =>
      _style(13, 1.4, FontWeight.w700, color).copyWith(fontFeatures: _tabular);

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
