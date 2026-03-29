part of 'rs_models.dart';

// ═══════════════════════════════════════════════════════════════════════
// Fan Engagement — Polls, Predictions, AI Commentary, Leaderboard
// ═══════════════════════════════════════════════════════════════════════

// ── Poll Types ────────────────────────────────────────────────────────

enum PollType {
  scorePrediction,
  motm,
  fanMood,
  custom;

  static PollType fromValue(String? value) {
    return switch ((value ?? '').toLowerCase()) {
      'score_prediction' => PollType.scorePrediction,
      'motm' => PollType.motm,
      'fan_mood' => PollType.fanMood,
      _ => PollType.custom,
    };
  }

  String get value => switch (this) {
    PollType.scorePrediction => 'score_prediction',
    PollType.motm => 'motm',
    PollType.fanMood => 'fan_mood',
    PollType.custom => 'custom',
  };

  String get label => switch (this) {
    PollType.scorePrediction => 'Score Prediction',
    PollType.motm => 'Man of the Match',
    PollType.fanMood => 'Fan Mood',
    PollType.custom => 'Poll',
  };

  String get emoji => switch (this) {
    PollType.scorePrediction => '⚽',
    PollType.motm => '🌟',
    PollType.fanMood => '🔥',
    PollType.custom => '📊',
  };
}

enum CommentaryType {
  preview,
  recap,
  highlight;

  static CommentaryType fromValue(String? value) {
    return switch ((value ?? '').toLowerCase()) {
      'preview' => CommentaryType.preview,
      'highlight' => CommentaryType.highlight,
      _ => CommentaryType.recap,
    };
  }

  String get value => name;

  String get label => switch (this) {
    CommentaryType.preview => 'Match Preview',
    CommentaryType.recap => 'Post-Match Recap',
    CommentaryType.highlight => 'Highlight Reel',
  };

  String get emoji => switch (this) {
    CommentaryType.preview => '📋',
    CommentaryType.recap => '📝',
    CommentaryType.highlight => '🎬',
  };
}

// ── Match Poll ────────────────────────────────────────────────────────

class RsMatchPoll extends Equatable {
  const RsMatchPoll({
    required this.id,
    required this.matchId,
    required this.pollType,
    required this.question,
    required this.options,
    required this.isActive,
    this.closesAt,
    required this.createdAt,
  });

  final String id;
  final String matchId;
  final PollType pollType;
  final String question;
  final List<String> options;
  final bool isActive;
  final DateTime? closesAt;
  final DateTime createdAt;

  bool get isClosed {
    if (!isActive) return true;
    if (closesAt != null && DateTime.now().isAfter(closesAt!)) return true;
    return false;
  }

  factory RsMatchPoll.fromJson(RsJsonMap json) {
    final rawOptions = json['options'];
    List<String> parsedOptions;
    if (rawOptions is List) {
      parsedOptions = rawOptions.map((e) => e.toString()).toList();
    } else {
      parsedOptions = const <String>[];
    }

    return RsMatchPoll(
      id: _asString(json['id']),
      matchId: _asString(json['match_id']),
      pollType: PollType.fromValue(json['poll_type']?.toString()),
      question: _asString(json['question']),
      options: parsedOptions,
      isActive: _asBool(json['is_active'], fallback: true),
      closesAt: _asDateTime(json['closes_at']),
      createdAt: _asDateTime(json['created_at']) ?? DateTime.now(),
    );
  }

  RsJsonMap toJson() => <String, Object?>{
    'id': id,
    'match_id': matchId,
    'poll_type': pollType.value,
    'question': question,
    'options': options,
    'is_active': isActive,
    'closes_at': closesAt?.toIso8601String(),
  };

  @override
  List<Object?> get props => [id, matchId, pollType, question, options, isActive, closesAt];
}

// ── Poll Vote ─────────────────────────────────────────────────────────

class RsPollVote extends Equatable {
  const RsPollVote({
    required this.id,
    required this.pollId,
    required this.selectedOption,
    required this.createdAt,
  });

  final String id;
  final String pollId;
  final String selectedOption;
  final DateTime createdAt;

  factory RsPollVote.fromJson(RsJsonMap json) {
    return RsPollVote(
      id: _asString(json['id']),
      pollId: _asString(json['poll_id']),
      selectedOption: _asString(json['selected_option']),
      createdAt: _asDateTime(json['created_at']) ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, pollId, selectedOption];
}

// ── Poll Result ───────────────────────────────────────────────────────

class RsPollResult extends Equatable {
  const RsPollResult({
    required this.option,
    required this.voteCount,
    required this.percentage,
  });

