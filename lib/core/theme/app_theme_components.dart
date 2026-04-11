import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme_text.dart';
import 'cool_foundations.dart';

/// Component-level [ThemeData] overrides — Tactile Monolith system.
abstract final class AppThemeComponents {
  static AppBarTheme appBar(
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
        fontFamily: AppThemeText.displayFontFamily,
        fontWeight: AppThemeText.extraBold,
        letterSpacing: -0.4,
      ),
      iconTheme: IconThemeData(color: colors.primaryText, size: 20),
      actionsIconTheme: IconThemeData(color: colors.secondaryText, size: 20),
    );
  }

  static BottomAppBarThemeData bottomAppBar(CoolSemanticColors colors) {
    return BottomAppBarThemeData(
      color: colors.glassSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    );
  }

  static BottomNavigationBarThemeData bottomNavigationBar(
    CoolSemanticColors colors,
  ) {
    return BottomNavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      selectedItemColor: colors.primaryText,
      unselectedItemColor: colors.secondaryText,
      type: BottomNavigationBarType.fixed,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      selectedLabelStyle: TextStyle(
        fontFamily: AppThemeText.labelFontFamily,
        fontSize: 14,
        fontWeight: AppThemeText.semibold,
        letterSpacing: 1.0,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily: AppThemeText.labelFontFamily,
        fontSize: 14,
        fontWeight: AppThemeText.medium,
        letterSpacing: 1.0,
      ),
    );
  }

  static NavigationBarThemeData navigationBar(CoolSemanticColors colors) {
    return NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      height: 72,
      indicatorColor: Colors.white.withValues(alpha: 0.10),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final isSelected = states.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: AppThemeText.labelFontFamily,
          fontSize: 14,
          fontWeight: isSelected ? AppThemeText.semibold : AppThemeText.medium,
          color: isSelected ? colors.primaryText : colors.secondaryText,
          letterSpacing: 1.0,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final isSelected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 18,
          color: isSelected ? colors.primaryText : colors.secondaryText,
        );
      }),
    );
  }

  static CardThemeData card(CoolSemanticColors colors, bool isDark) {
    return CardThemeData(
      color: colors.cardSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      margin: EdgeInsets.zero,
      // No-Line Rule: no border on cards. Depth via surface shifts.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        side: BorderSide.none,
      ),
    );
  }

  static BottomSheetThemeData bottomSheet(
    CoolSemanticColors colors,
    bool isDark,
  ) {
    return BottomSheetThemeData(
      backgroundColor: colors.overlaySurface,
      modalBackgroundColor: colors.overlaySurface,
      surfaceTintColor: Colors.transparent,
      shadowColor: colors.shadowColor.withValues(alpha: 0.50),
      elevation: CoolElevation.overlay,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(CoolRadii.xl)),
      ),
    );
  }

  static DialogThemeData dialog(CoolSemanticColors colors, bool isDark) {
    return DialogThemeData(
      backgroundColor: colors.overlaySurface,
      surfaceTintColor: Colors.transparent,
      shadowColor: colors.shadowColor.withValues(alpha: 0.50),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CoolRadii.xl),
      ),
      titleTextStyle: TextStyle(
        fontFamily: AppThemeText.displayFontFamily,
        fontSize: AppThemeText.headlineSmall,
        fontWeight: AppThemeText.extraBold,
        color: colors.primaryText,
        letterSpacing: -0.96,
      ),
      contentTextStyle: TextStyle(
        fontFamily: AppThemeText.bodyFontFamily,
        fontSize: AppThemeText.bodyMedium,
        fontWeight: AppThemeText.regular,
        color: colors.secondaryText,
        height: 1.5,
      ),
    );
  }

  static InputDecorationTheme inputDecoration(CoolSemanticColors colors) {
    // Sunken input: no visible border at rest. Ghost border on focus.
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(CoolRadii.md),
      borderSide: BorderSide.none,
    );
    return InputDecorationTheme(
      filled: true,
      fillColor: colors.inputSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: TextStyle(
        fontFamily: AppThemeText.bodyFontFamily,
        fontSize: AppThemeText.bodyMedium,
        fontWeight: AppThemeText.regular,
        color: colors.tertiaryText,
      ),
      labelStyle: TextStyle(
        fontFamily: AppThemeText.labelFontFamily,
        fontSize: AppThemeText.labelSmall,
        fontWeight: AppThemeText.semibold,
        color: colors.secondaryText,
        letterSpacing: 1.0,
      ),
      floatingLabelStyle: TextStyle(
        fontFamily: AppThemeText.labelFontFamily,
        fontSize: AppThemeText.labelSmall,
        fontWeight: AppThemeText.semibold,
        color: colors.accent,
        letterSpacing: 1.0,
      ),
      helperStyle: TextStyle(
        fontFamily: AppThemeText.bodyFontFamily,
        fontSize: AppThemeText.labelSmall,
        fontWeight: AppThemeText.medium,
        color: colors.secondaryText,
      ),
      errorStyle: TextStyle(
        fontFamily: AppThemeText.labelFontFamily,
        fontSize: AppThemeText.labelSmall,
        fontWeight: AppThemeText.bold,
        color: colors.danger,
      ),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      // Ghost border on focus: electric violet (#6C63FF) at 40%
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CoolRadii.md),
        borderSide: BorderSide(
          color: const Color(0xFF6C63FF).withValues(alpha: 0.40),
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CoolRadii.md),
        borderSide: BorderSide(color: colors.danger.withValues(alpha: 0.35)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CoolRadii.md),
        borderSide: BorderSide(color: colors.danger.withValues(alpha: 0.50)),
      ),
    );
  }

  static ElevatedButtonThemeData elevatedButton(CoolSemanticColors colors) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.buttonPrimaryBackground,
        foregroundColor: colors.accentForeground,
        disabledBackgroundColor: colors.cardSurfaceStrong,
        disabledForegroundColor: colors.tertiaryText,
        elevation: 0,
        minimumSize: const Size(double.infinity, 52),
        // High-gloss clay CTA: pill rounding, generous padding
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CoolRadii.pill),
        ),
        textStyle: TextStyle(
          fontFamily: AppThemeText.labelFontFamily,
          fontSize: AppThemeText.labelMedium,
          fontWeight: AppThemeText.semibold,
          letterSpacing: 2.0,
        ),
        splashFactory: NoSplash.splashFactory,
      ),
    );
  }

  static OutlinedButtonThemeData outlinedButton(CoolSemanticColors colors) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.primaryText,
        // Glassmorphic secondary: translucent, no hard border
        backgroundColor: colors.buttonSecondaryBackground,
        side: BorderSide.none,
        elevation: 0,
        minimumSize: const Size(double.infinity, 52),
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CoolRadii.pill),
        ),
        textStyle: TextStyle(
          fontFamily: AppThemeText.labelFontFamily,
          fontSize: AppThemeText.labelMedium,
          fontWeight: AppThemeText.semibold,
          letterSpacing: 2.0,
        ),
        splashFactory: NoSplash.splashFactory,
      ),
    );
  }

  static TextButtonThemeData textButton(CoolSemanticColors colors) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        // Tertiary: no container, primary light source color
        foregroundColor: colors.accentStrong,
        textStyle: TextStyle(
          fontFamily: AppThemeText.labelFontFamily,
          fontSize: AppThemeText.labelMedium,
          fontWeight: AppThemeText.semibold,
        ),
        splashFactory: NoSplash.splashFactory,
      ),
    );
  }

  static FloatingActionButtonThemeData fab(CoolSemanticColors colors) {
    return FloatingActionButtonThemeData(
      backgroundColor: colors.buttonPrimaryBackground,
      foregroundColor: colors.accentForeground,
      elevation: 0,
      highlightElevation: 0,
      splashColor: Colors.white.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CoolRadii.md),
      ),
    );
  }

  static DividerThemeData divider(CoolSemanticColors colors) {
    // No-Line Rule: dividers are invisible. Use whitespace/surface shifts.
    return const DividerThemeData(
      color: Colors.transparent,
      thickness: 0,
      space: 0,
    );
  }

  static ChipThemeData chip(CoolSemanticColors colors, bool isDark) {
    return ChipThemeData(
      backgroundColor: colors.chipBackground,
      selectedColor: colors.chipSelectedBackground,
      side: BorderSide.none,
      shadowColor: Colors.transparent,
      elevation: 0,
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        fontFamily: AppThemeText.labelFontFamily,
        fontSize: AppThemeText.labelMedium,
        fontWeight: AppThemeText.semibold,
        color: colors.primaryText,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  static SnackBarThemeData snackBar(CoolSemanticColors colors) {
    return SnackBarThemeData(
      backgroundColor: colors.cardSurfaceStrong,
      contentTextStyle: TextStyle(
        fontFamily: AppThemeText.bodyFontFamily,
        fontSize: AppThemeText.bodySmall,
        fontWeight: AppThemeText.medium,
        color: colors.primaryText,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CoolRadii.lg),
      ),
      behavior: SnackBarBehavior.floating,
    );
  }

  static TabBarThemeData tabBar(CoolSemanticColors colors) {
    return TabBarThemeData(
      labelColor: colors.primaryText,
      unselectedLabelColor: colors.secondaryText,
      indicatorColor: colors.accent,
      labelStyle: TextStyle(
        fontFamily: AppThemeText.labelFontFamily,
        fontSize: AppThemeText.labelMedium,
        fontWeight: AppThemeText.semibold,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily: AppThemeText.labelFontFamily,
        fontSize: AppThemeText.labelMedium,
        fontWeight: AppThemeText.medium,
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

  static TooltipThemeData tooltip(CoolSemanticColors colors) {
    return TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.circular(CoolRadii.sm),
      ),
      textStyle: TextStyle(
        fontFamily: AppThemeText.bodyFontFamily,
        fontSize: AppThemeText.labelSmall,
        fontWeight: AppThemeText.medium,
        color: colors.primaryText,
      ),
    );
  }

  static ProgressIndicatorThemeData progressIndicator(
    CoolSemanticColors colors,
  ) {
    return ProgressIndicatorThemeData(
      color: colors.accent,
      linearTrackColor: colors.chipBackground,
    );
  }

  static SwitchThemeData switchTheme(CoolSemanticColors colors) {
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? colors.accent
            : colors.tertiaryText;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? colors.accent.withValues(alpha: 0.30)
            : colors.chipBackground;
      }),
    );
  }

  static CheckboxThemeData checkbox(CoolSemanticColors colors) {
    return CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? colors.accent
            : Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(colors.accentForeground),
      side: BorderSide(color: colors.borderStrong, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CoolRadii.xs),
      ),
    );
  }

  static RadioThemeData radio(CoolSemanticColors colors) {
    return RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? colors.accent
            : colors.tertiaryText;
      }),
    );
  }
}
