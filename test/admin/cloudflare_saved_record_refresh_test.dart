import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/cloudflare_admin_app.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_data_refresh.dart';
import 'package:collect_app/admin/core/cloudflare_admin_operating_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:collect_app/main_admin_cloudflare.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cloudflare_core_fixtures.dart';
import 'cloudflare_operating_pages_test.dart'
    show pumpOperating, reasonAndReview, clean;
import 'cloudflare_operating_repository_test.dart'
    show operatingRepository, operatingResponse, operatingReceipt, otherId;

Map<String, dynamic> groupDetail(int version, String description) => {
  'resource_type': 'groups',
  'resource': {
    'id': coreId,
    'version': version,
    'title': 'Refresh example group',
    'slug': 'refresh-example',
    'status': 'draft',
    'collection_type': 'ikimina',
    'description': description,
    'visibility': 'private',
    'is_platform_sponsored': false,
  },
  'current_actor_id': coreId,
  'can_manage': true,
  'related': {
    'memberships': [
      {
        'group_id': coreId,
        'user_id': otherId,
        'display_name': version == 2 ? 'Previous member' : 'Current member',
        'role': 'member',
        'status': 'active',
      },
    ],
  },
  'related_truncated': false,
};

Future<ProviderContainer> pumpSavedRecordApp(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) respond,
) async {
  tester.view.physicalSize = const Size(1440, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = CloudflareAdminSession(
    MockClient((request) async {
      if (request.url.path.endsWith('/auth/session')) {
        return operatingResponse(
          coreSession(
            permissions: [
              'overview.read',
              'account.manage',
              'collections.read',
              'collections.manage',
              'collections.create',
              'users.manage',
            ],
          ),
        );
      }
      return respond(request);
    }),
    origin: Uri.parse('https://admin.example.test/'),
  );
  final container = ProviderContainer(
    overrides: [
      ...cloudflareAdminOverrides(),
      cloudflareAdminSessionProvider.overrideWith((_) => session),
      adminPendingAttemptStorageProvider.overrideWithValue(
        MemoryAdminPendingAttemptStorage(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await session.refresh();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const CloudflareAdminApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final lostReply in [false, true]) {
    testWidgets(
      'saved group ${lostReply ? 'GET recovery' : 'receipt'} opens fresh detail and refreshes list/summary',
      (tester) async {
        var version = 2,
            writes = 0,
            detailReads = 0,
            listReads = 0,
            overviewReads = 0,
            requestReads = 0;
        var description = 'Before saved change';
        String? originalKey;
        final container = await pumpSavedRecordApp(tester, (request) async {
          final path = request.url.path;
          if (path.endsWith('/core/overview')) {
            overviewReads++;
            return operatingResponse(coreOverview(count: version));
          }
          if (path.endsWith('/core/groups')) {
            listReads++;
            return operatingResponse({
              'rows': [
                {
                  ...coreRow(CloudflareCoreArea.groups),
                  'title': 'Refresh example group',
                  'active_members': version,
                  'amount': '$version members',
                },
              ],
              'total': 1,
            });
          }
          if (path.endsWith('/operations/groups/$coreId')) {
            if (request.method == 'GET') {
              detailReads++;
              return operatingResponse(groupDetail(version, description));
            }
            expect(request.method, 'PATCH');
            writes++;
            originalKey = request.headers['idempotency-key'];
            final body = jsonDecode(request.body) as Map;
            expect(body['expected_version'], 2);
            description = body['description'] as String;
            version = 3;
            if (lostReply) throw http.ClientException('saved response lost');
            return operatingResponse(operatingReceipt(version: version));
          }
          if (originalKey != null &&
              path.endsWith('/operations/requests/$originalKey')) {
            expectSync(request.method, 'GET');
            requestReads++;
            return operatingResponse({
              'status': 'succeeded',
              'request_id': otherId,
              'receipt': operatingReceipt(version: version),
            });
          }
          return operatingResponse({'rows': [], 'total': 0});
        });
        final router = container.read(cloudflareAdminRouterProvider);
        router.go('/admin/groups');
        await tester.pumpAndSettle();
        router.go('/admin/groups/$coreId');
        await tester.pumpAndSettle();
        expect(find.text('Version 2'), findsOneWidget);
        await tapVisible(
          tester,
          find.widgetWithText(OutlinedButton, 'Edit group'),
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Description'),
          'Authoritative saved description',
        );
        await reasonAndReview(tester);
        await tapVisible(tester, find.text('Confirm change'));
        if (lostReply) {
          expect(find.text('Change saved'), findsNothing);
          await tapVisible(tester, find.text('Check request status'));
        }
        expect(find.text('Change saved'), findsOneWidget);
        expect(writes, 1);
        expect(requestReads, lostReply ? 1 : 0);
        final readsBeforeOpen = detailReads;
        await tapVisible(tester, find.text('Open saved record'));
        expect(detailReads, greaterThan(readsBeforeOpen));
        expect(find.text('Version 3'), findsOneWidget);
        expect(find.text('Authoritative saved description'), findsOneWidget);
        expect(find.text('Before saved change'), findsNothing);
        expect(find.text('Current member'), findsOneWidget);
        expect(find.text('Previous member'), findsNothing);
        await tapVisible(tester, find.byTooltip('Back to records'));
        expect(listReads, greaterThan(1));
        final groups = tester.widget<AdminDataTable>(
          find.byWidgetPredicate(
            (w) => w is AdminDataTable && w.tableLabel == 'Groups',
          ),
        );
        expect(groups.rows.single.extra['active_members'], 3);
        router.go('/admin');
        await tester.pumpAndSettle();
        expect(overviewReads, greaterThan(1));
        expect(
          find.byKey(const ValueKey('cloudflare-core-count-Groups')),
          findsOneWidget,
        );
        expect(writes, 1);
        expect(tester.takeException(), isNull);
        container.read(cloudflareAdminSessionProvider.notifier).clear();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'canceling a reviewed group edit does not save or invalidate data',
    (tester) async {
      var writes = 0;
      final repo = await operatingRepository((request) async {
        if (request.method != 'GET') writes++;
        return operatingResponse({});
      });
      final detail = CloudflareOperatingDetail(
        type: 'groups',
        resource:
            groupDetail(2, 'Unchanged')['resource'] as Map<String, dynamic>,
        actorId: coreId,
        canManage: true,
        related: const {},
        truncated: false,
      );
      final container = await pumpOperating(
        tester,
        repo,
        CloudflareOperatingForm(
          operation: CloudflareOperation.updateGroup,
          detail: detail,
        ),
      );
      final revision = container.read(cloudflareAdminDataRevisionProvider);
      await reasonAndReview(tester);
      await tapVisible(tester, find.text('Back to edit'));
      expect(writes, 0);
      expect(container.read(cloudflareAdminDataRevisionProvider), revision);
      expect(find.text('Change saved'), findsNothing);
      await clean(tester, repo);
    },
  );

  testWidgets(
    'recovered receipt stays visible while fresh authoritative detail loads',
    (tester) async {
      final refreshed = Completer<http.Response>();
      var detailReads = 0, writes = 0;
      final repo = await operatingRepository((request) async {
        if (request.method != 'GET') writes++;
        if (request.url.path.endsWith('/operations/groups/$coreId')) {
          detailReads++;
          return detailReads == 1
              ? operatingResponse(groupDetail(2, 'Before saved change'))
              : refreshed.future;
        }
        return operatingResponse({
          'status': 'succeeded',
          'request_id': otherId,
          'receipt': operatingReceipt(version: 3),
        });
      });
      final container = await pumpOperating(
        tester,
        repo,
        const CloudflareOperatingDetailPage(
          type: 'groups',
          id: coreId,
          backPath: '/admin/groups',
        ),
      );
      container
          .read(adminPendingAttemptStoreProvider)
          .retain(
            family: 'operating-updategroup',
            resourceId: coreId,
            requestKey: 'recovery-group-original-key',
            permission: 'collections.manage',
            intent: {
              'expected_version': 2,
              'reason': 'Reviewed original group change',
            },
            schema: const AdminPendingAttemptSchema(
              fields: {'expected_version', 'reason'},
            ),
          );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Check request status'));
      await tester.tap(find.text('Check request status'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Change saved'), findsOneWidget);
      expect(find.text('Loading record'), findsOneWidget);
      refreshed.complete(
        operatingResponse(groupDetail(3, 'Recovered description')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Version 3'), findsOneWidget);
      expect(find.text('Recovered description'), findsOneWidget);
      expect(find.text('Change saved'), findsOneWidget);
      expect(writes, 0);
      await clean(tester, repo);
    },
  );

  testWidgets(
    'request lookup refreshes pending history and opens the current record beyond its receipt version',
    (tester) async {
      var succeeded = false, recentReads = 0, writes = 0;
      const key = 'historical-original-request';
      final container = await pumpSavedRecordApp(tester, (request) async {
        if (request.method != 'GET') writes++;
        final path = request.url.path;
        if (path.endsWith('/core/overview')) {
          return operatingResponse(coreOverview());
        }
        if (path.endsWith('/operations/requests')) {
          recentReads++;
          return operatingResponse({
            'rows': [
              {
                'id': otherId,
                'idempotency_key': key,
                'scope': 'groups.patch',
                'status': succeeded ? 'succeeded' : 'pending',
                'created_at': 1792056432,
                if (succeeded) 'receipt': operatingReceipt(version: 3),
              },
            ],
            'total': 1,
          });
        }
        if (path.endsWith('/operations/requests/$key')) {
          succeeded = true;
          return operatingResponse({
            'status': 'succeeded',
            'request_id': otherId,
            'receipt': operatingReceipt(version: 3),
          });
        }
        if (path.endsWith('/operations/groups/$coreId')) {
          return operatingResponse(
            groupDetail(4, 'Newer authoritative description'),
          );
        }
        return operatingResponse({'rows': [], 'total': 0});
      });
      container.read(cloudflareAdminRouterProvider).go('/admin/requests');
      await tester.pumpAndSettle();
      expect(find.text('Pending'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Request reference'),
        key,
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Check request'),
      );
      expect(find.text('Change saved'), findsOneWidget);
      expect(find.text('Pending'), findsNothing);
      expect(recentReads, 2);
      final history = tester.widget<AdminDataTable>(
        find.byWidgetPredicate(
          (w) =>
              w is AdminDataTable &&
              w.rows.any((row) => row.extra['idempotency_key'] == key),
        ),
      );
      expect(history.rows.single.extra['status'], 'succeeded');
      await tapVisible(tester, find.text('Open saved record'));
      expect(find.text('Version 4'), findsOneWidget);
      expect(find.text('Newer authoritative description'), findsOneWidget);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('an old related-page response cannot replace refreshed detail', (
    tester,
  ) async {
    final oldPage = Completer<http.Response>();
    var detailReads = 0;
    Map<String, dynamic> paged(int version, {int offset = 0}) => {
      ...groupDetail(
        version,
        version == 2 ? 'Previous description' : 'Current description',
      ),
      'related_pages': {
        'memberships': {
          'total': 2,
          'limit': 1,
          'offset': offset,
          'next_offset': offset == 0 ? 1 : null,
        },
      },
    };
    final repo = await operatingRepository((request) async {
      expectSync(request.method, 'GET');
      if (request.url.queryParameters['relation'] == 'memberships') {
        return oldPage.future;
      }
      detailReads++;
      return operatingResponse(paged(detailReads == 1 ? 2 : 3));
    });
    final container = await pumpOperating(
      tester,
      repo,
      const CloudflareOperatingDetailPage(
        type: 'groups',
        id: coreId,
        backPath: '/admin/groups',
      ),
    );
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Next'));
    await tester.tap(find.widgetWithText(TextButton, 'Next'));
    await tester.pump();
    // A validated mutation from another mounted form invalidates this detail.
    container.read(cloudflareAdminDataRevisionProvider.notifier).state++;
    await tester.pumpAndSettle();
    expect(find.text('Version 3'), findsOneWidget);
    oldPage.complete(operatingResponse(paged(2, offset: 1)));
    await tester.pumpAndSettle();
    expect(find.text('Version 3'), findsOneWidget);
    expect(find.text('Current description'), findsOneWidget);
    expect(find.text('Previous description'), findsNothing);
    expect(tester.takeException(), isNull);
    await clean(tester, repo);
  });
}
