import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/cloudflare_admin_app.dart';
import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:collect_app/admin/shared/components/admin_page.dart';
import 'package:collect_app/main_admin_cloudflare.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cloudflare_core_fixtures.dart';
import '../support/legacy_backend_fixture.dart';

Map<String, dynamic> _fixture(String key) => Map<String, dynamic>.from(
  (jsonDecode(File('test/admin/admin-dto-examples.json').readAsStringSync())
          as Map)[key]
      as Map,
);

Map<String, dynamic> _ledgerRow(String key) =>
    Map<String, dynamic>.from((_fixture(key)['rows'] as List).single as Map);

// The resource bytes are retained actual Worker list rows. The detail envelope
// is source-derived from API18 admin_records.js, not a captured detail response.
Map<String, dynamic> _canonicalDetail(String key) => {
  'contract_version': 2,
  'model': 'canonical_evidence_ledger',
  'resource_type': 'ledgers',
  'resource': _ledgerRow(key),
  'current_actor_id': coreId,
  'can_manage': false,
  'allowed_operations': <String>[],
  'related': <String, dynamic>{},
  'related_pages': <String, dynamic>{},
  'related_truncated': false,
};

Map<String, dynamic> _legacyDetail() => {
  'resource_type': 'journals',
  'resource': {
    'id': coreId,
    'version': 2,
    'description': 'Legacy journal',
    'status': 'posted',
    'group_id': coreId,
  },
  'current_actor_id': coreId,
  'can_manage': false,
  'related': {'entries': <Object>[]},
  'related_truncated': false,
};

