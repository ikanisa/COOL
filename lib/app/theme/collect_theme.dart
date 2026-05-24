import 'package:flutter/material.dart';

import 'collect_colors.dart';
import 'collect_component_tokens.dart';
import 'collect_radius.dart';
import 'collect_spacing.dart';
import 'collect_typography.dart';

class CollectTheme {
  const CollectTheme._();

  static ThemeData light() => _build(CollectColors.light, Brightness.light);

  static ThemeData dark() => _build(CollectColors.dark, Brightness.dark);

  static ThemeData _build(CollectColors colors, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.navy,
      onPrimary: Colors.white,
      secondary: colors.aqua,
      onSecondary: Colors.white,
      error: colors.danger,
      onError: Colors.white,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      surfaceContainerHighest: colors.surfaceMuted,
      onSurfaceVariant: colors.textSecondary,
      outline: colors.border,
      outlineVariant: colors.border,
      tertiary: colors.coral,
      onTertiary: Colors.white,
    );
    final textTheme = CollectTypography.textTheme(
      colors.textPrimary,
      colors.textSecondary,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.surface,
      textTheme: textTheme,
      extensions: [colors],
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: CollectRadius.cardBorder,
          side: BorderSide(color: colors.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: colors.surfaceRaised.withValues(alpha: 0.97),
        indicatorColor: colors.statusBackground(CollectStatusTone.info),
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? colors.blue : colors.textMuted,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(CollectSpacing.target, CollectSpacing.target),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: CollectRadius.pillBorder),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(CollectSpacing.target, CollectSpacing.target),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: CollectRadius.pillBorder),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceRaised,
        border: OutlineInputBorder(
          borderRadius: CollectRadius.mdBorder,
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: CollectRadius.mdBorder,
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: CollectRadius.mdBorder,
          borderSide: BorderSide(color: colors.blue, width: 1.6),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.blue,
        linearTrackColor: colors.surfaceMuted,
        borderRadius: CollectRadius.pillBorder,
      ),
    );
  }
}

extension CollectButtonStyles on BuildContext {
  ButtonStyle get collectFilledButton =>
      CollectComponentTokens.filledButton(this);

  ButtonStyle get collectOutlinedButton =>
      CollectComponentTokens.outlinedButton(this);
}
