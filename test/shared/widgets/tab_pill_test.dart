import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/shared/widgets/tab_pill.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  group('TabPill', () {
    testWidgets('renders label', (tester) async {
      await tester.pumpWidget(_wrap(
        TabPill(label: 'All', isActive: false, onTap: () {}),
      ));
      expect(find.text('All'), findsOneWidget);
    });

    testWidgets('calls onTap when pressed', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        TabPill(label: 'Active', isActive: false, onTap: () => tapped = true),
      ));
      await tester.tap(find.text('Active'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('renders correctly for active state', (tester) async {
      await tester.pumpWidget(_wrap(
        TabPill(label: 'Selected', isActive: true, onTap: () {}),
      ));
      expect(find.text('Selected'), findsOneWidget);
      // AnimatedContainer renders for both states
      expect(find.byType(AnimatedContainer), findsOneWidget);
    });
  });
}
