import 'package:flutter/material.dart';

import 'collect_colors.dart';
import 'collect_component_tokens.dart';
import 'collect_radius.dart';
import 'collect_spacing.dart';
import 'collect_typography.dart';
import 'collect_universal_tokens.dart';

class CollectTheme {
  const CollectTheme._();

  static ThemeData light() => _build(CollectColors.light, Brightness.light);
  static ThemeData dark() => _build(CollectColors.dark, Brightness.dark);
  static ThemeData highContrastLight() =>
      _build(CollectColors.light, Brightness.light, highContrast: true);
  static ThemeData highContrastDark() =>
      _build(CollectColors.dark, Brightness.dark, highContrast: true);

  static ThemeData _build(
    CollectColors colors,
    Brightness brightness, {
    bool highContrast = false,
  }) {
    final contrastOutline = brightness == Brightness.dark
        ? CollectColors.brandPaper
        : CollectColors.publicBlack;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.actionColor,
      onPrimary: colors.onAccent,
      primaryContainer: colors.infoContainer,
      onPrimaryContainer: colors.infoForeground,
      secondary: colors.textPrimary,
      onSecondary: colors.onAccent,
      secondaryContainer: colors.neutralContainer,
      onSecondaryContainer: colors.textSecondary,
      error: colors.danger,
      onError: colors.surfaceReadable,
      errorContainer: colors.dangerContainer,
      onErrorContainer: colors.dangerForeground,
      surface: colors.surfaceReadable,
      onSurface: colors.textPrimary,
      surfaceContainerHighest: colors.surfaceMuted,
      onSurfaceVariant: colors.textSecondary,
      outline: highContrast ? contrastOutline : colors.controlBorder,
      outlineVariant: highContrast ? contrastOutline : colors.borderAccent,
      tertiary: colors.success,
      onTertiary: colors.surfaceReadable,
      tertiaryContainer: colors.successContainer,
      onTertiaryContainer: colors.successForeground,
    );
    final textTheme = CollectTypography.textTheme(
      colors.textPrimary,
      colors.textSecondary,
    );
    final universalTokens = CollectUniversalTokens.fromColors(
      colors,
      brightness,
      highContrast: highContrast,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: CollectTypography.fontFamily,
      scaffoldBackgroundColor: colors.screenBase,
      textTheme: textTheme,
      extensions: [colors, universalTokens],
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
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
        color: colors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: CollectRadius.cardBorder,
          side: highContrast
              ? BorderSide(color: contrastOutline, width: 2)
              : BorderSide.none,
        ),
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
          foregroundColor: WidgetStatePropertyAll(colors.onAccent),
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
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size(CollectSpacing.target, CollectSpacing.target),
          ),
        ),
      ),
      elevatedButtonTheme: const ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size(CollectSpacing.target, CollectSpacing.target),
          ),
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size.square(CollectSpacing.iconTarget),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: UnderlineInputBorder(
          borderSide: BorderSide(
            color: highContrast ? contrastOutline : colors.controlBorder,
            width: highContrast ? 2 : 1,
          ),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(
            color: highContrast ? contrastOutline : colors.controlBorder,
            width: highContrast ? 2 : 1,
          ),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(
            color: highContrast ? contrastOutline : colors.focusRing,
            width: highContrast ? 3 : 2,
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.actionColor,
        linearTrackColor: colors.neutralContainer,
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
