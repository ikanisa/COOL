import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/cloudflare_admin_app.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_core_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/main_admin_cloudflare.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cloudflare_core_fixtures.dart';

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
      if (request.url.path.endsWith('/core/overview')) {
        return response(jsonEncode(coreOverview()), 200);
      }
      return respond(request);
    }),
    origin: Uri.parse('https://admin.example.test/'),
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
          'Created',
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
          'Created',
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
          'Created',
          'Open',
        ],
        CloudflareCoreArea.payees: [
          'Name',
          'Group',
          'MoMo number',
          'MoMo code',
          'Status',
          'Created',
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
          'Created',
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
          'Created',
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
        expect(table.rows.single.onSelectChanged, isNotNull);
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
                  amounts: {
                    'total_collected_rwf': '9223372036854775807',
                    'total_unallocated_rwf': '25000',
                  },
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
      final summary = tester.widget<DataTable>(
        find.ancestor(
          of: find.byKey(
            const ValueKey('cloudflare-core-count-Total unallocated'),
          ),
          matching: find.byType(DataTable),
        ),
      );
      DataRow summaryRow(String metric) => summary.rows.singleWhere(
        (row) => (row.cells[1].child as Text).data == metric,
      );
      final unallocated = summaryRow('Total unallocated');
      expect((unallocated.cells[2].child as Text).data, '25,000');
      expect(
        (unallocated.cells[3].child as Text).data,
        'Remaining amounts from non-rejected recorded payments',
      );
      expect(
        (summaryRow('Total collected').cells[3].child as Text).data,
        'Confirmed recorded payments',
      );
      expect(find.text('SMS receipts'), findsOneWidget);
      expect(find.text('Member receipt submissions'), findsNothing);
      final card = find.byKey(
        const ValueKey('cloudflare-core-count-Direct users'),
      );
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
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
