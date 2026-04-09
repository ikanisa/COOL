import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_theme_components.dart';
import 'app_theme_text.dart';
import 'cool_foundations.dart';

/// Global [ThemeData] for the production design system.
abstract final class AppTheme {
  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    semanticColors: CoolSemanticColors.dark,
  );

  static ThemeData get light => _build(
    brightness: Brightness.light,
    semanticColors: CoolSemanticColors.light,
  );

  static ThemeData _build({
    required Brightness brightness,
    required CoolSemanticColors semanticColors,
  }) {
    final textTheme = AppThemeText.build(
      brightness: brightness,
      semanticColors: semanticColors,
    );

    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: semanticColors.buttonPrimaryBackground,
          brightness: brightness,
          surface: semanticColors.elevatedBackground,
        ).copyWith(
          primary: semanticColors.buttonPrimaryBackground,
          secondary: semanticColors.accentGold,
          error: semanticColors.danger,
          onPrimary: semanticColors.accentForeground,
          onSurface: semanticColors.primaryText,
          onError: Colors.white,
        );
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: GoogleFonts.spaceGrotesk().fontFamily,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: semanticColors.appBackground,
      colorScheme: colorScheme,
      canvasColor: semanticColors.elevatedBackground,
      extensions: <ThemeExtension<dynamic>>[semanticColors],
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

      // ── Branded page transition (Fade + Scale, 300ms) ───────────────
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: const _CoolPageTransitionsBuilder(),
        },
      ),

      // ── Global interaction overrides ─────────────────────────────────
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      iconTheme: IconThemeData(color: semanticColors.secondaryText, size: 20),

      // ── Web focus ring (WCAG 2.4.7) ──────────────────────────────────
      // On web, keyboard Tab-navigation must show a visible focus indicator.
      // Native platforms use their own focus systems.
      focusColor: kIsWeb
          ? semanticColors.accent.withValues(alpha: 0.24)
          : Colors.transparent,
    );
  }
}

/// Branded fade + subtle scale page transition for all Material routes.
class _CoolPageTransitionsBuilder extends PageTransitionsBuilder {
  const _CoolPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurveTween(curve: Curves.easeOut).animate(animation),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.98, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    );
  }
}
