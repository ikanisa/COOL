import 'package:flutter/material.dart';

import 'app_theme_components.dart';
import 'app_theme_text.dart';
import 'cool_foundations.dart';

/// Global [ThemeData] definitions for the Cool app.
///
/// Delegates to [AppThemeText] for typography and
/// [AppThemeComponents] for individual component themes.
abstract final class AppTheme {
  static ThemeData get dark =>
      _build(brightness: Brightness.dark, palette: CoolPalette.dark);

  static ThemeData get light =>
      _build(brightness: Brightness.light, palette: CoolPalette.light);

  static ThemeData _build({
    required Brightness brightness,
    required CoolPalette palette,
  }) {
    final isDark = brightness == Brightness.dark;
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
      fontFamily: GoogleFonts.manrope().fontFamily,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: semanticColors.appBackground,
      colorScheme: colorScheme,
      canvasColor: semanticColors.elevatedBackground,
      extensions: <ThemeExtension<dynamic>>[palette, semanticColors],
      textTheme: textTheme,

      // ── Component themes (delegated) ─────────────────────────────────
      appBarTheme: AppThemeComponents.appBar(
        palette,
        semanticColors,
        textTheme,
        isDark,
      ),
      cardTheme: AppThemeComponents.card(palette, semanticColors, isDark),
      bottomAppBarTheme: AppThemeComponents.bottomAppBar(
        palette,
        semanticColors,
      ),
      bottomNavigationBarTheme: AppThemeComponents.bottomNavigationBar(
        palette,
        semanticColors,
      ),
      navigationBarTheme: AppThemeComponents.navigationBar(
        palette,
        semanticColors,
      ),
      inputDecorationTheme: AppThemeComponents.inputDecoration(
        palette,
        semanticColors,
      ),
      elevatedButtonTheme: AppThemeComponents.elevatedButton(
        palette,
        semanticColors,
      ),
      outlinedButtonTheme: AppThemeComponents.outlinedButton(
        palette,
        semanticColors,
      ),
      textButtonTheme: AppThemeComponents.textButton(palette, semanticColors),
      floatingActionButtonTheme: AppThemeComponents.fab(
        palette,
        semanticColors,
      ),
      bottomSheetTheme: AppThemeComponents.bottomSheet(
        palette,
        semanticColors,
        isDark,
      ),
      dialogTheme: AppThemeComponents.dialog(palette, semanticColors, isDark),
      dividerTheme: AppThemeComponents.divider(palette, semanticColors),
      chipTheme: AppThemeComponents.chip(palette, semanticColors, isDark),
      snackBarTheme: AppThemeComponents.snackBar(palette, semanticColors),
      tabBarTheme: AppThemeComponents.tabBar(palette, semanticColors),
      iconButtonTheme: AppThemeComponents.iconButton(),
      tooltipTheme: AppThemeComponents.tooltip(palette, semanticColors),
      progressIndicatorTheme: AppThemeComponents.progressIndicator(
        palette,
        semanticColors,
      ),
      switchTheme: AppThemeComponents.switchTheme(palette, semanticColors),
      checkboxTheme: AppThemeComponents.checkbox(palette, semanticColors),
      radioTheme: AppThemeComponents.radio(palette, semanticColors),

      // ── Global interaction overrides ─────────────────────────────────
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      iconTheme: IconThemeData(color: semanticColors.secondaryText, size: 24),
    );
  }
}
