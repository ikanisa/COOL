import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/quick_action.dart';
import '../repositories/quick_action_repository.dart';

/// Provides a singleton [QuickActionRepository].
final quickActionRepositoryProvider = Provider<QuickActionRepository>(
  (ref) => QuickActionRepository(),
);

/// Fetches all active quick actions, optionally filtered by country.
final quickActionsProvider =
    FutureProvider.family<List<QuickAction>, String?>((ref, country) {
  final repo = ref.read(quickActionRepositoryProvider);
  return repo.fetchAll(country: country);
});
