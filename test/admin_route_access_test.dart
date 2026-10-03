import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/admin_governed_settings_models.dart';
import 'package:collect_app/admin/core/admin_governed_settings_sdk.dart';
import 'package:collect_app/admin/core/admin_receipt_operational_history_sdk.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/admin_read_fixture.dart';
import 'support/admin_gateway_fixture.dart';
import 'support/admin_exception_fixture.dart';
import 'support/admin_entity_audit_state_fixture.dart';
import 'support/settings_fixture.dart' as settings;
import 'package:collect_app/admin/core/admin_entity_audit.dart';
import 'package:collect_app/admin/core/admin_exception_models.dart';

const _runRoute = '/admin/automations/runs/:id';
const _runId = 'e805bb70-90fe-4aa7-9a49-3883bbf3607c';

bool _ownerReadRoute(String route) =>
    route == adminAuditStateRoute ||
    route == '/admin/settings' ||
    route == _runRoute;

String _accessPath(String route) => adminAuditStatePath(
  route,
  route == _runRoute ? _runId : 'synthetic-qa-record',
);

class _RouteOwnerSessions extends AdminSessionController {
  _RouteOwnerSessions(String userId) : super(null) {
    state = (
      key: (userId: userId, sessionId: 'synthetic-declared-owner-route'),
      generation: 1,
    );
  }
}

class _RouteSettingsApi extends settings.SettingsApiFake {
  _RouteSettingsApi(this.repository);
  final _AccessRepository repository;

  @override
  Future<AdminSettingsCatalog> catalog(
    AdminSettingsFamily family, {
    int limit = 25,
    Map<String, Object?>? after,
  }) async {
    const rpc = 'admin_list_runtime_controls_v2';
    repository.dataRequests.add(rpc);
    if (repository._fails(rpc)) throw StateError('Network timeout');
    // Adapt only presentation timestamps and the requested page limit; the
    // captured catalog's family, identities and revision remain strictly parsed.
    final raw = settings.observed('catalog');
    final now = DateTime.now().toUtc();
    raw['limit'] = limit;
    raw['checked_at'] = settingsUtc(now);
    raw['sample_valid_until'] = settingsUtc(
      now.add(const Duration(seconds: 60)),
    );
    return AdminSettingsCatalog.parse(raw, family, limit: limit);
  }
}

class _AccessRepository extends AdminEvidenceRepository {
  _AccessRepository({required this.identity, this.failFirstRecords = false});

  Future<AdminIdentity?> Function() identity;
  int identityRequests = 0;
  final dataRequests = <String>[];
  final bool failFirstRecords;
  final failedReads = <String>{};

  // This route case models one failed read. Overview's independent additional
  // sections have their own outage cases and do not need to fail together.
  bool _fails(String rpcName) =>
      failFirstRecords && failedReads.isEmpty && failedReads.add(rpcName);

  @override
  AdminGovernedSettingsApi get governedSettings => _RouteSettingsApi(this);

  @override
  AdminReceiptOperationalHistoryApi
  get receiptOperationalHistory => AdminReceiptOperationalHistoryApi(
    rpc: (name, parameters) async {
      dataRequests.add(name);
      if (_fails(name)) throw StateError('Network timeout');
      if (name != 'admin_get_receipt_operation_run_v1' ||
          parameters['p_run_id'] != _runId) {
        throw StateError('Unexpected route read');
      }
      final raw = Map<String, dynamic>.from(
        jsonDecode(
              File(
                'test/fixtures/admin_receipt_operational_history_actual/run-unavailable.json',
              ).readAsStringSync(),
            )
            as Map,
      );
      // This synthetic current sample preserves unavailable run scope; it
      // does not infer a hosted run, history or authorization acceptance.
      final now = DateTime.now().toUtc();
      raw['checked_at'] = now.toIso8601String();
      raw['sample_valid_until'] = now
          .add(const Duration(seconds: 60))
          .toIso8601String();
      return raw;
    },
  );

  @override
  Future<AdminIdentity?> currentIdentity() {
    identityRequests++;
    return identity();
  }

  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async => null;
  @override
  Future<Map<String, dynamic>> receiptOverview({String? countryCode}) async {
    dataRequests.add('admin_receipt_overview_v1');
    return adminReceiptOverviewFixture(DateTime.now().toUtc());
  }

