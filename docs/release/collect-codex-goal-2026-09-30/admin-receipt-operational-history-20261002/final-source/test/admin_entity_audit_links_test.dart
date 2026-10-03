import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_entity_audit.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_exception_models.dart';
import 'package:collect_app/admin/core/admin_gateway_contracts.dart';
import 'package:collect_app/admin/core/admin_investigation_view.dart';
import 'package:collect_app/admin/core/admin_receipt_cancel_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_cancel_models.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/app/theme/collect_runtime_assets.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'admin_exception_models_test.dart' as exceptions;
import 'admin_gateway_models_test.dart' as gateway;
import 'admin_receipt_cancel_models_test.dart' as cancellation;
import 'support/admin_entity_audit_fixture.dart';
import 'admin_exception_history_v2_models_test.dart' as joined;

const _ownerId = '99710000-0000-4000-8000-000000000001';
const _owner = AdminIdentity(
  userId: _ownerId,
  displayName: 'Synthetic history reviewer',
  roles: ['platform_owner'],
  permissions: [
    'audit.read',
    'payments.read',
    'system_health.read',
    'notifications.read',
  ],
);
final _identity = StateProvider<Future<AdminIdentity?>>((_) async => _owner);
final _now = DateTime.utc(2026, 10, 1, 2);

Map<String, dynamic> _kindFixture(AdminAuditEntityKind kind) => switch (kind) {
  AdminAuditEntityKind.receiptOperationsPolicy ||
  AdminAuditEntityKind.receiptOperationRun => Map<String, dynamic>.from(
    jsonDecode(
          File(
            'test/fixtures/admin_receipt_operational_history_actual/audit-${kind.wire}.json',
          ).readAsStringSync(),
        )
        as Map,
  ),
  _ => auditObserved(switch (kind) {
    AdminAuditEntityKind.shadowRun => 'shadow',
    AdminAuditEntityKind.gatewayDevice => 'gateway',
    AdminAuditEntityKind.supervisorIdentity => 'supervisor',
    AdminAuditEntityKind.exception => 'exception',
    AdminAuditEntityKind.receipt => 'receipt',
    _ => throw StateError('Unsupported fixture kind'),
  }),
};

class _Sessions extends AdminSessionController {
  _Sessions({String actor = _ownerId, bool absent = false}) : super(null) {
    if (!absent) {
      state = (
        key: (userId: actor, sessionId: 'synthetic-link-session'),
        generation: 1,
      );
    }
  }
  void depart() => state = null;
}

class _Store implements AdminReceiptCancelCheckpointStore {
  final values = <String, String>{};
  @override
  String? read(String owner) => values[owner];
  @override
  void write(String owner, String encoded) => values[owner] = encoded;
  @override
  void clear(String owner) => values.remove(owner);
}

Map<String, dynamic> _fresh(Map<String, dynamic> raw) => auditCopy(raw)
  ..['checked_at'] = exceptions.exceptionUtc(_now)
  ..['sample_valid_until'] = exceptions.exceptionUtc(
    _now.add(const Duration(seconds: 60)),
  );

class _Repository extends AdminEvidenceRepository {
  _Repository() {
    (((gatewayRaw['rows'] as List).first as Map)['health']
            as Map)['freshness'] =
        'stale';
  }
  final reads = <AdminEntityAuditQuery>[];
  final lookups = <String>[];
  int mutations = 0;
  final gatewayRaw = gateway.gatewayListFixture();
  final exceptionRaw = exceptions.exceptionFixture();
  final investigationRaw = Map<String, dynamic>.from(
    jsonDecode(
          File('test/fixtures/admin_investigation_v1.json').readAsStringSync(),
        )
        as Map,
  );
  String get gatewayId =>
      ((gatewayRaw['rows'] as List).first as Map)['device_id'] as String;
  String get exceptionId =>
      ((exceptionRaw['rows'] as List).first as Map)['id'] as String;
  String get investigationReceiptId =>
      (investigationRaw['receipt'] as Map)['id'] as String;

  @override
  Future<AdminIdentity?> currentIdentity() async => _owner;
  @override
  Future<Map<String, dynamic>> operatorEntityAudit(
    AdminEntityAuditQuery query,
  ) async {
    reads.add(query);
    // Derived mock read: only echoed entity and read window are rebound.
    return _fresh(_kindFixture(query.kind))..['entity_id'] = query.id;
  }

