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

  factory RsMembershipPackage.fromJson(Map<String, dynamic> json) {
    final rawBenefits = json['benefits'];
    final benefits = rawBenefits is List
        ? rawBenefits
              .whereType<Map>()
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

  static List<RsMembershipPackage> fallback() {
    return <RsMembershipPackage>[
      const RsMembershipPackage(
        tier: FanTier.blue,
        title: 'Blue Membership',
        subtitle: 'Free every fan starts',
        description: 'Entry tier for all',
        benefits: <RsMembershipPackageBenefit>[
          RsMembershipPackageBenefit(
            title: 'Standard Tickets',
            description: 'Buy match tickets at',
          ),
          RsMembershipPackageBenefit(
            title: 'Club Shop Access',
            description: 'Browse and purchase official',
          ),
          RsMembershipPackageBenefit(
            title: 'Fan Points',
            description: 'Earn points from attendance',
          ),
        ],
        sortOrder: 0,
      ),
      const RsMembershipPackage(
        tier: FanTier.silver,
        title: 'Silver Membership',
        subtitle: '1 000 pts dedicated',
        description:
            'Priority access and profile',
        benefits: <RsMembershipPackageBenefit>[
          RsMembershipPackageBenefit(
            title: '5% Ticket Discount',
            description: 'Save on every match',
          ),
          RsMembershipPackageBenefit(
            title: 'Priority Queue',
            description: 'Jump the queue when',
          ),
          RsMembershipPackageBenefit(
            title: 'Silver Badge',
            description: 'Exclusive silver badge on',
          ),
        ],
        sortOrder: 1,
      ),
      const RsMembershipPackage(
        tier: FanTier.gold,
        title: 'Gold Membership',
        subtitle: '2 000 pts elite',
        description:
            'Higher-value supporter benefits for',
        benefits: <RsMembershipPackageBenefit>[
          RsMembershipPackageBenefit(
            title: 'Priority Tickets',
            description: 'Get earlier access to',
          ),
          RsMembershipPackageBenefit(
            title: '10% Shop Discount',
            description: 'Unlock supporter pricing on',
          ),
          RsMembershipPackageBenefit(
            title: 'VIP Events',
            description: 'Access select fan sessions',
          ),
        ],
        sortOrder: 2,
      ),
      const RsMembershipPackage(
        tier: FanTier.platinum,
        title: 'Platinum Membership',
        subtitle: '5 000 pts ultimate',
        description:
            'Top-tier supporter access across',
        benefits: <RsMembershipPackageBenefit>[
          RsMembershipPackageBenefit(
            title: 'Priority Tickets + 15% Off',
            description: 'Best pricing and first',
          ),
          RsMembershipPackageBenefit(
            title: 'Meet & Greet',
            description: 'Join premium player and',
          ),
          RsMembershipPackageBenefit(
            title: 'Free Kit',
            description: 'Receive one complimentary official',
          ),
          RsMembershipPackageBenefit(
            title: 'All Gold Benefits',
            description:
                'VIP events shop discounts',
          ),
        ],
        sortOrder: 3,
      ),
    ];
  }
}
