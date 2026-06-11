import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const expectedAdminRoutes = <String>[
    '/admin/login',
    '/admin/denied',
    '/admin',
    '/admin/groups',
    '/admin/groups/:id',
    '/admin/members',
    '/admin/members/:id',
    '/admin/payment-intents',
    '/admin/payment-intents/:id',
    '/admin/payment-events',
    '/admin/payment-events/:id',
    '/admin/allocations',
    '/admin/exceptions',
    '/admin/ledger',
    '/admin/receivers',
    '/admin/receivers/:id',
    '/admin/sms',
    '/admin/sms/:id',
    '/admin/audit-logs',
    '/admin/settings',
    '/admin/feature-flags',
    '/admin/system-health',
    '/admin/admin-users',
  ];

  test('admin routes are exact', () {
    expect(adminRoutePaths, expectedAdminRoutes);
  });

  testWidgets('admin app blocks default non-admin state', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CollectAdminApp()));
    await tester.pumpAndSettle();
    expect(find.text('Collect admin login'), findsOneWidget);
    final phoneField = tester.widget<TextField>(find.byType(TextField).first);
    expect(phoneField.controller?.text, '+250788767816');
    expect(find.text('Operations overview'), findsNothing);
  });

  testWidgets('admin app renders shell under explicit admin override', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminAuthGuardProvider.overrideWithValue(
            const AdminAuthGuard(isAuthorized: true),
          ),
          adminIdentityProvider.overrideWith((ref) async => _adminIdentity),
        ],
        child: const CollectAdminApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Collect Admin'), findsWidgets);
    expect(find.text('Operations overview'), findsOneWidget);
  });

  testWidgets('admin shell can render directly', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminIdentityProvider.overrideWith((ref) async => _adminIdentity),
        ],
        child: const MaterialApp(
          home: AdminShell(
            location: '/admin',
            child: Text('Operations overview'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Collect Admin'), findsWidgets);
    expect(find.text('Operations overview'), findsOneWidget);
  });

  testWidgets('admin shell does not show fake actions or metrics', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminAuthGuardProvider.overrideWithValue(
            const AdminAuthGuard(isAuthorized: true),
          ),
          adminIdentityProvider.overrideWith((ref) async => _adminIdentity),
        ],
        child: const CollectAdminApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('BioPay'), findsNothing);
    expect(find.textContaining('wallet'), findsNothing);
  });
}

const _adminIdentity = AdminIdentity(
  userId: '00000000-0000-0000-0000-000000000001',
  displayName: 'Collect admin',
  roles: ['platform_owner'],
  permissions: ['overview.read'],
);