  @override
  Future<List<AdminMetric>> overviewMetrics() {
    dataRequests.add('admin_overview');
    if (_fails('admin_overview')) {
      return Future.error(StateError('Network timeout'));
    }
    return super.overviewMetrics();
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
  }) {
    dataRequests.add(rpcName);
    if (_fails(rpcName)) return Future.error(StateError('Network timeout'));
    return super.list(
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
  Future<Map<String, dynamic>> detail(String rpcName, String id) {
    dataRequests.add(rpcName);
    if (_fails(rpcName)) return Future.error(StateError('Network timeout'));
    if (rpcName == 'admin_system_health') {
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/admin_operational_health148.json',
                ).readAsStringSync(),
              )
              as Map;
      return Future.value(Map<String, dynamic>.from(raw['receipt'] as Map));
    }
    return super.detail(rpcName, id);
  }

  @override
  Future<Map<String, dynamic>> smsQueueHealth() async => {
    'enabled': false,
    'queued': 0,
    'awaiting_confirmation': 0,
    'send_started': 0,
    'uncertain': 0,
    'suppressed': 0,
    'active_workers': 0,
    'oldest_queued_at': null,
    'observed_at': DateTime.now().toUtc().toIso8601String(),
  };

  @override
  Future<Map<String, dynamic>> gatewayDevices({
    int limit = 20,
    DateTime? beforeEnrolledAt,
    String? beforeDeviceId,
  }) async {
    dataRequests.add('admin_list_gateway_devices_v1');
    if (_fails('admin_list_gateway_devices_v1')) {
      throw StateError('Network timeout');
    }
    return adminGatewayListFixture(DateTime.now().toUtc(), limit: limit);
  }

  @override
  Future<Map<String, dynamic>> exceptionInbox({
    bool active = true,
    int limit = 20,
    AdminExceptionSource? source,
    DateTime? beforeChangedAt,
    String? beforeId,
  }) async {
    dataRequests.add('admin_list_operational_exceptions_v2');
    if (_fails('admin_list_operational_exceptions_v2')) {
      throw StateError('Network timeout');
    }
    return adminExceptionListFixture(DateTime.now().toUtc(), limit: limit);
  }

  @override
  Future<Map<String, dynamic>> operatorEntityAudit(
    AdminEntityAuditQuery query,
  ) async {
    dataRequests.add('admin_get_operator_entity_audit_v1');
    if (_fails('admin_get_operator_entity_audit_v1')) {
      throw StateError('Network timeout');
    }
    return adminAuditStateFixture(DateTime.now().toUtc(), query);
  }

  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) {
    dataRequests.add(rpcName);
    return super.action(rpcName, params);
  }
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  _AccessRepository repository,
  String path, {
  bool signedIn = true,
  String sessionUserId = '00000000-0000-0000-0000-00000000e001',
}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(null),
      adminAuthGuardProvider.overrideWithValue(
        AdminAuthGuard(isAuthorized: signedIn),
      ),
      adminAuthUserIdProvider.overrideWithValue(
        signedIn ? sessionUserId : null,
      ),
      adminReconciliationSessionKeyProvider.overrideWith((ref) {
        final userId = ref.watch(adminAuthUserIdProvider);
        return userId == null ? null : '$userId/synthetic-route-session';
      }),
      adminRepositoryProvider.overrideWithValue(repository),
      if (signedIn && path.startsWith('/admin/audit-logs/entity/'))
        adminAuthSessionScopeProvider.overrideWith(
          (_) => AdminAuditStateSessions(sessionUserId),
        ),
      if (signedIn &&
          (path == '/admin/settings' ||
              path.startsWith('/admin/automations/runs/')))
        adminAuthSessionScopeProvider.overrideWith(
          (_) => _RouteOwnerSessions(sessionUserId),
        ),
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

