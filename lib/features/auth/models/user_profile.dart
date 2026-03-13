import '../../../core/config/country_catalog.dart';
import '../../../core/identity/public_user_identity.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.phone,
    required this.fullName,
    this.publicUserId = '',
    required this.momoNumber,
    this.momoCode,
    this.momoRouteType,
    required this.momoProvider,
    required this.country,
    required this.languageCode,
    required this.isDriver,
    this.isAdmin = false,
    this.vehicleType,
    this.avatarUrl,
    this.officialName,
    this.officialPhone,
    this.kycStatus = 'unverified',
    this.kycVerifiedAt,
    this.creditConsentGrantedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String phone;
  final String fullName;
  final String publicUserId;
  final String momoNumber;
  final String? momoCode;
  final MomoRecipientType? momoRouteType;
  final String momoProvider;
  final String country;
  final String languageCode;
  final bool isDriver;
  final bool isAdmin;
  final String? vehicleType;
  final String? avatarUrl;
  final String? officialName;
  final String? officialPhone;
  final String kycStatus;
  final DateTime? kycVerifiedAt;
  final DateTime? creditConsentGrantedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasBasicProfile =>
      fullName.trim().isNotEmpty && country.trim().isNotEmpty;

  bool get hasMomoRecipient => momoRecipientValue.isNotEmpty;

  bool get hasOfficialIdentity =>
      (officialName?.trim().isNotEmpty ?? false) &&
      (officialPhone?.trim().isNotEmpty ?? false);

  /// A user is minimally ready for in-app flows when the public profile and
  /// wallet receive route are both configured.
  bool get isProfileComplete => hasBasicProfile && hasMomoRecipient;

  String get persistedPublicUserId =>
      PublicUserIdentity.normalize(publicUserId);

  MomoRecipientType? get effectiveMomoRouteType {
    if (momoRouteType != null) {
      return momoRouteType;
    }

    final trimmedNumber = momoNumber.trim();
    final trimmedCode = momoCode?.trim() ?? '';
    if (trimmedNumber.isNotEmpty) {
      return MomoRecipientType.phoneNumber;
    }
    if (trimmedCode.isNotEmpty) {
      return MomoRecipientType.code;
    }
    return null;
  }

  String get momoRecipientValue {
    return switch (effectiveMomoRouteType) {
      MomoRecipientType.code => momoCode?.trim() ?? '',
      MomoRecipientType.phoneNumber => momoNumber.trim(),
      null =>
        momoCode?.trim().isNotEmpty == true
            ? momoCode!.trim()
            : momoNumber.trim(),
    };
  }

  bool get canShowMomoQr =>
      effectiveMomoRouteType == MomoRecipientType.phoneNumber &&
      momoNumber.trim().isNotEmpty;

  String get displayUserId => PublicUserIdentity.resolve(
    publicUserId: publicUserId,
    userId: id,
    phone: phone,
  );

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final phone = json['phone']?.toString() ?? '';
    final rawCountry = json['country']?.toString() ?? '';
    final country = rawCountry.isEmpty
        ? ''
        : CoolCountryCatalog.normalizeCountryCode(rawCountry);
    final rawProvider = json['momo_provider']?.toString() ?? '';
    final rawMomoNumber = json['momo_number']?.toString() ?? '';
    final normalizedMomoNumber = _normalizeStoredMomoNumber(
      rawMomoNumber: rawMomoNumber,
      country: country,
      providerId: rawProvider,
    );

    return UserProfile(
      id: json['id']?.toString() ?? '',
      phone: phone,
      fullName: json['full_name']?.toString() ?? json['name']?.toString() ?? '',
      publicUserId: PublicUserIdentity.normalize(
        json['public_user_id']?.toString() ?? json['publicUserId']?.toString(),
      ),
      momoNumber: normalizedMomoNumber,
      momoCode: json['momo_code']?.toString(),
      momoRouteType: _parseMomoRecipientType(
        json['momo_route_type']?.toString(),
      ),
      momoProvider: rawProvider.isEmpty && country.isEmpty && phone.isEmpty
          ? ''
          : CoolCountryCatalog.normalizeProviderId(
              providerId: rawProvider,
              country: country,
              phone: phone,
            ),
      country: country,
      languageCode:
          json['language_code']?.toString() ??
          json['language']?.toString() ??
          'en',
      isDriver: _asBool(json['is_driver']),
      isAdmin: _asBool(json['is_admin']),
      vehicleType: json['vehicle_type']?.toString(),
      avatarUrl: _asNonEmptyString(json['avatar_url']),
      officialName: _asNonEmptyString(json['official_name']),
      officialPhone: _asNonEmptyString(json['official_phone']),
      kycStatus: _asNonEmptyString(json['kyc_status']) ?? 'unverified',
      kycVerifiedAt: _parseDateTime(json['kyc_verified_at']),
      creditConsentGrantedAt: _parseDateTime(json['credit_consent_granted_at']),
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    final normalizedCountry = country.isEmpty
        ? ''
        : CoolCountryCatalog.normalizeCountryCode(country);
    final normalizedProvider =
        momoProvider.isEmpty && normalizedCountry.isEmpty && phone.isEmpty
        ? ''
        : CoolCountryCatalog.normalizeProviderId(
            providerId: momoProvider,
            country: normalizedCountry,
            phone: phone,
          );

    final data = <String, dynamic>{
      'id': id,
      'phone': phone,
      'full_name': fullName,
      'public_user_id': persistedPublicUserId.isEmpty
          ? null
          : persistedPublicUserId,
      'momo_number': momoNumber,
      'momo_code': momoCode,
      'momo_route_type': _serializeMomoRecipientType(effectiveMomoRouteType),
      'momo_provider': normalizedProvider,
      'country': normalizedCountry,
      'language_code': languageCode,
      'is_driver': isDriver,
      'is_admin': isAdmin,
      'vehicle_type': vehicleType,
      'avatar_url': _asNonEmptyString(avatarUrl),
      'official_name': _asNonEmptyString(officialName),
      'official_phone': _asNonEmptyString(officialPhone),
      'kyc_status': kycStatus,
      'kyc_verified_at': kycVerifiedAt?.toIso8601String(),
      'credit_consent_granted_at': creditConsentGrantedAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };

    data.removeWhere((_, value) => value == null);
    return data;
  }

  UserProfile copyWith({
    String? id,
    String? phone,
    String? fullName,
    String? publicUserId,
    String? momoNumber,
    String? momoCode,
    MomoRecipientType? momoRouteType,
    String? momoProvider,
    String? country,
    String? languageCode,
    bool? isDriver,
    bool? isAdmin,
    String? vehicleType,
    String? avatarUrl,
    String? officialName,
    String? officialPhone,
    String? kycStatus,
    DateTime? kycVerifiedAt,
    DateTime? creditConsentGrantedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final nextPhone = phone ?? this.phone;
    final nextCountry = country ?? this.country;
    final nextProvider = momoProvider ?? this.momoProvider;

    return UserProfile(
      id: id ?? this.id,
      phone: nextPhone,
      fullName: fullName ?? this.fullName,
      publicUserId: PublicUserIdentity.normalize(publicUserId) != ''
          ? PublicUserIdentity.normalize(publicUserId)
          : this.publicUserId,
      momoNumber: momoNumber ?? this.momoNumber,
      momoCode: momoCode ?? this.momoCode,
      momoRouteType: momoRouteType ?? this.momoRouteType,
      momoProvider:
          nextProvider.isEmpty && nextCountry.isEmpty && nextPhone.isEmpty
          ? ''
          : CoolCountryCatalog.normalizeProviderId(
              providerId: nextProvider,
              country: nextCountry,
              phone: nextPhone,
            ),
      country: nextCountry.isEmpty
          ? ''
          : CoolCountryCatalog.normalizeCountryCode(nextCountry),
      languageCode: languageCode ?? this.languageCode,
      isDriver: isDriver ?? this.isDriver,
      isAdmin: isAdmin ?? this.isAdmin,
      vehicleType: vehicleType ?? this.vehicleType,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      officialName: officialName ?? this.officialName,
      officialPhone: officialPhone ?? this.officialPhone,
      kycStatus: kycStatus ?? this.kycStatus,
      kycVerifiedAt: kycVerifiedAt ?? this.kycVerifiedAt,
      creditConsentGrantedAt:
          creditConsentGrantedAt ?? this.creditConsentGrantedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
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

String? _asNonEmptyString(dynamic value) {
  if (value == null) {
    return null;
  }
  final normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

MomoRecipientType? _parseMomoRecipientType(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'phone_number' => MomoRecipientType.phoneNumber,
    'code' => MomoRecipientType.code,
    _ => null,
  };
}

String? _serializeMomoRecipientType(MomoRecipientType? value) {
  return switch (value) {
    MomoRecipientType.phoneNumber => 'phone_number',
    MomoRecipientType.code => 'code',
    null => null,
  };
}

String _normalizeStoredMomoNumber({
  required String rawMomoNumber,
  required String country,
  required String providerId,
}) {
  final trimmed = rawMomoNumber.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  final shouldNormalize =
      country.isNotEmpty || providerId.isNotEmpty || trimmed.startsWith('+');
  if (!shouldNormalize) {
    return trimmed;
  }

  try {
    final resolvedCountry = CoolCountryCatalog.resolve(
      country: country,
      phone: trimmed,
      providerId: providerId,
    );
    return resolvedCountry.normalizeNationalPhone(trimmed);
  } catch (_) {
    return trimmed;
  }
}
