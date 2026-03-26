// ignore_for_file: deprecated_member_use_from_same_package
import 'package:flutter/material.dart';

import 'app_theme_components.dart';
import 'app_theme_text.dart';
import 'cool_foundations.dart';

/// Global [ThemeData] definitions for the Cool app.
///
/// Delegates to [AppThemeText] for typography and
/// [AppThemeComponents] for individual component themes.
abstract final class AppTheme {
  static ThemeData get dark => _build(brightness: Brightness.dark);

  static ThemeData get light => _build(brightness: Brightness.light);

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;
    // ignore: deprecated_member_use
    final palette = isDark ? CoolPalette.dark : CoolPalette.light;
    final semanticColors = isDark
        ? CoolSemanticColors.dark
        : CoolSemanticColors.light;
    final textTheme = AppThemeText.build(
      brightness: brightness,
      semanticColors: semanticColors,
    );

    final colorScheme = isDark
        ? ColorScheme.dark(
            surface: semanticColors.elevatedBackground,
            primary: semanticColors.buttonPrimaryBackground,
            secondary: semanticColors.success,
            error: semanticColors.danger,
            onPrimary: semanticColors.accentForeground,
            onSurface: semanticColors.primaryText,
            onError: Colors.white,
          )
        : ColorScheme.light(
            surface: semanticColors.elevatedBackground,
            primary: semanticColors.buttonPrimaryBackground,
            secondary: semanticColors.success,
            error: semanticColors.danger,
            onPrimary: semanticColors.accentForeground,
            onSurface: semanticColors.primaryText,
            onError: Colors.white,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: GoogleFonts.inter().fontFamily,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: semanticColors.appBackground,
      colorScheme: colorScheme,
      canvasColor: semanticColors.elevatedBackground,
      extensions: <ThemeExtension<dynamic>>[palette, semanticColors],
      textTheme: textTheme,

      // ── Component themes (delegated) ─────────────────────────────────
      appBarTheme: AppThemeComponents.appBar(semanticColors, textTheme, isDark),
      cardTheme: AppThemeComponents.card(semanticColors, isDark),
      bottomAppBarTheme: AppThemeComponents.bottomAppBar(semanticColors),
      bottomNavigationBarTheme: AppThemeComponents.bottomNavigationBar(
        semanticColors,
      ),
      navigationBarTheme: AppThemeComponents.navigationBar(semanticColors),
      inputDecorationTheme: AppThemeComponents.inputDecoration(semanticColors),
      elevatedButtonTheme: AppThemeComponents.elevatedButton(semanticColors),
      outlinedButtonTheme: AppThemeComponents.outlinedButton(semanticColors),
      textButtonTheme: AppThemeComponents.textButton(semanticColors),
      floatingActionButtonTheme: AppThemeComponents.fab(semanticColors),
      bottomSheetTheme: AppThemeComponents.bottomSheet(semanticColors, isDark),
      dialogTheme: AppThemeComponents.dialog(semanticColors, isDark),
      dividerTheme: AppThemeComponents.divider(semanticColors),
      chipTheme: AppThemeComponents.chip(semanticColors, isDark),
      snackBarTheme: AppThemeComponents.snackBar(semanticColors),
      tabBarTheme: AppThemeComponents.tabBar(semanticColors),
      iconButtonTheme: AppThemeComponents.iconButton(),
      tooltipTheme: AppThemeComponents.tooltip(semanticColors),
      progressIndicatorTheme: AppThemeComponents.progressIndicator(
        semanticColors,
      ),
      switchTheme: AppThemeComponents.switchTheme(semanticColors),
      checkboxTheme: AppThemeComponents.checkbox(semanticColors),
      radioTheme: AppThemeComponents.radio(semanticColors),

      // ── Global interaction overrides ─────────────────────────────────
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      iconTheme: IconThemeData(color: semanticColors.secondaryText, size: 24),
    );
  }
}
