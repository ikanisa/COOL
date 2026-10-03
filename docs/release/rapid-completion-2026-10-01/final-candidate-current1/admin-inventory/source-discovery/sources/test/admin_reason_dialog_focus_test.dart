import 'package:collect_app/admin/shared/components/admin_confirm_dialog.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reason remains editable with compact keyboard and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? submitted;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            viewInsets: const EdgeInsets.only(bottom: 220),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Review'),
              onPressed: () async {
                submitted = await showAdminReasonDialog(
                  context,
                  title: 'Retry notification delivery',
                  actionLabel: 'Retry delivery',
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Confirmed the recipient');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Retry delivery'));
    await tester.tap(find.text('Retry delivery'));
    await tester.pumpAndSettle();
    expect(submitted, 'Confirmed the recipient');
    expect(tester.takeException(), isNull);
  });

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
