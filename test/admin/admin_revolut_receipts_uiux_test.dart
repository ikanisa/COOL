import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/core/admin_receipt_presentation.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:collect_app/admin/shared/components/admin_empty_state.dart';
import 'package:collect_app/admin/shared/components/admin_record_facts_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _recordOne = AdminTableRowData(
  id: 'receipt-one',
  title: 'Receipt one',
  subtitle: '',
  status: 'needs_review',
  amount: '25000',
);
const _recordTwo = AdminTableRowData(
  id: 'receipt-two',
  title: 'Receipt two',
  subtitle: '',
  status: 'reviewed',
  amount: '10000',
);

void main() {
  test('contact projection is safe even when the masked field is incorrect', () {
    expect(AdminReceiptPresentation.maskedContact('0788767816'), '•••• 816');
    expect(AdminReceiptPresentation.maskedContact('***7816'), '•••• 816');
    expect(AdminReceiptPresentation.maskedContact('***816'), '•••• 816');
    expect(AdminReceiptPresentation.maskedContact('7'), '••••');
    expect(AdminReceiptPresentation.maskedContact(null), '—');
  });

  test('unknown duplicate counts are not displayed as no conflicts', () {
    expect(AdminReceiptPresentation.conflicts(null), 'Conflict count unavailable');
    expect(AdminReceiptPresentation.conflicts('-1'), 'Conflict count unavailable');
    expect(AdminReceiptPresentation.conflicts('0'), 'No conflicting references');
    expect(AdminReceiptPresentation.conflicts('1'), '1 conflicting reference');
    expect(AdminReceiptPresentation.conflicts(2), '2 conflicting references');
  });

  test('source-only capture does not pretend a parser ran', () {
    expect(
      AdminReceiptPresentation.extraction('parsed', sourceMetadata: true),
      'Source metadata',
    );
    expect(AdminReceiptPresentation.extraction(null), 'Extraction not established');
  });

  test('out-of-range receipt pages preserve truthful totals and recovery', () {
    expect(
      AdminReceiptPresentation.pageSummary(total: 13, offset: 25, shown: 0),
      'No records on this page · 13 matching records',
    );
    expect(
      AdminReceiptPresentation.outOfRangePage(
        total: 13,
        offset: 25,
        shown: 0,
      ),
      isTrue,
    );
    expect(
      AdminReceiptPresentation.pageSummary(total: 13, offset: 0, shown: 13),
      'Showing 1–13 of 13',
    );
    expect(
      AdminReceiptPresentation.pageSummary(total: 0, offset: 0, shown: 0),
      '0 records',
    );
    expect(
      AdminReceiptPresentation.outOfRangePage(
        total: 0,
        offset: 0,
        shown: 0,
      ),
      isFalse,
    );
  });

  testWidgets('server-paginated table does not imply page-local searching', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminDataTable(
              rows: const [_recordOne, _recordTwo],
              columns: [
                AdminTableColumn(label: 'Record', value: (row) => row.title),
              ],
              tableLabel: 'SMS receipts',
              localToolsEnabled: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Receipt one'), findsOneWidget);
    expect(find.text('Receipt two'), findsOneWidget);
    expect(find.text('Search loaded rows'), findsNothing);
    expect(find.byTooltip('Filter loaded rows'), findsNothing);
    expect(find.text('2 of 2 loaded rows'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty state exposes real clearing action', (tester) async {
    var resetCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminEmptyState(
            title: 'No matching receipts',
            message: 'Try resetting the filters.',
            action: TextButton(
              onPressed: () => resetCount++,
              child: const Text('Clear filters'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('No matching receipts'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    expect(resetCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail facts reflow at 320px and reveal provenance explicitly', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminRecordFactsPanel(
              title: 'Source evidence',
              summary: [
                AdminRecordFact(label: 'Amount', value: '25,000'),
                AdminRecordFact(label: 'Status', value: 'Needs review'),
              ],
              supporting: [
                AdminRecordFact(label: 'Masked contact', value: '***321'),
              ],
              technical: [
                AdminRecordFact(
                  label: 'Source SHA-256',
                  value:
                      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('25,000'), findsOneWidget);
    expect(find.text('***321'), findsOneWidget);
    expect(find.text('Source SHA-256'), findsNothing);
    final technical = find.byKey(
      const Key('admin-record-technical-provenance'),
    );
    await tester.ensureVisible(technical);
    await tester.tap(technical);
    await tester.pumpAndSettle();
    expect(find.text('Source SHA-256'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
