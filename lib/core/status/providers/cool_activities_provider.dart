import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cool_activity.dart';

/// Provides the list of active token-earning activities from the DB.
///
/// Used by the "Ways to Earn" grid on the Cool Tokens screen
/// and various quest/gamification surfaces.
final coolActivitiesProvider =
    FutureProvider.autoDispose<List<CoolActivity>>((ref) async {
  final client = Supabase.instance.client;
  final rows = await client
      .from('cool_activities')
      .select()
      .eq('is_active', true)
      .order('sort_order', ascending: true);

  return (rows as List)
      .cast<Map<String, dynamic>>()
      .map(CoolActivity.fromJson)
      .toList(growable: false);
});
