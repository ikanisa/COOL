import 'package:cool_app/features/admin/providers/admin_providers.dart';
import 'package:cool_app/features/admin/screens/audit_log_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void _configureTallViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 2560);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets('filters audit entries and expands row details', (tester) async {
    _configureTallViewport(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          adminAuditLogProvider(null).overrideWith(
            (ref) async => <Map<String, dynamic>>[
              <String, dynamic>{
                'actor_name': 'Alice',
                'action': 'create',
                'target_table': 'tickets',
                'target_id': 'ticket-1',
                'created_at': '2026-03-15T12:00:00Z',
                'old_data': <String, dynamic>{'status': 'draft'},
                'new_data': <String, dynamic>{'status': 'confirmed'},
              },
            ],
          ),
          adminAuditLogProvider('update').overrideWith(
            (ref) async => <Map<String, dynamic>>[
              <String, dynamic>{
                'actor_name': 'Beatrice',
                'action': 'update',
                'target_table': 'payments',
                'target_id': 'payment-4',
                'created_at': '2026-03-16T09:45:00Z',
                'new_data': <String, dynamic>{'state': 'reconciled'},
              },
            ],
          ),
        ],
        child: const MaterialApp(home: AuditLogScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Audit Log'), findsOneWidget);
    expect(find.text('Alice · CREATE'), findsOneWidget);

    await tester.tap(find.text('Alice · CREATE'));
    await tester.pumpAndSettle();

    expect(find.text('Previous'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.textContaining('status: draft'), findsOneWidget);
    expect(find.textContaining('status: confirmed'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Update'));
    await tester.pumpAndSettle();

    expect(find.text('Beatrice · UPDATE'), findsOneWidget);
    expect(find.text('Alice · CREATE'), findsNothing);
  });
}
