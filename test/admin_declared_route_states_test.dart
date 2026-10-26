import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_error_boundary.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/admin_governed_settings_models.dart';
import 'package:collect_app/admin/core/admin_governed_settings_sdk.dart';
import 'package:collect_app/admin/core/admin_receipt_operational_history_models.dart';
import 'package:collect_app/admin/core/admin_receipt_operational_history_sdk.dart';
import 'package:collect_app/admin/core/admin_privacy_review_host.dart';
import 'package:collect_app/admin/core/admin_privacy_review_sdk.dart';
import 'package:collect_app/admin/shared/components/admin_empty_state.dart';
import 'package:collect_app/admin/shared/components/admin_loading_state.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/admin_read_fixture.dart';
import 'support/admin_gateway_fixture.dart';
import 'support/admin_exception_fixture.dart';
import 'support/admin_entity_audit_state_fixture.dart';
import 'support/settings_fixture.dart' as settings;
import 'support/privacy_review_fixtures.dart' as privacy;
import 'package:collect_app/admin/core/admin_entity_audit.dart';
import 'package:collect_app/admin/core/admin_exception_models.dart';

// Router surface inventory; source fixtures exercise presentation/state routing.
// Strict actual SDK wire/session contracts are tested separately.
const _runRoute = '/admin/automations/runs/:id';
const _runId = 'c0574327-4eeb-4cd4-a43a-e5ad1d918135';

bool _ownerReadRoute(String route) =>
    route == adminAuditStateRoute ||
    route == '/admin/settings' ||
    route == '/admin/privacy-requests' ||
    route == _runRoute;

const _reads = {
  '/admin': 'admin_overview',
  '/admin/groups': 'admin_list_collections',
  '/admin/groups/:id': 'admin_get_collection',
  '/admin/users': 'admin_list_users',
  '/admin/privacy-requests': 'admin_list_account_deletion_reviews_v1',
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
  '/admin/settings': 'admin_list_runtime_controls_v2',
  '/admin/feature-flags': 'admin_list_feature_flags',
  '/admin/system-health': 'admin_system_health',
  '/admin/automations': 'admin_system_health',
  _runRoute: 'admin_get_receipt_operation_run_v1',
  '/admin/staff': 'admin_list_staff_users',
  '/admin/staff/:id': 'admin_get_staff_user_v1',
  '/admin/sms-metadata': 'admin_list_sms_metadata',
  '/admin/sms-metadata/:id': 'admin_get_sms_metadata',
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
  _runRoute: ['admin_list_receipt_operation_evidence_v1'],
};

class _StateSettingsApi extends settings.SettingsApiFake {
  _StateSettingsApi(this.repository);
  final _StateRepository repository;

  @override
  Future<AdminSettingsCatalog> catalog(
    AdminSettingsFamily family, {
    int limit = 25,
    Map<String, Object?>? after,
  }) async {
    await repository._read('admin_list_runtime_controls_v2');
    final raw = settings.observed('catalog');
    final now = DateTime.parse(repository.health['checked_at'] as String);
    raw['limit'] = limit;
    raw['checked_at'] = settingsUtc(now);
    raw['sample_valid_until'] = settingsUtc(
      now.add(const Duration(seconds: 60)),
    );
    if (repository.empty) {
      raw['rows'] = <Object>[];
      raw['next_cursor'] = null;
    }
    // Original family, descriptor, identities and revisions remain parsed.
    // Only presentation time/page size and the explicit empty page are adapted.
    return AdminSettingsCatalog.parse(raw, family, limit: limit);
  }
}

