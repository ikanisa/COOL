import 'collect_models.dart';

/// A page and aggregates for the entire matching history, never just its rows.
class MemberHistoryPage {
  const MemberHistoryPage({
    required this.items,
    required this.totalCount,
    required this.totals,
    required this.ownTotals,
    required this.ownCollectionIds,
    required this.revision,
    this.nextCursor,
  });

  // Transport precision shared by native and web, not a payment/product limit.
  static const _maxExactInteger = 9007199254740991;
  static final _revisionPattern = RegExp(r'^[a-f0-9]{32}$');

  final List<Contribution> items;
  final int totalCount;
  final Map<String, int> totals;
  final Map<String, int> ownTotals;
  final Set<String> ownCollectionIds;
  final String revision;
  final Map<String, dynamic>? nextCursor;

  factory MemberHistoryPage.fromJson(
    Map<String, dynamic> json,
    List<Contribution> items,
  ) {
    final count = json['total_count'];
    final revision = json['revision'];
    final ids = json['own_collection_ids'];
    if (!_exactNonnegativeInteger(count) ||
        revision is! String ||
        !_revisionPattern.hasMatch(revision) ||
        ids is! List ||
        ids.any((id) => !_identifier(id)) ||
        ids.toSet().length != ids.length) {
      throw const FormatException('Invalid history page');
    }
    final result = MemberHistoryPage(
      items: List.unmodifiable(items),
      totalCount: count as int,
      totals: _amounts(json['totals']),
      ownTotals: _amounts(json['own_totals']),
      ownCollectionIds: Set.unmodifiable(ids.cast<String>()),
      revision: revision,
      nextCursor: _cursor(json['next_cursor'], revision),
    );
    result._validate();
    return result;
  }

  static bool _exactNonnegativeInteger(Object? value) =>
      value is int && value.isFinite && value >= 0 && value <= _maxExactInteger;

  static bool _identifier(Object? value) =>
      value is String && value.isNotEmpty && value.trim() == value;

  static Map<String, int> _amounts(Object? value) {
    if (value is! Map ||
        value.entries.any(
          (entry) =>
              entry.key != 'RWF' || !_exactNonnegativeInteger(entry.value),
        )) {
      throw const FormatException('Invalid history totals');
    }
    return Map.unmodifiable(Map<String, int>.from(value));
  }

  static Map<String, dynamic>? _cursor(Object? value, String revision) {
    if (value == null) return null;
    if (value is! Map ||
        value['revision'] != revision ||
        !_revisionPattern.hasMatch(revision) ||
        !_identifier(value['after']) ||
        (value['after'] as String).length > 100) {
      throw const FormatException('Invalid history cursor');
    }
    // The inspected RPC uses only these two scalar fields. Do not pass through
    // arbitrary nested metadata or retain an alias of the server response map.
    return Map<String, dynamic>.unmodifiable({
      'revision': revision,
      'after': value['after'],
    });
  }

  void _validate() {
    final seen = <String>{};
    if (!_exactNonnegativeInteger(totalCount) ||
        totalCount < items.length ||
        !_revisionPattern.hasMatch(revision) ||
        ownCollectionIds.any((id) => !_identifier(id)) ||
        items.any(
          (row) =>
              !_identifier(row.id) ||
              !_identifier(row.collectionId) ||
              row.currency != 'RWF' ||
              !_exactNonnegativeInteger(row.amountMinor) ||
              row.amountMinor == 0 ||
              !seen.add(row.id),
        )) {
      throw const FormatException('Invalid history page');
    }
    _amounts(totals);
    _amounts(ownTotals);
    if ((totalCount > 0 &&
            ((totals['RWF'] ?? 0) <= 0 || !ownTotals.containsKey('RWF'))) ||
        ownTotals.entries.any(
          (entry) => entry.value > (totals[entry.key] ?? 0),
        ) ||
        (totalCount == 0 &&
            (totals.values.any((amount) => amount != 0) ||
                ownTotals.values.any((amount) => amount != 0) ||
                ownCollectionIds.isNotEmpty))) {
      throw const FormatException('Invalid history aggregates');
    }
    final cursor = _cursor(nextCursor, revision);
    if (cursor != null &&
        (items.isEmpty ||
            cursor['after'] != items.last.id ||
            items.length >= totalCount)) {
      throw const FormatException('Invalid history continuation');
    }
  }