  @override
  Future<Map<String, dynamic>> exceptionEntityAudit(
    AdminEntityAuditQuery query,
  ) async {
    reads.add(query);
    // Declared joined presentation double, rebound only for this route clock.
    final raw = joined.historyFixture();
    for (final row in raw['rows'] as List) {
      (row as Map)['recorded_at'] = exceptions.exceptionUtc(
        _now.subtract(const Duration(hours: 1)),
      );
      if (row['due_at'] != null) {
        row['due_at'] = exceptions.exceptionUtc(
          _now.add(const Duration(hours: 1)),
        );
      }
    }
    return joined.historyWindow(_fresh(raw), query);
  }

  @override
  Future<Map<String, dynamic>> gatewayDevices({
    int limit = 20,
    DateTime? beforeEnrolledAt,
    String? beforeDeviceId,
  }) async => _fresh(gatewayRaw)..['limit'] = limit;
  @override
  Future<Map<String, dynamic>> exceptionInbox({
    bool active = true,
    int limit = 20,
    AdminExceptionSource? source,
    DateTime? beforeChangedAt,
    String? beforeId,
  }) async => _fresh(exceptionRaw)..['limit'] = limit;
  @override
  Future<Map<String, dynamic>> inspectUnstartedReceipt(String outboxId) async {
    final raw = _fresh(cancellation.cancelFixture('cancelled-inspection'))
      ..['outbox_id'] = outboxId;
    (raw['receipt'] as Map)['outbox_id'] = outboxId;
    return raw;
  }

  @override
  Future<Map<String, dynamic>> unstartedReceiptAction(String requestId) async {
    lookups.add(requestId);
    return _fresh(cancellation.cancelFixture('recorded-lookup'));
  }

  @override
  Future<Map<String, dynamic>> investigation({
    required String kind,
    required String id,
  }) async => _fresh(investigationRaw)
    ..['kind'] = 'receipt'
    ..['target_id'] = investigationReceiptId;
  @override
  Future<Map<String, dynamic>> action(
    String name,
    Map<String, dynamic> args,
  ) async {
    mutations++;
    throw StateError('Unexpected mutation');
  }

  @override
  Future<AdminGatewayActionReceipt> gatewayOwnerAction(
    AdminGatewayOwnerIntent intent,
  ) async {
    mutations++;
    throw StateError('Unexpected mutation');
  }

  @override
  Future<AdminExceptionReceipt> exceptionAction(
    AdminExceptionIntent intent,
  ) async {
    mutations++;
    throw StateError('Unexpected mutation');
  }

  @override
  Future<AdminReceiptCancelReceipt> cancelUnstartedReceipt(
    AdminReceiptCancelIntent intent,
  ) async {
    mutations++;
    throw StateError('Unexpected mutation');
  }
}

