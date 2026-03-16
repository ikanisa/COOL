import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/supabase_client_provider.dart';
import '../models/cool_leaderboard_entry.dart';

/// Top earners by total_points from the cool_status table.
final topEarnersProvider =
    FutureProvider.autoDispose<List<LeaderboardEntry>>((ref) async {
  final client = ref.read(supabaseClientProvider);

  // Fetch top 20 users ordered by total_points descending.
  // Join with profiles to get display names.
  final rows = await client
      .from('cool_status')
      .select('user_id, total_points, tier, profiles!inner(first_name, display_name, avatar_url)')
      .order('total_points', ascending: false)
      .limit(20);

  final results = <LeaderboardEntry>[];
  for (int i = 0; i < (rows as List).length; i++) {
    final row = rows[i] as Map<String, dynamic>;
    // Flatten the profiles join
    final profile = row['profiles'];
    final flat = <String, dynamic>{
      ...row,
      if (profile is Map) ...Map<String, dynamic>.from(profile),
    };
    results.add(LeaderboardEntry.fromJson(flat, i + 1));
  }
  return results;
});