class _LedgerWorkspace {
  _LedgerWorkspace({
    this.canonical = true,
    this.ledgerKey = 'ledgers',
    this.permissions = const ['overview.read', 'ledger.read', 'ledger.manage'],
    Map<String, dynamic>? detail,
    Future<http.Response> Function(http.Request)? detailRead,
  }) {
    session = CloudflareAdminSession(
      MockClient((request) async {
        http.Response json(Object value) => http.Response.bytes(
          utf8.encode(jsonEncode(value)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
        if (request.url.path == '/api/admin/auth/session') {
          final data = coreSession(permissions: permissions);
          (data['user'] as Map)['financialModel'] = canonical
              ? 'canonical_evidence_ledger'
              : 'transaction_journals';
          return json(data);
        }
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path == '/api/admin/core/overview') {
          return json(canonical ? _fixture('overview') : coreOverview());
        }
        if (request.url.path == '/api/admin/core/ledgers') {
          return json(
            canonical
                ? _fixture(ledgerKey)
                : {
                    'rows': [coreRow(CloudflareCoreArea.ledgers)],
                    'total': 1,
                  },
          );
        }
        if (request.url.path == '/api/admin/sync') {
          return json({
            'contract_version': 1,
            'events': [],
            'cursor': request.url.queryParameters['cursor'],
          });
        }
        final expected = canonical
            ? '/api/admin/operations/ledgers/$id'
            : '/api/admin/operations/journals/$id';
        if (request.method == 'GET' && request.url.path == expected) {
          expect(request.url.queryParameters, isEmpty);
          if (detailRead != null) return detailRead(request);
          return json(
            detail ??
                (canonical ? _canonicalDetail(ledgerKey) : _legacyDetail()),
          );
        }
        throw StateError(
          'Unexpected transport ${request.method} ${request.url.path}',
        );
      }),
      origin: Uri.parse('https://admin.example.test/'),
      environment: legacyBackendFixtureEnvironment,
    );
  }

  final bool canonical;
  final String ledgerKey;
  List<String> permissions;
  late final CloudflareAdminSession session;
  final requests = <String>[];
  String get id => canonical ? _ledgerRow(ledgerKey)['id'] as String : coreId;
  CloudflareAdminRepository get repository =>
      CloudflareAdminRepository(session);
}

Future<void> _withApp(
  WidgetTester tester,
  _LedgerWorkspace fixture,
  Future<void> Function(ProviderContainer) exercise,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 1000);
  tester.binding.platformDispatcher.defaultRouteNameTestValue = '/admin';
  final container = ProviderContainer(
    overrides: [
      ...cloudflareAdminOverrides(),
      cloudflareAdminSessionProvider.overrideWith((_) => fixture.session),
      adminPendingAttemptStorageProvider.overrideWithValue(
        MemoryAdminPendingAttemptStorage(),
      ),
    ],
  );
  try {
    await tester.runAsync(fixture.session.refresh);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CloudflareAdminApp(),
      ),
    );
    await tester.pumpAndSettle();
    await exercise(container);
    expect(tester.takeException(), isNull);
  } finally {
    fixture.session.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    container.dispose();
    tester.binding.platformDispatcher.clearDefaultRouteNameTestValue();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  for (final key in ['ledgers', 'reversal_ledger']) {
    test(
      '$key detail preserves exact evidence facts without journal authority',
      () async {
        final fixture = _LedgerWorkspace(ledgerKey: key);
        addTearDown(fixture.session.dispose);
        await fixture.session.refresh();
        final detail = await fixture.repository.operatingDetail(
          'ledgers',
          fixture.id,
        );
        expect(fixture.requests, [
          'GET /api/admin/operations/ledgers/${fixture.id}',
        ]);
        expect(detail.type, 'ledgers');
        expect(detail.resource, _ledgerRow(key));
        expect(detail.sourceModel, 'canonical_evidence_ledger');
        expect(detail.version, isNull);
        expect(detail.canManage, isFalse);
        expect(detail.allowedOperations, isEmpty);
        expect(detail.allows(CloudflareOperation.postJournal), isFalse);
        expect(detail.related, isEmpty);
        expect(detail.relatedPages, isEmpty);
        expect(detail.truncated, isFalse);
        expect(() => detail.resource['version'] = 1, throwsUnsupportedError);
      },
    );
  }

  test(
    'canonical detail rejects advertised writes, relations and journal facts',
    () async {
      final invalid = <Map<String, dynamic>>[
        {..._canonicalDetail('ledgers'), 'can_manage': true},
        {
          ..._canonicalDetail('ledgers'),
          'allowed_operations': ['postJournal'],
        },
        {
          ..._canonicalDetail('ledgers'),
          'related': {'entries': <Object>[]},
          'related_pages': {
            'entries': {
              'total': 0,
              'limit': 25,
              'offset': 0,
              'next_offset': null,
            },
          },
        },
        {
          ..._canonicalDetail('ledgers'),
          'resource': {..._ledgerRow('ledgers'), 'balanced': true},
        },
        {
          ..._canonicalDetail('ledgers'),
          'resource': {..._ledgerRow('ledgers'), 'provider_confirmation': true},
        },
        {
          ..._canonicalDetail('ledgers'),
          'resource': {..._ledgerRow('ledgers'), 'signed_amount_rwf': -1000},
        },
        {..._canonicalDetail('ledgers'), 'resource_type': 'journals'},
        {
          ..._canonicalDetail('ledgers'),
          'current_actor_id': _ledgerRow('ledgers')['id'],
        },
        {..._legacyDetail(), 'resource_type': 'ledgers'},
      ];
      for (final body in invalid) {
        final fixture = _LedgerWorkspace(detail: body);
        addTearDown(fixture.session.dispose);
        await fixture.session.refresh();
        await expectLater(
          fixture.repository.operatingDetail('ledgers', fixture.id),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'ledger permission, model and no-relation restrictions precede transport',
    () async {
      final missing = _LedgerWorkspace(permissions: const ['overview.read']);
      final legacy = _LedgerWorkspace(canonical: false);
      final canonical = _LedgerWorkspace();
      for (final fixture in [missing, legacy, canonical]) {
        addTearDown(fixture.session.dispose);
        await fixture.session.refresh();
      }
      await expectLater(
        missing.repository.operatingDetail('ledgers', missing.id),
        throwsA(isA<AdminAccountException>()),
      );
      await expectLater(
        legacy.repository.operatingDetail('ledgers', legacy.id),
        throwsFormatException,
      );
      await expectLater(
        canonical.repository.operatingDetail(
          'ledgers',
          canonical.id,
          relation: 'entries',
        ),
        throwsFormatException,
      );
      expect([
        ...missing.requests,
        ...legacy.requests,
        ...canonical.requests,
      ], isEmpty);
      expect(CloudflareCoreArea.ledgers.nativeResource, 'journals');
      expect(
        CloudflareCoreArea.ledgers.createOperation,
        CloudflareOperation.createJournal,
      );
    },
  );

  test('a late ledger completion cannot cross a permission refresh', () async {
    final pending = Completer<http.Response>();
    final fixture = _LedgerWorkspace(detailRead: (_) => pending.future);
    addTearDown(fixture.session.dispose);
    await fixture.session.refresh();
    final future = fixture.repository.operatingDetail('ledgers', fixture.id);
    final assertion = expectLater(
      future,
      throwsA(isA<AdminAccountException>()),
    );
    fixture.permissions = const ['overview.read'];
    await fixture.session.refresh();
    pending.complete(
      http.Response(jsonEncode(_canonicalDetail('ledgers')), 200),
    );
    await assertion;
    expect(fixture.requests, [
      'GET /api/admin/operations/ledgers/${fixture.id}',
    ]);
  });

  for (final canonical in [true, false]) {
    testWidgets(
      '${canonical ? 'canonical evidence' : 'legacy journal'} ledger row Open uses the correct detail route',
      (tester) async {
        final fixture = _LedgerWorkspace(canonical: canonical);
        await _withApp(tester, fixture, (container) async {
          final router = container.read(cloudflareAdminRouterProvider);
          router.go('/admin/ledgers');
          await tester.pumpAndSettle();
          final title = canonical
              ? _ledgerRow('ledgers')['title']
              : 'Example record';
          final open = find.byTooltip('Open $title');
          expect(open, findsOneWidget);
          if (canonical) {
            expect(find.text('Journal posting unavailable'), findsOneWidget);
          } else {
            expect(find.text('Create journal draft'), findsOneWidget);
          }
          await tester.ensureVisible(open);
          await tester.tap(open);
          await tester.pumpAndSettle();
          expect(
            router.routeInformationProvider.value.uri.path,
            '/admin/ledgers/${fixture.id}',
          );
          final expected = canonical ? 'ledgers' : 'journals';
          expect(
            fixture.requests.where((path) => path.contains('/operations/')),
            ['GET /api/admin/operations/$expected/${fixture.id}'],
          );
          final tables = tester.widgetList<AdminDataTable>(
            find.byType(AdminDataTable),
          );
          final facts = tables.singleWhere(
            (table) => table.tableLabel == 'Record details',
          );
          final columns = facts.columns!.map((column) => column.label).toList();
          if (canonical) {
            expect(
              find.text('Evidence ledger entry · Read-only'),
              findsOneWidget,
            );
            expect(
              find.text('Team access record · Managed in Admins and staff'),
              findsNothing,
            );
            expect(
              columns,
              containsAll([
                'Kind',
                'Signed Amount Rwf',
                'Payment Id',
                'Evidence Id',
                'Provider Confirmation',
                'Settlement Status',
                'Record ID',
              ]),
            );
            expect(facts.rows.single.extra, _ledgerRow('ledgers'));
            expect(columns, isNot(contains('Debit Rwf')));
            expect(columns, isNot(contains('Credit Rwf')));
            expect(find.text('Post journal'), findsNothing);
            expect(find.text('Replace journal draft'), findsNothing);
          } else {
            expect(
              tester.widget<AdminPage>(find.byType(AdminPage)).title,
              'Legacy journal',
            );
            expect(find.text('Version 2'), findsOneWidget);
            expect(columns, contains('Description'));
            expect(columns, isNot(contains('Signed Amount Rwf')));
          }
          expect(
            fixture.requests.every((path) => path.startsWith('GET ')),
            isTrue,
          );
        });
      },
    );
  }
}
