import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/shared/widgets/cool_text_field.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)));

void main() {
  group('CoolTextField', () {
    testWidgets('renders hint text', (tester) async {
      await tester.pumpWidget(_wrap(
        const CoolTextField(hint: 'Enter name'),
      ));
      expect(find.text('Enter name'), findsOneWidget);
    });

    testWidgets('renders label when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        const CoolTextField(hint: 'Enter phone', label: 'Phone'),
      ));
      expect(find.text('Phone'), findsOneWidget);
    });

    testWidgets('accepts text input', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(_wrap(
        CoolTextField(hint: 'Type here', controller: controller),
      ));
      await tester.enterText(find.byType(TextFormField), 'Hello');
      expect(controller.text, 'Hello');
    });

    testWidgets('calls onChanged callback', (tester) async {
      String? changedValue;
      await tester.pumpWidget(_wrap(
        CoolTextField(
          hint: 'Type',
          onChanged: (v) => changedValue = v,
        ),
      ));
      await tester.enterText(find.byType(TextFormField), 'Test');
      expect(changedValue, 'Test');
    });

    testWidgets('renders prefix icon when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        const CoolTextField(
          hint: 'Search',
          prefixIcon: Icons.search_rounded,
        ),
      ));
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });
  });
}
