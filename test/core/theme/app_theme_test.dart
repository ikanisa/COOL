import 'package:cool_app/core/theme/app_theme.dart';
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
  });
}
