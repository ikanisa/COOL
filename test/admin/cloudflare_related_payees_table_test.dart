import 'package:collect_app/admin/core/cloudflare_admin_operating_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'cloudflare_canonical_operating_test.dart' as canonical;
import 'cloudflare_canonical_reconciliation_support.dart' show FinancialHarness;
import 'cloudflare_core_fixtures.dart';
import 'cloudflare_shipping_table_test_support.dart';
import 'cloudflare_operating_repository_test.dart'
    show operatingRepository, operatingResponse, otherId;

Finder _payeesTable() => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is AdminDataTable && widget.tableLabel == 'Payees',
  ),
  matching: find.byType(DataTable),
);

List<String> _headers(DataTable table) => [
  for (final column in table.columns) (column.label as Text).data!,
];

void main() {
  testWidgets(
    'canonical related Payees display the exact title without a legacy label',
    (tester) async {
      final body = canonical.fixture('group');
      final groupId = (body['resource'] as Map)['id'] as String;
      final payee = ((body['related'] as Map)['payees'] as List).single as Map;
      const name = 'Canonical receiver 004200';
      payee['title'] = name;
      expect(payee.containsKey('label'), isFalse);
      final reads = <http.Request>[];
      final auth = canonical.fixture('session');
      auth['expiresAt'] = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 1))
          .toIso8601String();
      final harness = await FinancialHarness.create(
        ownsSession: false,
        auth: auth,
        reply: (request) async {
          reads.add(request);
          expect(request.method, 'GET');
          if (request.url.path ==
              '/api/admin/operations/groups/$groupId/notes') {
            return operatingResponse({
              'contract_version': 1,
              'entity_type': 'collection',
              'entity_id': groupId,
              'rows': [],
              'total': 0,
              'limit': 25,
              'offset': 0,
            });
          }
          expect(request.url.path, '/api/admin/operations/groups/$groupId');
          return operatingResponse(body);
        },
      );
      addTearDown(() {
        if (harness.session.mounted) harness.session.dispose();
      });
      final repo = CloudflareAdminRepository(harness.session);
      try {
        await pumpShippingTables(
          tester,
          repo,
          CloudflareOperatingDetailPage(
            type: 'groups',
            id: groupId,
            backPath: '/admin/groups',
          ),
          storage: harness.storage,
        );
        final tableFinder = _payeesTable();
        expect(tableFinder, findsOneWidget);
        await tester.ensureVisible(tableFinder);
        await tester.pumpAndSettle();
        final table = tester.widget<DataTable>(tableFinder);
        expect(_headers(table), [
          'Actions',
          'Title',
          'Momo Number Or Code',
          'Status',
        ]);
        expect(table.rows, hasLength(1));
        expect(
          find.descendant(of: tableFinder, matching: find.text(name)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: tableFinder, matching: find.text('250788123456')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: tableFinder, matching: find.text('Active')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: tableFinder, matching: find.text('Label')),
          findsNothing,
        );
        expect(
          find.descendant(of: tableFinder, matching: find.text('Open record')),
          findsOneWidget,
        );
        expect(
          reads.where(
            (r) => r.url.path == '/api/admin/operations/groups/$groupId',
          ),
          hasLength(1),
        );
        expect(reads.every((r) => r.method == 'GET'), isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await cleanShippingTables(tester, repo);
      }
    },
  );

  testWidgets(
    'unversioned related Payees retain the exact legacy label without a title',
    (tester) async {
      const name = 'Legacy receiver 004200';
      final reads = <http.Request>[];
      final repo = await operatingRepository((request) async {
        reads.add(request);
        expect(request.method, 'GET');
        expect(request.url.path, '/api/admin/operations/groups/$coreId');
        return operatingResponse({
          'resource_type': 'groups',
          'resource': {
            'id': coreId,
            'version': 1,
            'title': 'Retained fixture group',
            'status': 'active',
          },
          'current_actor_id': coreId,
          'can_manage': false,
          'related': {
            'payees': [
              {
                'id': otherId,
                'label': name,
                'momo_number_or_code': '004200',
                'status': 'active',
              },
            ],
          },
          'related_truncated': false,
        });
      });
      try {
        await pumpShippingTables(
          tester,
          repo,
          const CloudflareOperatingDetailPage(
            type: 'groups',
            id: coreId,
            backPath: '/admin/groups',
          ),
        );
        final tableFinder = _payeesTable();
        expect(tableFinder, findsOneWidget);
        await tester.ensureVisible(tableFinder);
        await tester.pumpAndSettle();
        final table = tester.widget<DataTable>(tableFinder);
        expect(_headers(table), [
          'Actions',
          'Label',
          'Momo Number Or Code',
          'Status',
        ]);
        expect(table.rows, hasLength(1));
        expect(
          find.descendant(of: tableFinder, matching: find.text(name)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: tableFinder, matching: find.text('004200')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: tableFinder, matching: find.text('Active')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: tableFinder, matching: find.text('Title')),
          findsNothing,
        );
        expect(
          find.descendant(of: tableFinder, matching: find.text('Open record')),
          findsOneWidget,
        );
        expect(reads, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        await cleanShippingTables(tester, repo);
      }
    },
  );
}
