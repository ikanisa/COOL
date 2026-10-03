import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_entity_audit.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/admin_entity_audit_fixture.dart';

const _ownerId = '99810000-0000-4000-8000-000000000001';
const _owner = AdminIdentity(
  userId: _ownerId,
  displayName: 'Synthetic audit reviewer',
  roles: ['platform_owner'],
  permissions: [
    'audit.read',
    'system_health.read',
    'notifications.read',
    'payments.read',
  ],
);
final _identityFuture = StateProvider<Future<AdminIdentity?>>(
  (_) async => _owner,
);

class _Sessions extends AdminSessionController {
  _Sessions() : super(null) {
    change(1);
  }
  void change(int generation, {String user = _ownerId}) => state = (
    key: (userId: user, sessionId: 'audit-synthetic-$generation'),
    generation: generation,
  );
}

class _Repository extends AdminEvidenceRepository {
  _Repository({Map<String, dynamic>? raw}) : raw = raw ?? auditObserved();
  Map<String, dynamic> raw;
  final queries = <AdminEntityAuditQuery>[];
  final started = Completer<void>();
  Object? error;
  Completer<Map<String, dynamic>>? gate;
  @override
  Future<AdminIdentity?> currentIdentity() async => _owner;
  @override
  Future<Map<String, dynamic>> operatorEntityAudit(
    AdminEntityAuditQuery query,
  ) async {
    queries.add(query);
    if (!started.isCompleted) started.complete();
    if (error != null) throw error!;
    if (gate != null) return gate!.future;
    return auditWindow(raw, query);
  }

