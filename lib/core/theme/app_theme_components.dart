import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme_text.dart';
import 'cool_foundations.dart';

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
      selectedItemColor: colors.buttonPrimaryBackground,
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
          color: isSelected
              ? colors.buttonPrimaryBackground
              : colors.secondaryText,
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
        side: BorderSide.none,
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
      borderSide: BorderSide.none,
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
        fontWeight: AppThemeText.extraBold,
        color: colors.secondaryText,
      ),
      floatingLabelStyle: TextStyle(
        fontSize: AppThemeText.bodySmall,
        fontWeight: AppThemeText.extraBold,
        color: colors.buttonPrimaryBackground,
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
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(
          color: colors.buttonPrimaryBackground.withValues(alpha: 0.22),
        ),
      ),
      errorBorder: border.copyWith(
        borderSide: BorderSide(color: colors.danger.withValues(alpha: 0.45)),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: BorderSide(color: colors.danger.withValues(alpha: 0.55)),
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
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
        side: BorderSide(color: colors.highlightColor.withValues(alpha: 0.10)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(
          fontSize: AppThemeText.labelLarge,
          fontWeight: AppThemeText.extraBold,
          letterSpacing: 0.2,
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
        backgroundColor: Colors.transparent,
        side: BorderSide(
          color: colors.border.withValues(alpha: 0.01),
          width: 0,
        ),
        elevation: 0,
        minimumSize: const Size(double.infinity, CoolTapTargets.comfortable),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(
          fontSize: AppThemeText.labelLarge,
          fontWeight: AppThemeText.bold,
          letterSpacing: 0.08,
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
        foregroundColor: colors.buttonPrimaryBackground,
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
      backgroundColor: colors.buttonPrimaryBackground,
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
    return DividerThemeData(color: colors.divider, thickness: 0.6, space: 0);
  }

  static ChipThemeData chip(
    CoolPalette palette,
    CoolSemanticColors colors,
    bool isDark,
  ) {
    return ChipThemeData(
      backgroundColor: colors.chipBackground,
      selectedColor: colors.chipSelectedBackground,
      side: BorderSide.none,
      shadowColor: colors.shadowColor.withValues(alpha: isDark ? 0.14 : 0.04),
      elevation: 0,
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        fontSize: AppThemeText.labelMedium,
        fontWeight: AppThemeText.extraBold,
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
      indicatorColor: colors.buttonPrimaryBackground,
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
      color: colors.buttonPrimaryBackground,
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
            ? colors.buttonPrimaryBackground
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
            ? colors.buttonPrimaryBackground
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
            ? colors.buttonPrimaryBackground
            : colors.tertiaryText;
      }),
    );
  }
}
