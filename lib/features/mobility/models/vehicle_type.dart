/// Model for a mobility vehicle type filter.
class VehicleType {
  const VehicleType({
    required this.id,
    required this.label,
    required this.value,
    this.emoji = '🚘',
    this.country,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;
  final String label;
  final String value;
  final String emoji;
  final String? country;
  final int sortOrder;
  final bool isActive;

  factory VehicleType.fromJson(Map<String, dynamic> json) {
    return VehicleType(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      emoji: json['emoji']?.toString() ?? '🚘',
      country: json['country']?.toString(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is VehicleType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