Future<(ProviderContainer, GoRouter)> _mount(
  WidgetTester tester,
  _Repository repository, {
  AdminIdentity? actor = _owner,
  _Sessions? sessions,
  Widget? widget,
  String? origin,
  bool dark = false,
  GlobalKey? capture,
}) async {
  tester.view.physicalSize = const Size(1440, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = _Store();
  final digest = adminReceiptCancelOwnerDigest(_owner.userId);
  store.values[digest] = AdminReceiptCancelCheckpoint(
    digest,
    cancellation.cancelIntent(),
  ).encode();
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(null),
      _identity.overrideWith((_) async => actor),
      adminIdentityProvider.overrideWith((ref) => ref.watch(_identity)),
      adminRepositoryProvider.overrideWithValue(repository),
      adminClockProvider.overrideWithValue(() => _now),
      adminAuthGuardProvider.overrideWithValue(
        const AdminAuthGuard(isAuthorized: true),
      ),
      adminAuthSessionScopeProvider.overrideWith(
        (_) => sessions ?? _Sessions(),
      ),
      adminReceiptCancelCheckpointStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(container.dispose);
  final actual = origin == 'gateway' || origin == 'exception';
  final router = actual
      ? container.read(adminRouterProvider)
      : GoRouter(
          initialLocation: '/record',
          routes: [
            GoRoute(
              path: '/record',
              builder: (_, _) => Scaffold(
                body: SingleChildScrollView(
                  child:
                      widget ??
                      (origin == 'receipt'
                          ? AdminReceiptCancelCard(
                              outboxId: cancellation.cancelIntent().outboxId,
                            )
                          : AdminInvestigationView(
                              kind: 'receipt',
                              id: repository.investigationReceiptId,
                            )),
                ),
              ),
            ),
            GoRoute(
              path: '/admin/audit-logs/entity/:kind/:id',
              builder: (_, state) => Scaffold(
                body: AdminEntityAuditPage(
                  entityKind: state.pathParameters['kind']!,
                  entityId: state.pathParameters['id']!,
                ),
              ),
            ),
          ],
        );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: dark ? CollectTheme.dark() : CollectTheme.light(),
        routerConfig: router,
        builder: (_, child) => RepaintBoundary(key: capture, child: child!),
      ),
    ),
  );
  await tester.pump();
  if (actual) {
    router.go(origin == 'gateway' ? '/admin/sms-gateway' : '/admin/exceptions');
  }
  await tester.pumpAndSettle();
  addTearDown(router.dispose);
  return (container, router);
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'dark and light local audit captures of four canonical record links',
    (tester) async {
      final destination = Platform.environment['COLLECT_ENTITY_AUDIT_CAPTURE'];
      if (destination == null) return;
      for (final origin in [
        'gateway',
        'exception',
        'receipt',
        'investigation',
      ]) {
        for (final dark in [true, false]) {
          final repository = _Repository(), boundaryKey = GlobalKey();
          await _mount(
            tester,
            repository,
            origin: origin,
            dark: dark,
            capture: boundaryKey,
          );
          if (origin == 'receipt') {
            await tester.ensureVisible(find.text('Check original request'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Check original request'));
            await tester.pumpAndSettle();
          }
          final kind = origin == 'gateway'
              ? AdminAuditEntityKind.gatewayDevice
              : origin == 'exception'
              ? AdminAuditEntityKind.exception
              : AdminAuditEntityKind.receipt;
          final id = origin == 'gateway'
              ? repository.gatewayId
              : origin == 'exception'
              ? repository.exceptionId
              : origin == 'receipt'
              ? cancellation.cancelIntent().outboxId
              : repository.investigationReceiptId;
          final link = find.byKey(
            ValueKey('entity-audit-link-${kind.wire}-$id'),
          );
          await tester.ensureVisible(link);
          await tester.pumpAndSettle();
          expect(link, findsOneWidget);
          await tester.runAsync(() async {
            await precacheImage(
              const AssetImage(CollectRuntimeAssets.officialLogo),
              boundaryKey.currentContext!,
            );
          });
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$destination/$origin-${dark ? 'dark' : 'light'}-1440x2200.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          expect(repository.reads, isEmpty);
          expect(repository.mutations, 0);
          await _finish(tester);
        }
      }
    },
  );
  for (final departure in ['permission', 'role', 'session']) {
    testWidgets(
      'loaded history navigation hides after current $departure loss',
      (tester) async {
        final repo = _Repository(), sessions = _Sessions();
        final (container, _) = await _mount(
          tester,
          repo,
          sessions: sessions,
          widget: AdminEntityAuditLink(
            kind: AdminAuditEntityKind.receipt,
            id: cancellation.cancelIntent().outboxId,
          ),
        );
        expect(find.text('View action history'), findsOneWidget);
        if (departure == 'session') {
          sessions.depart();
        } else {
          container.read(_identity.notifier).state = Future.value(
            AdminIdentity(
              userId: _ownerId,
              displayName: 'Synthetic',
              roles: departure == 'role' ? ['admin'] : _owner.roles,
              permissions: departure == 'permission'
                  ? _owner.permissions.where((p) => p != 'audit.read').toList()
                  : _owner.permissions,
            ),
          );
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        expect(find.text('View action history'), findsNothing);
        expect(repo.reads, isEmpty);
        expect(repo.mutations, 0);
        await _finish(tester);
      },
    );
  }
  for (final kind in AdminAuditEntityKind.values) {
    final id = _kindFixture(kind)['entity_id'] as String;
    for (final missing in kind.requiredPermissions) {
      testWidgets(
        '${kind.wire} link requires independent $missing before any history read',
        (tester) async {
          final repo = _Repository();
          await _mount(
            tester,
            repo,
            actor: AdminIdentity(
              userId: _owner.userId,
              displayName: 'Synthetic',
              roles: _owner.roles,
              permissions: _owner.permissions
                  .where((v) => v != missing)
                  .toList(),
            ),
            widget: AdminEntityAuditLink(kind: kind, id: id),
          );
          expect(find.text('View action history'), findsNothing);
          expect(repo.reads, isEmpty);
          expect(repo.mutations, 0);
          await _finish(tester);
        },
      );
    }
    testWidgets(
      '${kind.wire} loaded link hides on current identity loading and error',
      (tester) async {
        final repo = _Repository();
        final (container, _) = await _mount(
          tester,
          repo,
          widget: AdminEntityAuditLink(kind: kind, id: id),
        );
        expect(find.text('View action history'), findsOneWidget);
        final waiting = Completer<AdminIdentity?>();
        container.read(_identity.notifier).state = waiting.future;
        await tester.pump();
        expect(find.text('View action history'), findsNothing);
        waiting.completeError(StateError('PRIVATE_CANARY'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        expect(find.text('View action history'), findsNothing);
        expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
        expect(repo.reads, isEmpty);
        await _finish(tester);
      },
    );
  }
  for (final scenario in ['role', 'actor', 'absent', 'invalid']) {
    testWidgets('history link fails closed for $scenario without a read', (
      tester,
    ) async {
      final repo = _Repository();
      await _mount(
        tester,
        repo,
        actor: scenario == 'role'
            ? AdminIdentity(
                userId: _owner.userId,
                displayName: 'Synthetic',
                roles: ['admin'],
                permissions: _owner.permissions,
              )
            : _owner,
        sessions: _Sessions(
          actor: scenario == 'actor'
              ? '99710000-0000-4000-8000-000000000099'
              : _owner.userId,
          absent: scenario == 'absent',
        ),
        widget: AdminEntityAuditLink(
          kind: AdminAuditEntityKind.receipt,
          id: scenario == 'invalid'
              ? 'wrong-id'
              : cancellation.cancelIntent().outboxId,
        ),
      );
      expect(find.text('View action history'), findsNothing);
      expect(repo.reads, isEmpty);
      expect(repo.mutations, 0);
      await _finish(tester);
    });
  }
  for (final origin in ['gateway', 'exception', 'receipt', 'investigation']) {
    testWidgets(
      'actual $origin record opens its canonical entity history and returns without mutation',
      (tester) async {
        final repo = _Repository();
        final (_, router) = await _mount(tester, repo, origin: origin);
        if (origin == 'receipt') {
          await tester.ensureVisible(find.text('Check original request'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Check original request'));
          await tester.pumpAndSettle();
          expect(repo.lookups, [cancellation.cancelIntent().requestId]);
        }
        final kind = origin == 'gateway'
            ? AdminAuditEntityKind.gatewayDevice
            : origin == 'exception'
            ? AdminAuditEntityKind.exception
            : AdminAuditEntityKind.receipt;
        final id = origin == 'gateway'
            ? repo.gatewayId
            : origin == 'exception'
            ? repo.exceptionId
            : origin == 'receipt'
            ? cancellation.cancelIntent().outboxId
            : repo.investigationReceiptId;
        final sourcePath = router.routeInformationProvider.value.uri.path;
        final link = find.byKey(ValueKey('entity-audit-link-${kind.wire}-$id'));
        await tester.ensureVisible(link);
        await tester.pumpAndSettle();
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(find.byType(AdminEntityAuditPage), findsOneWidget);
        expect(repo.reads.single.id, id);
        expect(repo.reads.single.kind, kind);
        expect(repo.mutations, 0);
        if (origin == 'receipt') {
          expect(
            repo.reads.single.id,
            isNot(cancellation.cancelIntent().requestId),
          );
        }
        if (origin == 'exception') {
          expect(
            repo.reads.single.id,
            isNot(
              ((repo.exceptionRaw['rows'] as List).first as Map)['source_id'],
            ),
          );
        }
        expect(router.canPop(), true);
        router.pop();
        await tester.pumpAndSettle();
        expect(find.byType(AdminEntityAuditPage), findsNothing);
        expect(router.routeInformationProvider.value.uri.path, sourcePath);
        expect(repo.mutations, 0);
        await _finish(tester);
      },
    );
  }
}
