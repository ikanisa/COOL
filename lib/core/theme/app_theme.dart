import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Global dark [ThemeData] for the Cool app.
///
/// Uses DM Sans as the default font, with AppColors for every surface,
/// text style, component theme, and input decoration.
abstract final class AppTheme {
  // ── Typography constants ────────────────────────────────────────────
  static const _bold = FontWeight.w700;
  static const _semibold = FontWeight.w600;
  static const _medium = FontWeight.w500;
  static const _regular = FontWeight.w400;

  // Named sizes from the design system.
  static const _display = 32.0;
  static const _title = 22.0;
  static const _heading = 18.0;
  static const _body = 15.0;
  static const _small = 13.0;
  static const _tiny = 11.0;

  // ── Public theme getter ─────────────────────────────────────────────

  static ThemeData get dark {
    final baseTextTheme = GoogleFonts.dmSansTextTheme(
      ThemeData.dark().textTheme,
    );

    final textTheme = baseTextTheme.copyWith(
      // Display
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        fontSize: _display,
        fontWeight: _bold,
        color: AppColors.text,
        height: 1.2,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        fontSize: _display,
        fontWeight: _semibold,
        color: AppColors.text,
        height: 1.2,
      ),
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        fontSize: _display,
        fontWeight: _medium,
        color: AppColors.text,
        height: 1.2,
      ),
      // Title
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        fontSize: _title,
        fontWeight: _bold,
        color: AppColors.text,
        height: 1.3,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontSize: _heading,
        fontWeight: _semibold,
        color: AppColors.text,
        height: 1.3,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: _title,
        fontWeight: _bold,
        color: AppColors.text,
        height: 1.3,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: _title,
        fontWeight: _semibold,
        color: AppColors.text,
        height: 1.3,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontSize: _heading,
        fontWeight: _semibold,
        color: AppColors.text,
        height: 1.3,
      ),
      // Heading → headlineSmall
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontSize: _heading,
        fontWeight: _semibold,
        color: AppColors.text,
        height: 1.3,
      ),
      // Body
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: _body,
        fontWeight: _medium,
        color: AppColors.text,
        height: 1.5,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: _body,
        fontWeight: _regular,
        color: AppColors.text,
        height: 1.5,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontSize: _small,
        fontWeight: _regular,
        color: AppColors.text2,
        height: 1.4,
      ),
      // Small / Tiny → labels
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: _small,
        fontWeight: _semibold,
        color: AppColors.text,
        height: 1.4,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: _small,
        fontWeight: _medium,
        color: AppColors.text2,
        height: 1.4,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: _tiny,
        fontWeight: _regular,
        color: AppColors.text3,
        letterSpacing: 0.4,
        height: 1.4,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: GoogleFonts.dmSans().fontFamily,

      // ── Colours ───────────────────────────────────────────────────
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.surface,
        primary: AppColors.accent,
        secondary: AppColors.accent2,
        error: AppColors.red,
        onPrimary: Colors.black,
        onSurface: AppColors.text,
        onError: Colors.white,
      ),

      // ── Text ──────────────────────────────────────────────────────
      textTheme: textTheme,

      // ── AppBar ────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: _heading,
          fontWeight: _semibold,
        ),
        iconTheme: const IconThemeData(color: AppColors.text, size: 22),
      ),

      // ── Card ──────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: AppColors.surface2,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      bottomAppBarTheme: const BottomAppBarThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),

      // ── Bottom Navigation Bar ─────────────────────────────────────
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.text3,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(fontSize: _tiny, fontWeight: _medium),
        unselectedLabelStyle: TextStyle(fontSize: _tiny, fontWeight: _regular),
      ),

      // ── NavigationBar (Material 3) ────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        height: 76,
        indicatorColor: AppColors.accentGlow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: _tiny,
            fontWeight: isSelected ? _medium : _regular,
            color: isSelected ? AppColors.accent : AppColors.text3,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: isSelected ? AppColors.accent : AppColors.text3,
          );
        }),
      ),

      // ── Input Decoration ──────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        hintStyle: GoogleFonts.dmSans(
          fontSize: _body,
          fontWeight: _regular,
          color: AppColors.text3,
        ),
        labelStyle: GoogleFonts.dmSans(
          fontSize: _small,
          fontWeight: _medium,
          color: AppColors.text2,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.red, width: 1.5),
        ),
      ),

      // ── Elevated Button ───────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColors.surface3,
          disabledForegroundColor: AppColors.text3,
          elevation: 0,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.dmSans(fontSize: _body, fontWeight: _bold),
          splashFactory: NoSplash.splashFactory,
        ),
      ),

      // ── Outlined Button ───────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: const BorderSide(color: AppColors.border2),
          elevation: 0,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.dmSans(fontSize: _body, fontWeight: _semibold),
          splashFactory: NoSplash.splashFactory,
        ),
      ),

      // ── Text Button ───────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: GoogleFonts.dmSans(fontSize: _body, fontWeight: _semibold),
          splashFactory: NoSplash.splashFactory,
        ),
      ),

      // ── Floating Action Button ────────────────────────────────────
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        elevation: 0,
        highlightElevation: 0,
        shape: CircleBorder(),
      ),

      // ── Bottom Sheet ──────────────────────────────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      // ── Dialog ────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.dmSans(
          fontSize: _heading,
          fontWeight: _semibold,
          color: AppColors.text,
        ),
        contentTextStyle: GoogleFonts.dmSans(
          fontSize: _body,
          fontWeight: _regular,
          color: AppColors.text2,
        ),
      ),

      // ── Divider ───────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 0,
      ),

      // ── Chip ──────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface2,
        selectedColor: AppColors.accentGlow,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        labelStyle: GoogleFonts.dmSans(
          fontSize: _small,
          fontWeight: _medium,
          color: AppColors.text,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      // ── Snack Bar ─────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface3,
        contentTextStyle: GoogleFonts.dmSans(
          fontSize: _small,
          fontWeight: _medium,
          color: AppColors.text,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Tab Bar ───────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.text3,
        indicatorColor: AppColors.accent,
        labelStyle: GoogleFonts.dmSans(fontSize: _small, fontWeight: _semibold),
        unselectedLabelStyle: GoogleFonts.dmSans(
          fontSize: _small,
          fontWeight: _regular,
        ),
        dividerColor: Colors.transparent,
      ),

      // ── Splash / Highlight suppression ────────────────────────────
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,

      // ── Icon ──────────────────────────────────────────────────────
      iconTheme: const IconThemeData(color: AppColors.text2, size: 22),

      // ── Tooltip ───────────────────────────────────────────────────
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: GoogleFonts.dmSans(fontSize: _small, color: AppColors.text),
      ),

      // ── Progress Indicator ────────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.surface3,
      ),

      // ── Switch / Checkbox / Radio ─────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.text3;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.accentGlow
              : AppColors.surface3;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.accent
              : Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.black),
        side: const BorderSide(color: AppColors.text3, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.text3;
        }),
      ),
    );
  }
}
