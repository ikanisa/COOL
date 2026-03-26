import 'package:cool_app/shared/widgets/cool_error_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoolErrorView', () {
    testWidgets('displays message and icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CoolErrorView(message: 'Something went wrong')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('hides retry button when onRetry is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CoolErrorView(message: 'Error')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Try Again'), findsNothing);
    });

    testWidgets('shows retry button and calls callback', (tester) async {
      var retryCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoolErrorView(
              message: 'Error happened',
              onRetry: () => retryCount++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Try Again'), findsOneWidget);
      await tester.tap(find.text('Try Again'));
      expect(retryCount, 1);
    });

    testWidgets('supports custom icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CoolErrorView(
              message: 'Offline',
              icon: Icons.wifi_off_rounded,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    });

    testWidgets('compact mode reduces padding', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CoolErrorView(message: 'Compact', compact: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Compact'), findsOneWidget);
    });
  });
}