  @override
  Future<Map<String, dynamic>> shadowRuns({
    int limit = 20,
    DateTime? beforeStartedAt,
    String? beforeRunId,
  }) async {
    // UI-only shadow fixture has its date shifted to this clock and its
    // canonical run ID bound to the actual audit observation. No SQL reruns.
    final history =
        jsonDecode(
              File(
                'contracts/collect-shadow-supervisor-v1.fixture.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final delta = DateTime.parse(
      raw['checked_at'] as String,
    ).difference(DateTime.parse(history['checked_at'] as String));
    Object? shift(Object? value) {
      if (value is Map) {
        return {
          for (final entry in value.entries) entry.key: shift(entry.value),
        };
      }
      if (value is List) return value.map(shift).toList();
      if (value is String && RegExp(r'T.*(?:Z|\+00:00)$').hasMatch(value)) {
        return DateTime.parse(value).add(delta).toIso8601String();
      }
      return value;
    }

    final shifted = Map<String, dynamic>.from(shift(history) as Map);
    ((shifted['rows'] as List).first as Map)['run_id'] = raw['entity_id'];
    return shifted;
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _Repository repository, {
  AdminIdentity? identity = _owner,
  _Sessions? sessions,
  DateTime Function()? clock,
  double width = 1440,
  double scale = 1,
  bool dark = true,
  int pageSize = 20,
  String? kind,
  String? id,
  bool router = false,
  GlobalKey? capture,
}) async {
  tester.view.physicalSize = Size(width, capture == null ? 1100 : 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(null),
      _identityFuture.overrideWith((_) async => identity),
      adminIdentityProvider.overrideWith((ref) => ref.watch(_identityFuture)),
      adminRepositoryProvider.overrideWithValue(repository),
      adminClockProvider.overrideWithValue(
        clock ?? () => DateTime.parse(repository.raw['checked_at'] as String),
      ),
      adminAuthSessionScopeProvider.overrideWith(
        (_) => sessions ?? _Sessions(),
      ),
      adminAuthGuardProvider.overrideWithValue(
        const AdminAuthGuard(isAuthorized: true),
      ),
    ],
  );
  addTearDown(container.dispose);
  final theme = dark ? CollectTheme.dark() : CollectTheme.light();
  final app = router
      ? MaterialApp.router(
          theme: theme,
          routerConfig: container.read(adminRouterProvider),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(key: capture, child: child!),
          ),
        )
      : MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: RepaintBoundary(
              key: capture,
              child: AdminEntityAuditPage(
                entityKind: kind ?? repository.raw['entity_kind'] as String,
                entityId: id ?? repository.raw['entity_id'] as String,
                pageSize: pageSize,
              ),
            ),
          ),
        );
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: app),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 30));
  return container;
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
    'pending evidence shows loading without rows or inferred empty history',
    (tester) async {
      final repository = _Repository();
      final gate = Completer<Map<String, dynamic>>();
      repository.gate = gate;
      await _mount(tester, repository);
      expect(find.text('Loading action evidence'), findsOneWidget);
      expect(find.text('Monitoring finished'), findsNothing);
      expect(
        find.text('No retained actions in this history window'),
        findsNothing,
      );
      expect(repository.queries, hasLength(1));
      gate.complete(auditWindow(repository.raw, repository.queries.single));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.text('Monitoring finished'), findsOneWidget);
      expect(repository.queries, hasLength(1));
      await _finish(tester);
    },
  );
  for (final name in [
    'shadow',
    'expiry',
    'gateway',
    'supervisor',
    'exception',
    'receipt',
  ]) {
    testWidgets(
      'actual $name action IDs render as historical evidence with no inferred totals',
      (tester) async {
        final repository = _Repository(raw: auditObserved(name));
        await _mount(tester, repository);
        expect(repository.queries, hasLength(1));
        expect(find.text('History is incomplete'), findsOneWidget);
        expect(
          find.text(repository.raw['entity_id'] as String),
          findsOneWidget,
        );
        final first = (repository.raw['rows'] as List).first as Map;
        expect(find.text(first['request_id'] as String), findsWidgets);
        expect(find.text('Actor ID'), findsWidgets);
        expect(find.textContaining('of total'), findsNothing);
        expect(find.text('Send'), findsNothing);
        expect(find.text('Retry'), findsNothing);
        expect(find.text('Policy approved'), findsNothing);
        await _finish(tester);
      },
    );
  }
  testWidgets(
    'shadow missing actor is explicit and never replaced with a name or system actor',
    (tester) async {
      final raw = auditObserved();
      ((raw['rows'] as List).first as Map)['actor_id'] = null;
      await _mount(tester, _Repository(raw: raw));
      expect(find.text('Actor not recorded'), findsOneWidget);
      expect(find.text('System actor'), findsNothing);
      await _finish(tester);
    },
  );
  for (final permission in [
    'audit.read',
    'system_health.read',
    'notifications.read',
    'payments.read',
  ]) {
    testWidgets('receipt page denies missing $permission before RPC', (
      tester,
    ) async {
      final repository = _Repository(raw: auditObserved('receipt'));
      await _mount(
        tester,
        repository,
        identity: AdminIdentity(
          userId: _ownerId,
          displayName: 'Synthetic',
          roles: ['platform_owner'],
          permissions: _owner.permissions
              .where((p) => p != permission)
              .toList(),
        ),
      );
      expect(find.text('Action history access denied'), findsOneWidget);
      expect(repository.queries, isEmpty);
      await _finish(tester);
    });
  }
  testWidgets(
    'member role or mismatched session actor cannot read action evidence',
    (tester) async {
      final repository = _Repository();
      await _mount(
        tester,
        repository,
        identity: AdminIdentity(
          userId: _ownerId,
          displayName: 'Synthetic',
          roles: ['member'],
          permissions: _owner.permissions,
        ),
      );
      expect(repository.queries, isEmpty);
      expect(find.text('Action history access denied'), findsOneWidget);
      await _finish(tester);
      final sessions = _Sessions()
        ..change(1, user: '99810000-0000-4000-8000-000000000099');
      await _mount(tester, repository, sessions: sessions);
      expect(repository.queries, isEmpty);
      await _finish(tester);
    },
  );
  for (final kind in ['payment', 'shadow_run']) {
    testWidgets('invalid route $kind fails closed before data fetch', (
      tester,
    ) async {
      final repository = _Repository();
      await _mount(
        tester,
        repository,
        kind: kind,
        id: kind == 'payment' ? repository.raw['entity_id'] as String : 'bad',
      );
      expect(find.text('Action history link unavailable'), findsOneWidget);
      expect(repository.queries, isEmpty);
      await _finish(tester);
    });
  }
  for (final code in ['42501', '55P03', '40001', '42883', 'XX000']) {
    testWidgets(
      'server $code is safe and cannot produce an empty successful history',
      (tester) async {
        final repository = _Repository()
          ..error = PostgrestException(
            message: 'PRIVATE_CANARY +250788000000',
            code: code,
          );
        await _mount(tester, repository);
        expect(repository.queries, hasLength(1));
        expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
        expect(
          find.text('No retained actions in this history window'),
          findsNothing,
        );
        expect(find.textContaining('Recorded '), findsNothing);
        await _finish(tester);
      },
    );
  }
  testWidgets(
    'malformed success cannot render rows or raw private diagnostics',
    (tester) async {
      final repository = _Repository()
        ..raw['private_diagnostic'] = 'PRIVATE_CANARY';
      await _mount(tester, repository);
      expect(find.text('Action history read failed'), findsOneWidget);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(find.text('Monitoring finished'), findsNothing);
      await _finish(tester);
    },
  );
  testWidgets(
    'available empty and unavailable records explain separate evidence limits',
    (tester) async {
      final raw = auditObserved()..['rows'] = [];
      await _mount(tester, _Repository(raw: raw));
      expect(
        find.text('No retained actions in this history window'),
        findsOneWidget,
      );
      await _finish(tester);
      raw['status'] = 'unavailable';
      await _mount(tester, _Repository(raw: raw));
      expect(find.text('Record unavailable in this scope'), findsOneWidget);
      expect(
        find.text('No retained actions in this history window'),
        findsNothing,
      );
      await _finish(tester);
    },
  );
  testWidgets(
    'keyset navigation uses original entity and paired cursor; refresh resets it',
    (tester) async {
      final repository = _Repository();
      await _mount(tester, repository, pageSize: 1);
      await tester.ensureVisible(find.text('Older actions'));
      await tester.tap(find.text('Older actions'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(repository.queries, hasLength(2));
      expect(repository.queries.last.id, repository.queries.first.id);
      expect(repository.queries.last.before, isNotNull);
      expect(find.text('Observation recorded'), findsOneWidget);
      await tester.ensureVisible(find.text('Newer actions'));
      await tester.tap(find.text('Newer actions'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.text('Monitoring finished'), findsOneWidget);
      await tester.ensureVisible(find.text('Refresh evidence'));
      await tester.tap(find.text('Refresh evidence'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(repository.queries.last.before, isNull);
      expect(find.text('Newer actions'), findsNothing);
      await _finish(tester);
    },
  );
  testWidgets(
    'exact TTL expiry hides historical rows and paging without an automatic read',
    (tester) async {
      final repository = _Repository();
      var now = DateTime.parse(repository.raw['checked_at'] as String);
      await _mount(tester, repository, clock: () => now, pageSize: 1);
      expect(find.text('Monitoring finished'), findsOneWidget);
      now = now.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Action history read expired'), findsOneWidget);
      expect(find.text('Monitoring finished'), findsNothing);
      expect(find.text('Older actions'), findsNothing);
      expect(repository.queries, hasLength(1));
      await _finish(tester);
    },
  );
  testWidgets(
    'identity refresh loading and permission loss hide retained data immediately',
    (tester) async {
      final repository = _Repository();
      final container = await _mount(tester, repository);
      final gate = Completer<AdminIdentity?>();
      container.read(_identityFuture.notifier).state = gate.future;
      await tester.pump();
      expect(find.text('Monitoring finished'), findsNothing);
      expect(find.text('Checking action history access'), findsOneWidget);
      gate.complete(
        const AdminIdentity(
          userId: _ownerId,
          displayName: 'Synthetic',
          roles: ['platform_owner'],
          permissions: [],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.text('Action history access denied'), findsOneWidget);
      expect(repository.queries, hasLength(1));
      await _finish(tester);
    },
  );
  testWidgets(
    'new same-person session drops prior cursor and suppresses old pending data',
    (tester) async {
      final repository = _Repository(), sessions = _Sessions();
      final container = await _mount(
        tester,
        repository,
        sessions: sessions,
        pageSize: 1,
      );
      await tester.ensureVisible(find.text('Older actions'));
      await tester.tap(find.text('Older actions'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(repository.queries.last.before, isNotNull);
      final old = Completer<Map<String, dynamic>>();
      repository.gate = old;
      container.invalidate(adminEntityAuditProvider(repository.queries.last));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      repository.gate = null;
      sessions.change(2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(repository.queries.last.before, isNull);
      old.complete(auditWindow(repository.raw, repository.queries[1]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.text('Monitoring finished'), findsOneWidget);
      expect(find.text('Observation recorded'), findsNothing);
      await _finish(tester);
    },
  );
  for (final (width, scale) in [(1440.0, 1.0), (760.0, 1.0), (320.0, 2.0)]) {
    testWidgets(
      'action evidence reflows at width$width text$scale with accessible event heading',
      (tester) async {
        final repository = _Repository();
        await _mount(tester, repository, width: width, scale: scale);
        expect(tester.takeException(), isNull);
        final semantics = tester.ensureSemantics();
        expect(
          tester
              .getSemantics(find.text('Monitoring finished'))
              .getSemanticsData()
              .flagsCollection
              .isHeader,
          true,
        );
        await tester.ensureVisible(find.text('Original request ID').first);
        await tester.pump();
        expect(tester.takeException(), isNull);
        semantics.dispose();
        await _finish(tester);
      },
    );
  }
  testWidgets(
    'actual registered audit route preserves general audit list and loads one fixed entity read',
    (tester) async {
      final repository = _Repository();
      final container = await _mount(tester, repository, router: true);
      final router = container.read(adminRouterProvider);
      router.go(
        adminEntityAuditPath(
          AdminAuditEntityKind.shadowRun,
          repository.raw['entity_id'] as String,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.byType(AdminEntityAuditPage), findsOneWidget);
      expect(repository.queries, hasLength(1));
      expect(adminRoutePaths, contains('/admin/audit-logs'));
      expect(adminRoutePaths, contains('/admin/audit-logs/entity/:kind/:id'));
      await _finish(tester);
      router.dispose();
    },
  );
  testWidgets(
    'manual shadow run links push its canonical action history and preserve return route',
    (tester) async {
      final repository = _Repository();
      final container = await _mount(tester, repository, router: true);
      final router = container.read(adminRouterProvider);
      router.go('/admin/automations');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final link = find.byKey(
        ValueKey('shadow-audit-${repository.raw['entity_id']}'),
      );
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(AdminEntityAuditPage), findsOneWidget);
      expect(repository.queries.single.id, repository.raw['entity_id']);
      expect(router.canPop(), true);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AdminEntityAuditPage), findsNothing);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/admin/automations',
      );
      await _finish(tester);
      router.dispose();
    },
  );
  testWidgets(
    'dark and light local audit captures use only synthetic retained evidence',
    (tester) async {
      final destination = Platform.environment['COLLECT_ENTITY_AUDIT_CAPTURE'];
      if (destination == null) return;
      for (final dark in [true, false]) {
        final capture = GlobalKey(), repository = _Repository();
        final container = await _mount(
          tester,
          repository,
          router: true,
          dark: dark,
          capture: capture,
        );
        final router = container.read(adminRouterProvider);
        router.go(
          adminEntityAuditPath(
            AdminAuditEntityKind.shadowRun,
            repository.raw['entity_id'] as String,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await tester.runAsync(
          () async => File(
            '$destination/audit-${dark ? 'dark' : 'light'}-1440x2200.png',
          ).writeAsBytes(bytes!.buffer.asUint8List()),
        );
        image.dispose();
        await _finish(tester);
        router.dispose();
      }
    },
  );
}
