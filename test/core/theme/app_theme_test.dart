import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/core/theme/app_theme_text.dart';
import 'package:cool_app/core/theme/cool_foundations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/google_fonts_test_assets.dart';

void main() {
  setUp(() {
    setUpBundledGoogleFonts();
  });

  tearDown(() {
    tearDownBundledGoogleFonts();
  });

  group('AppTheme', () {
    testWidgets('dark theme uses dark brightness and semantic colors', (
      tester,
    ) async {
      late ThemeData theme;
      late CoolSemanticColors? semanticColors;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              theme = Theme.of(context);
              semanticColors = theme.extension<CoolSemanticColors>();
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(theme.brightness, Brightness.dark);
      expect(
        theme.scaffoldBackgroundColor,
        CoolSemanticColors.dark.appBackground,
      );
      expect(
        theme.colorScheme.primary,
        CoolSemanticColors.dark.buttonPrimaryBackground,
      );
      expect(semanticColors, isNotNull);
      expect(
        semanticColors!.cardSurfaceStrong,
        CoolSemanticColors.dark.cardSurfaceStrong,
      );
    });

    testWidgets('light theme uses light brightness and semantic colors', (
      tester,
    ) async {
      late ThemeData theme;
      late CoolSemanticColors? semanticColors;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              theme = Theme.of(context);
              semanticColors = theme.extension<CoolSemanticColors>();
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(theme.brightness, Brightness.light);
      expect(
        theme.scaffoldBackgroundColor,
        CoolSemanticColors.light.appBackground,
      );
      expect(semanticColors, isNotNull);
      expect(
        semanticColors!.cardSurfaceStrong,
        CoolSemanticColors.light.cardSurfaceStrong,
      );
    });

    testWidgets('theme text roles resolve to the canonical font families', (
      tester,
    ) async {
      late ThemeData theme;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              theme = Theme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        theme.textTheme.displayLarge?.fontFamily,
        AppThemeText.displayFontFamily,
      );
      expect(
        theme.textTheme.headlineMedium?.fontFamily,
        AppThemeText.displayFontFamily,
      );
      expect(
        theme.textTheme.titleLarge?.fontFamily,
        AppThemeText.bodyFontFamily,
      );
      expect(
        theme.textTheme.bodyMedium?.fontFamily,
        AppThemeText.bodyFontFamily,
      );
      expect(
        theme.textTheme.labelLarge?.fontFamily,
        AppThemeText.labelFontFamily,
      );
    });

    testWidgets('cool text helpers enforce mono family and label minimums', (
      tester,
    ) async {
      late TextStyle monoStyle;
      late TextStyle labelStyle;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              final text = context.coolText;
              final theme = Theme.of(context);
              monoStyle = text.mono(theme.textTheme.labelLarge);
              labelStyle = text.mobiLabel();
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(monoStyle.fontFamily, 'DM Mono');
      expect(labelStyle.fontFamily, AppThemeText.labelFontFamily);
      expect(labelStyle.fontSize, greaterThanOrEqualTo(14));
      expect(
        labelStyle.fontWeight?.index ?? FontWeight.w500.index,
        greaterThanOrEqualTo(FontWeight.w500.index),
      );
    });
  });
}