void main() {
  final protectedPaths = adminRoutePaths.where(
    (path) => path != '/admin/login' && path != '/admin/denied',
  );
  for (final route in protectedPaths) {
    final path = _accessPath(route);
    testWidgets('signed-out deep link $route stays at login without data', (
      tester,
    ) async {
      final repository = _AccessRepository(identity: () async => null);
      final container = await _open(tester, repository, path, signedIn: false);
      await tester.pumpAndSettle();
      expect(
        container
            .read(adminRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/admin/login',
      );
      expect(find.text('Collect admin login'), findsOneWidget);
      expect(repository.identityRequests, 0);
      expect(repository.dataRequests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('non-Admin deep link $route denies before reading records', (
      tester,
    ) async {
      final repository = _AccessRepository(identity: () async => null);
      await _open(tester, repository, path);
      await tester.pumpAndSettle();
      expect(find.text('Admin access required'), findsOneWidget);
      expect(repository.identityRequests, 1);
      expect(repository.dataRequests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('an identity without capabilities cannot open $route', (
      tester,
    ) async {
      final repository = _AccessRepository(
        identity: () async => const AdminIdentity(
          userId: 'synthetic-no-permissions',
          displayName: 'Synthetic operator',
          roles: ['admin'],
          permissions: [],
        ),
      );
      await _open(
        tester,
        repository,
        path,
        sessionUserId: 'synthetic-no-permissions',
      );
      await tester.pumpAndSettle();
      expect(find.text('Admin access required'), findsOneWidget);
      expect(repository.dataRequests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('record request failure on $route can retry in place', (
      tester,
    ) async {
      final identity = await const AdminEvidenceRepository().currentIdentity();
      final repository = _AccessRepository(
        identity: () async => _ownerReadRoute(route) && identity != null
            ? adminAuditStateIdentity(identity)
            : identity,
        failFirstRecords: true,
      );
      final container = await _open(tester, repository, path);
      await tester.pumpAndSettle();
      final overview = route == '/admin';
      final gateway = route == '/admin/sms-gateway';
      final exceptions = route == '/admin/exceptions';
      final audit = route == adminAuditStateRoute;
      final settingsRoute = route == '/admin/settings';
      final run = route == _runRoute;
      final failureMessage = settingsRoute
          ? 'Settings could not be verified. Refresh or sign in again.'
          : run
          ? 'Operational run could not be authorized, loaded or validated.'
          : audit
          ? 'Action history read failed'
          : overview
          ? 'Queue totals · Unavailable'
          : exceptions
          ? 'Exception read failed'
          : gateway
          ? 'Gateway read failed'
          : 'The admin service could not be reached.';
      final retry = settingsRoute
          ? find.widgetWithText(TextButton, 'Refresh settings')
          : run
          ? find.widgetWithText(OutlinedButton, 'Refresh run evidence')
          : audit
          ? find.widgetWithText(OutlinedButton, 'Refresh evidence')
          : overview
          ? find.descendant(
              of: find
                  .ancestor(
                    of: find.text(failureMessage),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
              matching: find.widgetWithText(TextButton, 'Refresh measurement'),
            )
          : exceptions
          ? find.widgetWithText(TextButton, 'Refresh inbox')
          : gateway
          ? find.widgetWithText(OutlinedButton, 'Refresh devices')
          : find.widgetWithText(FilledButton, 'Retry');
      if (overview) {
        await tester.scrollUntilVisible(
          find.text(failureMessage),
          300,
          scrollable: find.descendant(
            of: find.byKey(const Key('admin-overview-workspace')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text(failureMessage), findsOneWidget);
      final firstRequestCount = repository.dataRequests.length;
      expect(firstRequestCount, greaterThan(0));
      expect(retry, findsOneWidget);
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(repository.dataRequests.length, greaterThan(firstRequestCount));
      expect(find.text(failureMessage), findsNothing);
      if (settingsRoute) {
        expect(repository.dataRequests.last, 'admin_list_runtime_controls_v2');
        expect(find.text('Revision 1'), findsOneWidget);
      }
      if (run) {
        expect(
          repository.dataRequests.last,
          'admin_get_receipt_operation_run_v1',
        );
        expect(
          find.text(
            'Current run scope is unavailable. No run or source evidence is inferred.',
          ),
          findsOneWidget,
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
  }

  for (final route in ['/admin/settings', _runRoute]) {
    testWidgets('an admin role without owner authority cannot read $route', (
      tester,
    ) async {
      final identity = await const AdminEvidenceRepository().currentIdentity();
      final repository = _AccessRepository(identity: () async => identity);
      final path = _accessPath(route);
      final container = await _open(tester, repository, path);
      await tester.pumpAndSettle();
      expect(
        find.text(
          route == '/admin/settings'
              ? 'Admin access required'
              : 'A current platform owner with payment, notification and system health read access is required.',
        ),
        findsOneWidget,
      );
      expect(repository.identityRequests, 1);
      expect(repository.dataRequests, isEmpty);
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
  }

  testWidgets('identity loading keeps a protected deep link free of data', (
    tester,
  ) async {
    final pending = Completer<AdminIdentity?>();
    final repository = _AccessRepository(identity: () => pending.future);
    await _open(tester, repository, '/admin/transactions/synthetic-qa-record');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Loading admin workspace'), findsOneWidget);
    expect(repository.dataRequests, isEmpty);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Admin access required'), findsOneWidget);
    expect(repository.dataRequests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an identity outage can retry and recover the requested route', (
    tester,
  ) async {
    final identity = await const AdminEvidenceRepository().currentIdentity();
    var attempts = 0;
    final repository = _AccessRepository(
      identity: () async {
        if (attempts++ == 0) throw StateError('Network timeout');
        return identity;
      },
    );
    final container = await _open(tester, repository, '/admin/groups');
    await tester.pumpAndSettle();
    expect(
      find.text('The admin service could not be reached.'),
      findsOneWidget,
    );
    expect(repository.dataRequests, isEmpty);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(repository.identityRequests, 2);
    expect(repository.dataRequests, contains('admin_list_collections'));
    expect(
      container
          .read(adminRouterProvider)
          .routeInformationProvider
          .value
          .uri
          .path,
      '/admin/groups',
    );
    expect(find.text('The admin service could not be reached.'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('identity retry stays denied when server access was revoked', (
    tester,
  ) async {
    var attempts = 0;
    final repository = _AccessRepository(
      identity: () async {
        if (attempts++ == 0) throw StateError('Network timeout');
        return null;
      },
    );
    await _open(tester, repository, '/admin/admin-users');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Admin access required'), findsOneWidget);
    expect(repository.identityRequests, 2);
    expect(repository.dataRequests, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
