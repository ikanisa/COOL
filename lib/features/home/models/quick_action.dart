/// Model for a home screen quick action card.
class QuickAction {
  const QuickAction({
    required this.id,
    required this.title,
    required this.route,
    this.subtitle,
    this.emoji = '⚡',
    this.country,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String emoji;
  final String route;
  final String? country;
  final int sortOrder;
  final bool isActive;

  factory QuickAction.fromJson(Map<String, dynamic> json) {
    return QuickAction(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['subtitle']?.toString(),
      emoji: json['emoji']?.toString() ?? '⚡',
      route: json['route']?.toString() ?? '/',
      country: json['country']?.toString(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is QuickAction && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
