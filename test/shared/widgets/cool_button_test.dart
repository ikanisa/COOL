import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/shared/widgets/cool_button.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('CoolButton', () {
    testWidgets('renders label text', (tester) async {
      await tester.pumpWidget(_wrap(
        CoolButton(label: 'Continue', onTap: () {}),
      ));
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('calls onTap when pressed', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        CoolButton(label: 'Go', onTap: () => tapped = true),
      ));
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('shows spinner when isLoading is true', (tester) async {
      await tester.pumpWidget(_wrap(
        CoolButton(label: 'Save', onTap: () {}, isLoading: true),
      ));
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      // Label should not be visible during loading
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('does not call onTap when isLoading', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        CoolButton(label: 'Save', onTap: () => tapped = true, isLoading: true),
      ));
      await tester.tap(find.byType(CoolButton));
      await tester.pump();
      expect(tapped, isFalse);
    });

    testWidgets('renders icon when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        CoolButton(
          label: 'Send',
          onTap: () {},
          icon: Icons.send_rounded,
        ),
      ));
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
    });

    testWidgets('secondary variant renders', (tester) async {
      await tester.pumpWidget(_wrap(
        CoolButton(
          label: 'Cancel',
          onTap: () {},
          variant: CoolButtonVariant.secondary,
        ),
      ));
      expect(find.text('Cancel'), findsOneWidget);
    });
  });
}
