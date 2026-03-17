import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../../../core/identity/public_user_identity.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/rs_colors.dart';
import '../rayon_ticket_qr.dart';

import 'rs_initiative_models.dart';
export 'rs_initiative_models.dart';

part 'rs_achievement_models.dart';
part 'rs_data_models.dart';
part 'rs_membership_models.dart';
part 'rs_shop_models.dart';
part 'rs_ticket_models.dart';

const Object _unset = Object();

enum FanTier { blue, silver, gold, platinum }

extension FanTierX on FanTier {
  static FanTier fromValue(String? value) {
    return switch ((value ?? '').toLowerCase()) {
      'silver' => FanTier.silver,
      'gold' => FanTier.gold,
      'platinum' => FanTier.platinum,
      _ => FanTier.blue,
    };
  }

  static FanTier fromPoints(int points) {
    if (points >= 5000) {
      return FanTier.platinum;
    }
    if (points >= 2000) {
      return FanTier.gold;
    }
    if (points >= 1000) {
      return FanTier.silver;
    }
    return FanTier.blue;
  }

  String get value => name;

  String get label => switch (this) {
    FanTier.blue => 'Blue',
    FanTier.silver => 'Silver',
    FanTier.gold => 'Gold',
    FanTier.platinum => 'Platinum',
  };

  Color get color => switch (this) {
    FanTier.blue => AppColors.blue,
    FanTier.silver => const Color(0xFFC0C0C0),
    FanTier.gold => const Color(0xFFFFD700),
    FanTier.platinum => const Color(0xFFE5E4E2),
  };

  int get minPoints => switch (this) {
    FanTier.blue => 0,
    FanTier.silver => 1000,
    FanTier.gold => 2000,
    FanTier.platinum => 5000,
  };

  Color get glowColor => switch (this) {
    FanTier.blue => AppColors.blue.withValues(alpha: 0.4),
    FanTier.silver => const Color(0xFFC0C0C0).withValues(alpha: 0.4),
    FanTier.gold => const Color(0xFFFFD700).withValues(alpha: 0.4),
    FanTier.platinum => const Color(0xFFE5E4E2).withValues(alpha: 0.4),
  };
}

enum InitiativeCategory { stadium, youth, community, kit }

extension InitiativeCategoryX on InitiativeCategory {
  static InitiativeCategory fromValue(String? value) {
    return switch ((value ?? '').toLowerCase()) {
      'stadium' || 'matchday' || 'infrastructure' => InitiativeCategory.stadium,
      'youth' || 'academy' => InitiativeCategory.youth,
      'kit' || 'kits' || 'merch' || 'merchandise' => InitiativeCategory.kit,
      _ => InitiativeCategory.community,
    };
  }

  String get value => name;
}

enum SeatType { general, vip }

extension SeatTypeX on SeatType {
  static SeatType fromValue(String? value) {
    return switch ((value ?? '').toLowerCase()) {
      'vip' => SeatType.vip,
      _ => SeatType.general,
    };
  }

  String get value => name;
}

enum TicketStatus { pending, valid, used, cancelled, voided, refunded }

extension TicketStatusX on TicketStatus {
  static TicketStatus fromValue(String? value) {
    return switch ((value ?? '').toLowerCase()) {
      'valid' => TicketStatus.valid,
      'used' => TicketStatus.used,
      'cancelled' => TicketStatus.cancelled,
      'voided' => TicketStatus.voided,
      'refunded' => TicketStatus.refunded,
      _ => TicketStatus.pending,
    };
  }

  String get value => name;

  String get label => switch (this) {
    TicketStatus.pending => 'Pending',
    TicketStatus.valid => 'Valid',
    TicketStatus.used => 'Used',
    TicketStatus.cancelled => 'Cancelled',
    TicketStatus.voided => 'Voided',
    TicketStatus.refunded => 'Refunded',
  };

  bool get isTerminal => switch (this) {
    TicketStatus.used || TicketStatus.cancelled || TicketStatus.voided || TicketStatus.refunded => true,
    _ => false,
  };
}

enum OrderStatus { pending, paid, confirmed, packed, shipped, fulfilled, delivered, cancelled }

