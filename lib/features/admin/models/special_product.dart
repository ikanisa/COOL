import 'package:flutter/material.dart';

/// Admin-managed special product (e.g. Burimunci daily savings).
class SpecialProduct {
  const SpecialProduct({
    required this.id,
    required this.slug,
    required this.title,
    this.subtitle = '',
    this.description = '',
    required this.amount,
    this.currency = 'RWF',
    this.iconName = 'star',
    this.colorHex = '#C9A84C',
    this.interestRate,
    this.loanMultiplier,
    required this.momoRecipient,
    this.momoRecipientType = 'code',
    this.targetAudience = 'Everyone',
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String slug;
  final String title;
  final String subtitle;
  final String description;
  final int amount;
  final String currency;
  final String iconName;
  final String colorHex;
  final String? interestRate;
  final String? loanMultiplier;
  final String momoRecipient;
  final String momoRecipientType;
  final String targetAudience;
  final bool isActive;
  final int sortOrder;

  factory SpecialProduct.fromJson(Map<String, dynamic> json) {
    return SpecialProduct(
      id: json['id']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      currency: json['currency']?.toString() ?? 'RWF',
      iconName: json['icon_name']?.toString() ?? 'star',
      colorHex: json['color_hex']?.toString() ?? '#C9A84C',
      interestRate: json['interest_rate']?.toString(),
      loanMultiplier: json['loan_multiplier']?.toString(),
      momoRecipient: json['momo_recipient']?.toString() ?? '',
      momoRecipientType: json['momo_recipient_type']?.toString() ?? 'code',
      targetAudience: json['target_audience']?.toString() ?? 'Everyone',
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'slug': slug,
    'title': title,
    'subtitle': subtitle,
    'description': description,
    'amount': amount,
    'currency': currency,
    'icon_name': iconName,
    'color_hex': colorHex,
    'interest_rate': interestRate,
    'loan_multiplier': loanMultiplier,
    'momo_recipient': momoRecipient,
    'momo_recipient_type': momoRecipientType,
    'target_audience': targetAudience,
    'is_active': isActive,
    'sort_order': sortOrder,
    'updated_at': DateTime.now().toIso8601String(),
  };

  Color get accentColor {
    try {
      final hex = colorHex.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFFC9A84C);
    }
  }

  Color get accentColorLight => Color.lerp(accentColor, Colors.white, 0.25)!;

  IconData get icon {
    const map = <String, IconData>{
      'directions_car': Icons.directions_car_rounded,
      'savings': Icons.savings_rounded,
      'school': Icons.school_rounded,
      'star': Icons.star_rounded,
      'home': Icons.home_rounded,
      'agriculture': Icons.agriculture_rounded,
      'local_hospital': Icons.local_hospital_rounded,
      'construction': Icons.construction_rounded,
      'store': Icons.store_rounded,
      'electric_bolt': Icons.electric_bolt_rounded,
    };
    return map[iconName] ?? Icons.star_rounded;
  }

  String get formattedAmount {
    final str = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return '$buffer $currency';
  }
}
