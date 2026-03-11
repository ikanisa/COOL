import '../../../core/config/country_catalog.dart';

class Group {
  const Group({
    this.id,
    required this.creatorId,
    required this.name,
    required this.type,
    required this.visibility,
    required this.amount,
    required this.targetAmount,
    required this.country,
    this.memberCount = 0,
    this.monthlyContribution,
    this.description,
    this.bankPartner,
    this.momoNumber,
    this.momoRouteType,
    this.institutionId,
    this.inviteCode,
    this.frequency,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String creatorId;
  final String name;
  final String type;
  final String visibility;
  final int amount;
  final int targetAmount;
  final String country;
  final int memberCount;
  final int? monthlyContribution;
  final String? description;
  final String? bankPartner;
  final String? momoNumber;
  final String? momoRouteType;
  final String? institutionId;
  final String? inviteCode;
  final String? frequency;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Group.fromJson(Map<String, dynamic> json) {
    final rawCountry = json['country']?.toString() ?? '';
    final fundPurpose = json['fund_purpose']?.toString().toUpperCase();
    final rawVisibility =
        json['visibility']?.toString() ??
        json['group_type']?.toString() ??
        json['type']?.toString() ??
        (_asBool(json['is_public']) ? 'public' : 'private');
    final visibility = _normalizeVisibility(rawVisibility);
    final type = _normalizeType(
      json['type']?.toString(),
      fundPurpose: fundPurpose,
      fallbackVisibility: visibility,
    );

    return Group(
      id: json['id']?.toString(),
      creatorId: json['creator_id']?.toString() ?? '',
      name: json['name']?.toString() ?? json['group_name']?.toString() ?? '',
      type: type,
      visibility: visibility,
      amount: _asInt(
        json['amount'] ??
            json['balance'] ??
            json['current_amount'] ??
            json['raised_amount'] ??
            json['contribution_amount'],
      ),
      targetAmount: _asInt(
        json['target_amount'] ??
            json['expected_amount'] ??
            json['contribution_amount'],
      ),
      country: rawCountry.isEmpty
          ? ''
          : CoolCountryCatalog.normalizeCountryCode(rawCountry),
      memberCount: _extractMemberCount(json),
      monthlyContribution:
          _nullableInt(json['monthly_contribution']) ??
          _nullableInt(json['contribution_amount']) ??
          _nullableInt(json['expected_amount']),
      description:
          json['description']?.toString() ??
          json['group_description']?.toString(),
      bankPartner:
          json['bank_partner']?.toString() ?? json['bank_ref']?.toString(),
      momoNumber:
          json['momo_number']?.toString() ??
          json['receiving_momo_code']?.toString(),
      momoRouteType: json['receiving_momo_route_type']?.toString(),
      institutionId: json['institution_id']?.toString(),
      inviteCode: json['invite_code']?.toString(),
      frequency: _normalizeFrequency(json['frequency'], json['cycle_days']),
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    final normalizedCountry = country.isEmpty
        ? ''
        : CoolCountryCatalog.normalizeCountryCode(country);
    final data = <String, dynamic>{
      'id': id,
      'creator_id': creatorId,
      'name': name,
      'type': type,
      'visibility': visibility,
      'amount': amount,
      'target_amount': targetAmount,
      'country': normalizedCountry,
      'member_count': memberCount,
      'monthly_contribution': monthlyContribution,
      'description': description,
      'bank_partner': bankPartner,
      'momo_number': momoNumber,
      'receiving_momo_route_type': momoRouteType,
      'institution_id': institutionId,
      'invite_code': inviteCode,
      'frequency': frequency,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };

    data.removeWhere((_, value) => value == null);
    return data;
  }

  Map<String, dynamic> toInsertJson() {
    final normalizedCountry = country.isEmpty
        ? ''
        : CoolCountryCatalog.normalizeCountryCode(country);
    final data = <String, dynamic>{
      'creator_id': creatorId,
      'name': name,
      'type': type,
      'visibility': visibility,
      'amount': amount,
      'target_amount': targetAmount,
      'country': normalizedCountry,
      'monthly_contribution': monthlyContribution,
      'description': description,
      'bank_partner': bankPartner,
      'momo_number': momoNumber,
      'receiving_momo_route_type': momoRouteType,
      'institution_id': institutionId,
      'invite_code': inviteCode,
      'frequency': frequency,
    };

    data.removeWhere((_, value) => value == null);
    return data;
  }

  Group copyWith({
    String? id,
    String? creatorId,
    String? name,
    String? type,
    String? visibility,
    int? amount,
    int? targetAmount,
    String? country,
    int? memberCount,
    int? monthlyContribution,
    String? description,
    String? bankPartner,
    String? momoNumber,
    String? momoRouteType,
    String? institutionId,
    String? inviteCode,
    String? frequency,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Group(
      id: id ?? this.id,
      creatorId: creatorId ?? this.creatorId,
      name: name ?? this.name,
      type: type ?? this.type,
      visibility: visibility ?? this.visibility,
      amount: amount ?? this.amount,
      targetAmount: targetAmount ?? this.targetAmount,
      country: country == null
          ? this.country
          : country.isEmpty
          ? ''
          : CoolCountryCatalog.normalizeCountryCode(country),
      memberCount: memberCount ?? this.memberCount,
      monthlyContribution: monthlyContribution ?? this.monthlyContribution,
      description: description ?? this.description,
      bankPartner: bankPartner ?? this.bankPartner,
      momoNumber: momoNumber ?? this.momoNumber,
      momoRouteType: momoRouteType ?? this.momoRouteType,
      institutionId: institutionId ?? this.institutionId,
      inviteCode: inviteCode ?? this.inviteCode,
      frequency: frequency ?? this.frequency,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

String _normalizeVisibility(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.contains('public')) {
    return 'public';
  }
  return 'private';
}

String _normalizeType(
  String? legacyType, {
  String? fundPurpose,
  required String fallbackVisibility,
}) {
  final normalizedLegacy = legacyType?.trim().toLowerCase() ?? '';
  final normalizedPurpose = fundPurpose?.trim().toUpperCase() ?? '';

  if (normalizedPurpose == 'COMMUNITY_COLLECTION') {
    return 'community';
  }
  if (normalizedPurpose == 'GROUP_SAVINGS') {
    return 'saving';
  }
  if (normalizedLegacy.contains('community')) {
    return 'community';
  }
  if (normalizedLegacy.contains('saving')) {
    return 'saving';
  }
  if (normalizedLegacy == 'public' || normalizedLegacy == 'private') {
    return fallbackVisibility == 'public' ? 'community' : 'saving';
  }
  return 'saving';
}

int _extractMemberCount(Map<String, dynamic> json) {
  final directCount = _nullableInt(json['member_count']);
  if (directCount != null) {
    return directCount;
  }

  final counts = json['member_counts'];
  if (counts is List && counts.isNotEmpty) {
    final first = counts.first;
    if (first is Map) {
      return _asInt(first['count']);
    }
  }

  final members = json['group_members'] ?? json['members'];
  if (members is List) {
    return members.length;
  }

  return 0;
}

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

int? _nullableInt(dynamic value) {
  if (value == null) {
    return null;
  }
  return _asInt(value);
}

bool _asBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.toLowerCase().trim();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}

String? _normalizeFrequency(dynamic frequency, dynamic cycleDays) {
  final normalized = frequency?.toString().trim().toLowerCase();
  if (normalized != null && normalized.isNotEmpty) {
    return normalized;
  }

  final days = _nullableInt(cycleDays);
  if (days == null) {
    return null;
  }
  if (days <= 1) {
    return 'daily';
  }
  if (days <= 7) {
    return 'weekly';
  }
  return 'monthly';
}
