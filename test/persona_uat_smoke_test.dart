import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Future<void> pumpLaunchFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i += 1) {
      await tester.pump();
    }
  }

  Future<void> pumpMainAppAt(
    WidgetTester tester,
    String initialLocation, {
    CollectRepository? repository,
  }) async {
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

  testWidgets('main app launches without admin or secret-bearing surface', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: CollectApp()));
    await pumpLaunchFrames(tester);

    expect(find.text('Collect'), findsWidgets);
    expect(find.text('Platform admin'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets(
    'public supporter browses public directory without receiver data leakage',
    (tester) async {
      await pumpMainAppAt(tester, '/public');

      expect(find.text('Public directory'), findsOneWidget);
      expect(find.text('Public-safe browsing'), findsOneWidget);
      expect(find.text('St Michel building fund'), findsOneWidget);
      expect(find.textContaining('+250788'), findsNothing);
      expect(find.textContaining('raw SMS'), findsOneWidget);
      expectNoGlobalSecrets();
    },
  );

  testWidgets(
    'contributor creates intent, sees MOMO instructions, and posts ledger entry',
    (tester) async {
      final repository = CollectRepository.seeded();
      await pumpMainAppAt(
        tester,
        '/collections/col-church/contribute',
        repository: repository,
      );

      expect(find.text('Contribute'), findsOneWidget);
      expect(find.text('Direct payment'), findsOneWidget);
      expect(find.text('No money held'), findsOneWidget);
      expect(
        find.text('Used only to improve matching; never public.'),
        findsOneWidget,
      );
      await tapVisible(tester, find.text('Continue to MOMO instructions'));

      expect(find.text('MOMO instructions'), findsOneWidget);
      expect(find.text('St Michel treasury'), findsOneWidget);
      expect(find.textContaining('+250788123456'), findsWidgets);
      final intent = repository.state.paymentIntents.single;
      await repository.markIntentPaid(intent.id, transactionId: 'TX-UAT-1');
      final router = GoRouter.of(
        tester.element(find.text('MOMO instructions')),
      );
      router.go('/collections/col-church/ledger');
      await pumpLaunchFrames(tester);

      expect(find.text('Ledger'), findsOneWidget);
      expect(find.text('Private evidence'), findsOneWidget);
      expect(find.text('Ledger safety'), findsOneWidget);
      expect(find.text('Anonymous supporter'), findsWidgets);
      expectNoGlobalSecrets();
    },
  );

  testWidgets(
    'creator share and invite routes preserve public and private boundaries',
    (tester) async {
      await pumpMainAppAt(tester, '/collections/col-church/share');

      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Safe share'), findsOneWidget);
      expect(
        find.textContaining('does not include phone numbers'),
        findsOneWidget,
      );
      expect(find.textContaining('+250788'), findsNothing);

      final router = GoRouter.of(tester.element(find.text('Share')));
      router.go('/collections/col-church/invite');
      await pumpLaunchFrames(tester);

      expect(find.text('Invite members'), findsOneWidget);
      expect(find.text('Private invite'), findsOneWidget);
      final inviteTarget = find.byType(TextField).first;
      await tester.ensureVisible(inviteTarget);
      await tester.enterText(inviteTarget, '038491');
      await tester.pump();
      await tapVisible(tester, find.text('Generate invite link'));

      expect(find.text('Prepared for User #038491.'), findsOneWidget);
      expect(find.textContaining('/i/'), findsOneWidget);
      expectNoGlobalSecrets();
    },
  );

  testWidgets(
    'receiver operator manual SMS ingestion goes to review without public leakage',
    (tester) async {
      await pumpMainAppAt(tester, '/receiver/manual');

      expect(find.text('Manual SMS paste'), findsOneWidget);
      expect(find.text('Restricted SMS handling'), findsOneWidget);
      expect(find.textContaining('Raw SMS is never public'), findsOneWidget);
      final fields = find.byType(TextField);
      await tester.ensureVisible(fields.at(1));
      await tester.enterText(
        fields.at(1),
        'You have received 10,000 RWF from Jane. TxId ABC123. Balance is 500000 RWF.',
      );
      await tapVisible(tester, find.text('Ingest SMS'));

      expect(find.text('SMS parsed as needs_review.'), findsOneWidget);
      expectNoGlobalSecrets();
    },
  );

  testWidgets('admin app opens at login for default non-admin state', (
    tester,
  ) async {
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
    await pumpLaunchFrames(tester);

    expect(find.text('Collect admin login'), findsOneWidget);
    expect(find.text('Operations overview'), findsNothing);
    expect(find.textContaining('service_role'), findsNothing);
  });

  testWidgets(
    'admin personas review moderation, payment, compliance, audit, and health routes',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeAdminRepository();
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
      expect(find.text('Collect Admin'), findsWidgets);
      expect(find.textContaining('service_role'), findsNothing);

      final router = GoRouter.of(
        tester.element(find.text('Operations overview')),
      );
      router.go('/admin/public-requests');
      await pumpLaunchFrames(tester);
      expect(find.text('Public requests'), findsWidgets);
      expect(find.text('St Michel public listing'), findsOneWidget);
      await tapTableAction(tester, 'Approve');
      await tester.enterText(
        find.byType(TextField).last,
        'Public copy reviewed',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await pumpLaunchFrames(tester);
      expect(
        repository.actions,
        contains('admin_review_public_request:Public copy reviewed'),
      );

      router.go('/admin/unallocated');
      await pumpLaunchFrames(tester);
      expect(find.text('Unallocated payments'), findsWidgets);
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
      await tapVisible(tester, find.text('Reveal raw SMS'));
      expect(
        find.text('Enter a reason before revealing sensitive data.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byType(TextField).last,
        'Compliance audit sample',
      );
      await tester.tap(find.text('Reveal raw SMS'));
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
  );
}

const _platformOwnerIdentity = AdminIdentity(
  userId: '00000000-0000-0000-0000-000000000001',
  displayName: 'Collect platform owner',
  roles: ['platform_owner'],
  permissions: [
    'public_requests.review',
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
  }) async {
    return AdminListResult(
      rows: switch (rpcName) {
        'admin_list_public_requests' => const [
          AdminTableRowData(
            id: 'public-request-1',
            title: 'St Michel public listing',
            subtitle: 'Public copy waiting for moderator review',
            status: 'needs_review',
            amount: '',
          ),
        ],
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
