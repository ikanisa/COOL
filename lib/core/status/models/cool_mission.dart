import 'package:equatable/equatable.dart';

/// Types of cooperative missions.
enum CoolMissionType {
  savingsSprint,     // group reaches X total contributions
  supporterSeason,   // chapter reaches Y initiative support
  commuterWeek,      // mobility circle completes Z reliable trips
  matchdayMonth,     // attend N matches in a month
}

extension CoolMissionTypeX on CoolMissionType {
  String get value => name;

  static CoolMissionType fromValue(String? value) {
    final normalized = (value ?? '').trim();
    return switch (normalized) {
      'savings_sprint' || 'savingsSprint'     => CoolMissionType.savingsSprint,
      'supporter_season' || 'supporterSeason' => CoolMissionType.supporterSeason,
      'commuter_week' || 'commuterWeek'       => CoolMissionType.commuterWeek,
      'matchday_month' || 'matchdayMonth'     => CoolMissionType.matchdayMonth,
      _ => CoolMissionType.savingsSprint,
    };
  }

  String get displayLabel => switch (this) {
    CoolMissionType.savingsSprint   => 'Savings Sprint',
    CoolMissionType.supporterSeason => 'Supporter Season',
    CoolMissionType.commuterWeek    => 'Commuter Week',
    CoolMissionType.matchdayMonth   => 'Matchday Month',
  };

  String get defaultEmoji => switch (this) {
    CoolMissionType.savingsSprint   => '💰',
    CoolMissionType.supporterSeason => '🤝',
    CoolMissionType.commuterWeek    => '🚗',
    CoolMissionType.matchdayMonth   => '⚽',
  };
}

/// Scope for mission participation.
enum MissionScope {
  group,    // single group
  chapter,  // fan club chapter
  global,   // everyone
}

extension MissionScopeX on MissionScope {
  String get value => name;

  static MissionScope fromValue(String? value) {
    return switch ((value ?? '').trim().toLowerCase()) {
      'group'   => MissionScope.group,
      'chapter' => MissionScope.chapter,
      _         => MissionScope.global,
    };
  }
}

/// A cooperative, time-bound mission.
class CoolMission extends Equatable {
  const CoolMission({
    required this.id,
    this.seasonId,
    required this.title,
    this.description,
    required this.missionType,
    required this.targetValue,
    required this.scope,
    this.scopeId,
    required this.emoji,
    required this.startsAt,
    required this.endsAt,
    required this.rewardPoints,
    this.rewardDescription,
    required this.isActive,
    this.userProgress,
    this.totalProgress,
  });

  final String id;
  final String? seasonId;
  final String title;
  final String? description;
  final CoolMissionType missionType;
  final int targetValue;
  final MissionScope scope;
  final String? scopeId;
  final String emoji;
  final DateTime startsAt;
  final DateTime endsAt;
  final int rewardPoints;
  final String? rewardDescription;
  final bool isActive;

  /// Current user's contribution toward this mission.
  final int? userProgress;

  /// Aggregate progress (all participants) — only available for group/chapter scope.
  final int? totalProgress;

  // ─── Computed helpers ───────────────────────────────────────────

  bool get isExpired => DateTime.now().isAfter(endsAt);
  bool get isUpcoming => DateTime.now().isBefore(startsAt);
  bool get isLive => isActive && !isExpired && !isUpcoming;

  Duration get timeRemaining {
    final now = DateTime.now();
    return endsAt.isAfter(now) ? endsAt.difference(now) : Duration.zero;
  }

  double get progressPercent {
    if (targetValue <= 0) return 0;
    final progress = totalProgress ?? userProgress ?? 0;
    return (progress / targetValue).clamp(0, 1).toDouble();
  }

  bool get isCompleted => progressPercent >= 1.0;

  String get timeRemainingLabel {
    final remaining = timeRemaining;
    if (remaining == Duration.zero) return 'Ended';
    if (remaining.inDays > 0) return '${remaining.inDays}d left';
    if (remaining.inHours > 0) return '${remaining.inHours}h left';
    return '${remaining.inMinutes}m left';
  }

  // ─── Serialization ──────────────────────────────────────────────

  factory CoolMission.fromJson(Map<String, dynamic> json) {
    return CoolMission(
      id: (json['id'] ?? '').toString(),
      seasonId: json['season_id']?.toString(),
      title: (json['title'] ?? 'Mission').toString(),
      description: json['description']?.toString(),
      missionType: CoolMissionTypeX.fromValue(json['mission_type']?.toString()),
      targetValue: _asInt(json['target_value']),
      scope: MissionScopeX.fromValue(json['scope_type']?.toString()),
      scopeId: json['scope_id']?.toString(),
      emoji: (json['emoji'] ?? '🎯').toString(),
      startsAt: _asDateTime(json['starts_at']) ?? DateTime.now(),
      endsAt: _asDateTime(json['ends_at']) ?? DateTime.now(),
      rewardPoints: _asInt(json['reward_points']),
      rewardDescription: json['reward_description']?.toString(),
      isActive: _asBool(json['is_active']),
      userProgress: json['user_progress'] != null
          ? _asInt(json['user_progress'])
          : null,
      totalProgress: json['total_progress'] != null
          ? _asInt(json['total_progress'])
          : null,
    );
  }

  @override
  List<Object?> get props => [
    id, seasonId, title, description, missionType, targetValue,
    scope, scopeId, emoji, startsAt, endsAt, rewardPoints,
    rewardDescription, isActive, userProgress, totalProgress,
  ];
}

/// A user's progress toward a specific mission.
class CoolMissionProgress extends Equatable {
  const CoolMissionProgress({
    required this.id,
    required this.missionId,
    required this.userId,
    required this.contributionValue,
    this.completedAt,
  });

  final String id;
  final String missionId;
  final String userId;
  final int contributionValue;
  final DateTime? completedAt;

  bool get isCompleted => completedAt != null;

  factory CoolMissionProgress.fromJson(Map<String, dynamic> json) {
    return CoolMissionProgress(
      id: (json['id'] ?? '').toString(),
      missionId: (json['mission_id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      contributionValue: _asInt(json['contribution_value']),
      completedAt: _asDateTime(json['completed_at']),
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'mission_id': missionId,
    'user_id': userId,
    'contribution_value': contributionValue,
  };

  @override
  List<Object?> get props => [id, missionId, userId, contributionValue, completedAt];
}

// ─── Parsing helpers ──────────────────────────────────────────────

int _asInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

DateTime? _asDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

bool _asBool(dynamic value, {bool fallback = true}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  final s = value.toString().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes';
}
