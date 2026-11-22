part of 'member_history_page.dart';

Map<String, int> _signedHistoryAmounts(
  Object? value, {
  bool nonnegative = false,
}) {
  if (value is! Map || value.length != 1 || !value.containsKey('RWF')) {
    throw const FormatException('Invalid signed history totals');
  }
  final amount = exactJsonInteger(
    value['RWF'],
    field: 'history.total',
    minimum: nonnegative ? 0 : -maxExactJsonInteger,
  );
  return Map.unmodifiable({'RWF': amount});
}

void _validateSignedHistory(MemberHistoryPage page) {
  final maps = [
    page.totals,
    page.ownTotals,
    page.creditTotals,
    page.debitTotals,
    page.ownCreditTotals,
    page.ownDebitTotals,
  ];
  for (var index = 0; index < maps.length; index++) {
    _signedHistoryAmounts(maps[index], nonnegative: index >= 2);
  }
  final credit = page.creditTotals['RWF']!, debit = page.debitTotals['RWF']!;
  final ownCredit = page.ownCreditTotals['RWF']!,
      ownDebit = page.ownDebitTotals['RWF']!;
  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  if (!MemberHistoryPage._exactNonnegativeInteger(page.totalCount) ||
      page.totalCount < page.items.length ||
      !MemberHistoryPage._revisionPattern.hasMatch(page.revision) ||
      page.ownCollectionIds.any((id) => !uuid.hasMatch(id)) ||
      credit - debit != page.totals['RWF'] ||
      ownCredit - ownDebit != page.ownTotals['RWF'] ||
      ownCredit > credit ||
      ownDebit > debit ||
      (page.totalCount > 0 && credit == 0 && debit == 0) ||
      ((ownCredit == 0 && ownDebit == 0) != page.ownCollectionIds.isEmpty) ||
      (page.totalCount == 0 &&
          (credit != 0 || debit != 0 || page.ownCollectionIds.isNotEmpty))) {
    throw const FormatException('Invalid signed history aggregates');
  }
  final byId = <String, Contribution>{};
  final compensated = <String>{}, loadedOwnIds = <String>{};
  var loadedCredit = 0,
      loadedDebit = 0,
      loadedOwnCredit = 0,
      loadedOwnDebit = 0;
  for (final row in page.items) {
    if (!row.isHistoryEvent || byId.containsKey(row.id)) {
      throw const FormatException('Invalid signed history identity');
    }
    // Recheck constructed/cache rows as strictly as received wire events.
    Contribution.historyEventFromJson(row.toHistoryEventJson());
    byId[row.id] = row;
    final positive = row.amountMinor > 0, amount = row.amountMinor.abs();
    final remaining = positive ? credit - loadedCredit : debit - loadedDebit;
    if (amount > remaining) {
      throw const FormatException('History rows exceed gross totals');
    }
    if (positive) {
      loadedCredit += amount;
    } else {
      loadedDebit += amount;
    }
    if (row.isCompensation && !compensated.add(row.reversesEntryId!)) {
      throw const FormatException('Repeated history compensation');
    }
    if (row.isCurrentUserContribution) {
      if (!page.ownCollectionIds.contains(row.collectionId) ||
          amount >
              (positive
                  ? ownCredit - loadedOwnCredit
                  : ownDebit - loadedOwnDebit)) {
        throw const FormatException('Invalid signed history ownership');
      }
      if (positive) {
        loadedOwnCredit += amount;
      } else {
        loadedOwnDebit += amount;
      }
      loadedOwnIds.add(row.collectionId);
    }
  }
  for (final row in page.items.where((row) => row.isCompensation)) {
    final original = byId[row.reversesEntryId];
    // A selected-entry query or page prefix can omit the original event.
    if (original != null &&
        (original.isCompensation ||
            original.paymentId != row.paymentId ||
            original.collectionId != row.collectionId ||
            original.evidenceId != row.evidenceId ||
            original.amountMinor != -row.amountMinor ||
            original.isCurrentUserContribution !=
                row.isCurrentUserContribution)) {
      throw const FormatException('Invalid history compensation lineage');
    }
  }
  if (page.items.length == page.totalCount &&
      (loadedCredit != credit ||
          loadedDebit != debit ||
          loadedOwnCredit != ownCredit ||
          loadedOwnDebit != ownDebit ||
          !loadedOwnIds.containsAll(page.ownCollectionIds) ||
          loadedOwnIds.length != page.ownCollectionIds.length)) {
    throw const FormatException('Complete signed history does not reconcile');
  }
  final cursor = MemberHistoryPage._cursor(page.nextCursor, page.revision);
  if (cursor != null &&
      (!uuid.hasMatch(cursor['after'] as String) ||
          page.items.isEmpty ||
          cursor['after'] != page.items.last.id ||
          page.items.length >= page.totalCount)) {
    throw const FormatException('Invalid signed history continuation');
  }
}
