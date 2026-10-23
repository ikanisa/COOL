import 'dart:async';

import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/cloudflare_admin_operating_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cloudflare_core_fixtures.dart';
import 'cloudflare_operating_pages_test.dart' show clean, reasonAndReview;
import 'cloudflare_operating_repository_test.dart'
    show operatingRepository, operatingResponse, otherId;
import '../support/legacy_backend_fixture.dart';

CloudflareOperatingDetail payeeDetail(Object? groupId) {
  final resource = <String, dynamic>{
    'id': coreId,
    'version': 2,
    'label': 'Recorded receiver',
    'status': 'active',
  };
  if (groupId != null) {
    resource['group_id'] = groupId;
  }
  return CloudflareOperatingDetail(
    type: 'payees',
    resource: resource,
    actorId: coreId,
    canManage: true,
    related: const {},
    truncated: false,
  );
}

Future<GoRouter> pumpPayee(
  WidgetTester tester,
  CloudflareAdminRepository repo, {
  Object? groupId = otherId,
  MemoryAdminPendingAttemptStorage? storage,
}) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      adminRepositoryProvider.overrideWithValue(repo),
      cloudflareAdminSessionProvider.overrideWith((_) => repo.session),
      if (storage != null)
        adminPendingAttemptStorageProvider.overrideWithValue(storage),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: '/admin/payees/$coreId/edit',
    routes: [
      GoRoute(
        path: '/admin/payees/:id/edit',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(
            child: CloudflareOperatingForm(
              operation: CloudflareOperation.updatePayee,
              detail: payeeDetail(groupId),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/admin/groups/:id',
        builder: (_, state) =>
            Scaffold(body: Text('Group ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets(
    'payee guidance opens its recorded group without changing either record',
    (tester) async {
      var calls = 0;
      final repo = await operatingRepository((_) async {
        calls++;
        return operatingResponse({});
      });
      final router = await pumpPayee(tester, repo);
      expect(find.textContaining('first suspend the group'), findsOneWidget);
      expect(
        find.textContaining('before reactivating the group'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Open group'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/admin/groups/$otherId',
      );
      expect(find.text('Group $otherId'), findsOneWidget);
      expect(calls, 0);
      await clean(tester, repo);
    },
  );

  for (final target in [null, 'not-a-group-id', '$otherId/../../users']) {
    testWidgets(
      'payee guidance cannot navigate a missing or invalid target $target',
      (tester) async {
        final repo = await operatingRepository(
          (_) async => operatingResponse({}),
        );
        final router = await pumpPayee(tester, repo, groupId: target);
        expect(find.textContaining('first suspend the group'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Open group'), findsNothing);
        expect(
          router.routeInformationProvider.value.uri.path,
          '/admin/payees/$coreId/edit',
        );
        expect(tester.takeException(), isNull);
        await clean(tester, repo);
      },
    );
  }

  for (final boundary in ['group permission', 'payee permission', 'session']) {
    testWidgets(
      'payee group navigation rejects a changed $boundary even through a retained callback',
      (tester) async {
        var readGroups = true, managePayees = true, sessionId = 'core-session';
        final session = CloudflareAdminSession(
          MockClient((request) async {
            expect(request.url.path, '/api/admin/auth/session');
            return operatingResponse(
              coreSession(
                sessionId: sessionId,
                permissions: [
                  'overview.read',
                  'receivers.read',
                  if (managePayees) 'receivers.manage',
                  if (readGroups) 'collections.read',
                ],
              ),
            );
          }),
          origin: Uri.parse('https://admin.example.test/'),
          environment: legacyBackendFixtureEnvironment,
        );
        addTearDown(() {
          if (session.mounted) session.dispose();
        });
        await session.refresh();
        final repo = CloudflareAdminRepository(session);
        final router = await pumpPayee(tester, repo);
        final retained = tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Open group'))
            .onPressed!;
        switch (boundary) {
          case 'group permission':
            readGroups = false;
          case 'payee permission':
            managePayees = false;
          case 'session':
            sessionId = 'different-session';
        }
        await session.refresh();
        await tester.pumpAndSettle();
        retained();
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/admin/payees/$coreId/edit',
        );
        final link = find.widgetWithText(TextButton, 'Open group');
        if (boundary == 'session') {
          expect(tester.widget<TextButton>(link).onPressed, isNull);
        } else {
          expect(link, findsNothing);
        }
        expect(tester.takeException(), isNull);
        await clean(tester, repo);
      },
    );
  }

  testWidgets(
    'payee group link stays locked while saving and after a lost response',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage();
      final response = Completer<http.Response>();
      var writes = 0;
      final repo = await operatingRepository((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/api/admin/operations/payees/$coreId');
        writes++;
        return response.future;
      });
      final router = await pumpPayee(tester, repo, storage: storage);
      final link = find.widgetWithText(TextButton, 'Open group');
      final retained = tester.widget<TextButton>(link).onPressed!;
      await reasonAndReview(tester);
      await tester.tap(find.text('Confirm change'));
      await tester.pump();
      expect(writes, 1);
      expect(tester.widget<TextButton>(link).onPressed, isNull);
      retained();
      await tester.pump();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/admin/payees/$coreId/edit',
      );
      response.completeError(
        http.ClientException('committed response was lost'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('The result is unconfirmed'), findsOneWidget);
      expect(tester.widget<TextButton>(link).onPressed, isNull);
      retained();
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/admin/payees/$coreId/edit',
      );
      expect(storage.values, isNotEmpty);
      expect(writes, 1);
      expect(tester.takeException(), isNull);
      await clean(tester, repo);
    },
  );
}
