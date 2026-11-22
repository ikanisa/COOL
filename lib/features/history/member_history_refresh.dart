import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/repositories/collect_repository.dart';

/// Refreshes the group snapshot before reloading the still-visible history.
Future<void> refreshMemberHistory({
  required WidgetRef ref,
  required MemberGroupSession session,
  required MemberHistoryQuery query,
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return;
  await session.repository.loadInitial();
  if (!isCurrent()) return;
  final history = ref.read(memberHistoryQueriesProvider)(query);
  await ref.read(history.notifier).refresh();
}
