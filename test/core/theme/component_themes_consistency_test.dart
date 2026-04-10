import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/core/theme/cool_foundations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/google_fonts_test_assets.dart';

/// Tests that ThemeData component themes use the correct semantic tokens.
void main() {
  setUp(setUpBundledGoogleFonts);
  tearDown(tearDownBundledGoogleFonts);

  const semanticColors = CoolSemanticColors.dark;

  group('dark component themes', () {
    testWidgets('AppBar background is transparent', (tester) async {
      final darkTheme = AppTheme.dark;
      expect(darkTheme.appBarTheme.backgroundColor, Colors.transparent);
    });

    testWidgets('ElevatedButton uses primary action color', (tester) async {
      final darkTheme = AppTheme.dark;
      final style = darkTheme.elevatedButtonTheme.style!;
      final bgColor = style.backgroundColor!.resolve({});
      expect(bgColor, semanticColors.buttonPrimaryBackground);
    });

    testWidgets('FAB uses primary action color', (tester) async {
      final darkTheme = AppTheme.dark;
      expect(
        darkTheme.floatingActionButtonTheme.backgroundColor,
        semanticColors.buttonPrimaryBackground,
      );
    });

    testWidgets('Scaffold background matches appBackground', (tester) async {
      final darkTheme = AppTheme.dark;
      expect(darkTheme.scaffoldBackgroundColor, semanticColors.appBackground);
    });

    testWidgets('Card uses cardSurface', (tester) async {
      final darkTheme = AppTheme.dark;
      expect(darkTheme.cardTheme.color, semanticColors.cardSurface);
    });

    testWidgets('Divider follows the no-line rule', (tester) async {
      final darkTheme = AppTheme.dark;
      expect(darkTheme.dividerTheme.color, Colors.transparent);
      expect(darkTheme.dividerTheme.thickness, 0);
    });

    testWidgets('ColorScheme primary matches buttonPrimaryBackground', (
      tester,
    ) async {
      final darkTheme = AppTheme.dark;
      expect(
        darkTheme.colorScheme.primary,
        semanticColors.buttonPrimaryBackground,
      );
    });

    testWidgets('CoolSemanticColors extension is registered', (tester) async {
      final darkTheme = AppTheme.dark;
      expect(darkTheme.extension<CoolSemanticColors>(), isNotNull);
    });

    testWidgets('BottomAppBar uses glass surface', (tester) async {
      final darkTheme = AppTheme.dark;
      expect(darkTheme.bottomAppBarTheme.color, semanticColors.glassSurface);
    });
  });
}
