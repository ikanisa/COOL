import 'dart:io';

import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

String readAdminRuntimeLibrary() {
  return [
    'lib/admin/core/admin_runtime.dart',
    'lib/admin/core/admin_login_runtime.dart',
    'lib/admin/core/admin_list_runtime.dart',
    'lib/admin/core/admin_detail_runtime.dart',
  ].map((path) => File(path).readAsStringSync()).join('\n');
}

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
    expect(script, contains('"COLLECT_PUBLIC_LANDING_HOME" => "true"'));
    expect(script, isNot(contains('--dart-define=SUPABASE_SERVICE_ROLE_KEY')));
    expect(script, isNot(contains('--dart-define=WHATSAPP_CLOUD_API_TOKEN')));
    expect(script, isNot(contains('--dart-define=OPENAI_API_KEY')));
    expect(script, isNot(contains('ADMIN_PWA_EVIDENCE_MODE')));
  });

  test('admin authenticated render evidence is explicit and masked', () {
    final script = File(
      'scripts/admin_pwa_authenticated_render_smoke.sh',
    ).readAsStringSync();
    final evidenceMode = File(
      'lib/admin/core/admin_evidence_mode.dart',
    ).readAsStringSync();

    expect(script, contains('--dart-define=ADMIN_PWA_EVIDENCE_MODE=true'));
    expect(script, contains('admin_pwa_evidence_mode'));
    expect(script, contains('png_capture_check.mjs'));
    expect(script, contains('/admin/payment-events'));
    expect(script, contains('/admin/sms/sms-1'));
    expect(evidenceMode, contains('bool.fromEnvironment'));
    expect(evidenceMode, contains('Masked sender and allocation review'));
    expect(evidenceMode, contains('+250***4321'));
    expect(evidenceMode, isNot(contains('service_role')));
    expect(evidenceMode, isNot(contains('MOMO body redacted for test')));
  });

  test('admin evidence overrides stay disabled by default', () {
    expect(adminPwaEvidenceMode, isFalse);
    expect(adminEvidenceOverrides(), isEmpty);
  });

  testWidgets('admin app blocks default non-admin state', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CollectAdminApp()));
    await tester.pumpAndSettle();
    expect(find.text('Collect admin login'), findsOneWidget);
    final phoneField = tester.widget<TextField>(find.byType(TextField).first);
    expect(phoneField.controller?.text, isEmpty);
    expect(find.text('Operations overview'), findsNothing);
  });

  testWidgets('admin login exposes accessible controls and status', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(const ProviderScope(child: CollectAdminApp()));
      await tester.pumpAndSettle();

      expect(find.semantics.byLabel('Collect admin login'), findsOne);
      expect(find.semantics.byLabel('WhatsApp phone'), findsWidgets);
      expect(
        find.semantics.byHint(
          'Registered Rwanda WhatsApp number used for Collect admin sign-in.',
        ),
        findsOne,
      );
      expect(find.semantics.byLabel('Send admin WhatsApp OTP'), findsOne);
      expect(find.semantics.byHint('Sends the OTP.'), findsOne);
      expect(find.semantics.byLabel(RegExp('Secure')), findsWidgets);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('admin login sanitizes raw Supabase hook failures', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(_RawHookErrorRepository()),
        ],
        child: const CollectAdminApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Send WhatsApp OTP'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'WhatsApp could not send the OTP. Check the approved template and try again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('status code returned from hook'), findsNothing);
    expect(find.textContaining('AuthRetryableFetchException'), findsNothing);
  });

  test('admin login does not render raw Supabase hook errors', () {
    final runtime = readAdminRuntimeLibrary();

    expect(runtime, contains('WhatsApp could not send the OTP.'));
    expect(runtime, contains('That code is expired or already used.'));
    expect(
      runtime,
      contains('WhatsApp verified, but this profile is not approved'),
    );
    expect(runtime, contains('status code returned from hook'));
    expect(runtime, contains('authretryablefetchexception'));
    expect(runtime, contains('error sending confirmation'));
    expect(runtime, isNot(contains('_error = error.toString()')));
  });

  test('admin OTP login uses persistent session state', () {
    final runtime = readAdminRuntimeLibrary();
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
    expect(runtime, isNot(contains("rpc<dynamic>('admin_bootstrap")));
    expect(runtime, contains('ref.invalidate(adminAuthGuardProvider)'));
    expect(runtime, isNot(contains('client?.auth.currentUser == null')));
  });

  test('admin bootstrap is disabled for browser roles', () {
    final migration = File(
      'supabase/migrations/20260612103000_disable_browser_admin_bootstrap.sql',
    ).readAsStringSync();
    final uat = File(
      'scripts/collect_admin_security_uat.sh',
    ).readAsStringSync();
    final readiness = File(
      'scripts/supabase_production_readiness.sh',
    ).readAsStringSync();

    expect(migration, contains('revoke execute'));
    expect(migration, contains('from public, anon, authenticated'));
    expect(migration, contains('to service_role'));
    expect(
      migration,
      contains('admin_bootstrap_whatsapp_operator is disabled'),
    );
    expect(
      uat,
      contains('admin_bootstrap_whatsapp_operator must not be executable'),
    );
    expect(
      readiness,
      isNot(
        contains(
          "('authenticated', 'admin_bootstrap_whatsapp_operator', 'EXECUTE')",
        ),
      ),
    );
  });

  test('release status requires fresh Admin PWA live gate', () {
    final script = File('scripts/release_status.sh').readAsStringSync();

    expect(script, contains('scripts/admin_pwa_live_gate.sh'));
    expect(script, contains('admin_pwa_live_gate'));
    expect(
      script,
      contains('Admin PWA live deployment gate failed for the current URL.'),
    );
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
    expect(find.text('Groups'), findsNothing);
    expect(find.text('SMS'), findsNothing);
  });

  testWidgets('admin unknown routes render branded recovery actions', (
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

    GoRouter.of(
      tester.element(find.text('Operations overview')),
    ).go('/admin/missing-screen');
    await tester.pumpAndSettle();

    expect(find.text('Admin route not found'), findsOneWidget);
    expect(find.textContaining('/admin/missing-screen'), findsOneWidget);
    expect(find.text('This admin screen is unavailable'), findsOneWidget);
    expect(find.text('Operations overview'), findsOneWidget);
    expect(find.text('Admin login'), findsOneWidget);
  });

  testWidgets('admin shell can render directly', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
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
      expect(find.text('Groups'), findsNothing);
      expect(
        find.semantics.byLabel('Collect admin primary navigation'),
        findsOne,
      );
      expect(find.semantics.byLabel('Overview admin section'), findsOne);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('admin shell denies direct route without permission', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminIdentityProvider.overrideWith((ref) async => _adminIdentity),
        ],
        child: const MaterialApp(
          home: AdminShell(
            location: '/admin/sms',
            child: Text('Raw SMS queue'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Raw SMS queue'), findsNothing);
    expect(find.text('Admin access required'), findsOneWidget);
    expect(find.text('Missing sms.metadata.read.'), findsOneWidget);
  });

  testWidgets('admin shell matches seeded role-matrix navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpAdminShell(
      tester,
      identity: _supportIdentity,
      location: '/admin/payment-events',
      child: const Text('Support payment queue'),
    );
    expect(find.text('Support payment queue'), findsOneWidget);
    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Ledger'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Admin users'), findsNothing);

    await _pumpAdminShell(
      tester,
      identity: _complianceIdentity,
      location: '/admin/sms',
      child: const Text('Compliance SMS metadata'),
    );
    expect(find.text('Compliance SMS metadata'), findsOneWidget);
    expect(find.text('SMS'), findsOneWidget);
    expect(find.text('Audit logs'), findsOneWidget);
    expect(find.text('Groups'), findsNothing);
    expect(find.text('Receivers'), findsNothing);
    expect(find.text('Settings'), findsNothing);

    await _pumpAdminShell(
      tester,
      identity: _paymentsIdentity,
      location: '/admin/receivers',
      child: const Text('Payments receiver routes'),
    );
    expect(find.text('Payments receiver routes'), findsOneWidget);
    expect(find.text('Payment intents'), findsOneWidget);
    expect(find.text('SMS parsing'), findsOneWidget);
    expect(find.text('Receivers'), findsOneWidget);
    expect(find.text('Members'), findsNothing);
    expect(find.text('Admin users'), findsNothing);

    await _pumpAdminShell(
      tester,
      identity: _readOnlyFullIdentity,
      location: '/admin/settings',
      child: const Text('Read-only settings catalog'),
    );
    expect(find.text('Read-only settings catalog'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Feature flags'), findsOneWidget);
    expect(find.text('Admin users'), findsOneWidget);
  });

  testWidgets(
    'admin shell explains missing permission for role direct routes',
    (tester) async {
      await _pumpAdminShell(
        tester,
        identity: _supportIdentity,
        location: '/admin/settings',
        child: const Text('Settings content'),
      );
      expect(find.text('Settings content'), findsNothing);
      expect(find.text('Admin access required'), findsOneWidget);
      expect(find.text('Missing settings.read.'), findsOneWidget);
    },
  );

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

  testWidgets('admin list pages page high-volume queues', (tester) async {
    final semantics = tester.ensureSemantics();
    final clipboardCalls = <MethodCall>[];
    _PagingAdminRepository.lastSlaKey = '';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardCalls.add(call);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    try {
      tester.view.physicalSize = const Size(1200, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminRepositoryProvider.overrideWithValue(_PagingAdminRepository()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AdminRpcListPage(
                title: 'SMS parsing',
                rpcName: 'admin_list_payment_events',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Showing 1-25 of 30'), findsOneWidget);
      expect(find.text('Ambiguous matches'), findsOneWidget);
      expect(find.text('Ambiguous'), findsOneWidget);
      expect(find.text('SMS parsing export: current page CSV'), findsOneWidget);
      expect(find.text('Export CSV'), findsOneWidget);
      expect(
        find.text('Target: Persisted SLA from admin policy'),
        findsOneWidget,
      );
      expect(find.text('Owner: Live operations owner'), findsOneWidget);
      expect(_PagingAdminRepository.lastSlaKey, 'admin_list_payment_events');
      expect(
        find.semantics.byLabel('Export SMS parsing current page CSV'),
        findsOne,
      );
      expect(find.semantics.byLabel('Next admin results page'), findsOne);
      expect(
        find.semantics.byHint('Shows the next page of admin queue results.'),
        findsOne,
      );
      expect(find.text('Queue item 1'), findsOneWidget);
      expect(find.text('Queue item 25'), findsOneWidget);
      expect(find.text('Queue item 26'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Export CSV'));
      await tester.pumpAndSettle();

      expect(clipboardCalls, hasLength(1));
      expect(clipboardCalls.single.arguments, isA<Map<dynamic, dynamic>>());
      final clipboardPayload =
          clipboardCalls.single.arguments as Map<dynamic, dynamic>;
      expect(clipboardPayload['text'], contains('id,title,subtitle,status'));
      expect(clipboardPayload['text'], contains('row-1,Queue item 1'));
      expect(find.text('SMS parsing CSV copied for export'), findsOneWidget);

      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();

      expect(find.text('Showing 26-30 of 30'), findsOneWidget);
      expect(find.text('Queue item 25'), findsNothing);
      expect(find.text('Queue item 26'), findsOneWidget);
      expect(find.text('Queue item 30'), findsOneWidget);
      expect(
        _PagingAdminRepository.lastQuery,
        contains(
          'admin_list_payment_events:limit=25:offset=25:sort=created_at_desc',
        ),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('payment event detail renders operator workflow panel', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final repository = _DetailAdminRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminRepositoryProvider.overrideWithValue(repository),
            adminIdentityProvider.overrideWith(
              (ref) async => _paymentReparseIdentity,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AdminDetailPage(
                title: 'Payment event detail',
                rpcName: 'admin_get_payment_event',
                id: 'event-1',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SMS payment event review'), findsOneWidget);
      expect(find.text('Parsed payment event.'), findsOneWidget);
      expect(find.text('Transaction'), findsOneWidget);
      expect(find.text('MOMO-001'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('RWF 7,777'), findsOneWidget);
      expect(
        find.semantics.byLabel('SMS payment event review detail panel'),
        findsOne,
      );
      expect(find.semantics.byHint('Parsed payment event.'), findsOne);
      expect(find.semantics.byValue('MOMO-001'), findsOne);
      expect(
        find.semantics.byLabel('Request SMS payment event reparse'),
        findsOne,
      );
      expect(
        find.semantics.byHint(
          'Opens a reason dialog before queuing this payment event for parser review.',
        ),
        findsOne,
      );
      expect(find.text('MOMO payment received from REDACTED.'), findsNothing);
      expect(find.textContaining('"raw_body"'), findsNothing);
      expect(find.textContaining('{'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Request reparse'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Parser missed allocation',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Request reparse').last,
      );
      await tester.pumpAndSettle();

      expect(
        repository.actions,
        contains('admin_reparse_payment_event:Parser missed allocation'),
      );
      expect(
        find.semantics.byLabel('Record SMS payment event review operator note'),
        findsOne,
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Record note'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Operator confirmed member impact',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Record note'));
      await tester.pumpAndSettle();

      expect(
        repository.actions,
        contains(
          'admin_record_operator_note:parsed_payment_event:Operator confirmed member impact',
        ),
      );
      expect(find.text('Operator note recorded'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('payment event actions hide without reparse permission', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(_DetailAdminRepository()),
          adminIdentityProvider.overrideWith(
            (ref) async => _paymentReadOnlyIdentity,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AdminRpcListPage(
              title: 'SMS parsing',
              rpcName: 'admin_list_payment_events',
              actionKind: 'payment_event_reparse',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Parsed MOMO event'), findsOneWidget);
    expect(find.text('Reparse'), findsNothing);
  });

  testWidgets('feature flags expose audited toggle actions', (tester) async {
    final repository = _FeatureFlagAdminRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(repository),
          adminIdentityProvider.overrideWith(
            (ref) async => _featureFlagManagerIdentity,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AdminRpcListPage(
              title: 'Feature flags',
              rpcName: 'admin_list_feature_flags',
              actionKind: 'feature_flag_toggle',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('enable_internal_receiver_mode'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Enable'), findsOneWidget);
    expect(
      find.semantics.byLabel(
        'Enable feature flag enable_internal_receiver_mode',
      ),
      findsOne,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Enable'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Enable for staged UAT',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Enable flag'));
    await tester.pumpAndSettle();

    expect(
      repository.actions,
      contains(
        'admin_set_feature_flag:enable_internal_receiver_mode:true:Enable for staged UAT',
      ),
    );
  });

  testWidgets('feature flag actions hide without manage permission', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(
            _FeatureFlagAdminRepository(),
          ),
          adminIdentityProvider.overrideWith(
            (ref) async => _readOnlyFullIdentity,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AdminRpcListPage(
              title: 'Feature flags',
              rpcName: 'admin_list_feature_flags',
              actionKind: 'feature_flag_toggle',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('enable_internal_receiver_mode'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Enable'), findsNothing);
  });

  testWidgets('group detail exposes audited support status actions', (
    tester,
  ) async {
    final repository = _DetailAdminRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(repository),
          adminIdentityProvider.overrideWith(
            (ref) async => _collectionModerationIdentity,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AdminDetailPage(
              title: 'Group detail',
              rpcName: 'admin_get_collection',
              id: 'collection-1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Group operations profile'), findsOneWidget);
    expect(find.text('Group support status'), findsOneWidget);
    expect(find.semantics.byLabel('Group support status actions'), findsOne);
    expect(find.widgetWithText(OutlinedButton, 'Set private'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Reject public'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Archive'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Archive'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Inactive duplicate group');
    await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
    await tester.pumpAndSettle();

    expect(
      repository.actions,
      contains(
        'admin_update_collection_support_status:archived:Inactive duplicate group',
      ),
    );
    expect(find.text('Group status updated: Archive'), findsOneWidget);
  });

  testWidgets(
    'group support status actions hide without moderation permission',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminRepositoryProvider.overrideWithValue(_DetailAdminRepository()),
            adminIdentityProvider.overrideWith(
              (ref) async => _collectionReadOnlyIdentity,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AdminDetailPage(
                title: 'Group detail',
                rpcName: 'admin_get_collection',
                id: 'collection-1',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Group operations profile'), findsOneWidget);
      expect(find.text('Group support status'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Archive'), findsNothing);
    },
  );

  testWidgets('raw SMS reveal is gated by compliance permission', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _DetailAdminRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(repository),
          adminIdentityProvider.overrideWith((ref) async => _supportIdentity),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AdminSmsDetailPage(id: 'sms-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Raw SMS restricted'), findsOneWidget);
    expect(find.text('Reveal raw SMS'), findsNothing);
    expect(repository.actions, isEmpty);

    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminRepositoryProvider.overrideWithValue(repository),
            adminIdentityProvider.overrideWith(
              (ref) async => _complianceIdentity,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: AdminSmsDetailPage(id: 'sms-1')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Raw SMS sensitive data reveal gate',
        ),
        findsOne,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Raw SMS reveal reason',
        ),
        findsOne,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Reveal Raw SMS',
        ),
        findsOne,
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Reveal reason'),
        'Compliance audit sample',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Reveal raw SMS'));
      await tester.pumpAndSettle();

      expect(find.text('MOMO body redacted for test'), findsOneWidget);
      expect(
        repository.actions,
        contains('admin_reveal_raw_sms:Compliance audit sample'),
      );
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _pumpAdminShell(
  WidgetTester tester, {
  required AdminIdentity identity,
  required String location,
  required Widget child,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminIdentityProvider.overrideWith((ref) async => identity)],
      child: MaterialApp(
        home: AdminShell(location: location, child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _adminIdentity = AdminIdentity(
  userId: '00000000-0000-0000-0000-000000000001',
  displayName: 'Collect admin',
  roles: ['platform_owner'],
  permissions: ['overview.read'],
);

const _supportIdentity = AdminIdentity(
  userId: '00000000-0000-0000-0000-000000000010',
  displayName: 'Collect support admin',
  roles: ['support_admin'],
  permissions: [
    'overview.read',
    'public_requests.read',
    'collections.read',
    'users.read',
    'receivers.read',
    'sms.metadata.read',
    'payment_events.read',
    'payments.read',
    'audit.read',
    'system_health.read',
  ],
);

const _complianceIdentity = AdminIdentity(
  userId: '00000000-0000-0000-0000-000000000011',
  displayName: 'Collect compliance admin',
  roles: ['compliance_admin'],
  permissions: [
    'overview.read',
    'users.read',
    'sms.metadata.read',
    'sms.raw.reveal',
    'payment_events.read',
    'payments.read',
    'ledger.read',
    'audit.read',
    'system_health.read',
  ],
);

const _paymentsIdentity = AdminIdentity(
  userId: '00000000-0000-0000-0000-000000000012',
  displayName: 'Collect payments admin',
  roles: ['payments_admin'],
  permissions: [
    'overview.read',
    'collections.read',
    'receivers.read',
    'sms.metadata.read',
    'payment_events.read',
    'payment_events.reparse',
    'payments.read',
    'payments.allocate',
    'ledger.read',
    'audit.read',
    'system_health.read',
  ],
);

const _readOnlyFullIdentity = AdminIdentity(
  userId: '00000000-0000-0000-0000-000000000013',
  displayName: 'Collect read-only admin',
  roles: ['read_only_admin'],
  permissions: [
    'overview.read',
    'public_requests.read',
    'collections.read',
    'users.read',
    'receivers.read',
    'sms.metadata.read',
    'payment_events.read',
    'payments.read',
    'ledger.read',
    'audit.read',
    'feature_flags.read',
    'settings.read',
    'system_health.read',
    'admin_users.read',
  ],
);

const _paymentReparseIdentity = AdminIdentity(
  userId: '00000000-0000-0000-0000-000000000002',
  displayName: 'Collect payments admin',
  roles: ['payments_admin'],
  permissions: ['payment_events.read', 'payment_events.reparse'],
);

const _paymentReadOnlyIdentity = AdminIdentity(
  userId: '00000000-0000-0000-0000-000000000003',
  displayName: 'Collect read-only admin',
  roles: ['read_only_admin'],
  permissions: ['payment_events.read'],
);

const _collectionModerationIdentity = AdminIdentity(
  userId: '00000000-0000-0000-0000-000000000004',
  displayName: 'Collect operations admin',
  roles: ['operations_admin'],
  permissions: ['collections.read', 'collections.moderate'],
);

const _collectionReadOnlyIdentity = AdminIdentity(
  userId: '00000000-0000-0000-0000-000000000005',
  displayName: 'Collect read-only admin',
  roles: ['read_only_admin'],
  permissions: ['collections.read'],
);

const _featureFlagManagerIdentity = AdminIdentity(
  userId: '00000000-0000-0000-0000-000000000006',
  displayName: 'Collect platform owner',
  roles: ['platform_owner'],
  permissions: ['feature_flags.read', 'feature_flags.manage'],
);

class _RawHookErrorRepository extends AdminRepository {
  _RawHookErrorRepository() : super(null);

  @override
  Future<void> sendOtp({required String phone}) async {
    throw Exception(
      'AuthRetryableFetchException: status code returned from hook: 500',
    );
  }
}

class _PagingAdminRepository extends AdminRepository {
  _PagingAdminRepository() : super(null);

  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
  }) async {
    lastQuery = '$rpcName:limit=$limit:offset=$offset:sort=$sortBy';
    final allRows = [
      for (var index = 1; index <= 30; index += 1)
        AdminTableRowData(
          id: 'row-$index',
          title: 'Queue item $index',
          subtitle: 'Payment event review',
          status: 'needs_review',
          amount: 'RWF $index',
        ),
    ];
    final start = (offset ?? 0).clamp(0, allRows.length);
    final end = (start + (limit ?? allRows.length)).clamp(
      start,
      allRows.length,
    );
    return AdminListResult(
      rows: allRows.sublist(start, end),
      total: allRows.length,
    );
  }

  static String lastQuery = '';
  static String lastSlaKey = '';

  @override
  Future<AdminQueueSla?> queueSla(String queueKey) async {
    lastSlaKey = queueKey;
    return const AdminQueueSla(
      target: 'Persisted SLA from admin policy',
      owner: 'Live operations owner',
      escalation: 'Escalate from persisted policy',
    );
  }
}

class _FeatureFlagAdminRepository extends AdminRepository {
  _FeatureFlagAdminRepository() : super(null);

  final actions = <String>[];

  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
  }) async {
    return const AdminListResult(
      rows: [
        AdminTableRowData(
          id: 'flag-1',
          title: 'enable_internal_receiver_mode',
          subtitle: 'Internal Android SMS receiver',
          status: 'disabled',
          amount: '',
        ),
      ],
      total: 1,
    );
  }

  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) async {
    actions.add(
      '$rpcName:${params['p_key']}:${params['p_enabled']}:${params['p_reason']}',
    );
    return {'status': 'updated'};
  }
}

class _DetailAdminRepository extends AdminRepository {
  _DetailAdminRepository() : super(null);

  final actions = <String>[];

  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
  }) async {
    return const AdminListResult(
      rows: [
        AdminTableRowData(
          id: 'event-1',
          title: 'Parsed MOMO event',
          subtitle: 'Waiting for review',
          status: 'needs_review',
          amount: 'RWF 7,777',
        ),
      ],
    );
  }

  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async {
    return switch (rpcName) {
      'admin_get_collection' => {
        'id': id,
        'title': 'St Michel building fund',
        'slug': 'st-michel-building-fund',
        'description': 'Church construction support',
        'status': 'public_approved',
        'active_members': '24',
        'active_receivers': '1',
        'pending_payment_intents': '2',
        'created_at': '2026-06-12T05:00:00Z',
      },
      'admin_get_sms_metadata' => {
        'id': id,
        'sender_masked': 'MOMO',
        'receiver_masked': '+250***1222',
        'status': 'needs_review',
        'received_at': '2026-06-12T05:00:00Z',
        'raw_body': 'MOMO body redacted for test',
      },
      _ => {
        'id': id,
        'transaction_id': 'MOMO-001',
        'amount': 'RWF 7,777',
        'sender_masked': '+250***4321',
        'receiver_masked': '+250***1222',
        'payment_intent_id': 'intent-1',
        'status': 'needs_review',
        'created_at': '2026-06-12T05:00:00Z',
        'raw_body': 'MOMO payment received from REDACTED.',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) async {
    if (rpcName == 'admin_record_operator_note') {
      actions.add('$rpcName:${params['p_entity_type']}:${params['p_body']}');
    } else if (rpcName == 'admin_update_collection_support_status') {
      actions.add('$rpcName:${params['p_status']}:${params['p_reason']}');
    } else {
      actions.add('$rpcName:${params['p_reason']}');
    }
    if (rpcName == 'admin_reveal_raw_sms') {
      return {'message': 'MOMO body redacted for test'};
    }
    return {'status': 'queued'};
  }
}
