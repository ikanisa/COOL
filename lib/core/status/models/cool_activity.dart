import 'package:equatable/equatable.dart';

/// A single admin-managed token-earning activity from the `cool_activities` table.
class CoolActivity extends Equatable {
  const CoolActivity({
    required this.id,
    required this.slug,
    required this.title,
    this.description = '',
    this.emoji = '⭐',
    this.category = 'general',
    this.tokensAwarded = 20,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String slug;
  final String title;
  final String description;
  final String emoji;
  final String category;
  final int tokensAwarded;
  final bool isActive;
  final int sortOrder;

  factory CoolActivity.fromJson(Map<String, dynamic> json) {
    return CoolActivity(
      id: (json['id'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      emoji: (json['emoji'] ?? '⭐').toString(),
      category: (json['category'] ?? 'general').toString(),
      tokensAwarded: _asInt(json['tokens_awarded'], fallback: 20),
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: _asInt(json['sort_order']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'slug': slug,
    'title': title,
    'description': description,
    'emoji': emoji,
    'category': category,
    'tokens_awarded': tokensAwarded,
    'is_active': isActive,
    'sort_order': sortOrder,
  };

  @override
  List<Object?> get props => [
    id,
    slug,
    title,
    category,
    tokensAwarded,
    isActive,
  ];
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}
