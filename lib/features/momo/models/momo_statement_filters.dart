import 'momo_statement.dart';

enum StatementPeriodPreset { day, week, month, year, custom, all }

enum StatementSortOption {
  newestFirst,
  oldestFirst,
  amountHighToLow,
  amountLowToHigh,
  nameAz,
  nameZa,
}

class StatementDateRange {
  const StatementDateRange({this.startDate, this.endDate});

  final DateTime? startDate;
  final DateTime? endDate;
}

StatementDateRange resolveStatementDateRange({
  required StatementPeriodPreset preset,
  DateTime? referenceDate,
  DateTime? customStartDate,
  DateTime? customEndDate,
}) {
  final today = _dateOnly(referenceDate ?? DateTime.now());
  switch (preset) {
    case StatementPeriodPreset.day:
      return StatementDateRange(startDate: today, endDate: today);
    case StatementPeriodPreset.week:
      return StatementDateRange(
        startDate: today.subtract(const Duration(days: 6)),
        endDate: today,
      );
    case StatementPeriodPreset.month:
      return StatementDateRange(
        startDate: today.subtract(const Duration(days: 30)),
        endDate: today,
      );
    case StatementPeriodPreset.year:
      return StatementDateRange(
        startDate: today.subtract(const Duration(days: 365)),
        endDate: today,
      );
    case StatementPeriodPreset.custom:
      final normalizedStart = customStartDate != null
          ? _dateOnly(customStartDate)
          : null;
      final normalizedEnd = customEndDate != null
          ? _dateOnly(customEndDate)
          : normalizedStart;
      if (normalizedStart == null && normalizedEnd == null) {
        return const StatementDateRange();
      }
      if (normalizedStart == null) {
        return StatementDateRange(
          startDate: normalizedEnd,
          endDate: normalizedEnd,
        );
      }
      if (normalizedEnd == null) {
        return StatementDateRange(
          startDate: normalizedStart,
          endDate: normalizedStart,
        );
      }
      if (normalizedStart.isAfter(normalizedEnd)) {
        return StatementDateRange(
          startDate: normalizedEnd,
          endDate: normalizedStart,
        );
      }
      return StatementDateRange(
        startDate: normalizedStart,
        endDate: normalizedEnd,
      );
    case StatementPeriodPreset.all:
      return const StatementDateRange();
  }
}

List<String> walletPartyOptions(List<MomoWalletEntry> entries) {
  final values = entries
      .map(walletPartyLabel)
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);
  values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return values;
}

List<String> savingsPartyOptions(List<SavingsStatementEntry> entries) {
  final values = entries
      .map((entry) => entry.groupName.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);
  values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return values;
}

List<MomoWalletEntry> applyWalletStatementView({
  required List<MomoWalletEntry> entries,
  String? partyFilter,
  StatementSortOption sortOption = StatementSortOption.newestFirst,
}) {
  final filtered = entries
      .where(
        (entry) =>
            partyFilter == null || walletPartyLabel(entry) == partyFilter,
      )
      .toList(growable: false);
  filtered.sort(
    (left, right) => _compareWalletEntries(left, right, sortOption),
  );
  return filtered;
}

List<SavingsStatementEntry> applySavingsStatementView({
  required List<SavingsStatementEntry> entries,
  String? partyFilter,
  StatementSortOption sortOption = StatementSortOption.newestFirst,
}) {
  final filtered = entries
      .where(
        (entry) => partyFilter == null || entry.groupName.trim() == partyFilter,
      )
      .toList(growable: false);
  filtered.sort(
    (left, right) => _compareSavingsEntries(left, right, sortOption),
  );
  return filtered;
}

String walletPartyLabel(MomoWalletEntry entry) {
  final counterparty = entry.counterpartyName?.trim() ?? '';
  if (counterparty.isNotEmpty) {
    return counterparty;
  }
  return entry.label.trim();
}

int _compareWalletEntries(
  MomoWalletEntry left,
  MomoWalletEntry right,
  StatementSortOption sortOption,
) {
  switch (sortOption) {
    case StatementSortOption.newestFirst:
      return right.occurredAt.compareTo(left.occurredAt);
    case StatementSortOption.oldestFirst:
      return left.occurredAt.compareTo(right.occurredAt);
    case StatementSortOption.amountHighToLow:
      final amountCompare = right.amount.compareTo(left.amount);
      return amountCompare != 0
          ? amountCompare
          : right.occurredAt.compareTo(left.occurredAt);
    case StatementSortOption.amountLowToHigh:
      final amountCompare = left.amount.compareTo(right.amount);
      return amountCompare != 0
          ? amountCompare
          : right.occurredAt.compareTo(left.occurredAt);
    case StatementSortOption.nameAz:
      final nameCompare = walletPartyLabel(
        left,
      ).toLowerCase().compareTo(walletPartyLabel(right).toLowerCase());
      return nameCompare != 0
          ? nameCompare
          : right.occurredAt.compareTo(left.occurredAt);
    case StatementSortOption.nameZa:
      final nameCompare = walletPartyLabel(
        right,
      ).toLowerCase().compareTo(walletPartyLabel(left).toLowerCase());
      return nameCompare != 0
          ? nameCompare
          : right.occurredAt.compareTo(left.occurredAt);
  }
}

int _compareSavingsEntries(
  SavingsStatementEntry left,
  SavingsStatementEntry right,
  StatementSortOption sortOption,
) {
  switch (sortOption) {
    case StatementSortOption.newestFirst:
      return right.createdAt.compareTo(left.createdAt);
    case StatementSortOption.oldestFirst:
      return left.createdAt.compareTo(right.createdAt);
    case StatementSortOption.amountHighToLow:
      final amountCompare = right.amount.compareTo(left.amount);
      return amountCompare != 0
          ? amountCompare
          : right.createdAt.compareTo(left.createdAt);
    case StatementSortOption.amountLowToHigh:
      final amountCompare = left.amount.compareTo(right.amount);
      return amountCompare != 0
          ? amountCompare
          : right.createdAt.compareTo(left.createdAt);
    case StatementSortOption.nameAz:
      final nameCompare = left.groupName.toLowerCase().compareTo(
        right.groupName.toLowerCase(),
      );
      return nameCompare != 0
          ? nameCompare
          : right.createdAt.compareTo(left.createdAt);
    case StatementSortOption.nameZa:
      final nameCompare = right.groupName.toLowerCase().compareTo(
        left.groupName.toLowerCase(),
      );
      return nameCompare != 0
          ? nameCompare
          : right.createdAt.compareTo(left.createdAt);
  }
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}
