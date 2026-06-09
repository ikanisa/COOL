import 'package:flutter/material.dart';

import 'collect_colors.dart';
import 'collect_component_tokens.dart';
import 'collect_radius.dart';
import 'collect_spacing.dart';
import 'collect_typography.dart';

class CollectTheme {
  const CollectTheme._();

  static ThemeData light() => _build(CollectColors.light, Brightness.light);

  static ThemeData _build(CollectColors colors, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.brandPrimary,
      onPrimary: colors.onAccent,
      secondary: colors.brandSecondary,
      onSecondary: colors.onAccent,
      error: colors.danger,
      onError: colors.onAccent,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      surfaceContainerHighest: colors.surfaceMuted,
      onSurfaceVariant: colors.textSecondary,
      outline: colors.border,
      outlineVariant: colors.border,
      tertiary: colors.success,
      onTertiary: colors.onAccent,
    );
    final textTheme = CollectTypography.textTheme(
      colors.textPrimary,
      colors.textSecondary,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.screenBase,
      textTheme: textTheme,
      extensions: [colors],
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.transparent,
        foregroundColor: colors.textPrimary,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surfaceMuted,
        shape: RoundedRectangleBorder(borderRadius: CollectRadius.cardBorder),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: colors.transparent,
        indicatorColor: colors.actionColor.withValues(alpha: 0.12),
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        height: 66,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? colors.textPrimary : colors.textMuted,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(CollectSpacing.target, CollectSpacing.target),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: CollectRadius.controlBorder),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(CollectSpacing.target, CollectSpacing.target),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: CollectRadius.controlBorder),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.textPrimary),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.textPrimary),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.actionColor, width: 2),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.actionColor,
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
