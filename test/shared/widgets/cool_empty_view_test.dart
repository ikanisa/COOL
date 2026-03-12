import 'package:cool_app/shared/widgets/cool_empty_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoolEmptyView', () {
    testWidgets('displays message and default icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CoolEmptyView(message: 'No items found'),
          ),
        ),
      );

      expect(find.text('No items found'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_rounded), findsOneWidget);
    });

    testWidgets('hides action button when action is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CoolEmptyView(message: 'Empty'),
          ),
        ),
      );

      // No TextButton present.
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('shows action button and calls callback', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoolEmptyView(
              message: 'No trips yet',
              action: () => tapped = true,
              actionLabel: 'Create Trip',
            ),
          ),
        ),
      );

      expect(find.text('Create Trip'), findsOneWidget);
      await tester.tap(find.text('Create Trip'));
      expect(tapped, true);
    });

    testWidgets('supports custom icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CoolEmptyView(
              message: 'No results',
              icon: Icons.search_off_rounded,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
    });
  });
}
