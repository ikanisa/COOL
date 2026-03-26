import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/shared/widgets/section_title.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('SectionTitle', () {
    testWidgets('renders title text', (tester) async {
      await tester.pumpWidget(_wrap(const SectionTitle(title: 'My Groups')));
      expect(find.text('My Groups'), findsOneWidget);
    });

    testWidgets('renders action label and calls onAction', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          SectionTitle(
            title: 'My Groups',
            actionLabel: 'See all',
            action: () => tapped = true,
          ),
        ),
      );
      expect(find.text('See all'), findsOneWidget);
      await tester.tap(find.text('See all'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('hides action label when null', (tester) async {
      await tester.pumpWidget(_wrap(const SectionTitle(title: 'Heading')));
      expect(find.text('Heading'), findsOneWidget);
      // No action label rendered
      expect(find.byType(GestureDetector), findsNothing);
    });
  });
}
