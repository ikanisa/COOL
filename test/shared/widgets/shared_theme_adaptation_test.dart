import 'package:cool_app/core/theme/cool_palette.dart';
import 'package:cool_app/shared/widgets/cool_button.dart';
import 'package:cool_app/shared/widgets/cool_card.dart';
import 'package:cool_app/shared/widgets/cool_screen_scaffold.dart';
import 'package:cool_app/shared/widgets/tab_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrapWithBrightness(Brightness brightness, Widget child) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
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
          const CoolCard(child: Text('Card content')),
        ),
      );

      final ink = tester.widget<Ink>(
        find.descendant(of: find.byType(CoolCard), matching: find.byType(Ink)),
      );
      final decoration = ink.decoration! as ShapeDecoration;

      expect(decoration.color, CoolPalette.light.surface2);
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

      expect(decoration.color, CoolPalette.light.surface2);
      expect(border.top.color, CoolPalette.light.border2);
    });

    testWidgets('CoolScreenScaffold resolves light background token', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          home: const CoolScreenScaffold(child: Text('Body')),
        ),
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, CoolPalette.light.bg);
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

      expect(decoration.color, CoolPalette.light.accentGlow);
      expect(border.top.color, CoolPalette.light.accent);
    });
  });
}
