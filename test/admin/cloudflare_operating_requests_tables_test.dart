import 'dart:async';

import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/cloudflare_admin_operating_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import 'cloudflare_core_fixtures.dart';
import 'cloudflare_operating_repository_test.dart'
    show
        operatingRepository,
        operatingResponse,
        operatingReceipt,
        otherId,
        requestKey,
        requestSmsFactsReceipt,
        requestReconciliationReceipt,
        smsFactsId;
import 'cloudflare_reconciliation_fixtures.dart';

Future<GoRouter> _pump(
  WidgetTester tester,
  Widget view, {
  CloudflareAdminRepository? repository,
}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      if (repository != null) ...[
        adminRepositoryProvider.overrideWithValue(repository),
        cloudflareAdminSessionProvider.overrideWith(
          (ref) => repository.session,
        ),
      ],
    ],
  );
  final router = GoRouter(
    initialLocation: '/admin/requests',
    routes: [
      GoRoute(
        path: '/admin/requests',
        builder: (_, _) => Scaffold(body: view),
      ),
      GoRoute(
        path: '/admin/groups/$coreId',
        builder: (_, _) =>
            const Scaffold(body: Text('Saved group destination')),
      ),
      GoRoute(
        path: '/admin/email',
        builder: (_, _) =>
            const Scaffold(body: Text('Email events destination')),
      ),
      GoRoute(
        path: '/admin/sms-receipts/:kind/:id',
        builder: (_, route) => Scaffold(
          body: Text(
            'SMS source ${route.pathParameters['kind']} ${route.pathParameters['id']}',
          ),
        ),
      ),
      GoRoute(
        path: '/admin/reconciliations/:id',
        builder: (_, route) => Scaffold(
          body: Text(
            'Transaction reconciliation ${route.pathParameters['id']}',
          ),
        ),
      ),
      GoRoute(path: '/admin', builder: (_, _) => const SizedBox.shrink()),
    ],
  );
  addTearDown(() async {
    repository?.session.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    router.dispose();
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Finder _table(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is AdminDataTable && widget.tableLabel == label,
  ),
  matching: find.byType(DataTable),
);

Future<void> _clean(
  WidgetTester tester, [
  CloudflareAdminRepository? repository,
]) async {
  repository?.session.clear();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

List<String> _headers(DataTable table) => [
  for (final column in table.columns) (column.label as Text).data!,
];

Map<String, dynamic> _requestRow({
  String key = requestKey,
  String status = 'succeeded',
}) => {
  'id': otherId,
  'idempotency_key': key,
  'scope': 'groups.post',
  'status': status,
  'created_at': 1760000000,
  if (status == 'succeeded') 'receipt': operatingReceipt(version: 7),
};

void main() {
  testWidgets(
    'a pending lookup keeps its reference until completion before another row can open',
    (tester) async {
      const secondKey = 'another-request-reference';
      const secondRequestId = '44444444-4444-4444-8444-444444444444';
      final firstResponse = Completer<http.Response>();
      final secondResponse = Completer<http.Response>();
      final lookups = <String>[];
      final repository = await operatingRepository((request) async {
        expect(request.method, 'GET');
        if (request.url.path == '/api/admin/operations/requests') {
          return operatingResponse({
            'rows': [
              _requestRow(status: 'pending'),
              {
                ..._requestRow(key: secondKey, status: 'pending'),
                'id': secondRequestId,
                'scope': 'payees.patch',
              },
            ],
            'total': 2,
          });
        }
        lookups.add(request.url.path);
        return request.url.path.endsWith('/$requestKey')
            ? firstResponse.future
            : secondResponse.future;
      });
      await _pump(
        tester,
        const CloudflareOperatingRequestPage(),
        repository: repository,
      );
      await tester.tap(find.text('groups.post'));
      await tester.pump();
      expect(find.text('Checking…'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is TextField &&
                    widget.decoration?.labelText == 'Request reference',
              ),
            )
            .enabled,
        isFalse,
      );
      await tester.tap(find.text('payees.patch'));
      await tester.pump();
      expect(lookups, ['/api/admin/operations/requests/$requestKey']);
      expect(
        tester
            .widget<TextField>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is TextField &&
                    widget.decoration?.labelText == 'Request reference',
              ),
            )
            .controller!
            .text,
        requestKey,
      );
      expect(find.text('Change saved'), findsNothing);
      firstResponse.complete(
        operatingResponse({
          'status': 'succeeded',
          'request_id': otherId,
          'receipt': operatingReceipt(version: 7),
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Change saved'), findsOneWidget);
      var table = tester.widget<AdminDataTable>(
        find.byWidgetPredicate(
          (widget) =>
              widget is AdminDataTable &&
              widget.tableLabel == 'Saved change receipt',
        ),
      );
      expect(table.rows.single.extra['request_id'], otherId);
      expect(table.rows.single.extra['resource_id'], coreId);
      expect(
        tester
            .widget<TextField>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is TextField &&
                    widget.decoration?.labelText == 'Request reference',
              ),
            )
            .controller!
            .text,
        requestKey,
      );
      await tester.ensureVisible(find.text('payees.patch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('payees.patch'));
      await tester.pump();
      expect(lookups, [
        '/api/admin/operations/requests/$requestKey',
        '/api/admin/operations/requests/$secondKey',
      ]);
      expect(find.text('Change saved'), findsNothing);
      expect(
        tester
            .widget<TextField>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is TextField &&
                    widget.decoration?.labelText == 'Request reference',
              ),
            )
            .controller!
            .text,
        secondKey,
      );
      secondResponse.complete(
        operatingResponse({
          'status': 'succeeded',
          'request_id': secondRequestId,
          'receipt': {
            ...operatingReceipt(id: otherId, version: 8),
            'request_id': secondRequestId,
          },
        }),
      );
      await tester.pumpAndSettle();
      table = tester.widget<AdminDataTable>(
        find.byWidgetPredicate(
          (widget) =>
              widget is AdminDataTable &&
              widget.tableLabel == 'Saved change receipt',
        ),
      );
      expect(table.rows.single.extra['request_id'], secondRequestId);
      expect(table.rows.single.extra['resource_id'], otherId);
      expect(table.rows.single.extra['version'], 8);
      expect(
        tester
            .widget<TextField>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is TextField &&
                    widget.decoration?.labelText == 'Request reference',
              ),
            )
            .controller!
            .text,
        secondKey,
      );
      expect(
        tester
            .widget<TextField>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is TextField &&
                    widget.decoration?.labelText == 'Request reference',
              ),
            )
            .enabled,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await _clean(tester, repository);
    },
  );

  testWidgets(
    'recent request facts use dedicated columns and row body checks its exact reference',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final lookups = <String>[];
      final repository = await operatingRepository((request) async {
        expect(request.method, 'GET');
        if (request.url.path == '/api/admin/operations/requests') {
          return operatingResponse({
            'rows': [_requestRow()],
            'total': 1,
          });
        }
        lookups.add(request.url.path);
        return operatingResponse({
          'status': 'succeeded',
          'request_id': otherId,
          'receipt': operatingReceipt(version: 7),
        });
      });
      await _pump(
        tester,
        const CloudflareOperatingRequestPage(),
        repository: repository,
      );
      final history = _table('Your recent requests');
      expect(_headers(tester.widget<DataTable>(history)), [
        'Request scope',
        'Status',
        'Created',
        'Reference',
        'Request ID',
        'Completed',
        'Resource',
        'Record ID',
        'Version',
        'Source kind',
        'Source ID',
        'Parser version',
        'Proposal status',
        'Transaction ID',
        'Review ID',
        'Allocation ID',
        'Transaction version',
        'Open',
      ]);
      expect(find.byType(ListTile), findsNothing);
      expect(
        find.bySemanticsLabel('Your recent requests table, 1 rows'),
        findsOneWidget,
      );
      expect(find.text('Succeeded'), findsOneWidget);
      await tester.ensureVisible(find.text(requestKey));
      expect(find.bySemanticsLabel('Reference: $requestKey'), findsOneWidget);
      await tester.ensureVisible(find.text('groups.post'));
      await tester.tap(find.text('groups.post'));
      await tester.pumpAndSettle();
      expect(lookups, ['/api/admin/operations/requests/$requestKey']);
      expect(
        tester
            .widget<TextField>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is TextField &&
                    widget.decoration?.labelText == 'Request reference',
              ),
            )
            .controller!
            .text,
        requestKey,
      );
      expect(find.text('Change saved'), findsOneWidget);
      final receipt = tester.widget<DataTable>(_table('Saved change receipt'));
      expect(_headers(receipt), [
        'Resource',
        'Record ID',
        'Request',
        'Version',
      ]);
      expect((receipt.rows.single.cells[3].child as Text).data, '7');
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await _clean(tester, repository);
    },
  );

  for (final kind in const ['member', 'receiver']) {
    testWidgets(
      '$kind SMS history opens its exact source receipt through a read-only lookup',
      (tester) async {
        final requests = <http.Request>[];
        final smsReceipt = requestSmsFactsReceipt(kind: kind);
        const normalId = '44444444-4444-4444-8444-444444444444';
        final repository = await operatingRepository((request) async {
          requests.add(request);
          expect(request.method, 'GET');
          if (request.url.path == '/api/admin/operations/requests') {
            return operatingResponse({
              'rows': [
                {
                  ..._requestRow(),
                  'scope': 'sms.extract',
                  'completed_at': 1760000001,
                  'receipt': smsReceipt,
                },
                {
                  ..._requestRow(key: 'normal-request-reference'),
                  'id': normalId,
                  'receipt': {
                    ...operatingReceipt(version: 7),
                    'request_id': normalId,
                  },
                },
              ],
              'total': 2,
            });
          }
          expect(
            request.url.path,
            '/api/admin/operations/requests/$requestKey',
          );
          return operatingResponse({
            'status': 'succeeded',
            'request_id': otherId,
            'receipt': smsReceipt,
          });
        });
        final router = await _pump(
          tester,
          const CloudflareOperatingRequestPage(),
          repository: repository,
        );
        final history = tester.widget<AdminDataTable>(
          find.byWidgetPredicate(
            (widget) =>
                widget is AdminDataTable &&
                widget.tableLabel == 'Your recent requests',
          ),
        );
        final sourceRow = history.rows.first;
        final normalRow = history.rows.last;
        String value(AdminTableRowData row, String label) => history.columns!
            .singleWhere((column) => column.label == label)
            .value(row);
        expect(value(sourceRow, 'Request ID'), otherId);
        expect(value(sourceRow, 'Resource'), 'SMS facts');
        expect(value(sourceRow, 'Record ID'), smsFactsId);
        expect(value(sourceRow, 'Version'), '—');
        expect(
          value(sourceRow, 'Source kind'),
          kind == 'member' ? 'Member' : 'Receiver',
        );
        expect(value(sourceRow, 'Source ID'), coreId);
        expect(
          value(sourceRow, 'Parser version'),
          smsReceipt['parser_version'],
        );
        expect(value(normalRow, 'Version'), '7');
        expect(value(normalRow, 'Source kind'), '—');
        expect(value(normalRow, 'Source ID'), '—');
        expect(value(normalRow, 'Parser version'), '—');
        await tester.tap(find.text('sms.extract'));
        await tester.pumpAndSettle();
        final table = tester.widget<DataTable>(
          _table('SMS extraction receipt'),
        );
        expect(_headers(table), [
          'Resource',
          'Facts ID',
          'Source kind',
          'Source ID',
          'Parser version',
          'Request',
        ]);
        expect(find.text('SMS facts recorded'), findsOneWidget);
        expect(find.text('Change saved'), findsNothing);
        expect(
          find.text(
            'The server recorded facts extracted from the preserved SMS source. This receipt does not confirm a payment or provider settlement.',
          ),
          findsOneWidget,
        );
        // A matched receipt refreshes recent history using reads only.
        expect(
          requests.map((request) => '${request.method} ${request.url.path}'),
          [
            'GET /api/admin/operations/requests',
            'GET /api/admin/operations/requests/$requestKey',
            'GET /api/admin/operations/requests',
          ],
        );
        expect(
          tester
              .widget<TextField>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is TextField &&
                      widget.decoration?.labelText == 'Request reference',
                ),
              )
              .controller!
              .text,
          requestKey,
        );
        await tester.ensureVisible(find.text('Open SMS source'));
        await tester.tap(find.text('Open SMS source'));
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/admin/sms-receipts/$kind/$coreId',
        );
        expect(find.text('SMS source $kind $coreId'), findsOneWidget);
        expect(requests.every((request) => request.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
        await _clean(tester, repository);
      },
    );
  }

  for (final status in const ['pending', 'approved', 'rejected']) {
    testWidgets(
      '$status reconciliation history preserves mixed receipts and opens its authorized transaction',
      (tester) async {
        final receipt = requestReconciliationReceipt(status: status);
        const smsId = '44444444-4444-4444-8444-444444444444';
        const genericId = '66666666-6666-4666-8666-666666666666';
        final scope = status == 'pending'
            ? 'reconciliations.propose'
            : 'reconciliations.review';
        final requests = <http.Request>[];
        final repository = await operatingRepository((request) async {
          requests.add(request);
          expect(request.method, 'GET');
          if (request.url.path == '/api/admin/operations/requests') {
            return operatingResponse({
              'rows': [
                {
                  ..._requestRow(),
                  'scope': scope,
                  'completed_at': 1760000001,
                  'receipt': receipt,
                },
                {
                  ..._requestRow(key: 'sms-request-reference'),
                  'id': smsId,
                  'scope': 'sms.extract',
                  'receipt': requestSmsFactsReceipt(requestId: smsId),
                },
                {
                  ..._requestRow(key: 'generic-request-reference'),
                  'id': genericId,
                  'receipt': {
                    ...operatingReceipt(version: 7),
                    'request_id': genericId,
                  },
                },
              ],
              'total': 3,
            });
          }
          expect(
            request.url.path,
            '/api/admin/operations/requests/$requestKey',
          );
          return operatingResponse({
            'status': 'succeeded',
            'request_id': otherId,
            'receipt': receipt,
          });
        }, additionalPermissions: ['reconciliations.read']);
        final router = await _pump(
          tester,
          const CloudflareOperatingRequestPage(),
          repository: repository,
        );
        final history = tester.widget<AdminDataTable>(
          find.byWidgetPredicate(
            (widget) =>
                widget is AdminDataTable &&
                widget.tableLabel == 'Your recent requests',
          ),
        );
        expect(history.rows, hasLength(3));
        String value(AdminTableRowData row, String label) => history.columns!
            .firstWhere((column) => column.label == label)
            .value(row);
        final row = history.rows.first;
        expect(value(row, 'Resource'), 'Reconciliation proposal');
        expect(value(row, 'Record ID'), reconProposalId);
        expect(value(row, 'Version'), status == 'pending' ? '1' : '2');
        expect(
          value(row, 'Proposal status'),
          status == 'pending'
              ? 'Pending'
              : status == 'approved'
              ? 'Approved'
              : 'Rejected',
        );
        expect(value(row, 'Transaction ID'), reconTransactionId);
        expect(
          value(row, 'Review ID'),
          status == 'pending' ? '—' : reconReviewId,
        );
        expect(
          value(row, 'Allocation ID'),
          status == 'approved' ? reconAllocationId : '—',
        );
        expect(
          value(row, 'Transaction version'),
          status == 'pending'
              ? '—'
              : status == 'approved'
              ? '3'
              : '2',
        );
        expect(value(history.rows[1], 'Resource'), 'SMS facts');
        expect(value(history.rows[2], 'Resource'), 'Groups');
        expect(value(history.rows[2], 'Proposal status'), '—');
        await tester.tap(find.text(scope));
        await tester.pumpAndSettle();
        expect(find.text('Reconciliation request recorded'), findsOneWidget);
        expect(find.text('Change saved'), findsNothing);
        final saved = tester.widget<DataTable>(
          _table('Reconciliation request receipt'),
        );
        expect(_headers(saved), [
          'Request',
          'Proposal ID',
          'Proposal status',
          'Transaction ID',
          'Version',
          'Review ID',
          'Allocation ID',
          'Transaction version',
          'Settlement status',
        ]);
        expect(
          find.text(
            'The server recorded this proposal or review. This receipt does not confirm provider settlement or ledger posting.',
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.text('Open transaction reconciliation'),
        );
        await tester.tap(find.text('Open transaction reconciliation'));
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/admin/reconciliations/$reconTransactionId',
        );
        expect(
          find.text('Transaction reconciliation $reconTransactionId'),
          findsOneWidget,
        );
        // A matched receipt refreshes recent history using reads only.
        expect(
          requests.map((request) => '${request.method} ${request.url.path}'),
          [
            'GET /api/admin/operations/requests',
            'GET /api/admin/operations/requests/$requestKey',
            'GET /api/admin/operations/requests',
          ],
        );
        expect(requests.every((request) => request.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
        await _clean(tester, repository);
      },
    );
  }
  testWidgets(
    'a request reader without reconciliation access sees its receipt but no detail action',
    (tester) async {
      final receipt = requestReconciliationReceipt(status: 'approved');
      final repository = await operatingRepository(
        (request) async => operatingResponse(
          request.url.path == '/api/admin/operations/requests'
              ? {
                  'rows': [
                    {
                      ..._requestRow(),
                      'scope': 'reconciliations.review',
                      'receipt': receipt,
                    },
                  ],
                  'total': 1,
                }
              : {
                  'status': 'succeeded',
                  'request_id': otherId,
                  'receipt': receipt,
                },
        ),
      );
      await _pump(
        tester,
        const CloudflareOperatingRequestPage(),
        repository: repository,
      );
      await tester.tap(find.text('reconciliations.review'));
      await tester.pumpAndSettle();
      expect(find.text('Reconciliation request recorded'), findsOneWidget);
      expect(_table('Reconciliation request receipt'), findsOneWidget);
      expect(find.text('Open transaction reconciliation'), findsNothing);
      expect(tester.takeException(), isNull);
      await _clean(tester, repository);
    },
  );
  testWidgets(
    'keyboard Open checks the selected reference without another write',
    (tester) async {
      var lookups = 0;
      final repository = await operatingRepository((request) async {
        expect(request.method, 'GET');
        if (request.url.path == '/api/admin/operations/requests') {
          return operatingResponse({
            'rows': [_requestRow(status: 'pending')],
            'total': 1,
          });
        }
        expect(request.url.path, '/api/admin/operations/requests/$requestKey');
        lookups++;
        return operatingResponse({'status': 'pending'});
      });
      await _pump(
        tester,
        const CloudflareOperatingRequestPage(),
        repository: repository,
      );
      await tester.ensureVisible(find.byTooltip('Open $requestKey'));
      var openFocused = false;
      // The expanded history retains focusable, selectable receipt IDs. Allow
      // traversal through those cells while still requiring Tab and Enter.
      for (var step = 0; step < 40; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final button = FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<IconButton>();
        if (button?.tooltip == 'Open $requestKey') {
          openFocused = true;
          break;
        }
      }
      expect(
        openFocused,
        isTrue,
        reason: 'Open must be reachable through Tab.',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(lookups, 1);
      expect(
        find.text(
          'This request is still pending. Check again before continuing.',
        ),
        findsOneWidget,
      );
      expect(find.text('Change saved'), findsNothing);
      expect(tester.takeException(), isNull);
      await _clean(tester, repository);
    },
  );

  testWidgets(
    'saved receipt facts are selectable and navigation opens the confirmed record',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final router = await _pump(
        tester,
        SingleChildScrollView(
          child: CloudflareReceiptView(
            receipt: CloudflareOperationReceipt.parse(
              operatingReceipt(version: 7),
            ),
          ),
        ),
      );
      final receipt = tester.widget<DataTable>(_table('Saved change receipt'));
      expect(receipt.rows, hasLength(1));
      expect(_headers(receipt), [
        'Resource',
        'Record ID',
        'Request',
        'Version',
      ]);
      expect(
        find.bySemanticsLabel('Saved change receipt table, 1 rows'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Record ID: $coreId'), findsOneWidget);
      expect(find.bySemanticsLabel('Request: $otherId'), findsOneWidget);
      expect(find.text('Groups'), findsOneWidget);
      expect(find.textContaining('Receipt:'), findsNothing);
      await tester.tap(find.text('Open saved record'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/admin/groups/$coreId',
      );
      expect(find.text('Saved group destination'), findsOneWidget);
      semantics.dispose();
      await _clean(tester);
    },
  );

  testWidgets(
    'email receipt counts stay separate from provider delivery guidance',
    (tester) async {
      final receipt = CloudflareOperationReceipt.parse({
        ...operatingReceipt(type: 'email_dispatch', id: otherId),
        'accepted': 1,
        'uncertain': 2,
        'suppressed': 3,
      });
      final router = await _pump(
        tester,
        SingleChildScrollView(child: CloudflareReceiptView(receipt: receipt)),
      );
      final table = tester.widget<DataTable>(_table('Email batch receipt'));
      expect(_headers(table), [
        'Resource',
        'Record ID',
        'Request',
        'Version',
        'Provider accepted',
        'Uncertain',
        'Suppressed',
      ]);
      expect(table.columns.skip(3).every((column) => column.numeric), isTrue);
      expect(
        [
          for (final cell in table.rows.single.cells.skip(3))
            (cell.child as Text).data,
        ],
        ['1', '1', '2', '3'],
      );
      expect(
        find.text(
          'Provider acceptance does not confirm inbox delivery. Uncertain messages are not retried automatically.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Provider accepted:'), findsNothing);
      await tester.tap(find.text('View email events'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/admin/email');
      expect(find.text('Email events destination'), findsOneWidget);
      await _clean(tester);
    },
  );

  testWidgets(
    'request table pagination uses server ranges and retains per-row references',
    (tester) async {
      final offsets = <int>[];
      final repository = await operatingRepository((request) async {
        expect(request.url.path, '/api/admin/operations/requests');
        expect(request.url.queryParameters['limit'], '25');
        final offset = int.parse(request.url.queryParameters['offset']!);
        offsets.add(offset);
        return operatingResponse({
          'rows': [
            for (var index = offset; index < (offset == 0 ? 25 : 26); index++)
              _requestRow(key: 'page-reference-$index', status: 'pending'),
          ],
          'total': 26,
        });
      });
      await _pump(
        tester,
        const CloudflareOperatingRequestPage(),
        repository: repository,
      );
      expect(
        tester.widget<DataTable>(_table('Your recent requests')).rows,
        hasLength(25),
      );
      expect(find.text('1–25 of 26'), findsOneWidget);
      await tester.ensureVisible(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DataTable>(_table('Your recent requests')).rows,
        hasLength(1),
      );
      expect(find.text('26–26 of 26'), findsOneWidget);
      expect(find.text('page-reference-25'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Next'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Previous'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Previous'));
      await tester.pumpAndSettle();
      expect(offsets, [0, 25, 0]);
      expect(find.text('1–25 of 26'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _clean(tester, repository);
    },
  );
}
