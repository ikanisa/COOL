import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/shared/widgets/cool_screen_scaffold.dart';

void main() {
  group('CoolScreenScaffold', () {
    testWidgets('renders child content', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CoolScreenScaffold(child: Text('Body content')),
        ),
      );
      expect(find.text('Body content'), findsOneWidget);
    });

    testWidgets('renders title in app bar when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CoolScreenScaffold(title: 'Settings', child: Text('Body')),
        ),
      );
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('shows back button by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CoolScreenScaffold(title: 'Page', child: Text('Body')),
        ),
      );
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    });

    testWidgets('hides back button when showBackButton is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CoolScreenScaffold(
            title: 'Page',
            showBackButton: false,
            child: Text('Body'),
          ),
        ),
      );
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    });
  });
}
