import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cool_event.dart';
import '../models/cool_status.dart';

/// Data access for the unified COOL Status system.
///
/// All reads/writes go through Supabase with RLS enforced.
class CoolStatusRepository {
  CoolStatusRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  // ─── Status CRUD ────────────────────────────────────────────────

  /// Fetch the current user's status, or create a default row if none exists.
  Future<CoolStatus> getOrCreateStatus(String userId) async {
    final existing = await _client
        .from('cool_status')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) {
      return CoolStatus.fromJson(existing);
    }

    // First access — seed an initial row
    final inserted = await _client
        .from('cool_status')
        .insert({'user_id': userId})
        .select()
        .single();

    return CoolStatus.fromJson(inserted);
  }

  /// Log an event and award points. Returns the updated [CoolStatus].
  Future<CoolStatus> logEvent(CoolEvent event) async {
    final updated = await _client.rpc(
      'apply_cool_event',
      params: <String, dynamic>{
        'p_user_id': event.userId,
        'p_event_type': event.eventType.value,
        'p_points': event.pointsAwarded,
        'p_source_id': event.sourceId,
        'p_metadata': event.metadata,
        'p_referrer_id': event.referrerId,
        'p_dedupe_key': event.dedupeKey,
        'p_campaign_id': event.campaignId,
        'p_season_id': event.seasonId,
      },
    );

    return CoolStatus.fromJson(Map<String, dynamic>.from(updated as Map));
  }

  /// Record a double-sided invite attribution.
  ///
  /// Called when the invitee completes their first qualifying action.
  Future<void> attributeInvite({
    required String inviterId,
    required String inviteeId,
    required CoolEventType qualifyingEventType,
    String? qualifyingEventId,
    int inviterBonus = 150,
    int inviteeBonus = 50,
  }) async {
    // Insert attribution row (idempotent via UNIQUE constraint)
    await _client.from('cool_invite_attributions').upsert({
      'inviter_id': inviterId,
      'invitee_id': inviteeId,
      'qualifying_event_type': qualifyingEventType.value,
      'qualifying_event_id': qualifyingEventId,
      'points_awarded_inviter': inviterBonus,
      'points_awarded_invitee': inviteeBonus,
    }, onConflict: 'inviter_id,invitee_id');

    // Award bonus points to inviter
    await logEvent(
      CoolEvent(
        userId: inviterId,
        eventType: CoolEventType.inviteQualified,
        sourceId: inviteeId,
        pointsAwarded: inviterBonus,
        dedupeKey: 'inviteQualified:$inviterId:$inviteeId',
        metadata: {
          'invitee_id': inviteeId,
          'qualifying_event': qualifyingEventType.value,
        },
      ),
    );
  }

  /// Fetch recent events for the current user (for activity feed / history).
  Future<List<CoolEvent>> getRecentEvents(
    String userId, {
    int limit = 20,
  }) async {
    final rows = await _client
        .from('cool_events')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(CoolEvent.fromJson)
        .toList(growable: false);
  }

  /// Increment streak (called on weekly check or qualifying action).
  Future<CoolStatus> maintainStreak(String userId) async {
    final status = await getOrCreateStatus(userId);
    final newStreak = status.currentStreak + 1;
    final newLongest = newStreak > status.longestStreak
        ? newStreak
        : status.longestStreak;

    final updated = await _client
        .from('cool_status')
        .update({
          'current_streak': newStreak,
          'longest_streak': newLongest,
          'streak_grace_remaining': 1, // Reset grace on successful streak
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('user_id', userId)
        .select()
        .single();

    return CoolStatus.fromJson(updated);
  }

  /// Use a streak grace day instead of breaking the streak.
  Future<CoolStatus> useStreakGrace(String userId) async {
    final status = await getOrCreateStatus(userId);

    if (status.streakGraceRemaining <= 0) {
      // No grace left — break streak
      final updated = await _client
          .from('cool_status')
          .update({
            'current_streak': 0,
            'streak_grace_remaining': 1,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId)
          .select()
          .single();
      return CoolStatus.fromJson(updated);
    }

    // Use grace
    final updated = await _client
        .from('cool_status')
        .update({
          'streak_grace_remaining': status.streakGraceRemaining - 1,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('user_id', userId)
        .select()
        .single();
    return CoolStatus.fromJson(updated);
  }
}
