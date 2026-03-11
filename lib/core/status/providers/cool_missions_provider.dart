import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cool_mission.dart';
import '../repositories/cool_missions_repository.dart';
import '../repositories/cool_status_repository.dart';

// ─── Repository provider ──────────────────────────────────────────

final coolMissionsRepositoryProvider = Provider<CoolMissionsRepository>((ref) {
  return CoolMissionsRepository();
});

// ─── Active missions ──────────────────────────────────────────────

final activeMissionsProvider =
    FutureProvider.family<List<CoolMission>, String>((ref, userId) async {
  final repo = ref.watch(coolMissionsRepositoryProvider);
  return repo.getActiveMissions(userId);
});

// ─── Upcoming missions ───────────────────────────────────────────

final upcomingMissionsProvider =
    FutureProvider<List<CoolMission>>((ref) async {
  final repo = ref.watch(coolMissionsRepositoryProvider);
  return repo.getUpcomingMissions();
});

// ─── Mission contribution action ─────────────────────────────────

final missionContributeProvider = Provider<MissionContributeAction>((ref) {
  return MissionContributeAction(ref);
});

class MissionContributeAction {
  MissionContributeAction(this._ref);
  final Ref _ref;

  /// Increment contribution toward a mission.
  /// Returns the updated progress, or null on failure.
  Future<CoolMissionProgress?> call({
    required String missionId,
    required String userId,
    required int amount,
  }) async {
    final repo = _ref.read(coolMissionsRepositoryProvider);
    final statusRepo = CoolStatusRepository();

    return repo.contribute(
      missionId: missionId,
      userId: userId,
      amount: amount,
      statusRepo: statusRepo,
    );
  }
}
