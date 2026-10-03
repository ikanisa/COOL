import 'package:collect_app/admin/core/admin_display_formatters.dart';
import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/core/admin_list_paging.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/data/exact_json_values.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row([Map<String, dynamic> extra = const {}]) => {
  'id': 'synthetic-record',
  'title': 'Synthetic record',
  ...extra,
};

void main() {
  test('unsafe page offset is rejected before any read', () async {
    var calls = 0;
    await expectLater(
      loadAdminListPage(
        page: 9007199254740992,
        fetch: (_, _) async {
          calls++;
          return const AdminListResult(rows: [], total: 0);
        },
      ),
      throwsRangeError,
    );
    expect(calls, 0);
  });
  for (final value in [
    maxExactJsonInteger + 1,
    9007199254740992.0,
    '9007199254740992',
    '0009007199254740992',
    '999999999999999999999999999999',
  ]) {
    test('list rejects unsafe exact count $value (${value.runtimeType})', () {
      expect(
        () => AdminListResult.fromJson({'rows': [], 'total': value}),
        throwsFormatException,
      );
    });
  }
  test('constructed list cannot bypass safe total bounds', () {
    expect(
      () => const AdminListResult(
        rows: [],
        total: 9007199254740992,
      ).validateWindow(limit: 25, offset: 9007199254740992),
      throwsFormatException,
    );
  });
  for (final value in [maxExactJsonInteger, '$maxExactJsonInteger']) {
    test('safe count boundary remains exact for $value', () {
      final result = AdminListResult.fromJson({'rows': [], 'total': value});
      expect(result.total, maxExactJsonInteger);
      expect(
        result.validateWindow(limit: 25, offset: maxExactJsonInteger).total,
        maxExactJsonInteger,
      );
    });
  }
  for (final value in [
    '2026-02-29T12:00:00Z',
    '2026-04-31T12:00:00Z',
    '2026-09-30T24:00:00Z',
    '2026-09-30T12:60:00Z',
    '2026-09-30T12:00:60Z',
    '2026-09-30T12:00:00+24:00',
    '2026-09-30T12:00:00+02:60',
    '2026-09-30T12:00:00',
    '2026-09-30',
    '2026-09-30T12:00:00.1234567Z',
    '',
    1,
  ]) {
    test('row rejects invalid or naive creation timestamp $value', () {
      expect(
        () => AdminTableRowData.fromJson(_row({'created_at': value})),
        throwsFormatException,
      );
    });
    test('row rejects invalid optional update timestamp $value', () {
      expect(
        () => AdminTableRowData.fromJson(_row({'updated_at': value})),
        throwsFormatException,
      );
    });
  }
  for (final value in [
    '2024-02-29T23:30:00Z',
    '2024-03-01T01:30:00+02:00',
    '2024-02-29 23:30:00+00',
    DateTime.utc(2024, 2, 29, 23, 30),
  ]) {
    test(
      'creation timestamps identify the same normalized instant: $value',
      () {
        final row = AdminTableRowData.fromJson(_row({'created_at': value}));
        expect(row.createdAt, DateTime.utc(2024, 2, 29, 23, 30));
        expect(row.createdAt!.isUtc, isTrue);
      },
    );
  }
  test('missing optional timestamp remains unknown', () {
    expect(AdminTableRowData.fromJson(_row()).createdAt, isNull);
    expect(
      AdminTableRowData.fromJson(_row({'created_at': null})).createdAt,
      isNull,
    );
  });
  for (final key in ['active_members', 'active_groups']) {
    for (final value in [-1, 1.5, 9007199254740992, '9007199254740992', true]) {
      test('row rejects unsafe $key: $value (${value.runtimeType})', () {
        expect(
          () => AdminTableRowData.fromJson(_row({key: value})),
          throwsFormatException,
        );
      });
    }
    test('row retains explicit zero and optional unknown $key', () {
      expect(AdminTableRowData.fromJson(_row({key: 0})).extra[key], 0);
      expect(
        AdminTableRowData.fromJson(_row()).extra.containsKey(key),
        isFalse,
      );
    });
  }
  for (final (instant, expected) in [
    (DateTime.utc(2024, 2, 29, 23, 30), '1 Mar 2024 · 01:30 · Africa/Kigali'),
    (DateTime.utc(2026, 12, 31, 23), '1 Jan 2027 · 01:00 · Africa/Kigali'),
    (DateTime.utc(2026, 3, 29, 0, 30), '29 Mar 2026 · 02:30 · Africa/Kigali'),
    (DateTime.utc(2026, 3, 29, 1, 30), '29 Mar 2026 · 03:30 · Africa/Kigali'),
    (DateTime.utc(2026, 10, 25, 0, 30), '25 Oct 2026 · 02:30 · Africa/Kigali'),
    (DateTime.utc(2026, 10, 25, 1, 30), '25 Oct 2026 · 03:30 · Africa/Kigali'),
  ]) {
    test('Kigali date crosses UTC/calendar/DST boundaries: $instant', () {
      expect(adminKigaliDateTime(instant), expected);
      expect(adminKigaliDateTime(instant.toLocal()), expected);
    });
  }
  for (final width in [390.0, 1440.0]) {
    for (final (amount, expected, label) in [
      ('RWF 9007199254740993', 'RWF 9,007,199,254,740,993', 'Amount'),
      (
        'RWF 999999999999999999999999',
        'RWF 999,999,999,999,999,999,999,999',
        'Amount',
      ),
      (
        'RWF 9007199254740993 =',
        'RWF 9,007,199,254,740,993 =',
        'Debit = credit',
      ),
      ('RWF 000001234', 'RWF 1,234', 'Amount'),
      ('RWF 12,34', 'RWF 12,34', 'Amount'),
    ]) {
      testWidgets('exact string money survives ${width}px table: $amount', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: AdminDataTable(
                valueLabel: label,
                rows: [
                  AdminTableRowData.fromJson(
                    _row({
                      'amount': amount,
                      'created_at': '2024-02-29T23:30:00Z',
                    }),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(expected), findsOneWidget);
        expect(find.text('1 Mar 2024 · 01:30 · Africa/Kigali'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
