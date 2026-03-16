/// Data model for a Cool partner (football club, bank, service firm).
///
/// Partners are stored in `public.partners` and managed dynamically.
/// Each partner is country-specific.
library;

import 'package:flutter/foundation.dart';

// ── Category enum ─────────────────────────────────────────────────────────

enum PartnerCategory {
  football,
  bank,
  organization;

  static PartnerCategory fromString(String? value) {
    return switch (value?.toLowerCase()) {
      'football' => PartnerCategory.football,
      'bank' => PartnerCategory.bank,
      'organization' => PartnerCategory.organization,
      _ => PartnerCategory.organization,
    };
  }
}

// ── Partner model ────────────────────────────────────────────────────────

@immutable
class Partner {
  const Partner({
    required this.id,
    required this.name,
    required this.slug,
    required this.category,
    required this.country,
    this.emoji = '🤝',
    this.subtitle,
    this.description,
    this.whatsappNumber,
    this.logoUrl,
    this.fanCount = 0,
    this.clubCount = 0,
    this.gameCount = 0,
    this.isActive = true,
    this.sortOrder = 0,
    this.metadata = const {},
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String slug;
  final PartnerCategory category;
  final String country;
  final String emoji;
  final String? subtitle;
  final String? description;
  final String? whatsappNumber;
  final String? logoUrl;
  final int fanCount;
  final int clubCount;
  final int gameCount;
  final bool isActive;
  final int sortOrder;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // ── JSON serialisation ───────────────────────────────────────────────

  factory Partner.fromJson(Map<String, dynamic> json) {
    return Partner(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String? ?? '',
      category: PartnerCategory.fromString(json['category'] as String?),
      country: json['country'] as String? ?? 'RW',
      emoji: json['emoji'] as String? ?? '🤝',
      subtitle: json['subtitle'] as String?,
      description: json['description'] as String?,
      whatsappNumber: json['whatsapp_number'] as String?,
      logoUrl: json['logo_url'] as String?,
      fanCount: (json['fan_count'] as num?)?.toInt() ?? 0,
      clubCount: (json['club_count'] as num?)?.toInt() ?? 0,
      gameCount: (json['game_count'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'category': category.name,
      'country': country,
      'emoji': emoji,
      'subtitle': subtitle,
      'description': description,
      'whatsapp_number': whatsappNumber,
      'logo_url': logoUrl,
      'fan_count': fanCount,
      'club_count': clubCount,
      'game_count': gameCount,
      'is_active': isActive,
      'sort_order': sortOrder,
      'metadata': metadata,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Partner && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Partner($slug, $name, $category, $country)';
}