Map<String, dynamic> _historyStateFixture(
  String name,
  DateTime now, {
  bool empty = false,
}) {
  final raw =
      jsonDecode(
            File(
              'test/fixtures/admin_receipt_operational_history_actual/$name.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final delta = now.toUtc().difference(
    DateTime.parse(raw['checked_at'] as String),
  );
  Object? shift(Object? value) {
    if (value is Map) {
      return {for (final e in value.entries) e.key: shift(e.value)};
    }
    if (value is List) return value.map(shift).toList();
    if (value is String && RegExp(r'^\d{4}-.*T.*Z$').hasMatch(value)) {
      return historyUtc(DateTime.parse(value).add(delta));
    }
    return value;
  }

  final adapted = Map<String, dynamic>.from(shift(raw) as Map);
  if (adapted['run'] != null) {
    // The quota window remains the UTC date boundary of the adapted run start;
    // shifting midnight by the read-time delta would violate the actual SDK.
    final start = historyInstant((adapted['run'] as Map)['started_at']);
    (adapted['quota_usage'] as Map)['window_start'] = historyUtc(
      DateTime.utc(start.year, start.month, start.day),
    );
  }
  if (empty) adapted['rows'] = <Object>[];
  // This remains a partial observed history window, including original IDs and
  // explicit incomplete attribution. An empty page never invents run completion.
  return adapted;
}

class _StateRepository extends AdminEvidenceRepository {
  _StateRepository({
    required this.health,
    this.empty = false,
    this.barrier,
    this.ownerRead = false,
    this.failReads = false,
  });
  final bool ownerRead;
  final bool failReads;
  final Map<String, dynamic> health;
  final bool empty;
  final Completer<void>? barrier;
  bool revoked = false;
  final reads = <String>[];
  Future<void> _read(String rpc) async {
    reads.add(rpc);
    await barrier?.future;
    if (failReads) {
      throw const FormatException(
        'SENSITIVE_PROVIDER_CANARY private_phone private_sql',
      );
    }
  }

  @override
  Future<AdminIdentity?> currentIdentity() async {
    if (revoked) return null;
    final identity = await super.currentIdentity();
    return ownerRead && identity != null
        ? adminAuditStateIdentity(identity)
        : identity;
  }

  @override
  AdminGovernedSettingsApi get governedSettings => _StateSettingsApi(this);

  @override
  AdminReceiptOperationalHistoryApi get receiptOperationalHistory =>
      AdminReceiptOperationalHistoryApi(
        rpc: (name, parameters) async {
          await _read(name);
          if (parameters['p_run_id'] != _runId) {
            throw StateError('Unexpected operational run identity');
          }
          final now = DateTime.parse(health['checked_at'] as String);
          if (name == 'admin_get_receipt_operation_run_v1') {
            return _historyStateFixture('run-closed', now);
          }
          if (name == 'admin_list_receipt_operation_evidence_v1') {
            return _historyStateFixture(
              'evidence-${parameters['p_section']}',
              now,
              empty: empty,
            );
          }
          throw StateError('Unexpected operational history reader');
        },
      );

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
    if (rpcName == 'admin_get_staff_user_v1') {
      return empty
          ? {}
          : {
              'id': id,
              'public_id': '974002',
              'display_name': 'Synthetic Staff record',
              'email': 'staff@example.test',
              'staff_access': true,
              'operator_approved': true,
              'created_at': adminReadDate,
            };
    }
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
                'test/fixtures/declared_admin/collect-shadow-supervisor-v1.fixture.json',
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
        collectBackendClientProvider.overrideWithValue(null),
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
        if (path.startsWith('/admin/audit-logs/entity/') ||
            path == '/admin/settings' ||
            path.startsWith('/admin/automations/runs/'))
          adminAuthSessionScopeProvider.overrideWith(
            (_) =>
                AdminAuditStateSessions('00000000-0000-0000-0000-00000000e001'),
          ),
        adminSettingsCheckpointStoreProvider.overrideWithValue(
          settings.MemorySettingsStore(),
        ),
        if (path == '/admin/privacy-requests') ...[
          // Declared route/state presentation fixture only. The production
          // concrete repository, bearer and session gate have separate mounts.
          adminPrivacyReviewAccessProvider.overrideWith((ref) {
            final identity = ref.watch(adminIdentityProvider).asData?.value;
            if (identity == null ||
                !adminPrivacyReviewIdentityAllows(identity)) {
              return null;
            }
            var current = true;
            ref.onDispose(() => current = false);
            ref.listen(adminIdentityProvider, (_, _) => current = false);
            bool valid() => current && !repo.revoked;
            return AdminPrivacyReviewAccess(
              api: AdminPrivacyReviewSdk(
                rpc: (name, parameters) async {
                  await repo._read(name);
                  if (name != 'admin_list_account_deletion_reviews_v1') {
                    throw StateError('Unexpected route presentation action');
                  }
                  return privacy.privacyPageRaw(
                    checked: checkedAt,
                    limit: parameters['p_limit'] as int,
                    items: repo.empty
                        ? []
                        : [
                            privacy.privacyItem(
                              accepted: checkedAt.subtract(
                                const Duration(days: 1),
                              ),
                            ),
                          ],
                  );
                },
                actorId: identity.userId,
                sessionId: privacy.privacySession,
                isCurrent: valid,
                now: () => checkedAt,
              ),
              actorId: identity.userId,
              sessionId: privacy.privacySession,
              isCurrent: valid,
            );
          }),
          adminPrivacyReviewStoreProvider.overrideWithValue(
            privacy.PrivacyJournalFixture().store,
          ),
        ],
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
    final path = adminAuditStatePath(
      route,
      route == _runRoute ? _runId : 'synthetic-state-record',
    );
    final ownerRead = _ownerReadRoute(route);
    testWidgets('allowed $route uses its declared data provider', (
      tester,
    ) async {
      final repo = _StateRepository(health: health, ownerRead: ownerRead);
      final container = await open(tester, repo, path);
      await tester.pumpAndSettle();
      expect(repo.reads, contains(_reads[route]));
      expect(
        repo.reads,
        containsAll(_additionalReads[route] ?? const <String>[]),
      );
      expect(find.byType(AdminSafeErrorPanel), findsNothing);
      expect(find.text('Admin access required'), findsNothing);
      if (route == '/admin/settings') {
        expect(find.textContaining('qa_runtime_current'), findsWidgets);
        expect(
          find.text(
            'Settings could not be verified. Refresh or sign in again.',
          ),
          findsNothing,
        );
      }
      if (route == _runRoute) {
        expect(find.text('Run $_runId'), findsOneWidget);
        expect(
          find.text(
            'Original summary does not record complete business handling.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Operational run could not be authorized, loaded or validated.',
          ),
          findsNothing,
        );
      }
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
        ownerRead: ownerRead,
      );
      await open(tester, repo, path);
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo.reads, contains(_reads[route]));
      expect(
        route == '/admin/sms-gateway'
            ? find.byType(LinearProgressIndicator)
            : route == '/admin/automations'
            ? find.byType(CircularProgressIndicator)
            : route == _runRoute
            ? find.text('Loading operational run evidence…')
            : find.byType(AdminLoadingState),
        findsWidgets,
      );
      expect(find.byType(AdminSafeErrorPanel), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets('failure $route shows a redacted explicit read failure', (
      tester,
    ) async {
      final repo = _StateRepository(
        health: health,
        failReads: true,
        ownerRead: ownerRead,
      );
      await open(tester, repo, path);
      await tester.pumpAndSettle();
      expect(repo.reads, contains(_reads[route]));
      expect(
        route == '/admin'
            ? find.text('Queue totals · Unavailable')
            : route == '/admin/sms-gateway'
            ? find.text('Gateway read failed')
            : route == '/admin/exceptions'
            ? find.text('Exception read failed')
            : route == adminAuditStateRoute
            ? find.text('Action history read failed')
            : route == '/admin/settings'
            ? find.text(
                'Settings could not be verified. Refresh or sign in again.',
              )
            : route == _runRoute
            ? find.text(
                'Operational run could not be authorized, loaded or validated.',
              )
            : route == '/admin/privacy-requests'
            ? find.text(
                'Current privacy review evidence could not be verified. Refresh to try again.',
              )
            : find.byType(AdminSafeErrorPanel),
        findsWidgets,
      );
      for (final private in [
        'SENSITIVE_PROVIDER_CANARY',
        'private_phone',
        'private_sql',
      ]) {
        expect(find.textContaining(private), findsNothing);
      }
      expect(find.text('Admin access required'), findsNothing);
      expect(find.byType(AdminLoadingState), findsNothing);
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
          ownerRead: ownerRead,
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
          route == '/admin/privacy-requests'
              ? find.text(
                  'No privacy requests on this page. Refresh to check again.',
                )
              : route == adminAuditStateRoute
              ? find.text('No retained actions in this history window')
              : route == '/admin/exceptions'
              ? find.text('No recorded exceptions in this view')
              : route == '/admin/sms-gateway'
              ? find.text('No enrolled devices')
              : route == _runRoute
              ? find.text('No retained evidence in this page.')
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
      final repo = _StateRepository(health: health, ownerRead: ownerRead);
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
