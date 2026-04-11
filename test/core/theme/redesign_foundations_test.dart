import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/core/theme/cool_foundations.dart';
import 'package:cool_app/core/theme/app_theme_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Redesign foundations', () {
    testWidgets('light theme exposes semantic redesign colors', (tester) async {
      late CoolSemanticColors semanticColors;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              semanticColors = context.coolSemanticColors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(semanticColors.cardSurface, CoolSemanticColors.light.cardSurface);
      expect(
        semanticColors.buttonPrimaryBackground,
        CoolSemanticColors.light.buttonPrimaryBackground,
      );
    });

    testWidgets('dark theme exposes semantic redesign colors', (tester) async {
      late CoolSemanticColors semanticColors;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) {
              semanticColors = context.coolSemanticColors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(semanticColors.cardSurface, CoolSemanticColors.dark.cardSurface);
      expect(
        semanticColors.buttonPrimaryBackground,
        CoolSemanticColors.dark.buttonPrimaryBackground,
      );
    });

    testWidgets('typography constants enforce the minimalist type scale', (
      tester,
    ) async {
      expect(AppThemeText.displayLarge, 40.0);
      expect(AppThemeText.headlineMedium, 20.0);
      expect(AppThemeText.bodySmall, 14.0);
      expect(AppThemeText.labelSmall, 14.0);
      expect(
        AppThemeText.medium.index,
        greaterThanOrEqualTo(FontWeight.w500.index),
      );
      expect(
        AppThemeText.semibold.index,
        greaterThanOrEqualTo(FontWeight.w600.index),
      );
      expect(AppThemeText.bold, FontWeight.w700);
      expect(AppThemeText.bold.index, lessThanOrEqualTo(FontWeight.w700.index));
    });
  });
}
