import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_error_boundary.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/shared/components/admin_empty_state.dart';
import 'package:collect_app/admin/shared/components/admin_loading_state.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/admin_read_fixture.dart';
import 'support/admin_gateway_fixture.dart';
import 'support/admin_exception_fixture.dart';
import 'support/admin_entity_audit_state_fixture.dart';
import 'package:collect_app/admin/core/admin_entity_audit.dart';
import 'package:collect_app/admin/core/admin_exception_models.dart';

// Router surface inventory; source fixtures exercise presentation/state routing.
// Strict actual SDK wire/session contracts are tested separately.
const _reads = {
  '/admin': 'admin_overview',
  '/admin/groups': 'admin_list_collections',
  '/admin/groups/:id': 'admin_get_collection',
  '/admin/users': 'admin_list_non_member_users',
  '/admin/users/:id': 'admin_get_user',
  '/admin/members': 'admin_list_members',
  '/admin/members/:id': 'admin_get_member_record',
  '/admin/payees': 'admin_list_collect_payees',
  '/admin/transactions': 'admin_list_collect_transactions',
  '/admin/transactions/:id': 'admin_get_collect_transaction',
  '/admin/reconciliations': 'admin_list_collect_reconciliations',
  '/admin/ledgers': 'admin_list_collect_ledgers',
  '/admin/sms-receipts': 'admin_list_hybrid_sms_receipts',
  '/admin/sms-receipts/:id': 'admin_get_hybrid_sms_receipt',
  '/admin/notifications': 'admin_list_notifications',
  '/admin/notifications/:id': 'admin_get_notification',
  '/admin/sms-gateway': 'admin_list_gateway_devices_v1',
  '/admin/exceptions': 'admin_list_operational_exceptions_v2',
  '/admin/audit-logs': 'admin_list_audit_logs',
  adminAuditStateRoute: 'admin_get_operator_entity_audit_v1',
  '/admin/settings': 'admin_list_settings',
  '/admin/feature-flags': 'admin_list_feature_flags',
  '/admin/system-health': 'admin_system_health',
  '/admin/automations': 'admin_system_health',
  '/admin/admin-users': 'admin_list_admin_users',
  '/admin/admin-users/:id': 'admin_get_admin_user',
};

const _additionalReads = {
  '/admin': [
    'admin_receipt_overview_v1',
    'admin_system_health',
    'collect-notification-operator',
  ],
  '/admin/automations': [
    'collect-notification-operator',
    'list_collect_shadow_runs_v1',
  ],
};

class _StateRepository extends AdminEvidenceRepository {
  _StateRepository({
    required this.health,
    this.empty = false,
    this.barrier,
    this.auditOwner = false,
  });
  final bool auditOwner;
  final Map<String, dynamic> health;
  final bool empty;
  final Completer<void>? barrier;
  bool revoked = false;
  final reads = <String>[];
  Future<void> _read(String rpc) async {
    reads.add(rpc);
    await barrier?.future;
  }

  @override
  Future<AdminIdentity?> currentIdentity() async {
    if (revoked) return null;
    final identity = await super.currentIdentity();
    return auditOwner && identity != null
        ? adminAuditStateIdentity(identity)
        : identity;
  }

  @override
  Future<Map<String, dynamic>> operatorEntityAudit(
    AdminEntityAuditQuery query,
  ) async {
    await _read('admin_get_operator_entity_audit_v1');
    return adminAuditStateFixture(
      DateTime.parse(health['checked_at'] as String),
      query,
      empty: empty,
    );
  }

  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async => null; // Explicit supported fixture adapter.
  @override
  Future<Map<String, dynamic>> receiptOverview({String? countryCode}) async {
    await _read('admin_receipt_overview_v1');
    return adminReceiptOverviewFixture(
      DateTime.parse(health['checked_at'] as String),
      empty: empty,
    );
  }

  @override
  Future<Map<String, dynamic>> smsQueueHealth() async {
    await _read('collect-notification-operator');
    return {
      'enabled': false,
      'queued': 0,
      'awaiting_confirmation': 0,
      'send_started': 0,
      'uncertain': 0,
      'suppressed': 0,
      'active_workers': 0,
      'oldest_queued_at': null,
      'observed_at': health['checked_at'],
    };
  }

  @override
  Future<Map<String, dynamic>> gatewayDevices({
    int limit = 20,
    DateTime? beforeEnrolledAt,
    String? beforeDeviceId,
  }) async {
    await _read('admin_list_gateway_devices_v1');
    return adminGatewayListFixture(
      DateTime.parse(health['checked_at'] as String),
      empty: empty,
      limit: limit,
    );
  }

  @override
  Future<Map<String, dynamic>> exceptionInbox({
    bool active = true,
    int limit = 20,
    AdminExceptionSource? source,
    DateTime? beforeChangedAt,
    String? beforeId,
  }) async {
    await _read('admin_list_operational_exceptions_v2');
    return adminExceptionListFixture(
      DateTime.parse(health['checked_at'] as String),
      empty: empty,
      limit: limit,
    );
  }

