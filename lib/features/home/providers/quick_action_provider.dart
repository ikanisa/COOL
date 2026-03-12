import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../models/quick_action.dart';
import '../repositories/quick_action_repository.dart';

/// Provides a singleton [QuickActionRepository].
final quickActionRepositoryProvider = Provider<QuickActionRepository>(
  (ref) => QuickActionRepository(client: ref.read(supabaseClientProvider)),
);

/// Fetches all active quick actions, optionally filtered by country.
final quickActionsProvider = FutureProvider.family<List<QuickAction>, String?>((
  ref,
  country,
) {
  final repo = ref.read(quickActionRepositoryProvider);
  return repo.fetchAll(country: country);
});

final currentCountryQuickActionsProvider = FutureProvider<List<QuickAction>>((
  ref,
) {
  final country = ref.watch(currentUserCountryCodeProvider);
  return ref.watch(quickActionsProvider(country).future);
});
