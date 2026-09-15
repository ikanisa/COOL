import 'dart:async';

import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _AccessRepository extends AdminEvidenceRepository {
  _AccessRepository({required this.identity, this.failFirstRecords = false});

  Future<AdminIdentity?> Function() identity;
  int identityRequests = 0;
  final dataRequests = <String>[];
  final bool failFirstRecords;
  final failedReads = <String>{};

  bool _fails(String rpcName) => failFirstRecords && failedReads.add(rpcName);

  @override
  Future<AdminIdentity?> currentIdentity() {
    identityRequests++;
    return identity();
  }

  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async => null;

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
    return super.detail(rpcName, id);
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
      adminRepositoryProvider.overrideWithValue(repository),
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
    final path = route.replaceAll(':id', 'synthetic-qa-record');
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
      await _open(tester, repository, path);
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
        identity: () async => identity,
        failFirstRecords: true,
      );
      final container = await _open(tester, repository, path);
      await tester.pumpAndSettle();
      expect(
        find.text('The admin service could not be reached.'),
        findsOneWidget,
      );
      final firstRequestCount = repository.dataRequests.length;
      expect(firstRequestCount, greaterThan(0));
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(repository.dataRequests.length, greaterThan(firstRequestCount));
      expect(
        find.text('The admin service could not be reached.'),
        findsNothing,
      );
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
