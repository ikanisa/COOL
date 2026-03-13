import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';
import '../models/quick_action.dart';
import '../repositories/quick_action_repository.dart';

/// Provides a singleton [QuickActionRepository].
final quickActionRepositoryProvider = Provider<QuickActionRepository>(
  (ref) => QuickActionRepository(client: ref.read(supabaseClientProvider)),
);

/// Fetches all active quick actions for the fixed Rwanda app shell.
final quickActionsProvider = FutureProvider<List<QuickAction>>((ref) {
  final repo = ref.read(quickActionRepositoryProvider);
  return repo.fetchAll();
});

final currentCountryQuickActionsProvider = quickActionsProvider;
