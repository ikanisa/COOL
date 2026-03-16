import 'package:flutter/material.dart';

/// Types of Nexus AI-driven recommendations.
enum NexusRecommendationType {
  aiMatch,
  efficiency,
  security,
  promotion,
}

extension NexusRecommendationTypeX on NexusRecommendationType {
  String get label => switch (this) {
    NexusRecommendationType.aiMatch => 'AI MATCH',
    NexusRecommendationType.efficiency => 'EFFICIENCY',
    NexusRecommendationType.security => 'SECURITY',
    NexusRecommendationType.promotion => 'PROMOTION',
  };
}

/// A dynamic recommendation card for the Home screen.
class NexusRecommendation {
  const NexusRecommendation({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.rationale,
    required this.type,
    required this.iconEmoji,
    required this.ctaAction,
    this.country,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;
  final String title;
  final String subtitle;
  final String rationale;
  final NexusRecommendationType type;
  final String iconEmoji;
  final String ctaAction;
  final String? country;
  final int sortOrder;
  final bool isActive;

  factory NexusRecommendation.fromJson(Map<String, dynamic> json) {
    return NexusRecommendation(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      rationale: json['rationale']?.toString() ?? '',
      type: _parseType(json['type']),
      iconEmoji: json['icon_emoji']?.toString() ?? '✨',
      ctaAction: json['cta_action']?.toString() ?? '',
      country: json['country']?.toString(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  static NexusRecommendationType _parseType(Object? value) {
    final normalized = value?.toString().trim().toUpperCase();
    return NexusRecommendationType.values.firstWhere(
      (t) => t.name.toUpperCase() == normalized,
      orElse: () => NexusRecommendationType.aiMatch,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NexusRecommendation && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
