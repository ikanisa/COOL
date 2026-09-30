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
        ? CollectColors.publicWhite
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
      surfaceDim: colors.canvas,
      surfaceBright: colors.surfaceRaised,
      surfaceContainerLowest: colors.canvas,
      surfaceContainerLow: colors.surfaceReadable,
      surfaceContainer: colors.surfaceReadable,
      surfaceContainerHigh: colors.surfaceRaised,
      surfaceContainerHighest: colors.surfaceMuted,
      surfaceTint: colors.transparent,
      scrim: CollectColors.publicBlack,
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
      // Focused tasks and operator overlays share the neutral reference
      // family. Explicit surfaces prevent framework elevation/tint defaults
      // from introducing a second palette into less frequently used flows.
      dialogTheme: DialogThemeData(
        backgroundColor: colors.panelSurface,
        surfaceTintColor: colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CollectRadius.bottomSheet),
          side: highContrast
              ? BorderSide(color: contrastOutline, width: 2)
              : BorderSide.none,
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.panelSurface,
        modalBackgroundColor: colors.panelSurface,
        surfaceTintColor: colors.transparent,
        elevation: 0,
        modalElevation: 0,
        modalBarrierColor: CollectColors.publicBlack.withValues(alpha: 0.64),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CollectRadius.bottomSheet),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.panelSurface,
        surfaceTintColor: colors.transparent,
        elevation: 0,
        textStyle: textTheme.bodyLarge,
        shape: RoundedRectangleBorder(
          borderRadius: CollectRadius.cardBorder,
          side: BorderSide(
            color: highContrast ? contrastOutline : colors.panelBorder,
            width: highContrast ? 2 : 1,
          ),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.panelSurface),
          surfaceTintColor: WidgetStatePropertyAll(colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: CollectRadius.cardBorder),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(
              color: highContrast ? contrastOutline : colors.panelBorder,
              width: highContrast ? 2 : 1,
            ),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceRaised,
        contentTextStyle: textTheme.bodyMedium,
        actionTextColor: colors.textPrimary,
        disabledActionTextColor: colors.textMuted,
        closeIconColor: colors.textPrimary,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: CollectRadius.cardBorder,
          side: BorderSide(
            color: highContrast ? contrastOutline : colors.panelBorder,
            width: highContrast ? 2 : 1,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.panelSurface,
        selectedColor: colors.actionColor,
        disabledColor: colors.neutralContainer,
        labelStyle: textTheme.labelLarge?.copyWith(color: colors.textPrimary),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: colors.onAccent,
        ),
        checkmarkColor: colors.onAccent,
        surfaceTintColor: colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: CollectRadius.pillBorder),
        side: BorderSide(
          color: highContrast ? contrastOutline : colors.controlBorder,
          width: highContrast ? 2 : 1,
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
