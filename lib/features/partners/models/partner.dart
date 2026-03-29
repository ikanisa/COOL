import '../../../core/config/country_catalog.dart';

enum PartnerCategory {
  bank,
  football,
  other;

  static PartnerCategory fromValue(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'bank':
      case 'custodian_bank':
        return PartnerCategory.bank;
      case 'football':
      case 'club':
      case 'sports':
      case 'rayon_sports':
        return PartnerCategory.football;
      default:
        return PartnerCategory.other;
    }
  }

  String get dbValue => switch (this) {
    PartnerCategory.bank => 'bank',
    PartnerCategory.football => 'football',
    PartnerCategory.other => 'other',
  };
}

class Partner {
  const Partner({
    required this.id,
    required this.name,
    required this.slug,
    required this.category,
    required this.country,
    this.subtitle,
    this.emoji,
    this.whatsAppNumber,
    this.isActive = true,
    this.fanCount = 0,
    this.clubCount = 0,
    this.gameCount = 0,
  });

  final String id;
  final String name;
  final String slug;
  final PartnerCategory category;
  final String country;
  final String? subtitle;
  final String? emoji;
  final String? whatsAppNumber;
  final bool isActive;
  final int fanCount;
  final int clubCount;
  final int gameCount;

  bool get isBank => category == PartnerCategory.bank;

  factory Partner.fromJson(Map<String, dynamic> json) {
    final rawCountry = json['country']?.toString() ?? 'RW';
    return Partner(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      category: PartnerCategory.fromValue(json['category']?.toString()),
      country: rawCountry.trim().isEmpty
          ? 'RW'
          : CoolCountryCatalog.normalizeCountryCode(rawCountry),
      subtitle: json['subtitle']?.toString(),
      emoji: json['emoji']?.toString(),
      whatsAppNumber: json['whatsapp_number']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
      fanCount: _asInt(json['fan_count']),
      clubCount: _asInt(json['club_count']),
      gameCount: _asInt(json['game_count']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'slug': slug,
      'category': category.dbValue,
      'country': CoolCountryCatalog.normalizeCountryCode(country),
      'subtitle': subtitle,
      'emoji': emoji,
      'whatsapp_number': whatsAppNumber,
      'is_active': isActive,
      'fan_count': fanCount,
      'club_count': clubCount,
      'game_count': gameCount,
    }..removeWhere((_, value) => value == null);
  }
}

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
