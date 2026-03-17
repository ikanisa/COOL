import 'package:equatable/equatable.dart';

enum CoolRewardType {
  digitalGoods, // frames, stickers, streak freeze
  partnerPerk, // discounts, zero-fee vouchers
  communityImpact, // voting power, initiative boost
}

/// A reward that can be redeemed using Cool Tokens.
class CoolReward extends Equatable {
  const CoolReward({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.tokenCost,
    required this.emoji,
    this.partnerId,
    this.isActive = true,
    this.expiryDate,
  });

  final String id;
  final CoolRewardType type;
  final String title;
  final String description;
  final int tokenCost;
  final String emoji;
  final String? partnerId;
  final bool isActive;
  final DateTime? expiryDate;

  factory CoolReward.fromJson(Map<String, dynamic> json) {
    return CoolReward(
      id: (json['id'] ?? '').toString(),
      type: _parseType(json['type']),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      tokenCost: int.tryParse(json['token_cost']?.toString() ?? '0') ?? 0,
      emoji: (json['emoji'] ?? '🎁').toString(),
      partnerId: json['partner_id']?.toString(),
      isActive: json['is_active'] != false,
      expiryDate: json['expiry_date'] != null
          ? DateTime.tryParse(json['expiry_date'].toString())
          : null,
    );
  }

  static CoolRewardType _parseType(dynamic value) {
    final raw = (value ?? '').toString().toLowerCase();
    if (raw.contains('partner')) return CoolRewardType.partnerPerk;
    if (raw.contains('community')) return CoolRewardType.communityImpact;
    return CoolRewardType.digitalGoods;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'description': description,
      'token_cost': tokenCost,
      'emoji': emoji,
      'partner_id': partnerId,
      'is_active': isActive,
      'expiry_date': expiryDate?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
    id,
    type,
    title,
    description,
    tokenCost,
    emoji,
    partnerId,
    isActive,
    expiryDate,
  ];
}
