import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme_text.dart';
import 'cool_foundations.dart';
import 'cool_palette.dart';

/// Component-level [ThemeData] overrides for the COOL design system.
abstract final class AppThemeComponents {
  static AppBarTheme appBar(
    CoolPalette palette,
    CoolSemanticColors colors,
    TextTheme textTheme,
    bool isDark,
  ) {
    return AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: colors.primaryText,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      titleTextStyle: textTheme.headlineSmall?.copyWith(
        fontWeight: AppThemeText.extraBold,
        letterSpacing: -0.5,
      ),
      iconTheme: IconThemeData(color: colors.primaryText, size: 26),
      actionsIconTheme: IconThemeData(color: colors.secondaryText, size: 24),
    );
  }

  static BottomAppBarThemeData bottomAppBar(
    CoolPalette palette,
    CoolSemanticColors colors,
  ) {
    return BottomAppBarThemeData(
      color: colors.glassSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    );
  }

  static BottomNavigationBarThemeData bottomNavigationBar(
    CoolPalette palette,
    CoolSemanticColors colors,
  ) {
    return BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      selectedItemColor: colors.accent,
      unselectedItemColor: colors.secondaryText,
      type: BottomNavigationBarType.fixed,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      selectedLabelStyle: const TextStyle(
        fontSize: AppThemeText.labelMedium,
        fontWeight: AppThemeText.bold,
      ),
      unselectedLabelStyle: const TextStyle(
        fontSize: AppThemeText.labelMedium,
        fontWeight: AppThemeText.medium,
      ),
    );
  }

  static NavigationBarThemeData navigationBar(
    CoolPalette palette,
    CoolSemanticColors colors,
  ) {
    return NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      height: 96,
      indicatorColor: colors.chipSelectedBackground,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final isSelected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: AppThemeText.labelMedium,
          fontWeight: isSelected ? AppThemeText.bold : AppThemeText.medium,
          color: isSelected ? colors.primaryText : colors.secondaryText,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final isSelected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 26,
          color: isSelected ? colors.accent : colors.secondaryText,
        );
      }),
    );
  }

  static CardThemeData card(
    CoolPalette palette,
    CoolSemanticColors colors,
    bool isDark,
  ) {
    return CardThemeData(
      color: colors.cardSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: colors.shadowColor.withValues(alpha: isDark ? 0.26 : 0.08),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        side: BorderSide(color: colors.border, width: 1),
      ),
    );
  }

  static BottomSheetThemeData bottomSheet(
    CoolPalette palette,
    CoolSemanticColors colors,
    bool isDark,
  ) {
    return BottomSheetThemeData(
      backgroundColor: colors.overlaySurface.withValues(
        alpha: isDark ? 0.94 : 0.98,
      ),
      modalBackgroundColor: colors.overlaySurface.withValues(
        alpha: isDark ? 0.94 : 0.98,
      ),
      surfaceTintColor: Colors.transparent,
      shadowColor: colors.shadowColor.withValues(alpha: isDark ? 0.28 : 0.12),
      elevation: CoolElevation.overlay,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CoolRadii.xxl),
        ),
      ),
    );
  }

  static DialogThemeData dialog(
    CoolPalette palette,
    CoolSemanticColors colors,
    bool isDark,
  ) {
    return DialogThemeData(
      backgroundColor: colors.overlaySurface.withValues(
        alpha: isDark ? 0.95 : 0.98,
      ),
      surfaceTintColor: Colors.transparent,
      shadowColor: colors.shadowColor.withValues(alpha: isDark ? 0.32 : 0.12),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CoolRadii.xl),
      ),
      titleTextStyle: TextStyle(
        fontSize: AppThemeText.headlineSmall,
        fontWeight: AppThemeText.extraBold,
        color: colors.primaryText,
        letterSpacing: -0.5,
      ),
      contentTextStyle: TextStyle(
        fontSize: AppThemeText.bodyMedium,
        fontWeight: AppThemeText.medium,
        color: colors.secondaryText,
        height: 1.42,
      ),
    );
  }

  static InputDecorationTheme inputDecoration(
    CoolPalette palette,
    CoolSemanticColors colors,
  ) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(CoolRadii.md),
      borderSide: BorderSide(color: colors.border, width: 1.2),
    );
    return InputDecorationTheme(
      filled: true,
      fillColor: colors.inputSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      hintStyle: TextStyle(
        fontSize: AppThemeText.bodyMedium,
        fontWeight: AppThemeText.semibold,
        color: colors.tertiaryText,
      ),
      labelStyle: TextStyle(
        fontSize: AppThemeText.bodySmall,
        fontWeight: AppThemeText.bold,
        color: colors.secondaryText,
      ),
      helperStyle: TextStyle(
        fontSize: AppThemeText.labelSmall,
        fontWeight: AppThemeText.medium,
        color: colors.secondaryText,
      ),
      errorStyle: TextStyle(
        fontSize: AppThemeText.labelSmall,
        fontWeight: AppThemeText.bold,
        color: colors.danger,
      ),
      border: border,
      enabledBorder: border,
      disabledBorder: border.copyWith(
        borderSide: BorderSide(color: colors.border.withValues(alpha: 0.65)),
      ),
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: colors.accent, width: 1.6),
      ),
      errorBorder: border.copyWith(
        borderSide: BorderSide(color: colors.danger, width: 1.4),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: BorderSide(color: colors.danger, width: 1.6),
      ),
    );
  }

  static ElevatedButtonThemeData elevatedButton(
    CoolPalette palette,
    CoolSemanticColors colors,
  ) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.buttonPrimaryBackground,
        foregroundColor: colors.accentForeground,
        disabledBackgroundColor: palette.surface3,
        disabledForegroundColor: colors.tertiaryText,
        elevation: 0,
        minimumSize: const Size(double.infinity, CoolTapTargets.comfortable),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CoolRadii.md),
        ),
        textStyle: const TextStyle(
          fontSize: AppThemeText.labelLarge,
          fontWeight: AppThemeText.extraBold,
          letterSpacing: -0.2,
        ),
        splashFactory: NoSplash.splashFactory,
      ),
    );
  }

  static OutlinedButtonThemeData outlinedButton(
    CoolPalette palette,
    CoolSemanticColors colors,
  ) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.primaryText,
        backgroundColor: colors.buttonSecondaryBackground,
        side: BorderSide(color: colors.borderStrong, width: 1.2),
        elevation: 0,
        minimumSize: const Size(double.infinity, CoolTapTargets.comfortable),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CoolRadii.md),
        ),
        textStyle: const TextStyle(
          fontSize: AppThemeText.labelLarge,
          fontWeight: AppThemeText.bold,
          letterSpacing: -0.2,
        ),
        splashFactory: NoSplash.splashFactory,
      ),
    );
  }

  static TextButtonThemeData textButton(
    CoolPalette palette,
    CoolSemanticColors colors,
  ) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.accent,
        textStyle: const TextStyle(
          fontSize: AppThemeText.labelLarge,
          fontWeight: AppThemeText.bold,
        ),
        splashFactory: NoSplash.splashFactory,
      ),
    );
  }

  static FloatingActionButtonThemeData fab(
    CoolPalette palette,
    CoolSemanticColors colors,
  ) {
    return FloatingActionButtonThemeData(
      backgroundColor: colors.accent,
      foregroundColor: colors.accentForeground,
      elevation: 0,
      highlightElevation: 0,
      splashColor: Colors.white.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
  }

  static DividerThemeData divider(
    CoolPalette palette,
    CoolSemanticColors colors,
  ) {
    return DividerThemeData(color: colors.divider, thickness: 1, space: 0);
  }

  static ChipThemeData chip(
    CoolPalette palette,
    CoolSemanticColors colors,
    bool isDark,
  ) {
    return ChipThemeData(
      backgroundColor: colors.chipBackground,
      selectedColor: colors.chipSelectedBackground,
      side: BorderSide(color: colors.border),
      shadowColor: colors.shadowColor.withValues(alpha: isDark ? 0.14 : 0.04),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CoolRadii.md),
      ),
      labelStyle: TextStyle(
        fontSize: AppThemeText.labelMedium,
        fontWeight: AppThemeText.bold,
        color: colors.primaryText,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    );
  }

  static SnackBarThemeData snackBar(
    CoolPalette palette,
    CoolSemanticColors colors,
  ) {
    return SnackBarThemeData(
      backgroundColor: colors.cardSurfaceStrong,
      contentTextStyle: TextStyle(
        fontSize: AppThemeText.bodySmall,
        fontWeight: AppThemeText.medium,
        color: colors.primaryText,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CoolRadii.md),
      ),
      behavior: SnackBarBehavior.floating,
    );
  }

  static TabBarThemeData tabBar(
    CoolPalette palette,
    CoolSemanticColors colors,
  ) {
    return TabBarThemeData(
      labelColor: colors.primaryText,
      unselectedLabelColor: colors.secondaryText,
      indicatorColor: colors.accent,
      labelStyle: const TextStyle(
        fontSize: AppThemeText.labelMedium,
        fontWeight: AppThemeText.bold,
      ),
      unselectedLabelStyle: const TextStyle(
        fontSize: AppThemeText.labelMedium,
        fontWeight: AppThemeText.semibold,
      ),
      dividerColor: Colors.transparent,
    );
  }

  static IconButtonThemeData iconButton() {
    return IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(CoolTapTargets.minimum),
        padding: const EdgeInsets.all(12),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }

  static TooltipThemeData tooltip(
    CoolPalette palette,
    CoolSemanticColors colors,
  ) {
    return TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.overlaySurface,
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: TextStyle(
        fontSize: AppThemeText.labelSmall,
        fontWeight: AppThemeText.medium,
        color: colors.primaryText,
      ),
    );
  }

  static ProgressIndicatorThemeData progressIndicator(
    CoolPalette palette,
    CoolSemanticColors colors,
  ) {
    return ProgressIndicatorThemeData(
      color: colors.accent,
      linearTrackColor: colors.chipBackground,
    );
  }

  static SwitchThemeData switchTheme(
    CoolPalette palette,
    CoolSemanticColors colors,
  ) {
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? colors.accent
            : colors.tertiaryText;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? colors.chipSelectedBackground
            : colors.chipBackground;
      }),
    );
  }

  static CheckboxThemeData checkbox(
    CoolPalette palette,
    CoolSemanticColors colors,
  ) {
    return CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? colors.accent
            : Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(colors.accentForeground),
      side: BorderSide(color: colors.tertiaryText, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  static RadioThemeData radio(CoolPalette palette, CoolSemanticColors colors) {
    return RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? colors.accent
            : colors.tertiaryText;
      }),
    );
  }
}
