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
    final cursor = json['next_cursor'];
    final ids = json['own_collection_ids'];
    if (count is! int ||
        count < items.length ||
        count < 0 ||
        revision is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(revision) ||
        ids is! List ||
        ids.any((id) => id is! String || id.isEmpty) ||
        (cursor != null &&
            (cursor is! Map ||
                cursor['revision'] != revision ||
                cursor['after'] is! String ||
                (cursor['after'] as String).isEmpty ||
                items.isEmpty ||
                cursor['after'] != items.last.id))) {
      throw const FormatException('Invalid history page');
    }
    return MemberHistoryPage(
      items: List.unmodifiable(items),
      totalCount: count,
      totals: _amounts(json['totals']),
      ownTotals: _amounts(json['own_totals']),
      ownCollectionIds: Set.unmodifiable(ids.cast<String>()),
      revision: revision,
      nextCursor: cursor == null
          ? null
          : Map<String, dynamic>.from(cursor as Map),
    );
  }

  static Map<String, int> _amounts(dynamic value) {
    if (value is! Map ||
        value.entries.any(
          (entry) =>
              !const {'RWF', 'EUR'}.contains(entry.key) ||
              entry.value is! int ||
              (entry.value as int) < 0,
        )) {
      throw const FormatException('Invalid history totals');
    }
    return Map.unmodifiable(Map<String, int>.from(value));
  }

  Map<String, dynamic> get metadata => {
    'total_count': totalCount,
    'totals': totals,
    'own_totals': ownTotals,
    'own_collection_ids': ownCollectionIds.toList(),
    'revision': revision,
    'next_cursor': nextCursor,
  };

  MemberHistoryPage append(MemberHistoryPage next) {
    final seen = items.map((row) => row.id).toSet();
    if (revision != next.revision ||
        totalCount != next.totalCount ||
        next.items.isEmpty ||
        next.items.any((row) => !seen.add(row.id)) ||
        items.length + next.items.length > totalCount) {
      throw const FormatException('History changed. Refresh to continue.');
    }
    if (next.nextCursor == null &&
        items.length + next.items.length != totalCount) {
      throw const FormatException(
        'History ended before all records were received.',
      );
    }
    return MemberHistoryPage(
      items: List.unmodifiable([...items, ...next.items]),
      totalCount: totalCount,
      totals: totals,
      ownTotals: ownTotals,
      ownCollectionIds: ownCollectionIds,
      revision: revision,
      nextCursor: next.nextCursor,
    );
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
