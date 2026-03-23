import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/utils/json_helpers.dart' as jh;

class BiopayProfile {
  const BiopayProfile({
    required this.id,
    required this.publicId,
    required this.userId,
    required this.displayName,
    required this.routeType,
    required this.recipientValue,
    required this.countryCode,
    required this.active,
    required this.consentVersion,
    this.consentAt,
    this.createdAt,
    this.updatedAt,
    this.revokedAt,
  });

  final String id;
  final String publicId;
  final String userId;
  final String displayName;
  final MomoRecipientType routeType;
  final String recipientValue;
  final String countryCode;
  final bool active;
  final String consentVersion;
  final DateTime? consentAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? revokedAt;

  String get routeLabel => switch (routeType) {
    MomoRecipientType.phoneNumber => 'MoMo number',
    MomoRecipientType.code => 'Merchant code',
  };

  String get maskedRecipientValue {
    final trimmed = recipientValue.trim();
    if (trimmed.length <= 4) {
      return trimmed;
    }
    final prefixLength = trimmed.length >= 9 ? 3 : 2;
    final suffixLength = trimmed.length >= 9 ? 3 : 2;
    return '${trimmed.substring(0, prefixLength)}•••${trimmed.substring(trimmed.length - suffixLength)}';
  }

  CoolCountry get country =>
      CoolCountryCatalog.byIsoCode(countryCode) ?? AppMarket.country;

  factory BiopayProfile.fromJson(Map<String, dynamic> json) {
    return BiopayProfile(
      id: jh.asStringOrNull(json['id']) ?? '',
      publicId: jh.asStringOrNull(json['public_id']) ?? '',
      userId: jh.asStringOrNull(json['user_id']) ?? '',
      displayName: jh.asStringOrNull(json['display_name']) ?? '',
      routeType: _parseRouteType(json['route_type']),
      recipientValue: jh.asStringOrNull(json['recipient_value']) ?? '',
      countryCode:
          jh.asStringOrNull(json['country_code']) ?? AppMarket.countryCode,
      active: jh.asBool(json['active']),
      consentVersion: jh.asStringOrNull(json['consent_version']) ?? 'biopay-v1',
      consentAt: jh.parseDateTime(json['consent_at']),
      createdAt: jh.parseDateTime(json['created_at']),
      updatedAt: jh.parseDateTime(json['updated_at']),
      revokedAt: jh.parseDateTime(json['revoked_at']),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'public_id': publicId,
      'user_id': userId,
      'display_name': displayName,
      'route_type': _serializeRouteType(routeType),
      'recipient_value': recipientValue,
      'country_code': countryCode,
      'active': active,
      'consent_version': consentVersion,
      'consent_at': consentAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'revoked_at': revokedAt?.toIso8601String(),
    };
  }

  static MomoRecipientType _parseRouteType(Object? value) {
    return switch (value?.toString()) {
      'code' => MomoRecipientType.code,
      _ => MomoRecipientType.phoneNumber,
    };
  }

  static String _serializeRouteType(MomoRecipientType value) {
    return switch (value) {
      MomoRecipientType.phoneNumber => 'phone_number',
      MomoRecipientType.code => 'code',
    };
  }
}
