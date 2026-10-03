import 'package:collect_app/admin/shared/components/admin_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final input in [' ', 'a' * 1001, '😀' * 1001]) {
    testWidgets('reason rejects ${input.runes.length} code points', (
      tester,
    ) async {
      String? submitted;
      await _open(tester, (value) => submitted = value);
      await tester.enterText(find.byType(TextField), input);
      await tester.pump();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Apply'),
      );
      expect(button.onPressed, isNull);
      expect(submitted, isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  }
  for (final input in ['a' * 1000, '😀' * 1000, '  Reviewed\nrecipient  ']) {
    testWidgets('reason preserves ${input.runes.length} code point input', (
      tester,
    ) async {
      String? submitted;
      await _open(tester, (value) => submitted = value);
      await tester.enterText(find.byType(TextField), input);
      await tester.pump();
      await tester.ensureVisible(find.text('Apply'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(submitted, input.trim());
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('oversize reason is retained for correction and cancellation', (
    tester,
  ) async {
    String? submitted;
    await _open(tester, (value) => submitted = value);
    final input = 'r' * 1001;
    await tester.enterText(find.byType(TextField), input);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      input,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(submitted, isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });
}

Future<void> _open(WidgetTester tester, void Function(String?) receipt) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => receipt(
              await showAdminReasonDialog(
                context,
                title: 'Accountable reason',
                actionLabel: 'Apply',
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
