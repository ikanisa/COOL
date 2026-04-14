import 'package:cool_app/features/momo/models/momo_statement_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveStatementDateRange', () {
    final referenceDate = DateTime(2026, 4, 14);

    test('day — returns same day start and end', () {
      final range = resolveStatementDateRange(
        preset: StatementPeriodPreset.day,
        referenceDate: referenceDate,
      );

      expect(range.startDate, DateTime(2026, 4, 14));
      expect(range.endDate, DateTime(2026, 4, 14));
    });

    test('week — returns 7-day window', () {
      final range = resolveStatementDateRange(
        preset: StatementPeriodPreset.week,
        referenceDate: referenceDate,
      );

      expect(range.startDate, DateTime(2026, 4, 8));
      expect(range.endDate, DateTime(2026, 4, 14));
    });

    test('month — returns 30-day window', () {
      final range = resolveStatementDateRange(
        preset: StatementPeriodPreset.month,
        referenceDate: referenceDate,
      );

      expect(range.startDate, DateTime(2026, 3, 15));
      expect(range.endDate, DateTime(2026, 4, 14));
    });

    test('year — returns 365-day window', () {
      final range = resolveStatementDateRange(
        preset: StatementPeriodPreset.year,
        referenceDate: referenceDate,
      );

      expect(range.startDate!.year, 2025);
      expect(range.endDate, DateTime(2026, 4, 14));
    });

    test('all — returns null bounds', () {
      final range = resolveStatementDateRange(
        preset: StatementPeriodPreset.all,
        referenceDate: referenceDate,
      );

      expect(range.startDate, isNull);
      expect(range.endDate, isNull);
    });

    test('custom — uses custom dates', () {
      final range = resolveStatementDateRange(
        preset: StatementPeriodPreset.custom,
        customStartDate: DateTime(2026, 1, 1),
        customEndDate: DateTime(2026, 2, 28),
      );

      expect(range.startDate, DateTime(2026, 1, 1));
      expect(range.endDate, DateTime(2026, 2, 28));
    });

    test('custom without dates — returns null bounds', () {
      final range = resolveStatementDateRange(
        preset: StatementPeriodPreset.custom,
      );

      expect(range.startDate, isNull);
      expect(range.endDate, isNull);
    });
  });

  group('StatementPeriodPreset', () {
    test('has expected values', () {
      expect(StatementPeriodPreset.values, hasLength(6));
      expect(
        StatementPeriodPreset.values,
        containsAll([
          StatementPeriodPreset.day,
          StatementPeriodPreset.week,
          StatementPeriodPreset.month,
          StatementPeriodPreset.year,
          StatementPeriodPreset.custom,
          StatementPeriodPreset.all,
        ]),
      );
    });
  });

  group('StatementSortOption', () {
    test('has expected values', () {
      expect(StatementSortOption.values, hasLength(6));
    });
  });
}
