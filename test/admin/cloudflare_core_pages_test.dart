import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/cloudflare_admin_app.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_core_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/main_admin_cloudflare.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cloudflare_core_fixtures.dart';
import '../support/legacy_backend_fixture.dart';

http.Response response(String body, int status) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Future<ProviderContainer> pumpCore(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) respond, {
  List<String>? permissions,
  String role = 'admin',
}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final service = CloudflareAdminSession(
    MockClient((request) async {
      if (request.url.path.endsWith('/auth/session')) {
        final session = coreSession(permissions: permissions);
        (session['user'] as Map<String, dynamic>)['role'] = role;
        return response(jsonEncode(session), 200);
      }
      if (request.url.path.endsWith('/sync')) {
        return response(
          jsonEncode({
            'contract_version': 1,
            'events': [],
            'cursor': request.url.queryParameters['cursor'],
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/core/overview')) {
        return response(jsonEncode(coreOverview()), 200);
      }
      return respond(request);
    }),
    origin: Uri.parse('https://admin.example.test/'),
    environment: legacyBackendFixtureEnvironment,
  );
  final container = ProviderContainer(
    overrides: [
      ...cloudflareAdminOverrides(),
      cloudflareAdminSessionProvider.overrideWith((_) => service),
    ],
  );
  addTearDown(container.dispose);
  await service.refresh();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const CloudflareAdminApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'live reads retain submitted filters, sort and the current table page',
    (tester) async {
      final queries = <Map<String, String>>[];
      final records = List<Map<String, dynamic>>.generate(
        26,
        (index) => {
          ...coreRow(CloudflareCoreArea.groups),
          'id':
              '11111111-1111-4111-8111-${(index + 1).toString().padLeft(12, '0')}',
          'title': 'Example record ${index + 1}',
          'created_at': DateTime.utc(2026, 10, 4, 12, index).toIso8601String(),
        },
      );
      final container = await pumpCore(tester, (request) async {
        final query = request.url.queryParameters;
        queries.add(query);
        final ordered = query['sort'] == 'created_at_asc'
            ? records
            : records.reversed;
        final offset = int.parse(query['offset']!);
        final limit = int.parse(query['limit']!);
        return response(
          jsonEncode({
            'rows': ordered.skip(offset).take(limit).toList(),
            'total': records.length,
          }),
          200,
        );
      });
      final router = container.read(cloudflareAdminRouterProvider);
      const location =
          '/admin/groups?search=example&status=active&page=2&sort=created_at_asc';
      router.go(location);
      await tester.pumpAndSettle();
      final before = queries.length;
      container.read(adminRealtimeTickProvider.notifier).state++;
      await tester.pumpAndSettle();
      expect(queries.length, greaterThan(before));
      expect(queries.last, containsPair('search', 'example'));
      expect(queries.last, containsPair('status', 'active'));
      expect(queries.last, containsPair('sort', 'created_at_asc'));
      expect(queries.last, containsPair('offset', '25'));
      expect(router.routeInformationProvider.value.uri.toString(), location);
      expect(find.text('26–26 of 26'), findsOneWidget);
      expect(container.read(adminLastSuccessfulRefreshProvider), isNotNull);
      final table = tester.widget<DataTable>(find.byType(DataTable));
      final created = table.columns.indexWhere(
        (column) => (column.label as Text).data == 'Created · Kigali',
      );
      expect(table.sortColumnIndex, created);
      expect(table.sortAscending, isTrue);
      expect(table.columns[created].onSort, isNotNull);
      table.columns[created].onSort!(created, false);
      await tester.pumpAndSettle();
      expect(queries.last, containsPair('sort', 'created_at_desc'));
      expect(queries.last, containsPair('offset', '0'));
      expect(queries.last, containsPair('search', 'example'));
      expect(queries.last, containsPair('status', 'active'));
      // Default descending order and page one are omitted from list URLs.
      // The HTTP assertions above still verify their explicit wire values.
      final sortedLocation = router.routeInformationProvider.value.uri;
      expect(sortedLocation.path, '/admin/groups');
      expect(sortedLocation.queryParameters, {
        'search': 'example',
        'status': 'active',
      });
      expect(find.byType(DataTable), findsOneWidget);
      final sortedTable = tester.widget<DataTable>(find.byType(DataTable));
      expect(sortedTable.sortColumnIndex, created);
      expect(sortedTable.sortAscending, isFalse);
      expect(sortedTable.rows, hasLength(25));
      expect(find.text('1–25 of 26'), findsOneWidget);
      expect(find.text('Example record 26'), findsOneWidget);
      expect(find.text('Example record 1'), findsNothing);
      expect(tester.takeException(), isNull);
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'all six registered routes expose authoritative empty lists and sidebar navigation',
    (tester) async {
      final requests = <String>[];
      final container = await pumpCore(tester, (request) async {
        requests.add(request.url.path);
        return response('{"rows":[],"total":0}', 200);
      });
      expect(
        find.byKey(const ValueKey('cloudflare-core-count-Users')),
        findsOneWidget,
      );
      // Every returned summary is exposed in the table without a disclosure.
      expect(
        find.byKey(const ValueKey('admin-all-workspace-totals')),
        findsOneWidget,
      );
      expect(find.text('0'), findsNWidgets(19));
      for (final area in CloudflareCoreArea.values) {
        expect(find.text(area.title), findsWidgets);
        container.read(cloudflareAdminRouterProvider).go(area.path);
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('cloudflare-core-empty-${area.name}')),
          findsOneWidget,
        );
        expect(find.text('Create group'), findsNothing);
        expect(find.text('Create payee'), findsNothing);
      }
      expect(requests.toSet(), {
        for (final area in CloudflareCoreArea.values)
          '/api/admin/core/${area.name}',
      });
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'failed list stays unavailable and user refresh can recover a real empty result',
    (tester) async {
      var unavailable = true;
      final container = await pumpCore(
        tester,
        (_) async => unavailable
            ? response('{}', 503)
            : response('{"rows":[],"total":0}', 200),
      );
      container.read(cloudflareAdminRouterProvider).go('/admin/groups');
      await tester.pumpAndSettle();
      expect(
        find.text('The admin request could not be completed.'),
        findsOneWidget,
      );
      expect(find.text('No groups yet'), findsNothing);
      unavailable = false;
      await tester.tap(find.byKey(const Key('admin-queue-refresh')));
      await tester.pumpAndSettle();
      expect(find.text('No groups yet'), findsOneWidget);
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('denied deep link never requests records', (tester) async {
    var requests = 0;
    final container = await pumpCore(tester, (_) async {
      requests++;
      return response('{"rows":[],"total":0}', 200);
    }, permissions: ['overview.read', 'account.manage']);
    container.read(cloudflareAdminRouterProvider).go('/admin/users');
    await tester.pumpAndSettle();
    expect(find.text('Your workspace'), findsOneWidget);
    expect(find.text('No users yet'), findsNothing);
    expect(requests, 0);
    container.read(cloudflareAdminSessionProvider.notifier).clear();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Staff sees only the explicitly granted group create control', (
    tester,
  ) async {
    final container = await pumpCore(
      tester,
      (_) async => response('{"rows":[],"total":0}', 200),
      role: 'staff',
      permissions: [
        'overview.read',
        'account.manage',
        'collections.read',
        'collections.create',
        'users.read',
      ],
    );
    final router = container.read(cloudflareAdminRouterProvider);
    router.go('/admin/groups');
    await tester.pumpAndSettle();
    expect(find.text('Create group'), findsOneWidget);
    router.go('/admin/users');
    await tester.pumpAndSettle();
    expect(find.text('Add person'), findsNothing);
    container.read(cloudflareAdminSessionProvider.notifier).clear();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'loading cannot display empty success and logout discards pending rows',
    (tester) async {
      final pending = Completer<http.Response>();
      final container = await pumpCore(tester, (_) => pending.future);
      container.read(cloudflareAdminRouterProvider).go('/admin/users');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Loading users'), findsOneWidget);
      expect(find.text('No users yet'), findsNothing);
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      pending.complete(
        response(
          jsonEncode({
            'rows': [coreRow(CloudflareCoreArea.users)],
            'total': 1,
          }),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Collect'), findsOneWidget);
      expect(find.text('Example record'), findsNothing);
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('detail return accepts only bounded same-area list locations', () {
    const location =
        '/admin/users?search=type%3Adirect&page=2&sort=created_at_asc';
    expect(
      cloudflareCoreReturnLocation(CloudflareCoreArea.users, location),
      location,
    );
    for (final invalid in [
      '//outside.example/admin/users',
      'https://outside.example/admin/users',
      '/admin/groups?page=2',
      '/admin/users?page=0',
      '/admin/users?page=2&page=3',
      '/admin/users?token=secret',
      '/admin/users?status=unsupported',
    ]) {
      expect(
        cloudflareCoreReturnLocation(CloudflareCoreArea.users, invalid),
        '/admin/users',
      );
    }
  });

  testWidgets(
    'all core areas show dedicated schemas with full numeric contact facts',
    (tester) async {
      final container = await pumpCore(tester, (request) async {
        final area = CloudflareCoreArea.values.byName(
          request.url.pathSegments.last,
        );
        return response(
          jsonEncode({
            'rows': [coreRow(area)],
            'total': 1,
          }),
          200,
        );
      });
      const schemas = {
        CloudflareCoreArea.groups: [
          'Name',
          'Slug',
          'Type',
          'Visibility',
          'Purpose',
          'Members',
          'Status',
          'Created · Kigali',
          'Open',
        ],
        CloudflareCoreArea.users: [
          'ID',
          'Name',
          'Type',
          'Email',
          'WhatsApp',
          'MoMo number',
          'MoMo code',
          'Groups',
          'Contributed',
          'Posted contributions',
          'Status',
          'Created · Kigali',
          'Open',
        ],
        CloudflareCoreArea.members: [
          'ID',
          'Name',
          'Type',
          'WhatsApp',
          'MoMo number',
          'MoMo code',
          'Groups',
          'Contributed',
          'Posted contributions',
          'Status',
          'Created · Kigali',
          'Open',
        ],
        CloudflareCoreArea.payees: [
          'Name',
          'Group',
          'MoMo number',
          'MoMo code',
          'Status',
          'Created · Kigali',
          'Open',
        ],
        CloudflareCoreArea.transactions: [
          'Transaction ID',
          'Status',
          'Amount',
          'Allocated',
          'Remaining',
          'Payer name',
          'Payer last 3',
          'Payee MoMo number / code',
          'SMS payee number',
          'SMS payee code',
          'MoMo transaction',
          'MoMo timestamp',
          'SMS timezone offset',
          'Wallet balance',
          'SMS network',
          'Direction',
          'Provider reference',
          'Group',
          'Payee',
          'Observed',
          'Created · Kigali',
          'Open',
        ],
        CloudflareCoreArea.ledgers: [
          'Description',
          'Group',
          'Debit',
          'Credit',
          'Entries',
          'Balanced',
          'Status',
          'Created · Kigali',
          'Posted',
          'Open',
        ],
      };
      for (final entry in schemas.entries) {
        container.read(cloudflareAdminRouterProvider).go(entry.key.path);
        await tester.pumpAndSettle();
        final table = tester.widget<DataTable>(find.byType(DataTable));
        expect(
          table.columns.map((column) => (column.label as Text).data).toList(),
          entry.value,
        );
        final created = table.columns.indexWhere(
          (column) => (column.label as Text).data == 'Created · Kigali',
        );
        expect(table.columns[created].onSort, isNotNull);
        expect(table.sortColumnIndex, created);
        expect(
          (table.rows.single.cells.last.child as IconButton).onPressed,
          isNotNull,
        );
        expect(find.text('RW'), findsNothing);
        expect(find.textContaining('RWF '), findsNothing);
        if (entry.key == CloudflareCoreArea.users ||
            entry.key == CloudflareCoreArea.members) {
          expect(find.text('000123'), findsOneWidget);
          expect(find.text('250788001234'), findsOneWidget);
          expect(find.text('0788001234'), findsOneWidget);
          expect(find.text('008000'), findsOneWidget);
          expect(find.text('5,000'), findsOneWidget);
          expect(find.textContaining('Collect ID'), findsNothing);
        }
        if (entry.key == CloudflareCoreArea.transactions) {
          expect(find.text('Unallocated'), findsOneWidget);
          expect(find.text('Confirmation recorded'), findsNothing);
          expect(find.text('9,007,199,254,740,991'), findsNWidgets(2));
        }
      }
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Overview shows exact totals and App/Direct summary links apply search intent',
    (tester) async {
      final searches = <String>[];
      final service = CloudflareAdminSession(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/session')) {
            return response(jsonEncode(coreSession()), 200);
          }
          if (request.url.path.endsWith('/core/overview')) {
            return response(
              jsonEncode(
                coreOverview(
                  amounts: {'total_collected_rwf': '9223372036854775807'},
                ),
              ),
              200,
            );
          }
          if (request.url.path.endsWith('/core/users')) {
            searches.add(request.url.queryParameters['search']!);
            return response('{"rows":[],"total":0}', 200);
          }
          return response('{"ok":true}', 200);
        }),
        origin: Uri.parse('https://admin.example.test/'),
        environment: legacyBackendFixtureEnvironment,
      );
      tester.view.physicalSize = const Size(1440, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [
          ...cloudflareAdminOverrides(),
          cloudflareAdminSessionProvider.overrideWith((_) => service),
        ],
      );
      addTearDown(container.dispose);
      await service.refresh();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CloudflareAdminApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('9,223,372,036,854,775,807'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('admin-all-workspace-totals')),
        findsOneWidget,
      );
      expect(find.text('SMS receipts'), findsOneWidget);
      expect(find.text('Member receipt submissions'), findsNothing);
      final summaryLink = find.byTooltip('Open Direct users').first;
      await tester.ensureVisible(summaryLink);
      await tester.pumpAndSettle();
      await tester.tap(summaryLink);
      await tester.pumpAndSettle();
      final uri = container
          .read(cloudflareAdminRouterProvider)
          .routeInformationProvider
          .value
          .uri;
      expect(uri.path, '/admin/users');
      expect(uri.queryParameters['search'], 'type:direct');
      expect(searches.last, 'type:direct');
      service.clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'row body and keyboard open real URLs and Back restores submitted list state',
    (tester) async {
      final container = await pumpCore(tester, (request) async {
        if (request.url.path.startsWith('/api/admin/operations/')) {
          return response(
            jsonEncode({
              'resource_type': 'groups',
              'resource': {
                'id': coreId,
                'title': 'Example record',
                'version': 1,
              },
              'current_actor_id': coreId,
              'can_manage': false,
              'related': {},
              'related_truncated': false,
            }),
            200,
          );
        }
        return response(
          jsonEncode({
            'rows': [coreRow(CloudflareCoreArea.groups)],
            'total': 26,
          }),
          200,
        );
      });
      final router = container.read(cloudflareAdminRouterProvider);
      const location =
          '/admin/groups?search=example&page=2&sort=created_at_asc';
      router.go(location);
      await tester.pumpAndSettle();
      expect(find.text('26–26 of 26'), findsOneWidget);
      await tester.tap(find.text('Example record'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/admin/groups/$coreId',
      );
      expect(
        Uri.parse(
          router
              .routeInformationProvider
              .value
              .uri
              .queryParameters['returnTo']!,
        ).queryParameters,
        Uri.parse(location).queryParameters,
      );
      await tester.tap(find.byTooltip('Back to records'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/admin/groups');
      expect(
        router.routeInformationProvider.value.uri.queryParameters,
        Uri.parse(location).queryParameters,
      );
      expect(find.text('26–26 of 26'), findsOneWidget);
      final open = find.byTooltip('Open Example record');
      Focus.of(tester.element(open)).requestFocus();
      await tester.pump();
      var focusedOpen = false;
      for (var attempt = 0; attempt < 20; attempt++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        if (FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<IconButton>()
                ?.tooltip ==
            'Open Example record') {
          focusedOpen = true;
          break;
        }
      }
      expect(
        focusedOpen,
        isTrue,
        reason: 'The row Open action must be keyboard reachable.',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/admin/groups/$coreId',
      );
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
