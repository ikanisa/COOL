import 'dart:convert';
import 'package:collect_app/admin/cloudflare_admin_app.dart';
import 'package:collect_app/admin/core/cloudflare_admin_reconciliation_api.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/main_admin_cloudflare.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'cloudflare_core_fixtures.dart';
import 'cloudflare_reconciliation_fixtures.dart';
import '../support/legacy_backend_fixture.dart';

http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
Future<ProviderContainer> pumpReconciliation(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler, {
  String role = 'staff',
  AdminPendingAttemptStorage? storage,
}) async {
  tester.view.physicalSize = const Size(1800, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = CloudflareAdminSession(
    MockClient((request) async {
      if (request.url.path.endsWith('/auth/session')) {
        return response(reconSession(role: role));
      }
      if (request.url.path.endsWith('/sync')) {
        return response({
          'contract_version': 1,
          'events': [],
          'cursor': request.url.queryParameters['cursor'],
        }, 200);
      }
      if (request.url.path.endsWith('/core/overview')) {
        return response(coreOverview());
      }
      if (request.url.path.endsWith('/sms-dispatch-gate')) {
        return response({'state': 'unavailable'}, 503);
      }
      return handler(request);
    }),
    origin: Uri.parse('https://admin.example.test'),
    environment: legacyBackendFixtureEnvironment,
  );
  final container = ProviderContainer(
    overrides: [
      ...cloudflareAdminOverrides(),
      cloudflareAdminSessionProvider.overrideWith((_) => session),
      if (storage != null)
        adminPendingAttemptStorageProvider.overrideWithValue(storage),
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

Future<void> visibleTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
Future<void> fill(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), text);
  await tester.pump();
}

Future<void> selectAndConfirm(WidgetTester tester) async {
  await visibleTap(tester, find.text('Select member'));
  await visibleTap(
    tester,
    find.text(
      'I confirm the recorded member name and MoMo number/code for this group',
    ),
  );
  await fill(tester, 'Amount', '400');
  await fill(
    tester,
    'Proposal reason',
    'Reviewed this recorded member payment.',
  );
}

void main() {
  testWidgets(
    'hard reload retains original key and requires lookup plus explicit current confirmation before retry',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage(),
          posts = <http.Request>[];
      Future<http.Response> handler(http.Request request) async {
        if (request.method == 'POST') {
          expect(storage.values, isNotEmpty);
          posts.add(request);
          return posts.length == 1
              ? response({'error': 'unavailable'}, 503)
              : response(reconReceipt());
        }
        if (request.url.path.contains('/requests/')) {
          return response({'status': 'not_found'});
        }
        if (request.url.path.endsWith('/members')) {
          return response(reconPage([reconMember()]));
        }
        if (request.url.path.endsWith(reconTransactionId)) {
          return response(reconDetail());
        }
        return response(reconPage([reconTransaction()]));
      }

      final first = await pumpReconciliation(tester, handler, storage: storage);
      first
          .read(cloudflareAdminRouterProvider)
          .go('/admin/reconciliations/$reconTransactionId');
      await tester.pumpAndSettle();
      await selectAndConfirm(tester);
      await visibleTap(tester, find.text('Record proposal'));
      final originalKey = posts.single.headers['Idempotency-Key'];
      await tester.pumpWidget(const SizedBox.shrink());
      first.dispose();
      expect(storage.values, isNotEmpty);
      final reloaded = await pumpReconciliation(
        tester,
        handler,
        storage: storage,
      );
      reloaded
          .read(cloudflareAdminRouterProvider)
          .go('/admin/reconciliations/$reconTransactionId');
      await tester.pumpAndSettle();
      expect(find.text(originalKey!), findsOneWidget);
      expect(posts, hasLength(1));
      expect(find.text('Retry original request'), findsNothing);
      expect(find.text('Reconfirm and retry original request'), findsNothing);
      await visibleTap(tester, find.text('Check original request'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Reconfirm and retry original request',
              ),
            )
            .onPressed,
        isNull,
      );
      await visibleTap(
        tester,
        find.text(
          'I reviewed the original confirmation and want to retry this same request',
        ),
      );
      await visibleTap(
        tester,
        find.text('Reconfirm and retry original request'),
      );
      expect(posts, hasLength(2));
      expect(posts.last.headers['Idempotency-Key'], originalKey);
      expect(posts.last.body, posts.first.body);
      expect(storage.values, isEmpty);
      expect(
        find.text(
          'Proposal recorded. An independent administrator must review it.',
        ),
        findsOneWidget,
      );
      reloaded.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'queue rows open an authorized real detail URL and Back restores submitted state',
    (tester) async {
      final requests = <http.Request>[];
      final container = await pumpReconciliation(tester, (request) async {
        requests.add(request);
        if (request.url.path.endsWith('/members')) {
          return response(reconPage([reconMember()]));
        }
        if (request.url.path.endsWith(reconTransactionId)) {
          return response(reconDetail());
        }
        return response(reconPage([reconTransaction()], total: 26, offset: 25));
      });
      final router = container.read(cloudflareAdminRouterProvider);
      router.go(
        '/admin/reconciliations?search=MOMO&verification=confirmation_recorded&page=2',
      );
      await tester.pumpAndSettle();
      final table = tester.widget<DataTable>(find.byType(DataTable).first);
      expect(
        table.columns.map((column) => (column.label as Text).data),
        containsAll([
          'Provider reference',
          'Payee MoMo',
          'Amount',
          'Allocated',
          'Remaining',
          'Allocation',
          'Verification',
          'Observed',
        ]),
      );
      expect(
        (table.rows.single.cells.last.child as IconButton).onPressed,
        isNotNull,
      );
      expect(find.text('0041258'), findsOneWidget);
      expect(find.text('Showing 26–26 of 26'), findsOneWidget);
      final queueRequest = requests.singleWhere(
        (request) => request.url.path.endsWith('/reconciliations'),
      );
      expect(queueRequest.url.queryParameters, containsPair('offset', '25'));
      expect(
        queueRequest.url.queryParameters,
        containsPair('verification_status', 'confirmation_recorded'),
      );
      await visibleTap(tester, find.text('456258123456789012'));
      expect(
        router.routeInformationProvider.value.uri.path,
        '/admin/reconciliations/$reconTransactionId',
      );
      expect(
        router.routeInformationProvider.value.uri.queryParameters['returnTo'],
        contains('page=2'),
      );
      await visibleTap(tester, find.byTooltip('Back to reconciliations'));
      expect(router.routeInformationProvider.value.uri.queryParameters, {
        'search': 'MOMO',
        'verification': 'confirmation_recorded',
        'page': '2',
      });
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Staff must explicitly confirm an existing Direct member before a durable proposal can be reported',
    (tester) async {
      final posts = <http.Request>[];
      final container = await pumpReconciliation(tester, (request) async {
        if (request.method == 'POST') {
          posts.add(request);
          return response(reconReceipt());
        }
        if (request.url.path.endsWith('/members')) {
          return response(reconPage([reconMember()]));
        }
        if (request.url.path.endsWith(reconTransactionId)) {
          return response(reconDetail());
        }
        return response(reconPage([reconTransaction()]));
      });
      container
          .read(cloudflareAdminRouterProvider)
          .go('/admin/reconciliations/$reconTransactionId');
      await tester.pumpAndSettle();
      expect(find.text('Approve allocation'), findsNothing);
      await visibleTap(tester, find.text('Select member'));
      expect(find.text('000123'), findsWidgets);
      expect(find.text('0788123456'), findsWidgets);
      expect(find.text('008001'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Record proposal'),
            )
            .onPressed,
        isNull,
      );
      await fill(tester, 'Amount', '400');
      await fill(
        tester,
        'Proposal reason',
        'Reviewed this recorded member payment.',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Record proposal'),
            )
            .onPressed,
        isNull,
      );
      await visibleTap(
        tester,
        find.text(
          'I confirm the recorded member name and MoMo number/code for this group',
        ),
      );
      await visibleTap(tester, find.text('Record proposal'));
      expect(posts, hasLength(1));
      final body = jsonDecode(posts.single.body) as Map;
      expect(body.containsKey('group_id'), isFalse);
      expect(body['expected_payment_identity'], reconIdentity());
      expect(
        find.text(
          'Proposal recorded. An independent administrator must review it.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Approval and allocation recorded. Settlement is not asserted.',
        ),
        findsNothing,
      );
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'unknown response keeps immutable request across polls and route changes; retry requires not_found',
    (tester) async {
      final posts = <http.Request>[];
      var authoritativeNotFound = false;
      final container = await pumpReconciliation(tester, (request) async {
        if (request.method == 'POST') {
          posts.add(request);
          return posts.length == 1
              ? response({'error': 'service_unavailable'}, 503)
              : response(reconReceipt());
        }
        if (request.url.path.contains('/requests/')) {
          return response(
            authoritativeNotFound
                ? {'status': 'not_found'}
                : {
                    'status': 'pending',
                    'request_id': reconRequestId,
                    'receipt': null,
                  },
          );
        }
        if (request.url.path.endsWith('/members')) {
          return response(reconPage([reconMember()]));
        }
        if (request.url.path.endsWith(reconTransactionId)) {
          return response(reconDetail());
        }
        return response(reconPage([reconTransaction()]));
      });
      final router = container.read(cloudflareAdminRouterProvider);
      router.go('/admin/reconciliations/$reconTransactionId');
      await tester.pumpAndSettle();
      await selectAndConfirm(tester);
      await visibleTap(tester, find.text('Record proposal'));
      expect(posts, hasLength(1));
      expect(find.text('Retry original request'), findsNothing);
      expect(
        container
            .read(cloudflareReconciliationAttemptsProvider)[reconTransactionId]!
            .key,
        posts.single.headers['Idempotency-Key'],
      );
      await container.read(cloudflareAdminSessionProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(find.text('Check original request'), findsOneWidget);
      router.go('/admin/reconciliations');
      await tester.pumpAndSettle();
      router.go('/admin/reconciliations/$reconTransactionId');
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Outcome unknown. Check the original request before continuing.',
        ),
        findsOneWidget,
      );
      await visibleTap(tester, find.text('Check original request'));
      expect(find.text('Retry original request'), findsNothing);
      authoritativeNotFound = true;
      await visibleTap(tester, find.text('Check original request'));
      await visibleTap(tester, find.text('Retry original request'));
      expect(posts, hasLength(2));
      expect(
        posts[1].headers['Idempotency-Key'],
        posts[0].headers['Idempotency-Key'],
      );
      expect(posts[1].body, posts[0].body);
      expect(
        find.text(
          'Proposal recorded. An independent administrator must review it.',
        ),
        findsOneWidget,
      );
      expect(container.read(cloudflareReconciliationAttemptsProvider), isEmpty);
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'independent administrator approval records an allocation receipt',
    (tester) async {
      final posts = <http.Request>[];
      final container = await pumpReconciliation(tester, (request) async {
        if (request.method == 'POST') {
          posts.add(request);
          return response(reconReceipt(status: 'approved'));
        }
        if (request.url.path.endsWith('/members')) {
          return response(reconPage([reconMember()]));
        }
        if (request.url.path.endsWith(reconTransactionId)) {
          return response(
            reconDetail(
              review: true,
              propose: false,
              proposals: [reconProposal()],
            ),
          );
        }
        return response(reconPage([reconTransaction()]));
      }, role: 'admin');
      container
          .read(cloudflareAdminRouterProvider)
          .go('/admin/reconciliations/$reconTransactionId');
      await tester.pumpAndSettle();
      await visibleTap(tester, find.text('Review'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Approve allocation'),
            )
            .onPressed,
        isNull,
      );
      await visibleTap(
        tester,
        find.text(
          'I independently reviewed this proposal and its recorded payment evidence',
        ),
      );
      await fill(
        tester,
        'Review reason',
        'Independently confirmed recorded identity.',
      );
      await visibleTap(tester, find.text('Approve allocation'));
      expect(
        posts.single.url.path,
        '/api/admin/reconciliations/proposals/$reconProposalId/reviews',
      );
      expect(jsonDecode(posts.single.body)['expected_proposal_version'], 1);
      expect(
        find.text(
          'Approval and allocation recorded. Settlement is not asserted.',
        ),
        findsOneWidget,
      );
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('own proposal has no independent review action', (tester) async {
    final container = await pumpReconciliation(tester, (request) async {
      if (request.url.path.endsWith(reconTransactionId)) {
        return response(
          reconDetail(
            review: true,
            propose: false,
            proposals: [reconProposal(proposer: reconActorId)],
          ),
        );
      }
      return response(reconPage([reconTransaction()]));
    }, role: 'admin');
    container
        .read(cloudflareAdminRouterProvider)
        .go('/admin/reconciliations/$reconTransactionId');
    await tester.pumpAndSettle();
    expect(find.text('Review'), findsNothing);
    final unavailable = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Unavailable'),
    );
    expect(unavailable.onPressed, isNull);
    container.read(cloudflareAdminSessionProvider.notifier).clear();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'related proposals page independently without truncating or replacing transaction facts',
    (tester) async {
      final requests = <http.Request>[];
      Map<String, dynamic> proposal(int index) => {
        ...reconProposal(),
        'id': '77777777-7777-4777-8777-${index.toString().padLeft(12, '0')}',
        'reason': 'Proposal evidence $index',
      };
      final container = await pumpReconciliation(tester, (request) async {
        requests.add(request);
        if (request.url.path.endsWith(reconTransactionId)) {
          final related = request.url.queryParameters['related'];
          if (related != null) {
            return response({
              ...reconDetail(relation: related, propose: false, offset: 25),
              'related': {
                'proposals': reconPage([proposal(26)], total: 26, offset: 25),
              },
            });
          }
          final detail = reconDetail(propose: false);
          (detail['related'] as Map)['proposals'] = reconPage([
            for (var index = 1; index <= 25; index++) proposal(index),
          ], total: 26);
          return response(detail);
        }
        return response(reconPage([reconTransaction()]));
      });
      container
          .read(cloudflareAdminRouterProvider)
          .go('/admin/reconciliations/$reconTransactionId');
      await tester.pumpAndSettle();
      final next = find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.tooltip == 'Next page' &&
            widget.onPressed != null,
      );
      await visibleTap(tester, next);
      expect(find.text('Proposal evidence 26'), findsOneWidget);
      expect(find.text('Showing 26–26 of 26'), findsOneWidget);
      expect(
        requests.any(
          (request) =>
              request.url.queryParameters['related'] == 'proposals' &&
              request.url.queryParameters['offset'] == '25',
        ),
        isTrue,
      );
      expect(find.text('MOMO-123456'), findsWidgets);
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'changed member prevents approval while stale write cannot display a success receipt',
    (tester) async {
      final posts = <http.Request>[];
      final container = await pumpReconciliation(tester, (request) async {
        if (request.method == 'POST') {
          posts.add(request);
          return response({'error': 'state_conflict'}, 409);
        }
        if (request.url.path.endsWith('/members')) {
          return response(
            reconPage([
              {...reconMember(), 'member_version': 2},
            ]),
          );
        }
        if (request.url.path.endsWith(reconTransactionId)) {
          return response(
            reconDetail(
              review: true,
              propose: false,
              proposals: [reconProposal()],
            ),
          );
        }
        return response(reconPage([reconTransaction()]));
      }, role: 'admin');
      container
          .read(cloudflareAdminRouterProvider)
          .go('/admin/reconciliations/$reconTransactionId');
      await tester.pumpAndSettle();
      await visibleTap(tester, find.text('Review'));
      await visibleTap(
        tester,
        find.text(
          'I independently reviewed this proposal and its recorded payment evidence',
        ),
      );
      await fill(tester, 'Review reason', 'Reject changed recorded identity.');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Approve allocation'),
            )
            .onPressed,
        isNull,
      );
      await visibleTap(tester, find.text('Reject proposal'));
      expect(posts, hasLength(1));
      expect(find.text('Refresh changed record'), findsOneWidget);
      expect(
        find.text('Rejection recorded. No allocation was created.'),
        findsNothing,
      );
      expect(find.text('Confirmed operation receipt'), findsNothing);
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
