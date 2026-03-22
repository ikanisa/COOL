import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/core/theme/cool_foundations.dart';
import 'package:cool_app/shared/widgets/cool_button.dart';
import 'package:cool_app/shared/widgets/cool_card.dart';
import 'package:cool_app/shared/widgets/cool_screen_scaffold.dart';
import 'package:cool_app/shared/widgets/tab_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrapWithBrightness(Brightness brightness, Widget child) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('Shared widgets adapt to theme brightness', () {
    testWidgets('CoolCard resolves light semantic surface by brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithBrightness(
          Brightness.light,
          const CoolCard(useGradient: false, child: Text('Card content')),
        ),
      );

      final ink = tester.widget<Ink>(
        find.descendant(of: find.byType(CoolCard), matching: find.byType(Ink)),
      );
      final decoration = ink.decoration! as ShapeDecoration;

      expect(decoration.color, CoolSemanticColors.light.cardSurface);
    });

    testWidgets('CoolButton secondary variant resolves light surface tokens', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithBrightness(
          Brightness.light,
          CoolButton(
            label: 'Cancel',
            onTap: () {},
            variant: CoolButtonVariant.secondary,
          ),
        ),
      );

      final ink = tester.widget<Ink>(
        find.descendant(
          of: find.byType(CoolButton),
          matching: find.byType(Ink),
        ),
      );
      final decoration = ink.decoration! as BoxDecoration;
      final border = decoration.border! as Border;

      expect(
        decoration.color,
        CoolSemanticColors.light.buttonSecondaryBackground,
      );
      expect(border.top.color, CoolSemanticColors.light.borderStrong);
    });

    testWidgets('CoolScreenScaffold resolves light background token', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const CoolScreenScaffold(child: Text('Body')),
        ),
      );

      // CoolScreenScaffold uses CoolScreenBackground wrapper with a
      // transparent Scaffold — verify that pattern.
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Colors.transparent);
    });

    testWidgets('TabPill active state resolves light accent tokens', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithBrightness(
          Brightness.light,
          TabPill(label: 'Selected', isActive: true, onTap: () {}),
        ),
      );

      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final decoration = container.decoration! as BoxDecoration;
      final border = decoration.border! as Border;

      expect(decoration.color, CoolSemanticColors.light.chipSelectedBackground);
      expect(border.top.color, CoolSemanticColors.light.accent);
    });
  });
}