extension OrderStatusX on OrderStatus {
  static OrderStatus fromValue(String? value) {
    return switch ((value ?? '').toLowerCase()) {
      'paid' => OrderStatus.paid,
      'confirmed' => OrderStatus.confirmed,
      'packed' => OrderStatus.packed,
      'shipped' => OrderStatus.shipped,
      'fulfilled' => OrderStatus.fulfilled,
      'delivered' => OrderStatus.delivered,
      'cancelled' => OrderStatus.cancelled,
      _ => OrderStatus.pending,
    };
  }

  String get value => name;

  String get label => switch (this) {
    OrderStatus.pending => 'Pending',
    OrderStatus.paid => 'Paid',
    OrderStatus.confirmed => 'Confirmed',
    OrderStatus.packed => 'Packed',
    OrderStatus.shipped => 'Shipped',
    OrderStatus.fulfilled => 'Fulfilled',
    OrderStatus.delivered => 'Delivered',
    OrderStatus.cancelled => 'Cancelled',
  };

  bool get isActive => switch (this) {
    OrderStatus.pending || OrderStatus.paid || OrderStatus.confirmed || OrderStatus.packed || OrderStatus.shipped => true,
    _ => false,
  };
}

enum ProductCategory {
  kits,
  apparel,
  outerwear,
  caps,
  scarves,
  footwear,
  accessories,
  equipment,
  bundles,
  other,
}

extension ProductCategoryX on ProductCategory {
  static ProductCategory fromValue(String? value) {
    final normalized = (value ?? '')
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll('-', ' ')
        .trim();

    return switch (normalized) {
      'replica' ||
      'replicas' ||
      'kit' ||
      'kits' ||
      'jersey' ||
      'jerseys' ||
      'heritage' ||
      'training' ||
      'warm up' ||
      'warmup' ||
      'matchday' => ProductCategory.kits,
      'polo' ||
      'polos' ||
      't shirt' ||
      't shirts' ||
      'tshirt' ||
      'tshirts' ||
      'tee' ||
      'tees' ||
      'shirt' ||
      'shirts' ||
      'lifestyle' => ProductCategory.apparel,
      'hoodie' ||
      'hoodies' ||
      'gilet' ||
      'gilets' ||
      'jacket' ||
      'jackets' ||
      'outerwear' => ProductCategory.outerwear,
      'cap' || 'caps' || 'hat' || 'hats' => ProductCategory.caps,
      'scarf' || 'scarves' => ProductCategory.scarves,
      'footwear' ||
      'boots' ||
      'shoes' ||
      'shoe' ||
      'slipper' ||
      'slippers' ||
      'sandals' ||
      'sneakers' => ProductCategory.footwear,
      'watch' ||
      'watches' ||
      'bag' ||
      'bags' ||
      'valeze' ||
      'travel' ||
      'luggage' ||
      'accessory' ||
      'accessories' => ProductCategory.accessories,
      'ball' || 'balls' || 'equipment' || 'gear' => ProductCategory.equipment,
      'bundle' || 'bundles' || 'combo' => ProductCategory.bundles,
      _ => ProductCategory.other,
    };
  }

  String get value => name;

  String get label => switch (this) {
    ProductCategory.kits => 'Kits',
    ProductCategory.apparel => 'Apparel',
    ProductCategory.outerwear => 'Outerwear',
    ProductCategory.caps => 'Caps',
    ProductCategory.scarves => 'Scarves',
    ProductCategory.footwear => 'Footwear',
    ProductCategory.accessories => 'Accessories',
    ProductCategory.equipment => 'Equipment',
    ProductCategory.bundles => 'Bundles',
    ProductCategory.other => 'Other',
  };

  IconData get icon => switch (this) {
    ProductCategory.kits => Icons.checkroom_rounded,
    ProductCategory.apparel => Icons.sports_football_rounded,
    ProductCategory.outerwear => Icons.layers_rounded,
    ProductCategory.caps => Icons.dry_cleaning_rounded,
    ProductCategory.scarves => Icons.gesture_rounded,
    ProductCategory.footwear => Icons.directions_walk_rounded,
    ProductCategory.accessories => Icons.watch_rounded,
    ProductCategory.equipment => Icons.sports_soccer_rounded,
    ProductCategory.bundles => Icons.inventory_2_rounded,
    ProductCategory.other => Icons.shopping_bag_rounded,
  };

