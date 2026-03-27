part of 'rs_models.dart';

/// A dynamic home screen banner card managed by admins in Supabase.
///
/// Used for promotional content like "Official Fan Registry", match-day
/// campaigns, partnerships, etc. Each banner has an image, title, CTA,
/// and routing target.
class RsHomeBanner extends Equatable {
  const RsHomeBanner({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.route,
    required this.sortOrder,
    this.badgeLabel,
    this.imageUrl,
    this.isActive = true,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? badgeLabel;
  final String ctaLabel;
  final String route;
  final String? imageUrl;
  final int sortOrder;
  final bool isActive;

  factory RsHomeBanner.fromJson(RsJsonMap json) {
    return RsHomeBanner(
      id: _asString(json['id']),
      title: _asString(json['title'], fallback: 'Banner'),
      subtitle: _asNullableString(json['subtitle']),
      badgeLabel: _asNullableString(json['badge_label'] ?? json['badgeLabel']),
      ctaLabel: _asString(
        json['cta_label'] ?? json['ctaLabel'],
        fallback: 'LEARN MORE',
      ),
      route: _asString(json['route'], fallback: '/'),
      imageUrl: _asNullableString(json['image_url'] ?? json['imageUrl']),
      sortOrder: _asInt(json['sort_order'] ?? json['sortOrder']),
      isActive: _asBool(json['is_active'] ?? json['isActive'], fallback: true),
    );
  }

  RsJsonMap toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'badge_label': badgeLabel,
      'cta_label': ctaLabel,
      'route': route,
      'image_url': imageUrl,
      'sort_order': sortOrder,
      'is_active': isActive,
    };
  }

  @override
  List<Object?> get props => [
    id,
    title,
    subtitle,
    badgeLabel,
    ctaLabel,
    route,
    imageUrl,
    sortOrder,
    isActive,
  ];
}