  @override
  Future<List<AdminMetric>> overviewMetrics() async {
    await _read('admin_overview');
    return empty ? [] : super.overviewMetrics();
  }

  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
    String? countryCode,
  }) async {
    await _read(rpcName);
    return empty
        ? const AdminListResult(rows: [], total: 0)
        : super.list(
            rpcName,
            search: search,
            status: status,
            limit: limit,
            offset: offset,
            sortBy: sortBy,
            countryCode: countryCode,
          );
  }

  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async {
    await _read(rpcName);
    if (rpcName == 'admin_system_health') return health;
    return empty ? {} : super.detail(rpcName, id);
  }

  @override
  Future<Map<String, dynamic>> shadowRuns({
    int limit = 20,
    DateTime? beforeStartedAt,
    String? beforeRunId,
  }) async {
    await _read('list_collect_shadow_runs_v1');
    final value =
        jsonDecode(
              File(
                'contracts/collect-shadow-supervisor-v1.fixture.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final now = DateTime.parse(health['checked_at'] as String);
    value['checked_at'] = now.toIso8601String();
    final row = (value['rows'] as List).single as Map<String, dynamic>;
    row['started_at'] = now
        .subtract(const Duration(seconds: 4))
        .toIso8601String();
    row['lease_expires_at'] = now
        .add(const Duration(seconds: 116))
        .toIso8601String();
    row['sampled_at'] = now
        .subtract(const Duration(seconds: 2))
        .toIso8601String();
    row['completed_at'] = now
        .subtract(const Duration(seconds: 1))
        .toIso8601String();
    if (empty) {
      value['rows'] = [];
      value['total'] = 0;
    }
    return value;
  }
}

void main() {
  final health = Map<String, dynamic>.from(
    (jsonDecode(
              File(
                'test/fixtures/admin_operational_health148.json',
              ).readAsStringSync(),
            )
            as Map)['receipt']
        as Map,
  );
  final checkedAt = DateTime.parse(health['checked_at'] as String);
  test('all declared protected routes have explicit state fixtures', () {
    expect(
      _reads.keys.toSet(),
      adminRoutePaths
          .where((p) => p != '/admin/login' && p != '/admin/denied')
          .toSet(),
    );
  });
  Future<ProviderContainer> open(
    WidgetTester tester,
    _StateRepository repo,
    String path,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(null),
        adminAuthGuardProvider.overrideWithValue(
          const AdminAuthGuard(isAuthorized: true),
        ),
        adminAuthUserIdProvider.overrideWithValue(
          '00000000-0000-0000-0000-00000000e001',
        ),
        adminReconciliationSessionKeyProvider.overrideWithValue(
          '00000000-0000-0000-0000-00000000e001/synthetic-state-session',
        ),
        adminRepositoryProvider.overrideWithValue(repo),
        if (path.startsWith('/admin/audit-logs/entity/'))
          adminAuthSessionScopeProvider.overrideWith(
            (_) =>
                AdminAuditStateSessions('00000000-0000-0000-0000-00000000e001'),
          ),
        adminClockProvider.overrideWithValue(() => checkedAt),
      ],
    );
    addTearDown(container.dispose);
    container.read(adminRouterProvider).go(path);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CollectAdminApp(),
      ),
    );
    await tester.pump();
    return container;
  }

  for (final route in _reads.keys) {
    final path = adminAuditStatePath(route, 'synthetic-state-record');
    final auditOwner = route == adminAuditStateRoute;
    testWidgets('allowed $route uses its declared data provider', (
      tester,
    ) async {
      final repo = _StateRepository(health: health, auditOwner: auditOwner);
      final container = await open(tester, repo, path);
      await tester.pumpAndSettle();
      expect(repo.reads, contains(_reads[route]));
      expect(
        repo.reads,
        containsAll(_additionalReads[route] ?? const <String>[]),
      );
      expect(find.byType(AdminSafeErrorPanel), findsNothing);
      expect(find.text('Admin access required'), findsNothing);
      expect(
        container
            .read(adminRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        path,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets('loading $route cannot present pending records', (
      tester,
    ) async {
      final gate = Completer<void>();
      final repo = _StateRepository(
        health: health,
        barrier: gate,
        auditOwner: auditOwner,
      );
      await open(tester, repo, path);
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo.reads, contains(_reads[route]));
      expect(
        route == '/admin/sms-gateway'
            ? find.byType(LinearProgressIndicator)
            : route == '/admin/automations'
            ? find.byType(CircularProgressIndicator)
            : find.byType(AdminLoadingState),
        findsWidgets,
      );
      expect(find.byType(AdminSafeErrorPanel), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    if (route != '/admin/system-health' && route != '/admin/automations') {
      testWidgets('empty $route is explicit after a successful read', (
        tester,
      ) async {
        final repo = _StateRepository(
          health: health,
          empty: true,
          auditOwner: auditOwner,
        );
        await open(tester, repo, path);
        await tester.pumpAndSettle();
        expect(repo.reads, contains(_reads[route]));
        if (route == '/admin') {
          // Measurements precede the queue in the lazy Overview workspace.
          // Exercise its real scroll rather than assume the queue is mounted.
          await tester.scrollUntilVisible(
            find.text('Queue is clear'),
            300,
            scrollable: find.descendant(
              of: find.byKey(const Key('admin-overview-workspace')),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Queue is clear'), findsOneWidget);
        }
        expect(
          route == adminAuditStateRoute
              ? find.text('No retained actions in this history window')
              : route == '/admin/exceptions'
              ? find.text('No recorded exceptions in this view')
              : route == '/admin/sms-gateway'
              ? find.text('No enrolled devices')
              : find.byType(AdminEmptyState),
          findsWidgets,
        );
        expect(find.byType(AdminSafeErrorPanel), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
    testWidgets('revoked $route removes previously authorized content', (
      tester,
    ) async {
      final repo = _StateRepository(health: health, auditOwner: auditOwner);
      final container = await open(tester, repo, path);
      await tester.pumpAndSettle();
      expect(repo.reads, contains(_reads[route]));
      final requests = repo.reads.length;
      repo.revoked = true;
      container.invalidate(adminIdentityProvider);
      await tester.pumpAndSettle();
      expect(find.text('Admin access required'), findsOneWidget);
      expect(repo.reads, hasLength(requests));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
