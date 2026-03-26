import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../models/nexus_recommendation.dart';
import '../repositories/nexus_repository.dart';

/// Singleton [NexusRepository].
final nexusRepositoryProvider = Provider<NexusRepository>((ref) {
  return NexusRepository(client: ref.read(supabaseClientProvider));
});

/// Fetches active Nexus recommendations.
final nexusRecommendationsProvider = FutureProvider<List<NexusRecommendation>>((
  ref,
) async {
  final repository = ref.read(nexusRepositoryProvider);
  // Default to Rwanda for now, or fetch from market provider if available.
  return repository.fetchRecommendations(country: 'RW');
});
