import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'admin_record_table_test.dart' show person, personColumns;

void main() {
  testWidgets(
    'table semantics follows real search from five rows to one to zero and back',
    (tester) async {
      final semantics = tester.ensureSemantics();
      String? opened;
      final rows = [
        person,
        for (final (index, name) in [
          'Alice',
          'Celine',
          'Diane',
          'Eric',
        ].indexed)
          AdminTableRowData(
            id: 'person-${index + 2}',
            title: '94000${index + 2}',
            subtitle: '',
            status: 'active',
            amount: '',
            extra: {
              'name': name,
              'momo_number': '+25078860000${index + 2}',
              'momo_code': '00400${index + 2}',
            },
          ),
      ];
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AdminDataTable(
                  rows: rows,
                  columns: personColumns(selectable: true),
                  tableLabel: 'Members',
                  onOpen: (row) => opened = row.id,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        void expectVisible(int count) {
          final label = 'Members table, $count of 5 loaded rows visible';
          final tableSemantics = find.bySemanticsLabel(label);
          expect(tableSemantics, findsOneWidget);
          expect(
            tester.getSemantics(tableSemantics).getSemanticsData().label,
            label,
          );
          expect(
            tester.widget<DataTable>(find.byType(DataTable)).rows,
            hasLength(count),
          );
          expect(find.text('$count of 5 loaded rows'), findsOneWidget);
        }

        expectVisible(5);
        final search = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Search loaded rows',
        );
        await tester.enterText(search, 'Alice');
        await tester.pumpAndSettle();
        expectVisible(1);
        expect(find.text('Berta Mukamana'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(DataTable),
            matching: find.text('Alice'),
          ),
          findsOneWidget,
        );
        expect(find.text('+250788600002'), findsOneWidget);
        final open = find.byTooltip('Open 940002');
        await tester.ensureVisible(open);
        await tester.pumpAndSettle();
        await tester.tap(open);
        expect(opened, 'person-2');
        await tester.ensureVisible(search);
        await tester.enterText(search, 'no-synthetic-person-matches');
        await tester.pumpAndSettle();
        expectVisible(0);
        expect(
          find.descendant(
            of: find.byType(DataTable),
            matching: find.text('Alice'),
          ),
          findsNothing,
        );
        expect(find.byType(Checkbox), findsNothing);
        expect(
          [
            for (final column
                in tester.widget<DataTable>(find.byType(DataTable)).columns)
              (column.label as Text).data,
          ],
          ['User ID', 'Name', 'MoMo number', 'MoMo code', 'Open'],
        );
        await tester.tap(find.byTooltip('Clear table search'));
        await tester.pumpAndSettle();
        expectVisible(5);
        expect(find.text('Berta Mukamana'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(DataTable),
            matching: find.text('Alice'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );
}
