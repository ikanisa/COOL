import 'package:collect_app/admin/shared/components/admin_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reason dialog restores focus to its triggering control', (
    tester,
  ) async {
    final triggerFocus = FocusNode(debugLabel: 'reason-dialog-trigger');
    addTearDown(triggerFocus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              focusNode: triggerFocus,
              onPressed: () => showAdminReasonDialog(
                context,
                title: 'Retry notification delivery',
                actionLabel: 'Retry delivery',
              ),
              child: const Text('Retry failed delivery'),
            ),
          ),
        ),
      ),
    );

    triggerFocus.requestFocus();
    await tester.pump();
    expect(triggerFocus.hasFocus, isTrue);

    await tester.tap(find.text('Retry failed delivery'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(triggerFocus.hasFocus, isTrue);
  });
}
