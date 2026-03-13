part of 'rs_models.dart';

class RsAchievement extends Equatable {
  const RsAchievement({
    required this.id,
    required this.userId,
    required this.badgeType,
    required this.emoji,
    required this.name,
    required this.description,
    required this.isEarned,
    required this.earnedAt,
  });

  final String id;
  final String userId;
  final String badgeType;
  final String emoji;
  final String name;
  final String description;
  final bool isEarned;
  final DateTime? earnedAt;

  factory RsAchievement.fromJson(RsJsonMap json) {
    final earnedAt = _asDateTime(json['earned_at'] ?? json['earnedAt']);

    return RsAchievement(
      id: _asString(json['id']),
      userId: _asString(json['user_id'] ?? json['userId']),
      badgeType: _asString(json['badge_type'] ?? json['badgeType']),
      emoji: _asString(json['emoji'], fallback: '🏆'),
      name: _asString(json['name'], fallback: 'Achievement'),
      description: _asString(json['description']),
      isEarned: _asBool(
        json['is_earned'] ?? json['isEarned'],
        fallback: earnedAt != null,
      ),
      earnedAt: earnedAt,
    );
  }

  RsJsonMap toJson() {
    return <String, Object?>{
      'id': id,
      'user_id': userId,
      'badge_type': badgeType,
      'emoji': emoji,
      'name': name,
      'description': description,
      'is_earned': isEarned,
      'earned_at': earnedAt?.toIso8601String(),
    };
  }

  RsAchievement copyWith({
    String? id,
    String? userId,
    String? badgeType,
    String? emoji,
    String? name,
    String? description,
    bool? isEarned,
    Object? earnedAt = _unset,
  }) {
    return RsAchievement(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      badgeType: badgeType ?? this.badgeType,
      emoji: emoji ?? this.emoji,
      name: name ?? this.name,
      description: description ?? this.description,
      isEarned: isEarned ?? this.isEarned,
      earnedAt: identical(earnedAt, _unset)
          ? this.earnedAt
          : earnedAt as DateTime?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    badgeType,
    emoji,
    name,
    description,
    isEarned,
    earnedAt,
  ];
}
