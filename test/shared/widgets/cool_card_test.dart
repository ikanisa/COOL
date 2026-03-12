import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/shared/widgets/cool_card.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('CoolCard', () {
    testWidgets('renders child content', (tester) async {
      await tester.pumpWidget(_wrap(
        const CoolCard(child: Text('Card content')),
      ));
      expect(find.text('Card content'), findsOneWidget);
    });

    testWidgets('calls onTap when tappable', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        CoolCard(onTap: () => tapped = true, child: const Text('Tap me')),
      ));
      await tester.tap(find.text('Tap me'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('renders without onTap (non-tappable)', (tester) async {
      await tester.pumpWidget(_wrap(
        const CoolCard(child: Text('Static card')),
      ));
      expect(find.text('Static card'), findsOneWidget);
    });
  });
}
