import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cool_event.dart';
import '../models/cool_mission.dart';
import 'cool_status_repository.dart';

/// Data access for cooperative missions.
class CoolMissionsRepository {
  CoolMissionsRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  /// Fetch all currently active missions.
  Future<List<CoolMission>> getActiveMissions(String userId) async {
    final now = DateTime.now().toIso8601String();

    final rows = await _client
        .from('cool_missions')
        .select()
        .eq('is_active', true)
        .lte('starts_at', now)
        .gte('ends_at', now)
        .order('ends_at', ascending: true);

    final missions = <CoolMission>[];

    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      // Fetch this user's progress for each mission
      final progressRow = await _client
          .from('cool_mission_progress')
          .select()
          .eq('mission_id', row['id'])
          .eq('user_id', userId)
          .maybeSingle();

      final userProgress = progressRow != null
          ? (progressRow['contribution_value'] as int? ?? 0)
          : 0;

      missions.add(
        CoolMission.fromJson({...row, 'user_progress': userProgress}),
      );
    }

    return missions;
  }

  /// Fetch upcoming missions (not yet started).
  Future<List<CoolMission>> getUpcomingMissions() async {
    final now = DateTime.now().toIso8601String();

    final rows = await _client
        .from('cool_missions')
        .select()
        .eq('is_active', true)
        .gt('starts_at', now)
        .order('starts_at', ascending: true)
        .limit(5);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(CoolMission.fromJson)
        .toList(growable: false);
  }

  /// Increment user's contribution toward a mission.
  ///
  /// If the mission is now complete, awards bonus points via [CoolStatusRepository].
  Future<CoolMissionProgress?> contribute({
    required String missionId,
    required String userId,
    required int amount,
    CoolStatusRepository? statusRepo,
  }) async {
    // Upsert progress
    final row = await _client
        .from('cool_mission_progress')
        .upsert({
          'mission_id': missionId,
          'user_id': userId,
          'contribution_value': amount,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'mission_id,user_id')
        .select()
        .maybeSingle();

    if (row == null) return null;

    final progress = CoolMissionProgress.fromJson(row);

    // Check if mission is now complete for this user
    final mission = await _getMission(missionId);
    if (mission != null &&
        progress.contributionValue >= mission.targetValue &&
        progress.completedAt == null) {
      // Mark as completed
      await _client
          .from('cool_mission_progress')
          .update({'completed_at': DateTime.now().toIso8601String()})
          .eq('mission_id', missionId)
          .eq('user_id', userId);

      // Award mission completion bonus
      if (statusRepo != null && mission.rewardPoints > 0) {
        await statusRepo.logEvent(
          CoolEvent(
            userId: userId,
            eventType: CoolEventType.missionCompleted,
            sourceId: missionId,
            pointsAwarded: mission.rewardPoints,
            metadata: {
              'mission_title': mission.title,
              'mission_type': mission.missionType.value,
            },
          ),
        );
      }
    }

    return progress;
  }

  /// Get a single mission by ID.
  Future<CoolMission?> _getMission(String missionId) async {
    final row = await _client
        .from('cool_missions')
        .select()
        .eq('id', missionId)
        .maybeSingle();

    return row != null ? CoolMission.fromJson(row) : null;
  }

  /// Get user's progress for a specific mission.
  Future<CoolMissionProgress?> getUserProgress({
    required String missionId,
    required String userId,
  }) async {
    final row = await _client
        .from('cool_mission_progress')
        .select()
        .eq('mission_id', missionId)
        .eq('user_id', userId)
        .maybeSingle();

    return row != null ? CoolMissionProgress.fromJson(row) : null;
  }
}
