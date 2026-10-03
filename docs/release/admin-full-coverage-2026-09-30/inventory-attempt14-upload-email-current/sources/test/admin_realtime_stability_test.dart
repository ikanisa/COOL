import 'dart:async';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _identity = AdminIdentity(
  userId: 'synthetic-operator',
  displayName: 'Synthetic operator',
  roles: ['admin'],
  permissions: ['notifications.read'],
);

class _SessionController extends AdminSessionController {
  _SessionController() : super(null) {
    replace(1);
  }

  void replace(int generation) => state = (
    key: (userId: _identity.userId, sessionId: 'session-$generation'),
    generation: generation,
  );
}

class _Repository extends AdminEvidenceRepository {
  final requests = <({String? search, String? status, String? sort})>[];
  String label = 'Original receipt';
  Completer<void>? pending;

  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async => null;

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
    requests.add((search: search, status: status, sort: sortBy));
    final currentLabel = label;
    await pending?.future;
    return AdminListResult(
      total: 1,
      rows: [
        AdminTableRowData(
          id: currentLabel,
          title: currentLabel,
          subtitle: 'Synthetic masked notification',
          status: 'queued',
          amount: '1',
          createdAt: DateTime.parse('2026-09-30T08:00:00Z'),
          extra: const {'country_code': 'RW'},
        ),
      ],
    );
  }
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  _Repository repository, {
  _SessionController? sessions,
}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(null),
      adminRepositoryProvider.overrideWithValue(repository),
      adminIdentityProvider.overrideWith((ref) async => _identity),
      adminRealtimeTickProvider.overrideWith((ref) => 7),
      if (sessions != null)
        adminAuthSessionScopeProvider.overrideWith((ref) => sessions),
    ],
  );
  addTearDown(container.dispose);
  await container.read(adminIdentityProvider.future);
  final router = GoRouter(
    initialLocation: '/notifications',
    routes: [
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const Scaffold(
          body: AdminRpcListPage(
            title: 'Notifications',
            rpcName: 'admin_list_notifications',
            detailPathPrefix: '/notifications',
          ),
        ),
      ),
      GoRoute(
        path: '/notifications/:id',
        builder: (context, state) =>
            Scaffold(body: Text('Opened ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('realtime advertises work without replacing the clicked record', (
    tester,
  ) async {
    final repository = _Repository();
    final container = await _open(tester, repository);
    expect(repository.requests, hasLength(1));
    expect(find.text('New activity available'), findsNothing);
    repository.label = 'New receipt';
    container.read(adminRealtimeTickProvider.notifier).state += 1;
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(1));
    expect(find.text('Original receipt'), findsOneWidget);
    expect(find.text('New receipt'), findsNothing);
    expect(find.text('New activity available'), findsOneWidget);
    await tester.tap(find.byTooltip('Open Original receipt'));
    await tester.pumpAndSettle();
    expect(find.text('Opened Original receipt'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('explicit refresh and filters consume pending activity', (
    tester,
  ) async {
    final repository = _Repository();
    final container = await _open(tester, repository);
    final search = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == 'Search',
    );
    await tester.enterText(search, 'applied query');
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    repository.label = 'New receipt';
    container.read(adminRealtimeTickProvider.notifier).state += 2;
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(2));
    await tester.tap(find.byKey(const Key('admin-apply-new-activity')));
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(3));
    expect(repository.requests.last.search, 'applied query');
    expect(find.text('New receipt'), findsOneWidget);
    expect(find.text('New activity available'), findsNothing);
    container.read(adminRealtimeTickProvider.notifier).state += 1;
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter: All'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Queued'));
    await tester.pumpAndSettle();
    expect(repository.requests.last.status, 'queued');
    expect(find.text('New activity available'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('same operator replacement session resets view and activity', (
    tester,
  ) async {
    final repository = _Repository();
    final sessions = _SessionController();
    final container = await _open(tester, repository, sessions: sessions);
    final search = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == 'Search',
    );
    await tester.enterText(search, 'old session query');
    container.read(adminRealtimeTickProvider.notifier).state += 1;
    await tester.pumpAndSettle();
    expect(find.text('New activity available'), findsOneWidget);
    sessions.replace(2);
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(2));
    expect(repository.requests.last.search, isEmpty);
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(find.text('New activity available'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'activity during a load stays pending after the older load ends',
    (tester) async {
      final repository = _Repository();
      final container = await _open(tester, repository);
      final pending = Completer<void>();
      repository.pending = pending;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pump();
      container.read(adminRealtimeTickProvider.notifier).state += 1;
      await tester.pump();
      expect(find.text('New activity available'), findsOneWidget);
      pending.complete();
      repository.pending = null;
      await tester.pumpAndSettle();
      expect(repository.requests, hasLength(2));
      expect(find.text('New activity available'), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin-apply-new-activity')));
      await tester.pumpAndSettle();
      expect(repository.requests, hasLength(3));
      expect(find.text('New activity available'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
