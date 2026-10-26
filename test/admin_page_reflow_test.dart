import 'package:collect_app/admin/shared/components/admin_page.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final variant in [
    (width: 320.0, scale: 1.0, stacked: true),
    (width: 390.0, scale: 2.0, stacked: true),
    (width: 1000.0, scale: 2.0, stacked: true),
    (width: 1000.0, scale: 1.0, stacked: false),
  ]) {
    testWidgets(
      'operator header reflows at ${variant.width}/${variant.scale}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(variant.width, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        var actions = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(variant.scale)),
              child: child!,
            ),
            home: Scaffold(
              body: AdminPage(
                title: 'Reconciliations',
                subtitle: 'Review pending Rwanda MoMo allocations.',
                trailing: FilledButton(
                  onPressed: () => actions++,
                  child: const Text('Review allocation'),
                ),
                child: const Text('Pending records'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final title = tester.getRect(find.text('Reconciliations'));
        final action = tester.getRect(find.byType(FilledButton));
        if (variant.stacked) {
          expect(action.top, greaterThan(title.bottom));
        } else {
          expect(action.left, greaterThan(title.right));
        }
        expect(action.right, lessThanOrEqualTo(variant.width));
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        expect(actions, 1);
      },
    );
  }
}
