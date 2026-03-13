import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../../../core/identity/public_user_identity.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/rs_colors.dart';
import '../rayon_ticket_qr.dart';

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

enum TicketStatus { pending, valid, used, cancelled }

extension TicketStatusX on TicketStatus {
  static TicketStatus fromValue(String? value) {
    return switch ((value ?? '').toLowerCase()) {
      'valid' => TicketStatus.valid,
      'used' => TicketStatus.used,
      'cancelled' => TicketStatus.cancelled,
      _ => TicketStatus.pending,
    };
  }

  String get value => name;

  String get label => switch (this) {
    TicketStatus.pending => 'Pending',
    TicketStatus.valid => 'Valid',
    TicketStatus.used => 'Used',
    TicketStatus.cancelled => 'Cancelled',
  };
}

enum OrderStatus { pending, confirmed, shipped, delivered, cancelled }

extension OrderStatusX on OrderStatus {
  static OrderStatus fromValue(String? value) {
    return switch ((value ?? '').toLowerCase()) {
      'paid' || 'confirmed' => OrderStatus.confirmed,
      'packed' || 'shipped' => OrderStatus.shipped,
      'fulfilled' || 'delivered' => OrderStatus.delivered,
      'cancelled' => OrderStatus.cancelled,
      _ => OrderStatus.pending,
    };
  }

  String get value => name;

