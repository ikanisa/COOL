import 'package:collect_app/admin/core/cloudflare_admin_operating_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_request_identity.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'cloudflare_canonical_operating_test.dart' as canonical;
import 'cloudflare_canonical_reconciliation_support.dart' show FinancialHarness;
import 'cloudflare_shipping_table_test_support.dart';
import 'cloudflare_operating_repository_test.dart'
    show operatingRepository, operatingResponse;

Finder _historyTable() => find.descendant(
  of: find.byWidgetPredicate(
    (widget) =>
        widget is AdminDataTable && widget.tableLabel == 'Your recent requests',
  ),
  matching: find.byType(DataTable),
);

int _column(DataTable table, String label) =>
    table.columns.indexWhere((column) => (column.label as Text).data == label);

String _cell(WidgetTester tester, DataCell cell) {
  final root = find.byWidget(cell.child);
  final selectable = find.descendant(
    of: root,
    matching: find.byType(SelectableText),
  );
  if (selectable.evaluate().isNotEmpty) {
    return tester.widget<SelectableText>(selectable).data!;
  }
  return tester
      .widget<Text>(find.descendant(of: root, matching: find.byType(Text)))
      .data!;
}

List<String> _references(WidgetTester tester) {
  final table = tester.widget<DataTable>(_historyTable());
  final reference = _column(table, 'Reference');
  expect(reference, greaterThanOrEqualTo(0));
  return [for (final row in table.rows) _cell(tester, row.cells[reference])];
}

