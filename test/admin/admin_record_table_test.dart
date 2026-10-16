import 'package:collect_app/admin/core/admin_display_formatters.dart';
import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const person = AdminTableRowData(
  id: 'person-1',
  title: '940001',
  subtitle: '',
  status: 'active',
  amount: '',
  extra: {
    'name': 'Berta Mukamana',
    'momo_number': '+250788600001',
    'momo_code': '008000',
  },
);

List<AdminTableColumn> personColumns({bool selectable = false}) => [
  AdminTableColumn(label: 'User ID', value: (row) => row.title),
  AdminTableColumn(label: 'Name', value: (row) => row.extra['name'] as String),
  AdminTableColumn(
    label: 'MoMo number',
    value: (row) => row.extra['momo_number'] as String,
    selectable: selectable,
  ),
  AdminTableColumn(
    label: 'MoMo code',
    value: (row) => row.extra['momo_code'] as String,
  ),
];

Future<void> pumpTable(
  WidgetTester tester, {
  bool selectable = false,
  ValueChanged<AdminTableRowData>? onOpen,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: AdminDataTable(
            rows: const [person],
            columns: personColumns(selectable: selectable),
            tableLabel: 'Members',
            onOpen: onOpen,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('whole local amounts retain exact large integers and omit currency', () {
    expect(
      adminFormatWholeAmount('9007199254740991999'),
      '9,007,199,254,740,991,999',
    );
    expect(adminFormatWholeAmount(25000), '25,000');
    expect(adminFormatWholeAmount('008000'), '008,000');
  });

  testWidgets('one field per column preserves full numbers and code zeros', (
    tester,
  ) async {
    await pumpTable(tester);
    final table = tester.widget<DataTable>(find.byType(DataTable));
    expect(table.columns.length, 4);
    expect(table.rows.single.cells.length, 4);
    expect(find.text('940001'), findsOneWidget);
    expect(find.text('+250788600001'), findsOneWidget);
    expect(find.text('008000'), findsOneWidget);
    expect(find.text('Record'), findsNothing);
    expect(find.text('Description'), findsNothing);
    expect(find.text('Country'), findsNothing);
  });

  testWidgets('a row body opens its record without selecting a checkbox', (
    tester,
  ) async {
    var opens = 0;
    await pumpTable(
      tester,
      onOpen: (row) {
        expect(row.id, person.id);
        opens++;
      },
    );
    await tester.tap(find.text('Berta Mukamana'));
    await tester.pump();
    expect(opens, 1);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('selectable facts expose their actual label and value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpTable(tester, selectable: true);
    final node = tester.getSemantics(
      find.bySemanticsLabel('MoMo number: +250788600001'),
    );
    expect(node.getSemanticsData().label, 'MoMo number: +250788600001');
    expect(find.byType(SelectableText), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('narrow table supports keyboard scrolling to later columns', (
    tester,
  ) async {
    await pumpTable(tester);
    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isTrue);
    final controller = scrollbar.controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));
    final focus = tester.widget<Focus>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Focus &&
            widget.focusNode?.debugLabel == 'Admin table horizontal scrolling',
      ),
    );
    focus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(controller.offset, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(controller.offset, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'loaded-row tools preserve numeric ordering, exact code and row action',
    (tester) async {
      String? opened;
      final rows = [
        person,
        const AdminTableRowData(
          id: 'person-2',
          title: '940002',
          subtitle: '',
          status: 'active',
          amount: '',
          extra: {
            'name': 'Alice',
            'momo_number': '+250788600002',
            'momo_code': '004000',
          },
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminDataTable(
                rows: rows,
                columns: personColumns(),
                tableLabel: 'Members',
                onOpen: (row) => opened = row.id,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('2 of 2 loaded rows'), findsOneWidget);
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField && w.decoration?.labelText == 'Search loaded rows',
        ),
        '"Alice" 004000',
      );
      await tester.pumpAndSettle();
      expect(find.text('Berta Mukamana'), findsNothing);
      expect(find.text('004000'), findsOneWidget);
      await tester.tap(find.text('Alice'));
      expect(opened, 'person-2');
      await tester.tap(find.byTooltip('Clear table search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DataTable>(find.byType(DataTable)).sortColumnIndex,
        1,
      );
      expect(
        tester
            .widget<DataTable>(find.byType(DataTable))
            .rows
            .first
            .cells[1]
            .child,
        isA<Text>(),
      );
      expect(
        (tester
                    .widget<DataTable>(find.byType(DataTable))
                    .rows
                    .first
                    .cells[1]
                    .child
                as Text)
            .data,
        'Alice',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'server sort headers dispatch a key without reordering one page locally',
    (tester) async {
      String? order;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminDataTable(
              rows: const [person],
              sortBy: 'name_desc',
              onSortChanged: (value) => order = value,
              columns: [
                AdminTableColumn(
                  label: 'Name',
                  sortKey: 'name',
                  value: (row) => row.extra['name'] as String,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();
      expect(order, 'name_asc');
      expect(find.text('Search loaded rows'), findsNothing);
    },
  );
}
