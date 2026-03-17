import 'package:equatable/equatable.dart';

import '../../../features/partners/rayon/models/rs_models.dart';

/// A single row in the Cool Tokens leaderboard.
class LeaderboardEntry extends Equatable {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.totalPoints,
    required this.tier,
  });

  final int rank;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int totalPoints;
  final FanTier tier;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json, int rank) {
    final points = _asInt(json['total_points']);
    return LeaderboardEntry(
      rank: rank,
      userId: (json['user_id'] ?? '').toString(),
      displayName: _displayName(json),
      avatarUrl: json['avatar_url']?.toString(),
      totalPoints: points,
      tier: json['tier'] != null
          ? FanTierX.fromValue(json['tier']?.toString())
          : FanTierX.fromPoints(points),
    );
  }

  @override
  List<Object?> get props => [rank, userId, totalPoints, tier];
}

String _displayName(Map<String, dynamic> json) {
  // Try profile fields first, then fall back to user_id prefix
  final first = (json['first_name'] ?? json['display_name'] ?? '')
      .toString()
      .trim();
  if (first.isNotEmpty) return first;
  final userId = (json['user_id'] ?? '').toString();
  return userId.length > 6 ? 'User ${userId.substring(0, 6)}' : 'User';
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}
