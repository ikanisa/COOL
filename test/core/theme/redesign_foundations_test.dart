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

    testWidgets('typography constants enforce the current weight tiers', (
      tester,
    ) async {
      expect(AppThemeText.displayLarge, greaterThanOrEqualTo(56));
      expect(AppThemeText.headlineMedium, greaterThanOrEqualTo(30));
      expect(AppThemeText.bodySmall, greaterThanOrEqualTo(15));
      expect(AppThemeText.labelSmall, greaterThanOrEqualTo(14));
      expect(
        AppThemeText.medium.index,
        greaterThanOrEqualTo(FontWeight.w500.index),
      );
      expect(
        AppThemeText.semibold.index,
        greaterThanOrEqualTo(FontWeight.w700.index),
      );
    });
  });
}
