import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'cool_palette.dart';

/// Global [ThemeData] definitions for the Cool app.
///
/// Uses DM Sans as the default font, with [CoolPalette] providing semantic
/// colors for text, surfaces, and component states.
abstract final class AppTheme {
  // ── Typography constants ────────────────────────────────────────────
  static const _black = FontWeight.w900;
  static const _extraBold = FontWeight.w800;
  static const _bold = FontWeight.w700;
  static const _semibold = FontWeight.w600;
  static const _medium = FontWeight.w500;
  static const _regular = FontWeight.w400;

  // Named sizes from the design system (Rule of 4 & Augmented Fourth Scale)
  static const _displayLarge = 44.0;
  static const _displayMedium = 36.0;
  static const _displaySmall = 32.0;
  static const _headlineLarge = 28.0;
  static const _headlineMedium = 24.0;
  static const _headlineSmall = 20.0;
  static const _titleLarge = 22.0;
  static const _bodyLarge = 17.0;
  static const _bodyMedium = 16.0;
  static const _bodySmall = 14.0;
  static const _labelSmall = 11.0;

  // ── Public theme getter ─────────────────────────────────────────────

  static ThemeData get dark {
    return _buildTheme(brightness: Brightness.dark, palette: CoolPalette.dark);
  }

  static ThemeData get light {
    return _buildTheme(
      brightness: Brightness.light,
      palette: CoolPalette.light,
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required CoolPalette palette,
  }) {
    final baseTheme = brightness == Brightness.dark
        ? ThemeData.dark()
        : ThemeData.light();
    final baseTextTheme = GoogleFonts.dmSansTextTheme(baseTheme.textTheme);

    final textTheme = baseTextTheme.copyWith(
      displayLarge: baseTextTheme.displayLarge?.copyWith(
        fontSize: _displayLarge,
        fontWeight: _black,
        color: palette.text,
        letterSpacing: -1.5,
        height: 1.1,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        fontSize: _displayMedium,
        fontWeight: _extraBold,
        color: palette.text,
        letterSpacing: -1.2,
        height: 1.1,
      ),
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        fontSize: _displaySmall,
        fontWeight: _extraBold,
        color: palette.text,
        letterSpacing: -1.0,
        height: 1.2,
      ),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        fontSize: _headlineLarge,
        fontWeight: _extraBold,
        color: palette.text,
        letterSpacing: -0.8,
        height: 1.2,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontSize: _headlineMedium,
        fontWeight: _extraBold,
        color: palette.text,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontSize: _headlineSmall,
        fontWeight: _extraBold,
        color: palette.text,
        letterSpacing: -0.2,
        height: 1.3,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: _titleLarge,
        fontWeight: _bold,
        color: palette.text,
        height: 1.3,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: _headlineSmall,
        fontWeight: _semibold,
        color: palette.text,
        height: 1.3,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontSize: _bodyLarge,
        fontWeight: _semibold,
        color: palette.text,
        height: 1.3,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: _bodyLarge,
        fontWeight: _medium,
        color: palette.text,
        height: 1.6,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: _bodyMedium,
        fontWeight: _regular,
        color: palette.text,
        height: 1.6,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontSize: _bodySmall,
        fontWeight: _regular,
        color: palette.text2,
        height: 1.5,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: _bodySmall,
        fontWeight: _semibold,
        color: palette.text,
        height: 1.4,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: _bodySmall,
        fontWeight: _medium,
        color: palette.text2,
        height: 1.4,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: _labelSmall,
        fontWeight: _medium,
        color: palette.text3,
        letterSpacing: 0.5,
        height: 1.4,
      ),
    );

    final isDark = brightness == Brightness.dark;
    final colorScheme = isDark
        ? ColorScheme.dark(
            surface: palette.surface,
            primary: palette.accent,
            secondary: palette.accent2,
            error: palette.red,
            onPrimary: Colors.black,
            onSurface: palette.text,
            onError: Colors.white,
          )
        : ColorScheme.light(
            surface: palette.surface,
            primary: palette.accent,
            secondary: palette.accent2,
            error: palette.red,
            onPrimary: Colors.black,
            onSurface: palette.text,
            onError: Colors.white,
          );
    final overlayStyle = isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: GoogleFonts.dmSans().fontFamily,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: palette.bg,
      colorScheme: colorScheme,
      extensions: <ThemeExtension<dynamic>>[palette],
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: overlayStyle,
        titleTextStyle: textTheme.headlineMedium?.copyWith(
          fontWeight: _extraBold,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: palette.text, size: 24),
      ),
      cardTheme: CardThemeData(
        color: palette.surface2,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: palette.border, width: 1.5),
        ),
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: palette.surface,
        elevation: 0,
        selectedItemColor: palette.accent,
        unselectedItemColor: palette.text3,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(
          fontSize: _labelSmall,
          fontWeight: _semibold,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: _labelSmall,
          fontWeight: _medium,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        elevation: 0,
        height: 80,
        indicatorColor: palette.accentGlow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: _labelSmall,
            fontWeight: isSelected ? _semibold : _medium,
            color: isSelected ? palette.accent : palette.text3,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: isSelected ? palette.accent : palette.text3,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        hintStyle: GoogleFonts.dmSans(
          fontSize: _bodyMedium,
          fontWeight: _regular,
          color: palette.text3,
        ),
        labelStyle: GoogleFonts.dmSans(
          fontSize: _bodySmall,
          fontWeight: _medium,
          color: palette.text2,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.accent, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.red, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.red, width: 2.0),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: Colors.black,
          disabledBackgroundColor: palette.surface3,
          disabledForegroundColor: palette.text3,
          elevation: 0,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: GoogleFonts.dmSans(
            fontSize: _bodyLarge,
            fontWeight: _extraBold,
            letterSpacing: -0.2,
          ),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.accent,
          side: BorderSide(color: palette.border2, width: 2.0),
          elevation: 0,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: GoogleFonts.dmSans(
            fontSize: _bodyLarge,
            fontWeight: _bold,
            letterSpacing: -0.2,
          ),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accent,
          textStyle: GoogleFonts.dmSans(
            fontSize: _bodyMedium,
            fontWeight: _bold,
          ),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.accent,
        foregroundColor: Colors.black,
        elevation: 0,
        highlightElevation: 0,
        shape: const CircleBorder(),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        modalBackgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: GoogleFonts.dmSans(
          fontSize: _headlineSmall,
          fontWeight: _extraBold,
          color: palette.text,
        ),
        contentTextStyle: GoogleFonts.dmSans(
          fontSize: _bodyMedium,
          fontWeight: _regular,
          color: palette.text2,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: 1,
        space: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surface2,
        selectedColor: palette.accentGlow,
        side: BorderSide(color: palette.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        labelStyle: GoogleFonts.dmSans(
          fontSize: _bodySmall,
          fontWeight: _medium,
          color: palette.text,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surface3,
        contentTextStyle: GoogleFonts.dmSans(
          fontSize: _bodySmall,
          fontWeight: _medium,
          color: palette.text,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: palette.accent,
        unselectedLabelColor: palette.text3,
        indicatorColor: palette.accent,
        labelStyle: GoogleFonts.dmSans(
          fontSize: _bodySmall,
          fontWeight: _semibold,
        ),
        unselectedLabelStyle: GoogleFonts.dmSans(
          fontSize: _bodySmall,
          fontWeight: _regular,
        ),
        dividerColor: Colors.transparent,
      ),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      iconTheme: IconThemeData(color: palette.text2, size: 24),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          padding: const EdgeInsets.all(12),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.surface3,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: GoogleFonts.dmSans(
          fontSize: _bodySmall,
          color: palette.text,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accent,
        linearTrackColor: palette.surface3,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? palette.accent
              : palette.text3;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? palette.accentGlow
              : palette.surface3;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? palette.accent
              : Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.black),
        side: BorderSide(color: palette.text3, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? palette.accent
              : palette.text3;
        }),
      ),
    );
  }
}
