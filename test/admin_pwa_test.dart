import 'dart:io';

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

  test('admin release build injects only public Supabase browser config', () {
    final script = File(
      'scripts/admin_pwa_release_build.sh',
    ).readAsStringSync();

    expect(script, contains('SUPABASE_PRODUCTION_URL'));
    expect(script, contains('SUPABASE_PRODUCTION_ANON_KEY'));
    expect(script, contains('--dart-define-from-file='));
    expect(script, contains('"SUPABASE_URL"'));
    expect(script, contains('"SUPABASE_ANON_KEY"'));
    expect(script, contains('"ADMIN_APP_URL"'));
    expect(script, contains('"APP_ENVIRONMENT" => "production"'));
    expect(script, isNot(contains('--dart-define=SUPABASE_SERVICE_ROLE_KEY')));
    expect(script, isNot(contains('--dart-define=WHATSAPP_CLOUD_API_TOKEN')));
    expect(script, isNot(contains('--dart-define=OPENAI_API_KEY')));
  });

  testWidgets('admin app blocks default non-admin state', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CollectAdminApp()));
    await tester.pumpAndSettle();
    expect(find.text('Collect admin login'), findsOneWidget);
    final phoneField = tester.widget<TextField>(find.byType(TextField).first);
    expect(phoneField.controller?.text, '+250788767816');
    expect(find.text('Operations overview'), findsNothing);
  });

  test('admin login does not render raw Supabase hook errors', () {
    final runtime = File(
      'lib/admin/core/admin_runtime.dart',
    ).readAsStringSync();

    expect(runtime, contains('WhatsApp could not send the OTP.'));
    expect(runtime, contains('That code is expired or already used.'));
    expect(
      runtime,
      contains('WhatsApp verified, but admin profile setup failed.'),
    );
    expect(runtime, contains('status code returned from hook'));
    expect(runtime, contains('AuthRetryableFetchException'));
    expect(runtime, isNot(contains('_error = error.toString()')));
  });

  test('admin OTP login uses persistent session state', () {
    final runtime = File(
      'lib/admin/core/admin_runtime.dart',
    ).readAsStringSync();
    final guard = File(
      'lib/admin/core/admin_auth_guard.dart',
    ).readAsStringSync();
    final module = File(
      'lib/core/supabase/supabase_module.dart',
    ).readAsStringSync();

    expect(module, contains('Supabase.initialize'));
    expect(guard, contains('auth.currentSession != null'));
    expect(runtime, contains('final response = await client.auth.verifyOTP'));
    expect(runtime, contains('response.session == null'));
    expect(runtime, contains('admin_bootstrap_whatsapp_operator'));
    expect(runtime, contains('ref.invalidate(adminAuthGuardProvider)'));
    expect(runtime, isNot(contains('client?.auth.currentUser == null')));
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
