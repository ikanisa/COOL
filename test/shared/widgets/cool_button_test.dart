import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/theme/app_theme_text.dart';
import 'package:cool_app/shared/widgets/cool_button.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('CoolButton', () {
    testWidgets('renders label text', (tester) async {
      await tester.pumpWidget(
        _wrap(CoolButton(label: 'Continue', onTap: () {})),
      );
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('calls onTap when pressed', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(CoolButton(label: 'Go', onTap: () => tapped = true)),
      );
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('shows spinner when isLoading is true', (tester) async {
      await tester.pumpWidget(
        _wrap(CoolButton(label: 'Save', onTap: () {}, isLoading: true)),
      );
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      // Label should not be visible during loading
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('does not call onTap when isLoading', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          CoolButton(
            label: 'Save',
            onTap: () => tapped = true,
            isLoading: true,
          ),
        ),
      );
      await tester.tap(find.byType(CoolButton));
      await tester.pump();
      expect(tapped, isFalse);
    });

    testWidgets('does not call onTap when disabled', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          CoolButton(
            label: 'Pay',
            onTap: () => tapped = true,
            isDisabled: true,
          ),
        ),
      );
      await tester.tap(find.byType(CoolButton));
      await tester.pump();
      expect(tapped, isFalse);
    });

    testWidgets('renders icon when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(
          CoolButton(label: 'Send', onTap: () {}, icon: Icons.send_rounded),
        ),
      );
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
    });

    testWidgets('secondary variant renders', (tester) async {
      await tester.pumpWidget(
        _wrap(
          CoolButton(
            label: 'Cancel',
            onTap: () {},
            variant: CoolButtonVariant.secondary,
          ),
        ),
      );
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('uses design-system CTA typography', (tester) async {
      await tester.pumpWidget(
        _wrap(CoolButton(label: 'Create Group', onTap: () {})),
      );

      final text = tester.widget<Text>(find.text('Create Group'));
      expect(text.style?.fontFamily, AppThemeText.labelFontFamily);
      expect(text.style?.fontSize, 14);
      expect(text.style?.fontWeight, FontWeight.w700);
      expect(text.style?.letterSpacing, 1.2);
    });

    testWidgets('expands vertically for large text without overflowing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SizedBox(
                  key: const ValueKey('button-host'),
                  width: 220,
                  child: CoolButton(
                    label: 'Confirm transfer and continue',
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Confirm transfer and continue'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('button-host'))).height,
        greaterThan(52),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('exposes the configured semantics label', (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _wrap(
          CoolButton(
            label: 'Continue',
            semanticsLabel: 'Continue securely',
            onTap: () {},
          ),
        ),
      );

      expect(find.bySemanticsLabel('Continue securely'), findsOneWidget);
      semantics.dispose();
    });
  });
}
