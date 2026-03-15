import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/quick_action.dart';

/// Fetches quick action cards from the `quick_actions` Supabase table.
class QuickActionRepository {
  QuickActionRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  /// Fetch all active quick actions for the fixed Rwanda app shell.
  Future<List<QuickAction>> fetchAll() async {
    final rows = await _client
        .from('quick_actions')
        .select()
        .eq('is_active', true)
        .order('sort_order')
        .order('title');
    return rows.map((r) => QuickAction.fromJson(r)).toList();
  }
}
