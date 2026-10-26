import 'package:flutter/material.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_universal_tokens.dart';

/// Desktop workspace adaptation of the selected Business surface family.
/// Product colours and Inter remain shared; member-app presentation is untouched.
class AdminTheme {
  const AdminTheme._();

  static ThemeData adapt(ThemeData base) {
    final source = base.extension<CollectColors>()!;
    final dark = base.brightness == Brightness.dark;
    final accent = dark
        ? CollectColors.referenceSwitchBlue
        : CollectColors.referenceAccountHighlight;
    // Keep the source neutral layers distinct. The selected operator table
    // composition is adapted to the user's theme, not a second design system.
    final colors = source.copyWith(focusRing: accent, borderAccent: accent);
    final tokens = base.extension<CollectUniversalTokens>()!.copyWith(
      adminRail: colors.canvas,
      adminWorkspace: colors.canvas,
      adminRailWidth: 224,
    );
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: tokens.highContrast
          ? BorderSide(color: colors.textPrimary, width: 2)
          : BorderSide.none,
    );
    return base.copyWith(
      scaffoldBackgroundColor: colors.canvas,
      extensions: [colors, tokens],
      colorScheme: base.colorScheme.copyWith(
        surface: colors.surfaceReadable,
        surfaceContainer: colors.surfaceReadable,
        surfaceContainerHigh: colors.surfaceRaised,
      ),
      iconTheme: IconThemeData(size: 28, color: colors.textPrimary),
      iconButtonTheme: IconButtonThemeData(
        style: base.iconButtonTheme.style?.copyWith(
          iconSize: const WidgetStatePropertyAll(28),
          minimumSize: const WidgetStatePropertyAll(Size.square(48)),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: colors.surfaceReadable,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline.copyWith(
          borderSide: BorderSide(color: colors.focusRing, width: 2),
        ),
        errorBorder: outline.copyWith(
          borderSide: BorderSide(color: colors.dangerForeground),
        ),
        focusedErrorBorder: outline.copyWith(
          borderSide: BorderSide(color: colors.dangerForeground, width: 2),
        ),
        disabledBorder: outline,
        labelStyle: base.textTheme.bodyMedium?.copyWith(
          color: colors.textSecondary,
        ),
        floatingLabelStyle: base.textTheme.labelLarge?.copyWith(
          color: colors.textSecondary,
        ),
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: colors.surfaceReadable,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: colors.surfaceReadable,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
