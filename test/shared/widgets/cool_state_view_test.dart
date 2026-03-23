import 'package:cool_app/shared/widgets/cool_state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('CoolStateView', () {
    testWidgets('renders title, message, and action', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        _wrap(
          CoolStateView.error(
            title: 'Connection failed',
            message: 'Please try again in a moment.',
            actionLabel: 'Retry',
            onAction: () => tapped = true,
          ),
        ),
      );

      expect(find.text('Connection failed'), findsOneWidget);
      expect(find.text('Please try again in a moment.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('compact loading state still renders copy', (tester) async {
      await tester.pumpWidget(
        _wrap(
          CoolStateView.loading(
            title: 'Loading',
            message: 'Fetching your dashboard.',
            compact: true,
          ),
        ),
      );

      expect(find.text('Loading'), findsOneWidget);
      expect(find.text('Fetching your dashboard.'), findsOneWidget);
    });
  });
}
