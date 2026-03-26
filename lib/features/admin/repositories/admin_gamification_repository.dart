import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/status/models/cool_activity.dart';
import '../../../core/status/models/cool_mission.dart';
import '../../../core/status/models/cool_season.dart';

/// Admin CRUD repository for missions and seasons.
class AdminGamificationRepository {
  AdminGamificationRepository({required SupabaseClient client})
    : _client = client;

  final SupabaseClient _client;

  // ═══════════════════════════════════════════════════════════════════
  // MISSIONS
  // ═══════════════════════════════════════════════════════════════════

  /// List all missions (newest first).
  Future<List<CoolMission>> listMissions() async {
    final rows = await _client
        .from('cool_missions')
        .select()
        .order('created_at', ascending: false);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(CoolMission.fromJson)
        .toList(growable: false);
  }

  /// Insert or update a mission. Pass `id` in data for update, omit for insert.
  Future<void> upsertMission(Map<String, dynamic> data) async {
    if (data['id'] != null && data['id'].toString().isNotEmpty) {
      final id = data['id'].toString();
      final updateData = Map<String, dynamic>.from(data)..remove('id');
      await _client.from('cool_missions').update(updateData).eq('id', id);
    } else {
      final insertData = Map<String, dynamic>.from(data)..remove('id');
      await _client.from('cool_missions').insert(insertData);
    }
  }

  /// Toggle mission active status.
  Future<void> toggleMissionActive(String id, {required bool isActive}) async {
    await _client
        .from('cool_missions')
        .update({'is_active': isActive})
        .eq('id', id);
  }

  /// Delete a mission by ID.
  Future<void> deleteMission(String id) async {
    await _client.from('cool_missions').delete().eq('id', id);
  }

  // ═══════════════════════════════════════════════════════════════════
  // SEASONS
  // ═══════════════════════════════════════════════════════════════════

  /// List all seasons (newest first).
  Future<List<CoolSeason>> listSeasons() async {
    final rows = await _client
        .from('cool_seasons')
        .select()
        .order('starts_at', ascending: false);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(CoolSeason.fromJson)
        .toList(growable: false);
  }

  /// Insert or update a season. Pass `id` in data for update, omit for insert.
  Future<void> upsertSeason(Map<String, dynamic> data) async {
    if (data['id'] != null && data['id'].toString().isNotEmpty) {
      final id = data['id'].toString();
      final updateData = Map<String, dynamic>.from(data)..remove('id');
      await _client.from('cool_seasons').update(updateData).eq('id', id);
    } else {
      final insertData = Map<String, dynamic>.from(data)..remove('id');
      await _client.from('cool_seasons').insert(insertData);
    }
  }

  /// Toggle season active status.
  Future<void> toggleSeasonActive(String id, {required bool isActive}) async {
    await _client
        .from('cool_seasons')
        .update({'is_active': isActive})
        .eq('id', id);
  }

  /// Delete a season by ID.
  Future<void> deleteSeason(String id) async {
    await _client.from('cool_seasons').delete().eq('id', id);
  }

  // ═══════════════════════════════════════════════════════════════════
  // ACTIVITIES
  // ═══════════════════════════════════════════════════════════════════

  /// List all activities (by sort_order).
  Future<List<CoolActivity>> listActivities() async {
    final rows = await _client
        .from('cool_activities')
        .select()
        .order('sort_order', ascending: true);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(CoolActivity.fromJson)
        .toList(growable: false);
  }

  /// Insert or update an activity.
  Future<void> upsertActivity(Map<String, dynamic> data) async {
    if (data['id'] != null && data['id'].toString().isNotEmpty) {
      final id = data['id'].toString();
      final updateData = Map<String, dynamic>.from(data)
        ..remove('id')
        ..['updated_at'] = DateTime.now().toIso8601String();
      await _client.from('cool_activities').update(updateData).eq('id', id);
    } else {
      final insertData = Map<String, dynamic>.from(data)..remove('id');
      await _client.from('cool_activities').insert(insertData);
    }
  }

  /// Toggle activity active/inactive.
  Future<void> toggleActivityActive(String id, {required bool isActive}) async {
    await _client
        .from('cool_activities')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  /// Delete an activity by ID.
  Future<void> deleteActivity(String id) async {
    await _client.from('cool_activities').delete().eq('id', id);
  }
}