  String get label => switch (this) {
    OrderStatus.pending => 'Pending',
    OrderStatus.confirmed => 'Confirmed',
    OrderStatus.shipped => 'Shipped',
    OrderStatus.delivered => 'Delivered',
    OrderStatus.cancelled => 'Cancelled',
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

class FanMembership extends Equatable {
  const FanMembership({
    this.id = '',
    required this.userId,
    required this.partnerId,
    this.displayName = 'Fan',
    required this.tier,
    required this.points,
    required this.chapter,
    required this.membershipNumber,
    required this.joinedAt,
  });

  final String id;
  final String userId;
  final String partnerId;
  final String displayName;
  final FanTier tier;
  final int points;
  final String chapter;
  final String membershipNumber;
  final DateTime joinedAt;

  int get nextTierPoints => switch (tier) {
    FanTier.blue => 1000,
    FanTier.silver => 2000,
    FanTier.gold => 5000,
    FanTier.platinum => points,
  };

  int get pointsToNextTier => switch (tier) {
    FanTier.platinum => 0,
    _ => (nextTierPoints - points).clamp(0, nextTierPoints),
  };

  double get progressToNextTier {
    if (tier == FanTier.platinum) {
      return 1;
    }

    final currentTierFloor = switch (tier) {
      FanTier.blue => 0,
      FanTier.silver => 1000,
      FanTier.gold => 2000,
      FanTier.platinum => points,
    };
    final span = nextTierPoints - currentTierFloor;
    if (span <= 0) {
      return 1;
    }

    return ((points - currentTierFloor) / span).clamp(0, 1).toDouble();
  }

  factory FanMembership.fromJson(Map<String, dynamic> json) {
    final points = _asInt(json['points']);
    final tier = json['tier'] == null
        ? FanTierX.fromPoints(points)
        : FanTierX.fromValue(json['tier']?.toString());
    final userId = _asString(json['user_id'] ?? json['userId']);

    return FanMembership(
      id: _asString(json['id']),
      userId: userId,
      partnerId: _asString(json['partner_id'] ?? json['partnerId']),
      displayName: PublicUserIdentity.resolve(
        publicUserId:
            json['display_name']?.toString() ??
            json['users']?['public_user_id']?.toString(),
        userId: userId,
      ),
      tier: tier,
      points: points,
      chapter: _asString(json['chapter'], fallback: 'Kigali Central'),
      membershipNumber: _asString(
        json['membership_number'] ?? json['membershipNumber'],
      ),
      joinedAt:
          _asDateTime(json['joined_at'] ?? json['joinedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'user_id': userId,
      'partner_id': partnerId,
      'display_name': displayName,
      'tier': tier.value,
      'points': points,
      'chapter': chapter,
      'membership_number': membershipNumber,
      'joined_at': joinedAt.toIso8601String(),
    };
  }

  FanMembership copyWith({
    String? id,
    String? userId,
    String? partnerId,
    String? displayName,
    FanTier? tier,
    int? points,
    String? chapter,
    String? membershipNumber,
    DateTime? joinedAt,
  }) {
    return FanMembership(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      partnerId: partnerId ?? this.partnerId,
      displayName: displayName ?? this.displayName,
      tier: tier ?? this.tier,
      points: points ?? this.points,
      chapter: chapter ?? this.chapter,
      membershipNumber: membershipNumber ?? this.membershipNumber,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    partnerId,
    displayName,
    tier,
    points,
    chapter,
    membershipNumber,
    joinedAt,
  ];
}

class RsMatch extends Equatable {
  const RsMatch({
    required this.id,
    required this.homeTeam,
    required this.awayTeam,
    required this.competition,
    required this.venue,
    required this.matchDate,
    required this.kickoffTime,
    required this.isOnSale,
    required this.ticketGeneralPrice,
    required this.ticketVipPrice,
    required this.saleStartsAt,
    required this.capacity,
    this.soldCount = 0,
  });

  final String id;
  final String homeTeam;
  final String awayTeam;
  final String competition;
  final String venue;
  final DateTime matchDate;
  final String kickoffTime;
  final bool isOnSale;
  final int ticketGeneralPrice;
  final int ticketVipPrice;
  final DateTime saleStartsAt;
  final int capacity;
  final int soldCount;

  /// True when every available seat has been sold.
  bool get isSoldOut => capacity > 0 && soldCount >= capacity;

  /// Number of unsold seats (0 when unlimited or sold out).
  int get remainingCapacity =>
      capacity > 0 ? (capacity - soldCount).clamp(0, capacity) : 0;

  bool isAccessibleForTier(FanTier tier) {
    if (!isOnSale || capacity <= 0 || isSoldOut) {
      return false;
    }

    final accessStart = switch (tier) {
      FanTier.platinum => saleStartsAt.subtract(const Duration(hours: 72)),
      FanTier.gold => saleStartsAt.subtract(const Duration(hours: 48)),
      FanTier.silver => saleStartsAt.subtract(const Duration(hours: 24)),
      FanTier.blue => saleStartsAt,
    };

    final now = DateTime.now();
    return !now.isBefore(accessStart);
  }

  factory RsMatch.fromJson(Map<String, dynamic> json) {
    final matchDate =
        _asDateTime(json['match_date'] ?? json['matchDate']) ?? DateTime.now();

    return RsMatch(
      id: _asString(json['id']),
      homeTeam: _asString(
        json['home_team'] ?? json['homeTeam'],
        fallback: 'Rayon Sports FC',
      ),
      awayTeam: _asString(
        json['away_team'] ?? json['awayTeam'],
        fallback: 'Opponent',
      ),
      competition: _asString(
        json['competition'],
        fallback: 'Rwanda Premier League',
      ),
      venue: _asString(json['venue'], fallback: 'Kigali Pelé Stadium'),
      matchDate: matchDate,
      kickoffTime: _normalizeKickoff(
        json['kickoff_time'] ?? json['kickoffTime'],
      ),
      isOnSale: _asBool(json['is_on_sale'] ?? json['isOnSale'], fallback: true),
      ticketGeneralPrice: _asInt(
        json['ticket_general_price'] ?? json['ticketGeneralPrice'],
      ),
      ticketVipPrice: _asInt(
        json['ticket_vip_price'] ?? json['ticketVipPrice'],
      ),
      saleStartsAt:
          _asDateTime(json['sale_starts_at'] ?? json['saleStartsAt']) ??
          matchDate.subtract(const Duration(days: 7)),
      capacity: _asInt(json['capacity'], fallback: 0),
      soldCount: _asInt(json['sold_count'] ?? json['soldCount'], fallback: 0),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'home_team': homeTeam,
      'away_team': awayTeam,
      'competition': competition,
      'venue': venue,
      'match_date': matchDate.toIso8601String(),
      'kickoff_time': kickoffTime,
      'is_on_sale': isOnSale,
      'ticket_general_price': ticketGeneralPrice,
      'ticket_vip_price': ticketVipPrice,
      'sale_starts_at': saleStartsAt.toIso8601String(),
      'capacity': capacity,
      'sold_count': soldCount,
    };
  }

  RsMatch copyWith({
    String? id,
    String? homeTeam,
    String? awayTeam,
    String? competition,
    String? venue,
    DateTime? matchDate,
    String? kickoffTime,
    bool? isOnSale,
    int? ticketGeneralPrice,
    int? ticketVipPrice,
    DateTime? saleStartsAt,
    int? capacity,
    int? soldCount,
  }) {
    return RsMatch(
      id: id ?? this.id,
      homeTeam: homeTeam ?? this.homeTeam,
      awayTeam: awayTeam ?? this.awayTeam,
      competition: competition ?? this.competition,
      venue: venue ?? this.venue,
      matchDate: matchDate ?? this.matchDate,
      kickoffTime: kickoffTime ?? this.kickoffTime,
      isOnSale: isOnSale ?? this.isOnSale,
      ticketGeneralPrice: ticketGeneralPrice ?? this.ticketGeneralPrice,
      ticketVipPrice: ticketVipPrice ?? this.ticketVipPrice,
      saleStartsAt: saleStartsAt ?? this.saleStartsAt,
      capacity: capacity ?? this.capacity,
      soldCount: soldCount ?? this.soldCount,
    );
  }

  @override
  List<Object?> get props => [
    id,
    homeTeam,
    awayTeam,
    competition,
    venue,
    matchDate,
    kickoffTime,
    isOnSale,
    ticketGeneralPrice,
    ticketVipPrice,
    saleStartsAt,
    capacity,
    soldCount,
  ];
}

class RsTicket extends Equatable {
  const RsTicket({
    required this.id,
    required this.matchId,
    required this.match,
    required this.userId,
    required this.seatType,
    required this.amountPaid,
    required this.qrCode,
    required this.momoReference,
    required this.status,
    required this.purchasedAt,
  });

  final String id;
  final String matchId;
  final RsMatch match;
  final String userId;
  final SeatType seatType;
  final int amountPaid;
  final String qrCode;
  final String momoReference;
  final TicketStatus status;
  final DateTime purchasedAt;

  String get qrData {
    if (isSignedRayonTicketQr(qrCode)) {
      return qrCode;
    }

    return buildRayonTicketQrData(
      ticketId: id,
      matchId: matchId,
      purchasedAt: purchasedAt,
    );
  }

  // Convenience getters — delegate to nested match
  String get matchTitle => '${match.homeTeam} vs ${match.awayTeam}';
  DateTime get matchDate => match.matchDate;
  String get competition => match.competition;
  String get venue => match.venue;
  String get kickoffTime => match.kickoffTime;
  String get fanId => userId;

  factory RsTicket.fromJson(Map<String, dynamic> json) {
    final nestedMatch = _asMap(json['match'] ?? json['rs_matches']);
    final fallbackMatchDate = _asDateTime(json['match_date']) ?? DateTime.now();

    return RsTicket(
      id: _asString(json['id']),
      matchId: _asString(json['match_id'] ?? json['matchId']),
      match: nestedMatch.isNotEmpty
          ? RsMatch.fromJson(nestedMatch)
          : RsMatch(
              id: _asString(json['match_id'] ?? json['matchId']),
              homeTeam: _asString(
                json['home_team'] ?? json['homeTeam'],
                fallback: 'Rayon Sports FC',
              ),
              awayTeam: _asString(
                json['away_team'] ?? json['awayTeam'],
                fallback: 'Opponent',
              ),
              competition: _asString(
                json['competition'],
                fallback: 'Rwanda Premier League',
              ),
              venue: _asString(json['venue'], fallback: 'Kigali Pelé Stadium'),
              matchDate: fallbackMatchDate,
              kickoffTime: _normalizeKickoff(
                json['kickoff_time'] ?? json['kickoffTime'],
              ),
              isOnSale: _asBool(
                json['is_on_sale'] ?? json['isOnSale'],
                fallback: false,
              ),
              ticketGeneralPrice: _asInt(
                json['ticket_general_price'] ?? json['ticketGeneralPrice'],
              ),
              ticketVipPrice: _asInt(
                json['ticket_vip_price'] ?? json['ticketVipPrice'],
              ),
              saleStartsAt:
                  _asDateTime(json['sale_starts_at'] ?? json['saleStartsAt']) ??
                  fallbackMatchDate.subtract(const Duration(days: 7)),
              capacity: _asInt(json['capacity']),
            ),
      userId: _asString(json['user_id'] ?? json['userId']),
      seatType: SeatTypeX.fromValue(
        (json['seat_type'] ?? json['seatType'])?.toString(),
      ),
      amountPaid: _asInt(json['amount_paid'] ?? json['amountPaid']),
      qrCode: _asString(json['qr_code'] ?? json['qrCode']),
      momoReference: _asString(json['momo_reference'] ?? json['momoReference']),
      status: TicketStatusX.fromValue(
        (json['status'] ?? json['ticket_status'])?.toString(),
      ),
      purchasedAt:
          _asDateTime(json['purchased_at'] ?? json['purchasedAt']) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'match_id': matchId,
      'match': match.toJson(),
      'user_id': userId,
      'seat_type': seatType.value,
      'amount_paid': amountPaid,
      'qr_code': qrCode,
      'momo_reference': momoReference,
      'status': status.value,
      'purchased_at': purchasedAt.toIso8601String(),
    };
  }

  RsTicket copyWith({
    String? id,
    String? matchId,
    RsMatch? match,
    String? userId,
    SeatType? seatType,
    int? amountPaid,
    String? qrCode,
    String? momoReference,
    TicketStatus? status,
    DateTime? purchasedAt,
  }) {
    return RsTicket(
      id: id ?? this.id,
      matchId: matchId ?? this.matchId,
      match: match ?? this.match,
      userId: userId ?? this.userId,
      seatType: seatType ?? this.seatType,
      amountPaid: amountPaid ?? this.amountPaid,
      qrCode: qrCode ?? this.qrCode,
      momoReference: momoReference ?? this.momoReference,
      status: status ?? this.status,
      purchasedAt: purchasedAt ?? this.purchasedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    matchId,
    match,
    userId,
    seatType,
    amountPaid,
    qrCode,
    momoReference,
    status,
    purchasedAt,
  ];
}

class RsInitiative extends Equatable {
  const RsInitiative({
    required this.id,
    required this.partnerId,
    required this.title,
    required this.description,
    required this.category,
    required this.targetAmount,
    required this.raisedAmount,
    required this.supporterCount,
    required this.isActive,
    required this.endsAt,
  });

  final String id;
  final String partnerId;
  final String title;
  final String description;
  final InitiativeCategory category;
  final int targetAmount;
  final int raisedAmount;
  final int supporterCount;
  final bool isActive;
  final DateTime? endsAt;

  double get progressPercent {
    if (targetAmount <= 0) {
      return 0;
    }

    return ((raisedAmount / targetAmount) * 100).clamp(0, 100).toDouble();
  }

  String get progressDisplay {
    final percent = progressPercent;
    final whole = percent.truncateToDouble() == percent;
    return '${percent.toStringAsFixed(whole ? 0 : 1)}% funded';
  }

  /// Alias used by some widgets.
  double get progress => progressPercent / 100;

  factory RsInitiative.fromJson(Map<String, dynamic> json) {
    return RsInitiative(
      id: _asString(json['id']),
      partnerId: _asString(json['partner_id'] ?? json['partnerId']),
      title: _asString(json['title'], fallback: 'Club Initiative'),
      description: _asString(json['description']),
      category: InitiativeCategoryX.fromValue(
        (json['category'] ?? json['initiative_category'])?.toString(),
      ),
      targetAmount: _asInt(json['target_amount'] ?? json['targetAmount']),
      raisedAmount: _asInt(json['raised_amount'] ?? json['raisedAmount']),
      supporterCount: _asInt(json['supporter_count'] ?? json['supporterCount']),
      isActive: _asBool(json['is_active'] ?? json['isActive'], fallback: true),
      endsAt: _asDateTime(json['ends_at'] ?? json['endsAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'partner_id': partnerId,
      'title': title,
      'description': description,
      'category': category.value,
      'target_amount': targetAmount,
      'raised_amount': raisedAmount,
      'supporter_count': supporterCount,
      'is_active': isActive,
      'ends_at': endsAt?.toIso8601String(),
    };
  }

  RsInitiative copyWith({
    String? id,
    String? partnerId,
    String? title,
    String? description,
    InitiativeCategory? category,
    int? targetAmount,
    int? raisedAmount,
    int? supporterCount,
    bool? isActive,
    Object? endsAt = _unset,
  }) {
    return RsInitiative(
      id: id ?? this.id,
      partnerId: partnerId ?? this.partnerId,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      targetAmount: targetAmount ?? this.targetAmount,
      raisedAmount: raisedAmount ?? this.raisedAmount,
      supporterCount: supporterCount ?? this.supporterCount,
      isActive: isActive ?? this.isActive,
      endsAt: identical(endsAt, _unset) ? this.endsAt : endsAt as DateTime?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    partnerId,
    title,
    description,
    category,
    targetAmount,
    raisedAmount,
    supporterCount,
    isActive,
    endsAt,
  ];
}

class RsInitiativeContribution extends Equatable {
  const RsInitiativeContribution({
    required this.id,
    required this.initiativeId,
    required this.userId,
    required this.amount,
    required this.momoReference,
    required this.status,
    required this.createdAt,
    this.supporterName,
  });

  final String id;
  final String initiativeId;
  final String userId;
  final int amount;
  final String momoReference;
  final String status;
  final DateTime createdAt;
  final String? supporterName;

  factory RsInitiativeContribution.fromJson(Map<String, dynamic> json) {
    return RsInitiativeContribution(
      id: _asString(json['id']),
      initiativeId: _asString(json['initiative_id'] ?? json['initiativeId']),
      userId: _asString(json['user_id'] ?? json['userId']),
      amount: _asInt(json['amount']),
      momoReference: _asString(json['momo_reference'] ?? json['momoReference']),
      status: _asString(json['status'], fallback: 'pending'),
      createdAt:
          _asDateTime(json['created_at'] ?? json['createdAt']) ??
          DateTime.now(),
      supporterName: _asNullableString(
        json['supporter_name'] ?? json['supporterName'] ?? json['name'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'initiative_id': initiativeId,
      'user_id': userId,
      'amount': amount,
      'momo_reference': momoReference,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      if (supporterName != null) 'supporter_name': supporterName,
    };
  }

  RsInitiativeContribution copyWith({
    String? id,
    String? initiativeId,
    String? userId,
    int? amount,
    String? momoReference,
    String? status,
    DateTime? createdAt,
    Object? supporterName = _unset,
  }) {
    return RsInitiativeContribution(
      id: id ?? this.id,
      initiativeId: initiativeId ?? this.initiativeId,
      userId: userId ?? this.userId,
      amount: amount ?? this.amount,
      momoReference: momoReference ?? this.momoReference,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      supporterName: identical(supporterName, _unset)
          ? this.supporterName
          : supporterName as String?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    initiativeId,
    userId,
    amount,
    momoReference,
    status,
    createdAt,
    supporterName,
  ];
}

class RsProduct extends Equatable {
  const RsProduct({
    required this.id,
    required this.partnerId,
    required this.name,
    this.description = '',
    required this.category,
    required this.price,
    required this.imageEmoji,
    required this.bgColor,
    required this.stock,
    required this.isActive,
    required this.isNew,
    this.imageUrl,
    this.availableSizes = const <String>[],
    this.badgeLabel,
    this.collection,
    this.sortOrder = 0,
  });

  final String id;
  final String partnerId;
  final String name;
  final String description;
  final ProductCategory category;
  final int price;
  final String imageEmoji;
  final Color bgColor;
  final int stock;
  final bool isActive;
  final bool isNew;
  final String? imageUrl;
  final List<String> availableSizes;
  final String? badgeLabel;
  final String? collection;
  final int sortOrder;

  int discountedPrice(double discountPct) {
    final normalized = discountPct.clamp(0, 100);
    return (price * (1 - normalized / 100)).round();
  }

  factory RsProduct.fromJson(Map<String, dynamic> json) {
    final category = ProductCategoryX.fromValue(
      (json['category'] ?? json['product_category'])?.toString(),
    );

    return RsProduct(
      id: _asString(json['id']),
      partnerId: _asString(json['partner_id'] ?? json['partnerId']),
      name: _asString(json['name'], fallback: 'Shop Item'),
      description: _asString(json['description'] ?? json['short_description']),
      category: category,
      price: _asInt(json['price'] ?? json['price_rwf']),
      imageEmoji: _asString(
        json['image_emoji'] ?? json['imageEmoji'],
        fallback: _defaultEmojiForCategory(category),
      ),
      bgColor: _asColor(
        json['bg_color'] ?? json['bgColor'],
        fallback: category.defaultBackgroundColor,
      ),
      stock: _asInt(
        json['stock'],
        fallback: _asBool(json['in_stock'] ?? json['inStock'], fallback: true)
            ? 99
            : 0,
      ),
      isActive: _asBool(json['is_active'] ?? json['isActive'], fallback: true),
      isNew: _asBool(json['is_new'] ?? json['isNew']),
      imageUrl: _asNullableString(json['image_url'] ?? json['imageUrl']),
      availableSizes:
          _asList(
                json['sizes'] ??
                    json['available_sizes'] ??
                    json['availableSizes'],
              )
              .map((size) => size.toString().trim())
              .where((size) => size.isNotEmpty)
              .toList(growable: false),
      badgeLabel: _asNullableString(json['badge_label'] ?? json['badgeLabel']),
      collection: _asNullableString(json['collection']),
      sortOrder: _asInt(json['sort_order'] ?? json['sortOrder']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'partner_id': partnerId,
      'name': name,
      'description': description,
      'category': category.value,
      'price': price,
      'image_emoji': imageEmoji,
      'bg_color': bgColor.toARGB32(),
      'stock': stock,
      'is_active': isActive,
      'is_new': isNew,
      'image_url': imageUrl,
      'sizes': availableSizes,
      'badge_label': badgeLabel,
      'collection': collection,
      'sort_order': sortOrder,
    };
  }

  RsProduct copyWith({
    String? id,
    String? partnerId,
    String? name,
    String? description,
    ProductCategory? category,
    int? price,
    String? imageEmoji,
    Color? bgColor,
    int? stock,
    bool? isActive,
    bool? isNew,
    Object? imageUrl = _unset,
    List<String>? availableSizes,
    Object? badgeLabel = _unset,
    Object? collection = _unset,
    int? sortOrder,
  }) {
    return RsProduct(
      id: id ?? this.id,
      partnerId: partnerId ?? this.partnerId,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      price: price ?? this.price,
      imageEmoji: imageEmoji ?? this.imageEmoji,
      bgColor: bgColor ?? this.bgColor,
      stock: stock ?? this.stock,
      isActive: isActive ?? this.isActive,
      isNew: isNew ?? this.isNew,
      imageUrl: identical(imageUrl, _unset)
          ? this.imageUrl
          : imageUrl as String?,
      availableSizes: availableSizes ?? this.availableSizes,
      badgeLabel: identical(badgeLabel, _unset)
          ? this.badgeLabel
          : badgeLabel as String?,
      collection: identical(collection, _unset)
          ? this.collection
          : collection as String?,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  List<Object?> get props => [
    id,
    partnerId,
    name,
    description,
    category,
    price,
    imageEmoji,
    bgColor,
    stock,
    isActive,
    isNew,
    imageUrl,
    availableSizes,
    badgeLabel,
    collection,
    sortOrder,
  ];
}

class CartItem extends Equatable {
  const CartItem({
    required this.product,
    required this.quantity,
    required this.selectedVariant,
  });

  final RsProduct product;
  final int quantity;
  final String? selectedVariant;

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final rawProduct = _asMap(json['product']);
    final productJson = rawProduct.isNotEmpty
        ? rawProduct
        : <String, dynamic>{
            'id': json['product_id'],
            'name': json['name'],
            'description': json['description'],
            'category': json['category'],
            'price': json['unit_price'] ?? json['price'] ?? json['price_rwf'],
            'image_emoji': json['image_emoji'],
            'image_url': json['image_url'],
            'bg_color': json['bg_color'],
            'sizes': json['sizes'],
          };
    return CartItem(
      product: RsProduct.fromJson(productJson),
      quantity: _asInt(json['quantity'], fallback: 1).clamp(1, 9999),
      selectedVariant: _asNullableString(
        json['selected_variant'] ??
            json['selectedVariant'] ??
            json['selected_size'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'product': product.toJson(),
      'quantity': quantity,
      'selected_variant': selectedVariant,
    };
  }

  CartItem copyWith({
    RsProduct? product,
    int? quantity,
    Object? selectedVariant = _unset,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      selectedVariant: identical(selectedVariant, _unset)
          ? this.selectedVariant
          : selectedVariant as String?,
    );
  }

  @override
  List<Object?> get props => [product, quantity, selectedVariant];
}

class RsShopOrder extends Equatable {
  const RsShopOrder({
    required this.id,
    required this.userId,
    required this.items,
    required this.subtotal,
    required this.discountAmount,
    required this.deliveryFee,
    required this.total,
    required this.deliveryAddress,
    required this.momoReference,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final List<CartItem> items;
  final int subtotal;
  final int discountAmount;
  final int deliveryFee;
  final int total;
  final String deliveryAddress;
  final String momoReference;
  final OrderStatus status;
  final DateTime createdAt;

  factory RsShopOrder.fromJson(Map<String, dynamic> json) {
    final items = _asList(
      json['items'],
    ).map((item) => CartItem.fromJson(_asMap(item))).toList(growable: false);
    final subtotal = _asInt(json['subtotal']);
    final discountAmount = _asInt(
      json['discount_amount'] ?? json['discountAmount'] ?? json['discount'],
    );
    final deliveryFee = _asInt(json['delivery_fee'] ?? json['deliveryFee']);

    return RsShopOrder(
      id: _asString(json['id']),
      userId: _asString(json['user_id'] ?? json['userId']),
      items: items,
      subtotal: subtotal,
      discountAmount: discountAmount,
      deliveryFee: deliveryFee,
      total: _asInt(
        json['total'],
        fallback: subtotal - discountAmount + deliveryFee,
      ),
      deliveryAddress: _asString(
        json['delivery_address'] ?? json['deliveryAddress'],
      ),
      momoReference: _asString(json['momo_reference'] ?? json['momoReference']),
      status: OrderStatusX.fromValue((json['status'])?.toString()),
      createdAt:
          _asDateTime(json['created_at'] ?? json['createdAt']) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'user_id': userId,
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'subtotal': subtotal,
      'discount_amount': discountAmount,
      'delivery_fee': deliveryFee,
      'total': total,
      'delivery_address': deliveryAddress,
      'momo_reference': momoReference,
      'status': status.value,
      'created_at': createdAt.toIso8601String(),
    };
  }

  RsShopOrder copyWith({
    String? id,
    String? userId,
    List<CartItem>? items,
    int? subtotal,
    int? discountAmount,
    int? deliveryFee,
    int? total,
    String? deliveryAddress,
    String? momoReference,
    OrderStatus? status,
    DateTime? createdAt,
  }) {
    return RsShopOrder(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      discountAmount: discountAmount ?? this.discountAmount,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      total: total ?? this.total,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      momoReference: momoReference ?? this.momoReference,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    items,
    subtotal,
    discountAmount,
    deliveryFee,
    total,
    deliveryAddress,
    momoReference,
    status,
    createdAt,
  ];
}

class RsFanClub extends Equatable {
  const RsFanClub({
    required this.id,
    required this.partnerId,
    required this.name,
    required this.region,
    required this.description,
    required this.memberCount,
    required this.eventCount,
    required this.rating,
    required this.bannerEmoji,
  });

  final String id;
  final String partnerId;
  final String name;
  final String region;
  final String description;
  final int memberCount;
  final int eventCount;
  final double rating;
  final String bannerEmoji;

  factory RsFanClub.fromJson(Map<String, dynamic> json) {
    return RsFanClub(
      id: _asString(json['id']),
      partnerId: _asString(json['partner_id'] ?? json['partnerId']),
      name: _asString(json['name'], fallback: 'Fan Club'),
      region: _asString(json['region'], fallback: 'Kigali'),
      description: _asString(json['description']),
      memberCount: _asInt(json['member_count'] ?? json['memberCount']),
      eventCount: _asInt(json['event_count'] ?? json['eventCount']),
      rating: _asDouble(json['rating']),
      bannerEmoji: _asString(
        json['banner_emoji'] ?? json['bannerEmoji'],
        fallback: '🥁',
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'partner_id': partnerId,
      'name': name,
      'region': region,
      'description': description,
      'member_count': memberCount,
      'event_count': eventCount,
      'rating': rating,
      'banner_emoji': bannerEmoji,
    };
  }

  RsFanClub copyWith({
    String? id,
    String? partnerId,
    String? name,
    String? region,
    String? description,
    int? memberCount,
    int? eventCount,
    double? rating,
    String? bannerEmoji,
  }) {
    return RsFanClub(
      id: id ?? this.id,
      partnerId: partnerId ?? this.partnerId,
      name: name ?? this.name,
      region: region ?? this.region,
      description: description ?? this.description,
      memberCount: memberCount ?? this.memberCount,
      eventCount: eventCount ?? this.eventCount,
      rating: rating ?? this.rating,
      bannerEmoji: bannerEmoji ?? this.bannerEmoji,
    );
  }

  @override
  List<Object?> get props => [
    id,
    partnerId,
    name,
    region,
    description,
    memberCount,
    eventCount,
    rating,
    bannerEmoji,
  ];
}

class RsAchievement extends Equatable {
  const RsAchievement({
    required this.id,
    required this.userId,
    required this.badgeType,
    required this.emoji,
    required this.name,
    required this.description,
    required this.isEarned,
    required this.earnedAt,
  });

  final String id;
  final String userId;
  final String badgeType;
  final String emoji;
  final String name;
  final String description;
  final bool isEarned;
  final DateTime? earnedAt;

  factory RsAchievement.fromJson(Map<String, dynamic> json) {
    final earnedAt = _asDateTime(json['earned_at'] ?? json['earnedAt']);

    return RsAchievement(
      id: _asString(json['id']),
      userId: _asString(json['user_id'] ?? json['userId']),
      badgeType: _asString(json['badge_type'] ?? json['badgeType']),
      emoji: _asString(json['emoji'], fallback: '🏆'),
      name: _asString(json['name'], fallback: 'Achievement'),
      description: _asString(json['description']),
      isEarned: _asBool(
        json['is_earned'] ?? json['isEarned'],
        fallback: earnedAt != null,
      ),
      earnedAt: earnedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'user_id': userId,
      'badge_type': badgeType,
      'emoji': emoji,
      'name': name,
      'description': description,
      'is_earned': isEarned,
      'earned_at': earnedAt?.toIso8601String(),
    };
  }

  RsAchievement copyWith({
    String? id,
    String? userId,
    String? badgeType,
    String? emoji,
    String? name,
    String? description,
    bool? isEarned,
    Object? earnedAt = _unset,
  }) {
    return RsAchievement(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      badgeType: badgeType ?? this.badgeType,
      emoji: emoji ?? this.emoji,
      name: name ?? this.name,
      description: description ?? this.description,
      isEarned: isEarned ?? this.isEarned,
      earnedAt: identical(earnedAt, _unset)
          ? this.earnedAt
          : earnedAt as DateTime?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    badgeType,
    emoji,
    name,
    description,
    isEarned,
    earnedAt,
  ];
}

String _asString(dynamic value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }

  final string = value.toString().trim();
  return string.isEmpty ? fallback : string;
}

String? _asNullableString(dynamic value) {
  final string = _asString(value);
  return string.isEmpty ? null : string;
}

int _asInt(dynamic value, {int fallback = 0}) {
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

double _asDouble(dynamic value, {double fallback = 0}) {
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

bool _asBool(dynamic value, {bool fallback = false}) {
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

DateTime? _asDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  return DateTime.tryParse(value.toString());
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, dynamic>{};
}

List<dynamic> _asList(dynamic value) {
  return value is List ? value : const <dynamic>[];
}

Color _asColor(dynamic value, {required Color fallback}) {
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

String _normalizeKickoff(dynamic value) {
  final kickoff = _asString(value, fallback: '15:00');
  return kickoff.length > 5 ? kickoff.substring(0, 5) : kickoff;
}

// ═════════════════════════════════════════════════════════════════════════════
// Registry Member (ported from rayon_sports_models.dart)
// ═════════════════════════════════════════════════════════════════════════════

class RsRegistryMember {
  const RsRegistryMember({
    required this.userId,
    required this.displayName,
    required this.membershipNumber,
    required this.points,
    required this.tier,
    required this.chapter,
    required this.joinedAt,
  });

  final String userId;
  final String displayName;
  final String membershipNumber;
  final int points;
  final FanTier tier;
  final String chapter;
  final DateTime joinedAt;

  factory RsRegistryMember.fromJson(Map<String, dynamic> json) {
    final userId = json['user_id']?.toString() ?? '';
    return RsRegistryMember(
      userId: userId,
      displayName: PublicUserIdentity.resolve(
        publicUserId:
            json['display_name']?.toString() ??
            json['users']?['public_user_id']?.toString(),
        userId: userId,
      ),
      membershipNumber: json['membership_number']?.toString() ?? '',
      points: (json['points'] as num?)?.toInt() ?? 0,
      tier: FanTierX.fromValue(json['tier']?.toString()),
      chapter: json['chapter']?.toString() ?? 'Kigali Central',
      joinedAt:
          DateTime.tryParse(json['joined_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Backward-compat type aliases
// (so existing code that imports old class names keeps compiling)
// ═════════════════════════════════════════════════════════════════════════════

/// Old name → now [FanMembership].
typedef RsFanMembership = FanMembership;

/// Old name → now [RsProduct].
typedef RsShopProduct = RsProduct;

/// Old name → now [TicketStatus].
typedef RsTicketStatus = TicketStatus;

// ═════════════════════════════════════════════════════════════════════════════
// Aggregate data holder (ported from rayon_sports_models.dart)
// ═════════════════════════════════════════════════════════════════════════════

class RayonSportsData {
  const RayonSportsData({
    required this.partnerId,
    required this.membership,
    required this.joinedClubIds,
    required this.registryMembers,
    required this.achievements,
    required this.clubs,
    required this.products,
    required this.initiatives,
    required this.matches,
    required this.tickets,
  });

  final String partnerId;
  final FanMembership? membership;
  final Set<String> joinedClubIds;
  final List<RsRegistryMember> registryMembers;
  final List<RsAchievement> achievements;
  final List<RsFanClub> clubs;
  final List<RsProduct> products;
  final List<RsInitiative> initiatives;
  final List<RsMatch> matches;
  final List<RsTicket> tickets;

  RsFanClub? clubById(String id) {
    for (final club in clubs) {
      if (club.id == id) return club;
    }
    return null;
  }

  RsInitiative? initiativeById(String id) {
    for (final initiative in initiatives) {
      if (initiative.id == id) return initiative;
    }
    return null;
  }

  List<RsProduct> productsByIds(Iterable<String> ids) {
    final idSet = ids.toSet();
    return products.where((p) => idSet.contains(p.id)).toList();
  }
}
