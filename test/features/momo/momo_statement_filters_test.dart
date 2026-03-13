import 'package:cool_app/features/momo/models/momo_statement.dart';
import 'package:cool_app/features/momo/models/momo_statement_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveStatementDateRange', () {
    test('resolves day, week, month, year, custom, and all presets', () {
      final reference = DateTime(2026, 3, 13, 17, 45);

      expect(
        resolveStatementDateRange(
          preset: StatementPeriodPreset.day,
          referenceDate: reference,
        ),
        isA<StatementDateRange>()
            .having(
              (value) => value.startDate,
              'startDate',
              DateTime(2026, 3, 13),
            )
            .having((value) => value.endDate, 'endDate', DateTime(2026, 3, 13)),
      );

      expect(
        resolveStatementDateRange(
          preset: StatementPeriodPreset.week,
          referenceDate: reference,
        ),
        isA<StatementDateRange>()
            .having(
              (value) => value.startDate,
              'startDate',
              DateTime(2026, 3, 7),
            )
            .having((value) => value.endDate, 'endDate', DateTime(2026, 3, 13)),
      );

      expect(
        resolveStatementDateRange(
          preset: StatementPeriodPreset.month,
          referenceDate: reference,
        ),
        isA<StatementDateRange>()
            .having(
              (value) => value.startDate,
              'startDate',
              DateTime(2026, 2, 12),
            )
            .having((value) => value.endDate, 'endDate', DateTime(2026, 3, 13)),
      );

      expect(
        resolveStatementDateRange(
          preset: StatementPeriodPreset.year,
          referenceDate: reference,
        ),
        isA<StatementDateRange>()
            .having(
              (value) => value.startDate,
              'startDate',
              DateTime(2025, 3, 14),
            )
            .having((value) => value.endDate, 'endDate', DateTime(2026, 3, 13)),
      );

      expect(
        resolveStatementDateRange(
          preset: StatementPeriodPreset.custom,
          customStartDate: DateTime(2026, 3, 5, 12),
          customEndDate: DateTime(2026, 3, 1, 9),
        ),
        isA<StatementDateRange>()
            .having(
              (value) => value.startDate,
              'startDate',
              DateTime(2026, 3, 1),
            )
            .having((value) => value.endDate, 'endDate', DateTime(2026, 3, 5)),
      );

      expect(
        resolveStatementDateRange(
          preset: StatementPeriodPreset.all,
          referenceDate: reference,
        ),
        isA<StatementDateRange>()
            .having((value) => value.startDate, 'startDate', isNull)
            .having((value) => value.endDate, 'endDate', isNull),
      );
    });
  });

  group('applyWalletStatementView', () {
    final entries = <MomoWalletEntry>[
      MomoWalletEntry(
        id: '1',
        entryType: 'credit',
        ledgerStatus: 'posted',
        amount: 2000,
        currency: 'RWF',
        occurredAt: DateTime(2026, 3, 12, 8),
        txCategory: 'salary',
        cashflowBucket: 'income',
        label: 'Salary',
        counterpartyName: 'Acme Ltd',
      ),
      MomoWalletEntry(
        id: '2',
        entryType: 'debit',
        ledgerStatus: 'posted',
        amount: 500,
        currency: 'RWF',
        occurredAt: DateTime(2026, 3, 13, 9),
        txCategory: 'groceries',
        cashflowBucket: 'expense',
        label: 'Groceries',
        counterpartyName: 'Kigali Market',
      ),
      MomoWalletEntry(
        id: '3',
        entryType: 'credit',
        ledgerStatus: 'posted',
        amount: 3000,
        currency: 'RWF',
        occurredAt: DateTime(2026, 3, 10, 7),
        txCategory: 'invoice',
        cashflowBucket: 'income',
        label: 'Invoice',
        counterpartyName: 'Acme Ltd',
      ),
    ];

    test('filters by party and sorts by amount high to low', () {
      final filtered = applyWalletStatementView(
        entries: entries,
        partyFilter: 'Acme Ltd',
        sortOption: StatementSortOption.amountHighToLow,
      );

      expect(filtered.map((entry) => entry.id), <String>['3', '1']);
    });
  });

  group('applySavingsStatementView', () {
    final entries = <SavingsStatementEntry>[
      SavingsStatementEntry(
        id: '1',
        groupId: 'a',
        groupName: 'Zamuka Group',
        amount: 5000,
        status: 'confirmed',
        createdAt: DateTime(2026, 3, 10),
      ),
      SavingsStatementEntry(
        id: '2',
        groupId: 'b',
        groupName: 'Abizeranye Group',
        amount: 1500,
        status: 'pending',
        createdAt: DateTime(2026, 3, 12),
      ),
    ];

    test('sorts savings statements by name ascending', () {
      final filtered = applySavingsStatementView(
        entries: entries,
        sortOption: StatementSortOption.nameAz,
      );

      expect(filtered.map((entry) => entry.id), <String>['2', '1']);
    });
  });
}