Future<void> _sort(WidgetTester tester, String label) async {
  final heading = find.descendant(
    of: _historyTable(),
    matching: find.text(label),
  );
  await tester.ensureVisible(heading);
  await tester.pumpAndSettle();
  await tester.tap(heading);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'canonical request Created headers sort real UTC history across days months and years',
    (tester) async {
      // Canonical history requires normalized .sssZ timestamps and has no
      // completed_at field. Do not bypass that DTO to inject offset strings.
      const dates = <(String, String)>[
        ('request-february', '2026-02-01T00:05:00.000Z'),
        ('request-january-ten', '2026-01-10T00:01:00.000Z'),
        ('request-old-year', '2025-12-31T21:30:00.000Z'),
        ('request-january-last', '2026-01-31T21:45:00.000Z'),
        ('request-january-two', '2026-01-02T00:01:00.000Z'),
        ('request-new-year', '2026-01-01T00:00:00.000Z'),
      ];
      const ascending = [
        'request-old-year',
        'request-new-year',
        'request-january-two',
        'request-january-ten',
        'request-january-last',
        'request-february',
      ];
      final principal =
          (canonical.fixture('session')['user'] as Map)['principalId']
              as String;
      final reads = <http.Request>[];
      const originalKey = 'request-january-two';
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
          if (request.url.path == '/api/admin/operations/requests') {
            return operatingResponse({
              'contract_version': 2,
              'model': 'canonical_evidence_ledger',
              'rows': [
                for (final (key, created) in dates)
                  {
                    'id': canonicalAdminRequestId(principal, key),
                    'idempotency_key': key,
                    'scope': 'groups.post',
                    'status': 'unconfirmed',
                    'receipt': null,
                    'created_at': created,
                  },
              ],
              'total': dates.length,
            });
          }
          expect(
            request.url.path,
            '/api/admin/operations/requests/$originalKey',
          );
          return operatingResponse({
            'contract_version': 2,
            'model': 'canonical_evidence_ledger',
            'status': 'unconfirmed',
            'request_id': canonicalAdminRequestId(principal, originalKey),
            'receipt': null,
          });
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
          const CloudflareOperatingRequestPage(),
          storage: harness.storage,
        );
        expect(_historyTable(), findsOneWidget);
        expect(_references(tester), [for (final date in dates) date.$1]);
        final initial = tester.widget<DataTable>(_historyTable());
        final completed = _column(initial, 'Completed');
        expect([
          for (final row in initial.rows) _cell(tester, row.cells[completed]),
        ], everyElement('—'));
        await _sort(tester, 'Created');
        expect(_references(tester), ascending);
        expect(tester.widget<DataTable>(_historyTable()).sortAscending, isTrue);
        await _sort(tester, 'Created');
        expect(_references(tester), ascending.reversed.toList());
        expect(
          tester.widget<DataTable>(_historyTable()).sortAscending,
          isFalse,
        );
        expect(
          reads,
          hasLength(1),
          reason: 'Local sorting must not fetch or replay an operation.',
        );
        final open = find.byTooltip('Open $originalKey');
        await tester.ensureVisible(open);
        await tester.pumpAndSettle();
        await tester.tap(open);
        await tester.pumpAndSettle();
        expect(reads.map((r) => r.url.path), [
          '/api/admin/operations/requests',
          '/api/admin/operations/requests/$originalKey',
        ]);
        final referenceInput = tester.widget<TextField>(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.labelText == 'Request reference',
          ),
        );
        expect(referenceInput.controller!.text, originalKey);
        expect(find.text('Change saved'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await cleanShippingTables(tester, repo);
      }
    },
  );

  testWidgets(
    'Completed headers order retained offsets and null distinctly from epoch zero',
    (tester) async {
      // The unversioned history parser is the existing seam admitting
      // completed_at; the canonical exact DTO does not expose this field.
      const dates = <(String, Object?)>[
        ('completed-february', '2026-02-01T02:00:00Z'),
        ('completed-january-ten', '2026-01-10T00:01:00Z'),
        ('completed-missing', null),
        ('completed-new-year', '2026-01-01T00:00:00+02:00'),
        ('completed-epoch', 0),
        ('completed-january-last', '2026-01-31T23:30:00-02:00'),
        ('completed-old-year', '2025-12-31T21:30:00Z'),
        ('completed-january-two', '2026-01-02T00:01:00Z'),
      ];
      const ascending = [
        'completed-missing',
        'completed-epoch',
        'completed-old-year',
        'completed-new-year',
        'completed-january-two',
        'completed-january-ten',
        'completed-january-last',
        'completed-february',
      ];
      final reads = <http.Request>[];
      final repo = await operatingRepository((request) async {
        reads.add(request);
        expect(request.method, 'GET');
        expect(request.url.path, '/api/admin/operations/requests');
        return operatingResponse({
          'rows': [
            for (final (index, date) in dates.indexed)
              {
                'id':
                    '60000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}',
                'idempotency_key': date.$1,
                'scope': 'groups.post',
                'status': 'pending',
                'created_at': 1760000000,
                'completed_at': date.$2,
              },
          ],
          'total': dates.length,
        });
      });
      try {
        await pumpShippingTables(
          tester,
          repo,
          const CloudflareOperatingRequestPage(),
        );
        expect(_historyTable(), findsOneWidget);
        expect(_references(tester), [for (final date in dates) date.$1]);
        final initial = tester.widget<DataTable>(_historyTable());
        final completed = _column(initial, 'Completed');
        final values = {
          for (final (index, row) in initial.rows.indexed)
            dates[index].$1: _cell(tester, row.cells[completed]),
        };
        expect(values['completed-missing'], '—');
        expect(values['completed-epoch'], '1 Jan 1970 · 02:00 · Africa/Kigali');
        expect(
          values['completed-new-year'],
          '1 Jan 2026 · 00:00 · Africa/Kigali',
        );
        expect(
          values['completed-january-last'],
          '1 Feb 2026 · 03:30 · Africa/Kigali',
        );
        await _sort(tester, 'Completed');
        expect(_references(tester), ascending);
        expect(tester.widget<DataTable>(_historyTable()).sortAscending, isTrue);
        await _sort(tester, 'Completed');
        expect(_references(tester), ascending.reversed.toList());
        expect(
          tester.widget<DataTable>(_historyTable()).sortAscending,
          isFalse,
        );
        expect(
          reads,
          hasLength(1),
          reason: 'Sorting a retained page remains local and read-only.',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await cleanShippingTables(tester, repo);
      }
    },
  );
}
