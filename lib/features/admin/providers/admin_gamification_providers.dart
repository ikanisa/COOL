import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';

import '../../../core/status/models/cool_activity.dart';
import '../../../core/status/models/cool_mission.dart';
import '../../../core/status/models/cool_season.dart';
import '../repositories/admin_gamification_repository.dart';

// ─── Repository singleton ────────────────────────────────────────

final adminGamificationRepositoryProvider =
    Provider<AdminGamificationRepository>((ref) {
  return AdminGamificationRepository(client: ref.read(supabaseClientProvider));
});

// ─── Missions ────────────────────────────────────────────────────

final adminMissionsProvider =
    FutureProvider.autoDispose<List<CoolMission>>((ref) async {
  final repo = ref.watch(adminGamificationRepositoryProvider);
  return repo.listMissions();
});

// ─── Seasons ─────────────────────────────────────────────────────

final adminSeasonsProvider =
    FutureProvider.autoDispose<List<CoolSeason>>((ref) async {
  final repo = ref.watch(adminGamificationRepositoryProvider);
  return repo.listSeasons();
});

// ─── Activities ──────────────────────────────────────────────────

final adminActivitiesProvider =
    FutureProvider.autoDispose<List<CoolActivity>>((ref) async {
  final repo = ref.watch(adminGamificationRepositoryProvider);
  return repo.listActivities();
});
