import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/supabase_client_provider.dart';

import '../models/cool_season.dart';
import '../services/quest_engine.dart';
import '../providers/cool_status_provider.dart';
import '../../../features/groups/providers/groups_provider.dart';

/// Active season (if any) — fetched from Supabase.
final activeSeasonProvider = FutureProvider.autoDispose<CoolSeason?>((
  ref,
) async {
  try {
    final data = await ref.read(supabaseClientProvider)
        .from('cool_seasons')
        .select()
        .eq('is_active', true)
        .lte('starts_at', DateTime.now().toIso8601String())
        .gte('ends_at', DateTime.now().toIso8601String())
        .order('starts_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (data == null) return null;
    return CoolSeason.fromJson(data);
  } catch (_) {
    return null;
  }
});

/// Personalized quests for the current user.
final questsProvider = Provider.autoDispose<List<CoolQuest>>((ref) {
  final statusAsync = ref.watch(coolStatusProvider);
  final status = statusAsync.valueOrNull;
  if (status == null) return const [];

  final groupsState = ref.watch(groupsProvider);

  return QuestEngine.generate(
    status: status,
    groupCount: groupsState.groups.length,
  );
});