  /// Validate a wire page against the request that produced it. Cached or
  /// accumulated pages are not wire windows and need not be limited to 50 rows.
  void validateRequest({
    required MemberHistoryQuery query,
    Map<String, dynamic>? cursor,
    int limit = 50,
  }) {
    _validate();
    if (limit < 1 || limit > 100 || items.length > limit) {
      throw const FormatException('Invalid history window');
    }
    if (query.collectionId != null &&
        items.any((row) => row.collectionId != query.collectionId)) {
      throw const FormatException('History does not match the selected group');
    }
    if (cursor == null) {
      if ((items.isEmpty && totalCount != 0) ||
          (nextCursor == null && items.length != totalCount)) {
        throw const FormatException('Incomplete history response');
      }
    } else {
      final requested = _cursor(cursor, revision)!;
      if (items.isEmpty || items.any((row) => row.id == requested['after'])) {
        throw const FormatException('History changed. Refresh to continue.');
      }
    }
    _validateOrder(query.sort);
  }

  void _validateOrder(String sort) {
    if (!const {'newest', 'oldest', 'highest', 'lowest'}.contains(sort)) {
      throw const FormatException('Invalid history sort');
    }
    for (var index = 1; index < items.length; index++) {
      if (_compare(items[index - 1], items[index], sort) > 0) {
        throw const FormatException('Invalid history order');
      }
    }
  }

  // Matches collect_member_actions.history_page: amount (when selected), then
  // posted_at, with payment_id ascending as the deterministic tie-breaker.
  static int _compare(Contribution left, Contribution right, String sort) {
    if (sort == 'highest' || sort == 'lowest') {
      final currency = left.currency.compareTo(right.currency);
      if (currency != 0) return currency;
      final amount = sort == 'highest'
          ? right.amountMinor.compareTo(left.amountMinor)
          : left.amountMinor.compareTo(right.amountMinor);
      if (amount != 0) return amount;
    }
    final date = sort == 'oldest'
        ? left.createdAt.compareTo(right.createdAt)
        : right.createdAt.compareTo(left.createdAt);
    return date != 0 ? date : left.id.compareTo(right.id);
  }

  Map<String, dynamic> get metadata => {
    'total_count': totalCount,
    'totals': totals,
    'own_totals': ownTotals,
    'own_collection_ids': ownCollectionIds.toList(),
    'revision': revision,
    'next_cursor': nextCursor,
  };

  static bool _sameAmounts(Map<String, int> left, Map<String, int> right) =>
      left.length == right.length &&
      left.entries.every((entry) => right[entry.key] == entry.value);

  MemberHistoryPage append(
    MemberHistoryPage next, {
    MemberHistoryQuery? query,
  }) {
    _validate();
    next._validate();
    final seen = items.map((row) => row.id).toSet();
    if (nextCursor == null ||
        revision != next.revision ||
        totalCount != next.totalCount ||
        !_sameAmounts(totals, next.totals) ||
        !_sameAmounts(ownTotals, next.ownTotals) ||
        ownCollectionIds.length != next.ownCollectionIds.length ||
        !ownCollectionIds.containsAll(next.ownCollectionIds) ||
        next.items.isEmpty ||
        next.items.any((row) => !seen.add(row.id)) ||
        items.length + next.items.length > totalCount) {
      throw const FormatException('History changed. Refresh to continue.');
    }
    final complete = items.length + next.items.length == totalCount;
    if ((next.nextCursor == null) != complete) {
      throw const FormatException(
        'History continuation does not match its count',
      );
    }
    if (query != null) {
      next.validateRequest(query: query, cursor: nextCursor);
    }
    final result = MemberHistoryPage(
      items: List.unmodifiable([...items, ...next.items]),
      totalCount: totalCount,
      totals: Map.unmodifiable(totals),
      ownTotals: Map.unmodifiable(ownTotals),
      ownCollectionIds: Set.unmodifiable(ownCollectionIds),
      revision: revision,
      nextCursor: _cursor(next.nextCursor, revision),
    );
    if (query != null) result._validateOrder(query.sort);
    return result;
  }
}

class MemberHistoryQuery {
  const MemberHistoryQuery({
    this.collectionId,
    this.search = '',
    this.sort = 'newest',
  });
  final String? collectionId;
  final String search;
  final String sort;
  bool get isDefault =>
      collectionId == null && search.isEmpty && sort == 'newest';

  @override
  bool operator ==(Object other) =>
      other is MemberHistoryQuery &&
      collectionId == other.collectionId &&
      search == other.search &&
      sort == other.sort;
  @override
  int get hashCode => Object.hash(collectionId, search, sort);
}
