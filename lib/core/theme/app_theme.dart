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
        fontSize: _display,
        fontWeight: _bold,
        color: palette.text,
        height: 1.2,
      ),
      displayMedium: baseTextTheme.displayMedium?.copyWith(
        fontSize: _display,
        fontWeight: _semibold,
        color: palette.text,
        height: 1.2,
      ),
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        fontSize: _display,
        fontWeight: _medium,
        color: palette.text,
        height: 1.2,
      ),
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        fontSize: _title,
        fontWeight: _bold,
        color: palette.text,
        height: 1.3,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontSize: _heading,
        fontWeight: _semibold,
        color: palette.text,
        height: 1.3,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: _title,
        fontWeight: _bold,
        color: palette.text,
        height: 1.3,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: _title,
        fontWeight: _semibold,
        color: palette.text,
        height: 1.3,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontSize: _heading,
        fontWeight: _semibold,
        color: palette.text,
        height: 1.3,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontSize: _heading,
        fontWeight: _semibold,
        color: palette.text,
        height: 1.3,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: _body,
        fontWeight: _medium,
        color: palette.text,
        height: 1.5,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: _body,
        fontWeight: _regular,
        color: palette.text,
        height: 1.5,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontSize: _small,
        fontWeight: _regular,
        color: palette.text2,
        height: 1.4,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: _small,
        fontWeight: _semibold,
        color: palette.text,
        height: 1.4,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(
        fontSize: _small,
        fontWeight: _medium,
        color: palette.text2,
        height: 1.4,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontSize: _tiny,
        fontWeight: _regular,
        color: palette.text3,
        letterSpacing: 0.4,
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
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: _heading,
          fontWeight: _semibold,
        ),
        iconTheme: IconThemeData(color: palette.text, size: 22),
      ),
      cardTheme: CardThemeData(
        color: palette.surface2,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: palette.border),
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
          fontSize: _tiny,
          fontWeight: _medium,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: _tiny,
          fontWeight: _regular,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        elevation: 0,
        height: 76,
        indicatorColor: palette.accentGlow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: _tiny,
            fontWeight: isSelected ? _medium : _regular,
            color: isSelected ? palette.accent : palette.text3,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: isSelected ? palette.accent : palette.text3,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        hintStyle: GoogleFonts.dmSans(
          fontSize: _body,
          fontWeight: _regular,
          color: palette.text3,
        ),
        labelStyle: GoogleFonts.dmSans(
          fontSize: _small,
          fontWeight: _medium,
          color: palette.text2,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.red, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: Colors.black,
          disabledBackgroundColor: palette.surface3,
          disabledForegroundColor: palette.text3,
          elevation: 0,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.dmSans(fontSize: _body, fontWeight: _bold),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.accent,
          side: BorderSide(color: palette.border2),
          elevation: 0,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.dmSans(fontSize: _body, fontWeight: _semibold),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accent,
          textStyle: GoogleFonts.dmSans(fontSize: _body, fontWeight: _semibold),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.dmSans(
          fontSize: _heading,
          fontWeight: _semibold,
          color: palette.text,
        ),
        contentTextStyle: GoogleFonts.dmSans(
          fontSize: _body,
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
          fontSize: _small,
          fontWeight: _medium,
          color: palette.text,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surface3,
        contentTextStyle: GoogleFonts.dmSans(
          fontSize: _small,
          fontWeight: _medium,
          color: palette.text,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: palette.accent,
        unselectedLabelColor: palette.text3,
        indicatorColor: palette.accent,
        labelStyle: GoogleFonts.dmSans(fontSize: _small, fontWeight: _semibold),
        unselectedLabelStyle: GoogleFonts.dmSans(
          fontSize: _small,
          fontWeight: _regular,
        ),
        dividerColor: Colors.transparent,
      ),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      iconTheme: IconThemeData(color: palette.text2, size: 22),
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
        textStyle: GoogleFonts.dmSans(fontSize: _small, color: palette.text),
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
