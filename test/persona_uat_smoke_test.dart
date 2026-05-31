import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/foundation.dart';
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

  testWidgets('member browses groups without receiver data leakage', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/groups');

    expect(find.text('Groups'), findsWidgets);
    expect(find.text('Automated allocation'), findsOneWidget);
    expect(find.text('St Michel building fund'), findsOneWidget);
    expect(find.textContaining('+250788'), findsNothing);
    expect(find.textContaining('MoMo SMS'), findsOneWidget);
    expectNoGlobalSecrets();
  });

  testWidgets('contributor creates intent and waits for SMS allocation', (
    tester,
  ) async {
    final repository = CollectRepository.seeded();
    await pumpMainAppAt(
      tester,
      '/groups/col-church/contribute',
      repository: repository,
    );

    expect(find.text('Contribute'), findsWidgets);
    expect(find.text('Automated SMS match'), findsOneWidget);
    expect(find.text('Collect ID'), findsOneWidget);
    expect(find.textContaining('manual'), findsNothing);

    final intent = await repository.createPaymentIntent(
      const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 5000),
    );
    final router = GoRouter.of(
      tester.element(find.text('Automated SMS match').first),
    );
    router.go('/groups/col-church/pay/${intent.id}');
    await pumpLaunchFrames(tester);

    expect(find.text('Payment intent'), findsWidgets);
    expect(find.text('Waiting for MoMo SMS'), findsOneWidget);
    expect(find.text('St Michel treasury'), findsOneWidget);
    expect(find.textContaining('+250788123456'), findsWidgets);
    router.go('/groups/col-church/ledger');
    await pumpLaunchFrames(tester);

    expect(find.text('Ledger'), findsOneWidget);
    expect(find.text('Private evidence'), findsOneWidget);
    expect(find.text('Ledger safety'), findsOneWidget);
    expect(find.text('Collect ID 038491'), findsWidgets);
    expectNoGlobalSecrets();
  });

  testWidgets('creator share routes preserve group boundaries', (tester) async {
    await pumpMainAppAt(tester, '/groups/col-church/share');

    expect(find.text('Share group'), findsWidgets);
    expect(find.text('Group sharing'), findsOneWidget);
    expect(
      find.textContaining('does not include phone numbers'),
      findsOneWidget,
    );
    expect(find.textContaining('+250788'), findsNothing);

    final router = GoRouter.of(tester.element(find.text('Share group')));
    router.go('/groups/col-church/invite');
    await pumpLaunchFrames(tester);

    expect(find.text('Share group'), findsWidgets);
    expect(find.text('SMS'), findsWidgets);
    expect(find.text('WhatsApp'), findsWidgets);
    expect(find.text('Copy deep link'), findsWidgets);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('/c/'), findsWidgets);
    expectNoGlobalSecrets();
  });

  testWidgets('member opens shared group link by slug', (tester) async {
    await pumpMainAppAt(tester, '/c/st-michel-building-fund');
    await pumpLaunchFrames(tester);

    expect(find.text('Group joined'), findsOneWidget);
    expect(find.text('St Michel building fund'), findsWidgets);
    expect(find.text('Open group'), findsWidgets);
    expect(find.textContaining('+250788'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('iPhone create group entry shows Android-only warning', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpMainAppAt(tester, '/home');

      await tapVisible(tester, find.byTooltip('Create group'));

      expect(
        find.text('group creation is available only on Android'),
        findsWidgets,
      );
      expect(find.text('Create group'), findsNothing);
      expectNoGlobalSecrets();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iPhone direct create route does not expose group form', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpMainAppAt(tester, '/groups/create');

      expect(find.text('Create group'), findsWidgets);
      expect(find.text('Group name'), findsNothing);
      expect(find.text('Receiver MoMo number'), findsNothing);
      expect(
        find.text('group creation is available only on Android'),
        findsWidgets,
      );
      expectNoGlobalSecrets();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('new profile does not prefill a sample MoMo number', (
    tester,
  ) async {
    await pumpMainAppAt(
      tester,
      '/settings/profile',
      repository: CollectRepository(),
    );

    expect(find.text('Profile'), findsWidgets);
    expect(find.textContaining('+250788123456'), findsNothing);
    expect(find.text('MoMo number'), findsOneWidget);
    expectNoGlobalSecrets();
  });

  testWidgets('settings exposes SMS access without manual paste', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/settings');

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('SMS access'), findsOneWidget);
    expect(find.textContaining('manual'), findsNothing);
    expectNoGlobalSecrets();
  });

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
    'admin personas review group operations, payment, compliance, audit, and health routes',
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
      router.go('/admin/groups');
      await pumpLaunchFrames(tester);
      expect(find.text('Groups'), findsWidgets);

      router.go('/admin/allocations');
      await pumpLaunchFrames(tester);
      expect(find.text('Allocations'), findsWidgets);
      expect(find.text('Allocated MOMO event'), findsOneWidget);

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
        'admin_list_allocations' => const [
          AdminTableRowData(
            id: 'event-allocated',
            title: 'Allocated MOMO event',
            subtitle: 'Matched to pending intent',
            status: 'allocated',
            amount: 'RWF 5,000',
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
