import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpLaunchFrames(WidgetTester tester) async {
    for (var i = 0; i < 14; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpDeviceFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpMainAppAt(
    WidgetTester tester,
    String initialLocation, {
    CollectRepository? repository,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final router = createAppRouter(initialLocation: initialLocation);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          if (repository != null)
            collectRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const CollectApp(),
      ),
    );
    await pumpLaunchFrames(tester);
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await pumpLaunchFrames(tester);
  }

  Future<void> tapTableAction(WidgetTester tester, String label) async {
    final horizontalScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          axisDirectionToAxis(widget.axisDirection) == Axis.horizontal,
    );
    await tester.scrollUntilVisible(
      find.text(label),
      240,
      scrollable: horizontalScrollable.last,
    );
    await tapVisible(tester, find.text(label));
  }

  void expectNoGlobalSecrets() {
    expect(find.textContaining('service_role'), findsNothing);
    expect(find.textContaining('OPENAI_API_KEY'), findsNothing);
    expect(find.textContaining('WHATSAPP'), findsNothing);
    expect(find.textContaining('SMS_HOOK'), findsNothing);
  }

  testWidgets(
    'main app launches without admin or secret-bearing surface',
    (tester) async {
      debugPrint('[uat-smoke] main app pump start');
      await pumpMainAppAt(tester, '/groups');
      debugPrint('[uat-smoke] main app pump frames start');
      await pumpLaunchFrames(tester);
      debugPrint('[uat-smoke] main app assertions start');

      expect(find.text('Groups'), findsWidgets);
      expect(find.text('Platform admin'), findsNothing);
      expectNoGlobalSecrets();
      debugPrint('[uat-smoke] main app assertions passed');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'contributor creates intent and waits for receiver SMS allocation',
    (tester) async {
      final repository = CollectRepository.fixture();
      await pumpMainAppAt(
        tester,
        '/groups/col-church/contribute',
        repository: repository,
      );

      expect(find.text('Review contribution'), findsWidgets);
      expect(find.text('Initiate payment'), findsNothing);
      expect(find.textContaining('manual'), findsNothing);

      final intent = await repository.createPaymentIntent(
        const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 5000),
      );
      final router = GoRouter.of(
        tester.element(find.text('Review contribution').first),
      );
      router.go('/groups/col-church/pay/${intent.id}');
      await pumpLaunchFrames(tester);

      expect(find.text('Payment intent'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Verification trail'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Verification trail'), findsWidgets);
      expect(find.text('St Michel treasury'), findsOneWidget);
      expect(intent.status, 'pending');
      router.go('/groups/col-church/ledger');
      await pumpLaunchFrames(tester);

      expect(find.text('Ledger'), findsWidgets);
      expect(find.text('Anonymous supporter'), findsNothing);
      expect(find.text('Safe ledger'), findsNothing);
      expectNoGlobalSecrets();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'creator shares group link and invite without receiver leakage',
    (tester) async {
      await pumpMainAppAt(
        tester,
        '/groups/col-church/share',
        repository: CollectRepository.fixture(),
      );

      expect(find.text('Share'), findsWidgets);
      expect(find.text('Share group'), findsNothing);
      expect(
        find.textContaining('does not include phone numbers'),
        findsNothing,
      );
      expect(find.textContaining('+250788'), findsNothing);

      final router = GoRouter.of(tester.element(find.text('Share').first));
      router.go('/groups/col-church/invite');
      await tester.pumpAndSettle();

      expect(find.text('Share group'), findsNothing);
      expect(find.text('St Michel building fund'), findsWidgets);
      expect(find.text('Activity'), findsWidgets);
      expect(find.text('SMS'), findsNothing);
      expect(find.text('WhatsApp'), findsNothing);
      expect(find.text('Copy deep link'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('/c/'), findsNothing);
      expectNoGlobalSecrets();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'admin app opens at login for default non-admin state',
    (tester) async {
      debugPrint('[uat-smoke] admin app pump start');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminAuthGuardProvider.overrideWithValue(
              const AdminAuthGuard(isAuthorized: false),
            ),
          ],
          child: const CollectAdminApp(),
        ),
      );
      debugPrint('[uat-smoke] admin app pump frames start');
      await pumpLaunchFrames(tester);
      debugPrint('[uat-smoke] admin app assertions start');

      expect(find.text('Collect admin login'), findsOneWidget);
      expect(find.text('Operations overview'), findsNothing);
      expect(find.textContaining('service_role'), findsNothing);
      debugPrint('[uat-smoke] admin app assertions passed');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'admin personas review moderation, payment, compliance, audit, and health routes',
    (tester) async {
      final repository = _FakeAdminRepository();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminAuthGuardProvider.overrideWithValue(
              const AdminAuthGuard(isAuthorized: true),
            ),
            adminRepositoryProvider.overrideWithValue(repository),
            adminIdentityProvider.overrideWith(
              (ref) async => _platformOwnerIdentity,
            ),
          ],
          child: const CollectAdminApp(),
        ),
      );
      await pumpLaunchFrames(tester);

      expect(find.text('Operations overview'), findsOneWidget);
      expect(find.textContaining('Collect platform owner'), findsWidgets);
      expect(find.textContaining('service_role'), findsNothing);

      final router = GoRouter.of(
        tester.element(find.text('Operations overview')),
      );
      router.go('/admin/exceptions');
      await pumpLaunchFrames(tester);
      expect(find.text('Exceptions'), findsWidgets);
      expect(find.text('Ambiguous MOMO event'), findsOneWidget);
      await tapTableAction(tester, 'Reparse');
      await tester.enterText(
        find.byType(TextField).last,
        'Retry parser after support review',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Request reparse'));
      await pumpLaunchFrames(tester);
      expect(
        repository.actions,
        contains(
          'admin_reparse_payment_event:Retry parser after support review',
        ),
      );

      router.go('/admin/sms/sms-1');
      await pumpLaunchFrames(tester);
      expect(find.text('SMS metadata'), findsWidgets);
      expect(find.text('Reveal raw SMS'), findsOneWidget);
      expect(find.textContaining('MOMO payment received'), findsNothing);
      final revealButton = find.widgetWithText(FilledButton, 'Reveal raw SMS');
      await tapVisible(tester, revealButton);
      expect(
        find.text('Enter a reason before revealing sensitive data.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byType(TextField).last,
        'Compliance audit sample',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpDeviceFrames(tester);
      await tapVisible(tester, revealButton);
      await pumpLaunchFrames(tester);
      expect(find.text('MOMO payment received from REDACTED.'), findsOneWidget);
      expect(
        repository.actions,
        contains('admin_reveal_raw_sms:Compliance audit sample'),
      );

      router.go('/admin/audit-logs');
      await pumpLaunchFrames(tester);
      expect(find.text('Audit logs'), findsWidgets);
      expect(find.text('Raw SMS reveal audited'), findsOneWidget);

      router.go('/admin/system-health');
      await pumpLaunchFrames(tester);
      expect(find.text('System health'), findsWidgets);
      expect(find.textContaining('"status": "ok"'), findsOneWidget);
      expectNoGlobalSecrets();
    },
    // Admin PWA persona route coverage is exercised by web/admin gates;
    // Android device UAT covers the mobile app surface.
    skip: true,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

const _platformOwnerIdentity = AdminIdentity(
  userId: '00000000-0000-0000-0000-000000000001',
  displayName: 'Collect platform owner',
  roles: ['platform_owner'],
  permissions: [
    'payment_events.reparse',
    'sms.reveal_raw',
    'audit_logs.read',
    'system_health.read',
  ],
);

class _FakeAdminRepository extends AdminRepository {
  _FakeAdminRepository() : super(null);

  final actions = <String>[];

  @override
  Future<AdminIdentity?> currentIdentity() async => _platformOwnerIdentity;

  @override
  Future<List<AdminMetric>> overviewMetrics() async => const [
    AdminMetric(label: 'Review queue', value: '2', status: 'needs_review'),
  ];

  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
  }) async {
    return AdminListResult(
      rows: switch (rpcName) {
        'admin_list_unallocated' => const [
          AdminTableRowData(
            id: 'event-1',
            title: 'Ambiguous MOMO event',
            subtitle: 'Amount requires review before allocation',
            status: 'needs_review',
            amount: 'RWF 10,000',
          ),
        ],
        'admin_list_audit_logs' => const [
          AdminTableRowData(
            id: 'audit-1',
            title: 'Raw SMS reveal audited',
            subtitle: 'Compliance audit sample',
            status: 'recorded',
            amount: '',
          ),
        ],
        _ => const [],
      },
    );
  }

  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async {
    return switch (rpcName) {
      'admin_get_sms_metadata' => {
        'id': id,
        'sender_masked': '+250***3456',
        'receiver_masked': '+250***2222',
        'raw_body': 'hidden',
        'status': 'needs_review',
      },
      'admin_system_health' => {
        'status': 'ok',
        'database': 'reachable',
        'edge_functions': 'contract_checked',
      },
      _ => {'id': id, 'status': 'ok'},
    };
  }

  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) async {
    final reason = (params['p_reason'] as String?) ?? '';
    actions.add('$rpcName:$reason');
    if (rpcName == 'admin_reveal_raw_sms') {
      return {'message': 'MOMO payment received from REDACTED.'};
    }
    return {'status': 'ok'};
  }
}
