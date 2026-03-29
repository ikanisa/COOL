import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rs_models.dart';
import '../repositories/rayon_sports_repository.dart';
import 'rayon_sports_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// Fan Engagement Providers — Polls, Predictions, Commentary, Leaderboard
// ═══════════════════════════════════════════════════════════════════════

/// Active polls for a given match.
final matchPollsProvider = FutureProvider.autoDispose
    .family<List<RsMatchPoll>, String>((ref, matchId) async {
      final repo = ref.read(rayonSportsRepositoryProvider);
      return repo.getMatchPolls(matchId);
    });

/// Aggregated results for a given poll.
final pollResultsProvider = FutureProvider.autoDispose
    .family<List<RsPollResult>, String>((ref, pollId) async {
      final repo = ref.read(rayonSportsRepositoryProvider);
      return repo.getPollResults(pollId);
    });

/// Current user's vote for a poll.
final myPollVoteProvider = FutureProvider.autoDispose
    .family<RsPollVote?, String>((ref, pollId) async {
      final repo = ref.read(rayonSportsRepositoryProvider);
      return repo.getMyVote(pollId);
    });

/// Current user's prediction for a match.
final myPredictionProvider = FutureProvider.autoDispose
    .family<RsMatchPrediction?, String>((ref, matchId) async {
      final repo = ref.read(rayonSportsRepositoryProvider);
      return repo.getMyPrediction(matchId);
    });

/// Published AI commentary for a match.
final matchCommentaryProvider = FutureProvider.autoDispose
    .family<List<RsMatchCommentary>, String>((ref, matchId) async {
      final repo = ref.read(rayonSportsRepositoryProvider);
      return repo.getMatchCommentary(matchId);
    });

/// Global fan leaderboard (top fans by prediction XP).
final fanLeaderboardProvider =
    FutureProvider.autoDispose<List<RsFanLeaderboardEntry>>((ref) async {
      final repo = ref.read(rayonSportsRepositoryProvider);
      return repo.getFanLeaderboard(limit: 50);
    });