  String get defaultEmoji => switch (this) {
    ProductCategory.kits => '👕',
    ProductCategory.apparel => '🧥',
    ProductCategory.outerwear => '🧢',
    ProductCategory.caps => '🧢',
    ProductCategory.scarves => '🧣',
    ProductCategory.footwear => '👟',
    ProductCategory.accessories => '⌚',
    ProductCategory.equipment => '⚽',
    ProductCategory.bundles => '🎁',
    ProductCategory.other => '🛍️',
  };

  Color get defaultBackgroundColor => switch (this) {
    ProductCategory.kits => RsColors.rsBlueLight.withValues(alpha: 0.24),
    ProductCategory.apparel => const Color(0xFF1D3B7A),
    ProductCategory.outerwear => const Color(0xFF22325A),
    ProductCategory.caps => RsColors.rsGold.withValues(alpha: 0.22),
    ProductCategory.scarves => RsColors.rsBlue.withValues(alpha: 0.20),
    ProductCategory.footwear => const Color(0xFF182A5A),
    ProductCategory.accessories => const Color(0xFF2B4C84),
    ProductCategory.equipment => const Color(0xFF173866),
    ProductCategory.bundles => const Color(0xFF21407D),
    ProductCategory.other => const Color(0xFF1A233E),
  };
}

String _defaultEmojiForCategory(ProductCategory category) =>
    category.defaultEmoji;

typedef RsJsonMap = Map<String, Object?>;
typedef RsJsonList = List<Object?>;

String _asString(Object? value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }

  final string = value.toString().trim();
  return string.isEmpty ? fallback : string;
}

String? _asNullableString(Object? value) {
  final string = _asString(value);
  return string.isEmpty ? null : string;
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value == null) {
    return fallback;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }

  final normalized = value.toString().replaceAll(',', '').trim();
  return int.tryParse(normalized) ?? fallback;
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value == null) {
    return fallback;
  }
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }

  final normalized = value.toString().replaceAll(',', '').trim();
  return double.tryParse(normalized) ?? fallback;
}

bool _asBool(Object? value, {bool fallback = false}) {
  if (value == null) {
    return fallback;
  }
  if (value is bool) {
    return value;
  }

  final normalized = value.toString().toLowerCase().trim();
  return switch (normalized) {
    'true' || '1' || 'yes' || 'y' => true,
    'false' || '0' || 'no' || 'n' => false,
    _ => fallback,
  };
}

DateTime? _asDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  return DateTime.tryParse(value.toString());
}

RsJsonMap _asMap(Object? value) {
  if (value is RsJsonMap) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, Object?>{};
}

RsJsonList _asList(Object? value) {
  if (value is RsJsonList) {
    return value;
  }
  if (value is List) {
    return List<Object?>.from(value);
  }
  return const <Object?>[];
}

Color _asColor(Object? value, {required Color fallback}) {
  if (value == null) {
    return fallback;
  }
  if (value is Color) {
    return value;
  }
  if (value is int) {
    return Color(value);
  }
  if (value is num) {
    return Color(value.toInt());
  }

  final raw = value.toString().trim();
  if (raw.isEmpty) {
    return fallback;
  }

  final normalized = raw.startsWith('#')
      ? raw.substring(1)
      : raw.startsWith('0x')
      ? raw.substring(2)
      : raw;
  final withAlpha = normalized.length == 6 ? 'FF$normalized' : normalized;
  final parsed = int.tryParse(withAlpha, radix: 16);
  return parsed == null ? fallback : Color(parsed);
}

String _normalizeKickoff(Object? value) {
  final kickoff = _asString(value, fallback: '15:00');
  return kickoff.length > 5 ? kickoff.substring(0, 5) : kickoff;
}

typedef RsFanMembership = FanMembership;
typedef RsShopProduct = RsProduct;
typedef RsTicketStatus = TicketStatus;
