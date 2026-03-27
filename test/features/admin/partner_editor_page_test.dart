import 'package:cool_app/features/admin/widgets/partner_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders semantic partner form with save action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            return MaterialApp(home: PartnerEditorPage(ref: ref));
          },
        ),
      ),
    );

    expect(find.text('New Partner'), findsOneWidget);
    expect(find.text('Name *'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Save'), findsOneWidget);
  });
}
