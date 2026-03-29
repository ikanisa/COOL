part of 'rayon_sports_repository.dart';

// ═══════════════════════════════════════════════════════════════════════
// Fan Engagement Repository — Polls, Predictions, Commentary, Leaderboard
// ═══════════════════════════════════════════════════════════════════════

extension RayonSportsEngagementRepository on RayonSportsRepository {

  // ── Polls ───────────────────────────────────────────────────────────

  /// Fetch active polls for a given match.
  Future<List<RsMatchPoll>> getMatchPolls(String matchId) async {
    final rows = await _client
        .from('rs_match_polls')
        .select()
        .eq('match_id', matchId)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((r) => RsMatchPoll.fromJson(Map<String, Object?>.from(r as Map)))
        .toList(growable: false);
  }

  /// Get the current user's vote for a poll (null if not voted).
  Future<RsPollVote?> getMyVote(String pollId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final rows = await _client
        .from('rs_poll_votes')
        .select()
        .eq('poll_id', pollId)
        .eq('user_id', userId)
        .limit(1);

    final list = rows as List;
    if (list.isEmpty) return null;
    return RsPollVote.fromJson(Map<String, Object?>.from(list.first as Map));
  }

  /// Submit a vote. Upserts (on conflict updates the selected option).
  Future<void> submitPollVote(String pollId, String option) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Authentication required');

    await _client.from('rs_poll_votes').upsert(
      {
        'poll_id': pollId,
        'user_id': userId,
        'selected_option': option,
      },
      onConflict: 'poll_id,user_id',
    );
  }

  /// Fetch aggregated poll results via RPC.
  Future<List<RsPollResult>> getPollResults(String pollId) async {
    final rows = await _client.rpc(
      'get_poll_results',
      params: {'p_poll_id': pollId},
    );

    return (rows as List)
        .map((r) => RsPollResult.fromJson(Map<String, Object?>.from(r as Map)))
        .toList(growable: false);
  }

  // ── Predictions ─────────────────────────────────────────────────────

  /// Get the current user's prediction for a match.
  Future<RsMatchPrediction?> getMyPrediction(String matchId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final rows = await _client
        .from('rs_match_predictions')
        .select()
        .eq('match_id', matchId)
        .eq('user_id', userId)
        .limit(1);

    final list = rows as List;
    if (list.isEmpty) return null;
    return RsMatchPrediction.fromJson(
      Map<String, Object?>.from(list.first as Map),
    );
  }

  /// Submit a score + MOTM prediction. Upserts on conflict.
  Future<void> submitPrediction({
    required String matchId,
    required int homeScore,
    required int awayScore,
    String? motm,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Authentication required');

    await _client.from('rs_match_predictions').upsert(
      {
        'match_id': matchId,
        'user_id': userId,
        'predicted_home_score': homeScore,
        'predicted_away_score': awayScore,
        'predicted_motm': motm,
      },
      onConflict: 'match_id,user_id',
    );
  }

  // ── Commentary ──────────────────────────────────────────────────────

  /// Get published commentary for a match.
  Future<List<RsMatchCommentary>> getMatchCommentary(String matchId) async {
    final rows = await _client
        .from('rs_match_commentary')
        .select()
        .eq('match_id', matchId)
        .eq('is_published', true)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((r) =>
            RsMatchCommentary.fromJson(Map<String, Object?>.from(r as Map)))
        .toList(growable: false);
  }

  // ── Leaderboard ─────────────────────────────────────────────────────

  /// Global fan leaderboard via RPC.
  Future<List<RsFanLeaderboardEntry>> getFanLeaderboard({
    int limit = 20,
    int offset = 0,
  }) async {
    final rows = await _client.rpc(
      'get_fan_leaderboard',
      params: {'p_limit': limit, 'p_offset': offset},
    );

    return (rows as List)
        .map((r) => RsFanLeaderboardEntry.fromJson(
              Map<String, Object?>.from(r as Map),
            ))
        .toList(growable: false);
  }

  // ── Admin: Polls ────────────────────────────────────────────────────

  /// Create a new poll for a match.
  Future<RsMatchPoll> createPoll({
    required String matchId,
    required PollType pollType,
    required String question,
    required List<String> options,
    DateTime? closesAt,
  }) async {
    final rows = await _client
        .from('rs_match_polls')
        .insert({
          'match_id': matchId,
          'poll_type': pollType.value,
          'question': question,
          'options': options,
          'closes_at': closesAt?.toIso8601String(),
        })
        .select();

    return RsMatchPoll.fromJson(
      Map<String, Object?>.from((rows as List).first as Map),
    );
  }

  /// Toggle poll active state.
  Future<void> togglePollActive(String pollId, {required bool isActive}) async {
    await _client
        .from('rs_match_polls')
        .update({'is_active': isActive})
        .eq('id', pollId);
  }

  /// Delete a poll.
  Future<void> deletePoll(String pollId) async {
    await _client.from('rs_match_polls').delete().eq('id', pollId);
  }

  // ── Admin: Award XP ─────────────────────────────────────────────────

  /// Award prediction XP for a match by calling the RPC.
  Future<int> awardPredictionXp({
    required String matchId,
    required int homeScore,
    required int awayScore,
  }) async {
    final result = await _client.rpc(
      'award_prediction_xp',
      params: {
        'p_match_id': matchId,
        'p_home_score': homeScore,
        'p_away_score': awayScore,
      },
    );
    return (result as num?)?.toInt() ?? 0;
  }

  // ── Admin: Commentary ───────────────────────────────────────────────

  /// Create AI commentary entry.
  Future<RsMatchCommentary> createCommentary({
    required String matchId,
    required CommentaryType type,
    required String title,
    required String body,
    Map<String, Object?>? metadata,
    bool isPublished = false,
  }) async {
    final rows = await _client
        .from('rs_match_commentary')
        .insert({
          'match_id': matchId,
          'commentary_type': type.value,
          'title': title,
          'body': body,
          'metadata': metadata ?? {},
          'is_published': isPublished,
        })
        .select();

    return RsMatchCommentary.fromJson(
      Map<String, Object?>.from((rows as List).first as Map),
    );
  }

  /// Publish a commentary entry.
  Future<void> publishCommentary(String commentaryId) async {
    await _client
        .from('rs_match_commentary')
        .update({'is_published': true})
        .eq('id', commentaryId);
  }

  // ── Admin: Roster ───────────────────────────────────────────────────

  /// Update the player roster for a match (used for MOTM picks).
  Future<void> updateMatchRoster(String matchId, List<String> roster) async {
    await _client
        .from('rs_matches')
        .update({'roster': roster})
        .eq('id', matchId);
  }
}
