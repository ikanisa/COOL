import 'package:collect_app/admin/core/admin_display_formatters.dart';
import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:collect_app/admin/shared/components/admin_status_chip.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/app/theme/collect_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'operation times use the Kigali day across UTC and offset boundaries',
    () {
      final utc = DateTime.parse('2026-09-29T22:30:00Z');
      final offset = DateTime.parse('2026-09-30T03:30:00+05:00');
      expect(adminKigaliDateTime(utc), '30 Sep 2026 · 00:30 · Africa/Kigali');
      expect(adminKigaliDateTime(offset), adminKigaliDateTime(utc));
      expect(adminKigaliDateTime(utc.toLocal()), adminKigaliDateTime(utc));
      expect(
        adminKigaliDateTime(utc, includeZone: false),
        '30 Sep 2026 · 00:30',
      );
      expect(
        adminKigaliDate(DateTime.parse('2026-12-31T23:00:00Z')),
        '1 Jan 2027',
      );
      expect(
        adminKigaliTime(DateTime.parse('2026-09-30T23:59:00+02:00')),
        '23:59',
      );
      expect(adminKigaliDateTime(null), '—');
      expect(adminKigaliDate(null), '—');
      expect(adminKigaliTime(null), '—');
    },
  );

  testWidgets(
    'unresolved outcomes have visible labels and attention treatment',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final labels = {
        'send_unknown': 'Send unknown',
        'uncertain': 'Uncertain',
        'unmatched': 'Unmatched',
        'unbalanced': 'Unbalanced',
        'awaiting_confirmation': 'Awaiting confirmation',
      };
      for (final entry in labels.entries) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Center(child: AdminStatusChip(label: entry.key)),
            ),
          ),
        );
        expect(find.text(entry.value), findsOneWidget);
        expect(find.bySemanticsLabel('Status: ${entry.value}'), findsOneWidget);
        final icon = tester.widget<Icon>(
          find.descendant(
            of: find.byType(AdminStatusChip),
            matching: find.byType(Icon),
          ),
        );
        expect(icon.color, CollectColors.dark.warningForeground);
        expect(icon.icon, isNot(Icons.check_circle_outline));
        expect(tester.takeException(), isNull);
      }
      semantics.dispose();
    },
  );

  for (final theme in {
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
  }.entries) {
    for (final viewport in [(1440.0, 1.0), (320.0, 2.0)]) {
      testWidgets(
        '${theme.key} records remain readable at ${viewport.$1} and ${viewport.$2}x text',
        (tester) async {
          tester.view.physicalSize = Size(viewport.$1, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          final row = AdminTableRowData(
            id: 'synthetic-receipt',
            title: 'Synthetic receipt',
            subtitle: 'Masked recipient · 078••••••12',
            status: 'uncertain',
            amount: 'RWF 1,000',
            createdAt: DateTime.parse('2026-09-29T22:30:00Z'),
          );
          String? opened;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.value,
              home: MediaQuery(
                data: MediaQueryData(
                  textScaler: TextScaler.linear(viewport.$2),
                ),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: AdminDataTable(
                      rows: [row],
                      rpcName: 'admin_list_hybrid_sms_receipts',
                      onOpen: (value) => opened = value.id,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Uncertain'), findsOneWidget);
          expect(find.text('Created'), findsOneWidget);
          expect(find.text('Amount'), findsOneWidget);
          expect(
            find.text('30 Sep 2026 · 00:30 · Africa/Kigali'),
            findsOneWidget,
          );
          expect(find.bySemanticsLabel('Status: Uncertain'), findsOneWidget);
          if (viewport.$1 > 700) {
            expect(find.text('Record'), findsOneWidget);
            expect(find.text('Status'), findsOneWidget);
          } else {
            expect(
              find.byKey(const Key('admin-compact-record-list')),
              findsOneWidget,
            );
          }
          final open = find.byTooltip('Open Synthetic receipt');
          await tester.ensureVisible(open);
          await tester.tap(open);
          expect(opened, row.id);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }
}