  final String option;
  final int voteCount;
  final double percentage;

  factory RsPollResult.fromJson(RsJsonMap json) {
    return RsPollResult(
      option: _asString(json['selected_option']),
      voteCount: _asInt(json['vote_count']),
      percentage: _asDouble(json['percentage']),
    );
  }

  @override
  List<Object?> get props => [option, voteCount, percentage];
}

// ── Match Prediction ──────────────────────────────────────────────────

class RsMatchPrediction extends Equatable {
  const RsMatchPrediction({
    required this.id,
    required this.matchId,
    required this.predictedHomeScore,
    required this.predictedAwayScore,
    this.predictedMotm,
    this.xpAwarded = 0,
    this.isCorrect,
    required this.createdAt,
  });

  final String id;
  final String matchId;
  final int predictedHomeScore;
  final int predictedAwayScore;
  final String? predictedMotm;
  final int xpAwarded;
  final bool? isCorrect;
  final DateTime createdAt;

  String get scoreDisplay => '$predictedHomeScore – $predictedAwayScore';

  factory RsMatchPrediction.fromJson(RsJsonMap json) {
    return RsMatchPrediction(
      id: _asString(json['id']),
      matchId: _asString(json['match_id']),
      predictedHomeScore: _asInt(json['predicted_home_score']),
      predictedAwayScore: _asInt(json['predicted_away_score']),
      predictedMotm: _asNullableString(json['predicted_motm']),
      xpAwarded: _asInt(json['xp_awarded']),
      isCorrect: json['is_correct'] == null ? null : _asBool(json['is_correct']),
      createdAt: _asDateTime(json['created_at']) ?? DateTime.now(),
    );
  }

  RsJsonMap toJson() => <String, Object?>{
    'match_id': matchId,
    'predicted_home_score': predictedHomeScore,
    'predicted_away_score': predictedAwayScore,
    'predicted_motm': predictedMotm,
  };

  @override
  List<Object?> get props => [
    id, matchId, predictedHomeScore, predictedAwayScore,
    predictedMotm, xpAwarded, isCorrect,
  ];
}

// ── Match Commentary ──────────────────────────────────────────────────

class RsMatchCommentary extends Equatable {
  const RsMatchCommentary({
    required this.id,
    required this.matchId,
    required this.commentaryType,
    required this.title,
    required this.body,
    this.metadata = const <String, Object?>{},
    required this.isPublished,
    required this.createdAt,
  });

  final String id;
  final String matchId;
  final CommentaryType commentaryType;
  final String title;
  final String body;
  final RsJsonMap metadata;
  final bool isPublished;
  final DateTime createdAt;

  factory RsMatchCommentary.fromJson(RsJsonMap json) {
    return RsMatchCommentary(
      id: _asString(json['id']),
      matchId: _asString(json['match_id']),
      commentaryType: CommentaryType.fromValue(json['commentary_type']?.toString()),
      title: _asString(json['title']),
      body: _asString(json['body']),
      metadata: _asMap(json['metadata']),
      isPublished: _asBool(json['is_published']),
      createdAt: _asDateTime(json['created_at']) ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, matchId, commentaryType, title, isPublished];
}

// ── Fan Leaderboard Entry ─────────────────────────────────────────────

class RsFanLeaderboardEntry extends Equatable {
  const RsFanLeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.totalXp,
    required this.predictionCount,
    required this.correctCount,
  });

  final int rank;
  final String userId;
  final int totalXp;
  final int predictionCount;
  final int correctCount;

  double get accuracy =>
      predictionCount > 0 ? (correctCount / predictionCount) * 100 : 0;

  FanTier get tier => FanTierX.fromPoints(totalXp);

  factory RsFanLeaderboardEntry.fromJson(RsJsonMap json) {
    return RsFanLeaderboardEntry(
      rank: _asInt(json['rank'], fallback: 0),
      userId: _asString(json['user_id']),
      totalXp: _asInt(json['total_xp']),
      predictionCount: _asInt(json['prediction_count']),
      correctCount: _asInt(json['correct_count']),
    );
  }

  @override
  List<Object?> get props => [rank, userId, totalXp, predictionCount, correctCount];
}
