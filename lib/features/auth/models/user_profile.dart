import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/identity/public_user_identity.dart';
import '../../../core/utils/json_helpers.dart' as jh;

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
    String? languageCode = AppMarket.languageCode,
    required this.isDriver,
    this.isAdmin = false,
    this.vehicleType,
    this.avatarUrl,
    this.officialName,
    this.officialPhone,
    this.dateOfBirth,
    this.nationalIdNumber,
    this.kycDocumentType,
    this.kycExtractedAt,
    this.kycExtractionProvider,
    this.identityData = const <String, Object?>{},
    this.kycSelfieUrl,
    this.kycIdPhotoUrl,
    this.kycStatus = 'unverified',
    this.kycVerifiedAt,
    this.creditConsentGrantedAt,
    this.themePreference = 'system',
    this.themePreferenceUpdatedAt,
    this.createdAt,
    this.updatedAt,
  }) : languageCode = AppMarket.languageCode;

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
  final String? dateOfBirth;
  final String? nationalIdNumber;
  final String? kycDocumentType;
  final DateTime? kycExtractedAt;
  final String? kycExtractionProvider;
  final Map<String, Object?> identityData;
  final String? kycSelfieUrl;
  final String? kycIdPhotoUrl;
  final String kycStatus;
  final DateTime? kycVerifiedAt;
  final DateTime? creditConsentGrantedAt;
  final String themePreference;
  final DateTime? themePreferenceUpdatedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasBasicProfile =>
      fullName.trim().isNotEmpty && country.trim().isNotEmpty;

  bool get hasMomoRecipient => momoRecipientValue.isNotEmpty;

  bool get hasOfficialIdentity =>
      (officialName?.trim().isNotEmpty ?? false) &&
      (dateOfBirth?.trim().isNotEmpty ?? false) &&
      (nationalIdNumber?.trim().isNotEmpty ?? false);

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
          AppMarket.languageCode,
      isDriver: _asBool(json['is_driver']),
      isAdmin: _asBool(json['is_admin']),
      vehicleType: json['vehicle_type']?.toString(),
      avatarUrl: _asNonEmptyString(json['avatar_url']),
      officialName: _asNonEmptyString(json['official_name']),
      officialPhone: _asNonEmptyString(json['official_phone']),
      dateOfBirth: _asNonEmptyString(json['date_of_birth']),
      nationalIdNumber: _asNonEmptyString(json['national_id_number']),
      kycDocumentType: _asNonEmptyString(json['kyc_document_type']),
      kycExtractedAt: _parseDateTime(json['kyc_extracted_at']),
      kycExtractionProvider: _asNonEmptyString(json['kyc_extraction_provider']),
      identityData: _asJsonMap(json['identity_data']),
      kycSelfieUrl: _asNonEmptyString(json['kyc_selfie_url']),
      kycIdPhotoUrl: _asNonEmptyString(json['kyc_id_photo_url']),
      kycStatus: _asNonEmptyString(json['kyc_status']) ?? 'unverified',
      kycVerifiedAt: _parseDateTime(json['kyc_verified_at']),
      creditConsentGrantedAt: _parseDateTime(json['credit_consent_granted_at']),
      themePreference: json['theme_preference']?.toString() ?? 'system',
      themePreferenceUpdatedAt: _parseDateTime(
        json['theme_preference_updated_at'],
      ),
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
      'language_code': AppMarket.languageCode,
      'is_driver': isDriver,
      'is_admin': isAdmin,
      'vehicle_type': vehicleType,
      'avatar_url': _asNonEmptyString(avatarUrl),
      'official_name': _asNonEmptyString(officialName),
      'official_phone': _asNonEmptyString(officialPhone),
      'date_of_birth': _asNonEmptyString(dateOfBirth),
      'national_id_number': _asNonEmptyString(nationalIdNumber),
      'kyc_document_type': _asNonEmptyString(kycDocumentType),
      'kyc_extracted_at': kycExtractedAt?.toIso8601String(),
      'kyc_extraction_provider': _asNonEmptyString(kycExtractionProvider),
      'identity_data': identityData,
      'kyc_selfie_url': _asNonEmptyString(kycSelfieUrl),
      'kyc_id_photo_url': _asNonEmptyString(kycIdPhotoUrl),
      'kyc_status': kycStatus,
      'kyc_verified_at': kycVerifiedAt?.toIso8601String(),
      'credit_consent_granted_at': creditConsentGrantedAt?.toIso8601String(),
      'theme_preference': themePreference,
      'theme_preference_updated_at': themePreferenceUpdatedAt
          ?.toIso8601String(),
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
    String? dateOfBirth,
    String? nationalIdNumber,
    String? kycDocumentType,
    DateTime? kycExtractedAt,
    String? kycExtractionProvider,
    Map<String, Object?>? identityData,
    String? kycSelfieUrl,
    String? kycIdPhotoUrl,
    String? kycStatus,
    DateTime? kycVerifiedAt,
    DateTime? creditConsentGrantedAt,
    String? themePreference,
    DateTime? themePreferenceUpdatedAt,
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
      languageCode: AppMarket.languageCode,
      isDriver: isDriver ?? this.isDriver,
      isAdmin: isAdmin ?? this.isAdmin,
      vehicleType: vehicleType ?? this.vehicleType,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      officialName: officialName ?? this.officialName,
      officialPhone: officialPhone ?? this.officialPhone,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      nationalIdNumber: nationalIdNumber ?? this.nationalIdNumber,
      kycDocumentType: kycDocumentType ?? this.kycDocumentType,
      kycExtractedAt: kycExtractedAt ?? this.kycExtractedAt,
      kycExtractionProvider:
          kycExtractionProvider ?? this.kycExtractionProvider,
      identityData: identityData ?? this.identityData,
      kycSelfieUrl: kycSelfieUrl ?? this.kycSelfieUrl,
      kycIdPhotoUrl: kycIdPhotoUrl ?? this.kycIdPhotoUrl,
      kycStatus: kycStatus ?? this.kycStatus,
      kycVerifiedAt: kycVerifiedAt ?? this.kycVerifiedAt,
      creditConsentGrantedAt:
          creditConsentGrantedAt ?? this.creditConsentGrantedAt,
      themePreference: themePreference ?? this.themePreference,
      themePreferenceUpdatedAt:
          themePreferenceUpdatedAt ?? this.themePreferenceUpdatedAt,
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

Map<String, Object?> _asJsonMap(dynamic value) {
  final map = jh.asMapOrNull(value);
  return map == null
      ? const <String, Object?>{}
      : Map<String, Object?>.from(map);
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
