import 'models/rs_models.dart';

class RsMembershipPackageBenefit {
  const RsMembershipPackageBenefit({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  factory RsMembershipPackageBenefit.fromJson(Map<String, dynamic> json) {
    return RsMembershipPackageBenefit(
      title: json['title']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{'title': title, 'description': description};
  }
}

class RsMembershipPackage {
  const RsMembershipPackage({
    this.id = '',
    this.partnerId = '',
    required this.tier,
    required this.title,
    required this.subtitle,
    this.description = '',
    this.benefits = const <RsMembershipPackageBenefit>[],
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String partnerId;
  final FanTier tier;
  final String title;
  final String subtitle;
  final String description;
  final List<RsMembershipPackageBenefit> benefits;
  final bool isActive;
  final int sortOrder;

  int get minPoints => tier.minPoints;

  factory RsMembershipPackage.fallback() {
    return const RsMembershipPackage(
      tier: FanTier.fan,
      title: 'Fan',
      subtitle: 'Standard Membership',
    );
  }

  factory RsMembershipPackage.fromJson(Map<String, dynamic> json) {
    final rawBenefits = json['benefits'];
    final benefits = rawBenefits is List
        ? rawBenefits
              .whereType<Map<dynamic, dynamic>>()
              .map(
                (benefit) => RsMembershipPackageBenefit.fromJson(
                  Map<String, dynamic>.from(benefit),
                ),
              )
              .toList(growable: false)
        : const <RsMembershipPackageBenefit>[];

    return RsMembershipPackage(
      id: json['id']?.toString() ?? '',
      partnerId: json['partner_id']?.toString() ?? '',
      tier: FanTierX.fromValue(json['tier']?.toString()),
      title: json['title']?.toString().trim() ?? '',
      subtitle: json['subtitle']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      benefits: benefits,
      isActive: json['is_active'] == null
          ? true
          : json['is_active'] == true || json['is_active'].toString() == 'true',
      sortOrder: int.tryParse(json['sort_order']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'partner_id': partnerId,
      'tier': tier.value,
      'title': title,
      'subtitle': subtitle,
      'description': description,
      'benefits': benefits.map((benefit) => benefit.toJson()).toList(),
      'is_active': isActive,
      'sort_order': sortOrder,
    };
  }
}
