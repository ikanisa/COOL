import 'package:equatable/equatable.dart';

/// A global achievement in the Cool SuperApp.
/// 
/// Achievements are earned by completing milestones in various features 
/// (Mobility, Groups, Shop, etc.) and are displayed in the user's profile 
/// and the Cool Tokens hub.
class CoolAchievement extends Equatable {
  const CoolAchievement({
    required this.id,
    required this.userId,
    required this.badgeType,
    required this.emoji,
    required this.name,
    required this.description,
    required this.isEarned,
    this.earnedAt,
    this.featureContext,
    this.pointsValue = 0,
  });

  final String id;
  final String userId;
  final String badgeType; // e.g. 'gold', 'silver', 'blue'
  final String emoji;
  final String name;
  final String description;
  final bool isEarned;
  final DateTime? earnedAt;
  
  /// The feature where this achievement was earned (e.g., 'mobility', 'groups')
  final String? featureContext;
  
  /// Bonus tokens awarded for unlocking this achievement
  final int pointsValue;

  factory CoolAchievement.fromJson(Map<String, dynamic> json) {
    final earnedAt = json['earned_at'] != null 
        ? DateTime.tryParse(json['earned_at'].toString()) 
        : null;

    return CoolAchievement(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      badgeType: (json['badge_type'] ?? 'blue').toString(),
      emoji: (json['emoji'] ?? '🏆').toString(),
      name: (json['name'] ?? 'Achievement').toString(),
      description: (json['description'] ?? '').toString(),
      isEarned: json['is_earned'] == true || earnedAt != null,
      earnedAt: earnedAt,
      featureContext: json['feature_context']?.toString(),
      pointsValue: int.tryParse(json['points_value']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'badge_type': badgeType,
      'emoji': emoji,
      'name': name,
      'description': description,
      'is_earned': isEarned,
      'earned_at': earnedAt?.toIso8601String(),
      'feature_context': featureContext,
      'points_value': pointsValue,
    };
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
    featureContext,
    pointsValue,
  ];
}
