import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/nexus_recommendation.dart';

/// Fetches personalized opportunities from the `nexus_opportunities` table.
class NexusRepository {
  NexusRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  /// Fetch active recommendations, optionally filtered by country.
  Future<List<NexusRecommendation>> fetchRecommendations({String? country}) async {
    var query = _client
        .from('nexus_opportunities')
        .select()
        .eq('is_active', true);
    
    if (country != null) {
      query = query.or('country.is.null,country.eq.$country');
    }

    final rows = await query.order('sort_order', ascending: false);
    
    return rows.map((r) => NexusRecommendation.fromJson(r)).toList();
  }
}
