/// Model for a partner service (loan, insurance, professional service, etc.)
class PartnerService {
  const PartnerService({
    required this.id,
    required this.partnerId,
    required this.title,
    this.subtitle,
    this.emoji = '📋',
    this.category = 'general',
    this.details = const <ServiceDetail>[],
    this.ctaLabel,
    this.ctaAction,
    this.country = 'RW',
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;
  final String partnerId;
  final String title;
  final String? subtitle;
  final String emoji;
  final String category;
  final List<ServiceDetail> details;
  final String? ctaLabel;
  final String? ctaAction;
  final String country;
  final int sortOrder;
  final bool isActive;

  factory PartnerService.fromJson(Map<String, dynamic> json) {
    final rawDetails = json['details'];
    final List<ServiceDetail> parsedDetails;
    if (rawDetails is List) {
      parsedDetails = rawDetails
          .whereType<Map<String, dynamic>>()
          .map(ServiceDetail.fromJson)
          .toList();
    } else {
      parsedDetails = const <ServiceDetail>[];
    }

    return PartnerService(
      id: json['id']?.toString() ?? '',
      partnerId: json['partner_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString(),
      emoji: json['emoji']?.toString() ?? '📋',
      category: json['category']?.toString() ?? 'general',
      details: parsedDetails,
      ctaLabel: json['cta_label']?.toString(),
      ctaAction: json['cta_action']?.toString(),
      country: json['country']?.toString() ?? 'RW',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PartnerService && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A single detail row inside a [PartnerService] card.
class ServiceDetail {
  const ServiceDetail({
    required this.label,
    required this.value,
    this.icon = '📋',
  });

  final String label;
  final String value;
  final String icon;

  factory ServiceDetail.fromJson(Map<String, dynamic> json) {
    return ServiceDetail(
      label: json['label']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      icon: json['icon']?.toString() ?? '📋',
    );
  }
}
