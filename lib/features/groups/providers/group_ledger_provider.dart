import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'groups_provider.dart';
import '../models/group_contribution.dart';

/// Immutable query params for the group ledger view.
@immutable
class GroupLedgerQuery {
  const GroupLedgerQuery({
    required this.groupId,
    this.contributorId,
    this.startDate,
    this.endDate,
  });

  final String groupId;
  final String? contributorId;
  final DateTime? startDate;
  final DateTime? endDate;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is GroupLedgerQuery &&
            other.groupId == groupId &&
            other.contributorId == contributorId &&
            other.startDate == startDate &&
            other.endDate == endDate;
  }

  @override
  int get hashCode => Object.hash(groupId, contributorId, startDate, endDate);
}

/// Fetches all contributions for a group, filtered by contributor and date range.
final groupLedgerProvider = FutureProvider.autoDispose
    .family<List<GroupContribution>, GroupLedgerQuery>((ref, query) async {
  final repository = ref.watch(groupRepositoryProvider);
  return repository.fetchAllContributions(
    query.groupId,
    userId: query.contributorId,
    startDate: query.startDate,
    endDate: query.endDate,
  );
});
