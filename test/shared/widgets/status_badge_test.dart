import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/shared/widgets/status_badge.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('StatusBadge', () {
    testWidgets('renders label', (tester) async {
      await tester.pumpWidget(_wrap(const StatusBadge(label: 'Active')));
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('renders emoji when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(const StatusBadge(label: 'Hot', emoji: '🔥')),
      );
      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('Hot'), findsOneWidget);
    });

    testWidgets('saving preset renders correctly', (tester) async {
      await tester.pumpWidget(_wrap(const StatusBadge.saving()));
      expect(find.text('Saving'), findsOneWidget);
    });

    testWidgets('community preset renders', (tester) async {
      await tester.pumpWidget(_wrap(const StatusBadge.community()));
      expect(find.text('Community'), findsOneWidget);
    });

    testWidgets('public preset renders', (tester) async {
      await tester.pumpWidget(_wrap(const StatusBadge.public()));
      expect(find.text('Public'), findsOneWidget);
    });

    testWidgets('private preset renders', (tester) async {
      await tester.pumpWidget(_wrap(const StatusBadge.private()));
      expect(find.text('Private'), findsOneWidget);
    });

    testWidgets('offline preset renders label', (tester) async {
      await tester.pumpWidget(_wrap(const StatusBadge.offline()));
      expect(find.text('Offline'), findsOneWidget);
    });

    testWidgets('online preset renders label', (tester) async {
      await tester.pumpWidget(_wrap(const StatusBadge.online()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Online'), findsOneWidget);
    });
  });
}
