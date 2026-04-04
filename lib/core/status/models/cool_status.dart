import 'package:equatable/equatable.dart';

import 'package:flutter/material.dart'; // For colors in extension

/// The generic progression tier system for COOL applications.
enum CoolTier {
  member,
  silver,
  gold,
  platinum;

  String get value => name;

  String get label => switch (this) {
    CoolTier.member => 'Member',
    CoolTier.silver => 'Silver',
    CoolTier.gold => 'Gold',
    CoolTier.platinum => 'Platinum',
  };

  int get minPoints => switch (this) {
    CoolTier.member => 0,
    CoolTier.silver => 100,
    CoolTier.gold => 300,
    CoolTier.platinum => 500,
  };

  Color get color => switch (this) {
    CoolTier.member => const Color(0xFF6B7280),
    CoolTier.silver => const Color(0xFF9CA3AF),
    CoolTier.gold => const Color(0xFFFBBF24),
    CoolTier.platinum => const Color(0xFFE5E7EB),
  };
}

extension CoolTierX on CoolTier {
  static CoolTier fromValue(String? value) {
    if (value == null) return CoolTier.member;
    return CoolTier.values.firstWhere(
      (e) => e.value.toLowerCase() == value.toLowerCase(),
      orElse: () => CoolTier.member,
    );
  }

  static CoolTier fromPoints(int points) {
    if (points >= CoolTier.platinum.minPoints) return CoolTier.platinum;
    if (points >= CoolTier.gold.minPoints) return CoolTier.gold;
    if (points >= CoolTier.silver.minPoints) return CoolTier.silver;
    return CoolTier.member;
  }
}

/// Unified cross-app status for a user.
class CoolStatus extends Equatable {
  const CoolStatus({
    required this.id,
    required this.userId,
    required this.totalPoints,
    required this.tier,
    required this.currentStreak,
    required this.longestStreak,
    required this.streakGraceRemaining,
    required this.seasonPoints,
    this.activeSeasonId,
    required this.updatedAt,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final int totalPoints;
  final CoolTier tier;
  final int currentStreak;
  final int longestStreak;
  final int streakGraceRemaining;
  final int seasonPoints;
  final String? activeSeasonId;
  final DateTime updatedAt;
  final DateTime createdAt;

  // ─── Progress helpers ───────────────────────────────────────────

  int get nextTierPoints => switch (tier) {
    CoolTier.member => CoolTier.silver.minPoints,
    CoolTier.silver => CoolTier.gold.minPoints,
    CoolTier.gold => CoolTier.platinum.minPoints,
    CoolTier.platinum => totalPoints,
  };

  int get pointsToNextTier => switch (tier) {
    CoolTier.platinum => 0,
    _ => (nextTierPoints - totalPoints).clamp(0, nextTierPoints),
  };

  double get progressToNextTier {
    if (tier == CoolTier.platinum) return 1;
    final floor = tier.minPoints;
    final span = nextTierPoints - floor;
    if (span <= 0) return 1;
    return ((totalPoints - floor) / span).clamp(0, 1).toDouble();
  }

  bool get hasStreak => currentStreak > 0;

  // ─── Serialization ──────────────────────────────────────────────

  factory CoolStatus.fromJson(Map<String, dynamic> json) {
    final points = _asInt(json['total_points']);
    final tier = json['tier'] == null
        ? CoolTierX.fromPoints(points)
        : CoolTierX.fromValue(json['tier']?.toString());

    return CoolStatus(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      totalPoints: points,
      tier: tier,
      currentStreak: _asInt(json['current_streak']),
      longestStreak: _asInt(json['longest_streak']),
      streakGraceRemaining: _asInt(json['streak_grace_remaining'], fallback: 1),
      seasonPoints: _asInt(json['season_points']),
      activeSeasonId: json['active_season_id']?.toString(),
      updatedAt: _asDateTime(json['updated_at']) ?? DateTime.now(),
      createdAt: _asDateTime(json['created_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'total_points': totalPoints,
    'tier': tier.value,
    'current_streak': currentStreak,
    'longest_streak': longestStreak,
    'streak_grace_remaining': streakGraceRemaining,
    'season_points': seasonPoints,
    'active_season_id': activeSeasonId,
    'updated_at': updatedAt.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  // ─── Default (new user) ─────────────────────────────────────────

  factory CoolStatus.empty(String userId) => CoolStatus(
    id: '',
    userId: userId,
    totalPoints: 0,
    tier: CoolTier.member,
    currentStreak: 0,
    longestStreak: 0,
    streakGraceRemaining: 1,
    seasonPoints: 0,
    updatedAt: DateTime.now(),
    createdAt: DateTime.now(),
  );

  @override
  List<Object?> get props => [
    id,
    userId,
    totalPoints,
    tier,
    currentStreak,
    longestStreak,
    streakGraceRemaining,
    seasonPoints,
    activeSeasonId,
    updatedAt,
    createdAt,
  ];
}

// ─── Parsing helpers (match rs_models.dart pattern) ───────────────

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
