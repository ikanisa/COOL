part of 'rs_models.dart';

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
    this.expiresAt,
    this.renewedAt,
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
  final DateTime? expiresAt;
  final DateTime? renewedAt;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

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

  factory FanMembership.fromJson(RsJsonMap json) {
    final points = _asInt(json['points']);
    final tier = json['tier'] == null
        ? FanTierX.fromPoints(points)
        : FanTierX.fromValue(json['tier']?.toString());
    final userId = _asString(json['user_id'] ?? json['userId']);

    return FanMembership(
      id: _asString(json['id']),
      userId: userId,
      partnerId: _asString(json['partner_id'] ?? json['partnerId']),
      displayName: _resolveMembershipDisplayName(json, userId: userId),
      tier: tier,
      points: points,
      chapter: _asString(json['chapter'], fallback: 'Kigali Central'),
      membershipNumber: _asString(
        json['membership_number'] ?? json['membershipNumber'],
      ),
      joinedAt:
          _asDateTime(json['joined_at'] ?? json['joinedAt']) ?? DateTime.now(),
      expiresAt: _asDateTime(json['expires_at'] ?? json['expiresAt']),
      renewedAt: _asDateTime(json['renewed_at'] ?? json['renewedAt']),
    );
  }

  RsJsonMap toJson() {
    return <String, Object?>{
      'id': id,
      'user_id': userId,
      'partner_id': partnerId,
      'display_name': displayName,
      'tier': tier.value,
      'points': points,
      'chapter': chapter,
      'membership_number': membershipNumber,
      'joined_at': joinedAt.toIso8601String(),
      if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      if (renewedAt != null) 'renewed_at': renewedAt!.toIso8601String(),
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
    Object? expiresAt = _unset,
    Object? renewedAt = _unset,
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
      expiresAt: identical(expiresAt, _unset)
          ? this.expiresAt
          : expiresAt as DateTime?,
      renewedAt: identical(renewedAt, _unset)
          ? this.renewedAt
          : renewedAt as DateTime?,
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
    expiresAt,
    renewedAt,
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

  factory RsFanClub.fromJson(RsJsonMap json) {
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

  RsJsonMap toJson() {
    return <String, Object?>{
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

  factory RsRegistryMember.fromJson(RsJsonMap json) {
    final userId = json['user_id']?.toString() ?? '';
    return RsRegistryMember(
      userId: userId,
      displayName: _resolveMembershipDisplayName(json, userId: userId),
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

String _resolveMembershipDisplayName(RsJsonMap json, {required String userId}) {
  final explicitDisplayName = _asString(
    json['display_name'] ?? json['displayName'],
  );
  if (explicitDisplayName.isNotEmpty) {
    return explicitDisplayName;
  }

  final userJson = _asMap(json['users']);
  final nestedFullName = _asString(userJson['full_name'] ?? userJson['name']);
  if (nestedFullName.isNotEmpty) {
    return nestedFullName;
  }

  return PublicUserIdentity.resolve(
    publicUserId:
        userJson['public_user_id']?.toString() ??
        json['public_user_id']?.toString(),
    userId: userId,
    fallback: 'Fan',
  );
}
