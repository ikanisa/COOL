import '../../../core/config/country_catalog.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.phone,
    required this.fullName,
    required this.momoNumber,
    this.momoCode,
    required this.momoProvider,
    required this.country,
    required this.languageCode,
    required this.isDriver,
    this.isAdmin = false,
    this.vehicleType,
    this.officialName,
    this.officialPhone,
    this.kycStatus = 'unverified',
    this.creditConsentGrantedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String phone;
  final String fullName;
  final String momoNumber;
  final String? momoCode;
  final String momoProvider;
  final String country;
  final String languageCode;
  final bool isDriver;
  final bool isAdmin;
  final String? vehicleType;
  final String? officialName;
  final String? officialPhone;
  final String kycStatus;
  final DateTime? creditConsentGrantedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// A profile is complete when registration has been finished.
  /// Minimum: fullName + country must be non-empty.
  bool get isProfileComplete => fullName.isNotEmpty && country.isNotEmpty;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final phone = json['phone']?.toString() ?? '';
    final rawCountry = json['country']?.toString() ?? '';
    final country = rawCountry.isEmpty
        ? ''
        : CoolCountryCatalog.normalizeCountryCode(rawCountry);
    final rawProvider = json['momo_provider']?.toString() ?? '';

    return UserProfile(
      id: json['id']?.toString() ?? '',
      phone: phone,
      fullName: json['full_name']?.toString() ?? json['name']?.toString() ?? '',
      momoNumber: json['momo_number']?.toString() ?? '',
      momoCode: json['momo_code']?.toString(),
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
      officialName:
          _asNonEmptyString(json['official_name']) ??
          _asNonEmptyString(json['full_name']),
      officialPhone:
          _asNonEmptyString(json['official_phone']) ??
          _asNonEmptyString(json['phone']),
      kycStatus: _asNonEmptyString(json['kyc_status']) ?? 'unverified',
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
      'momo_number': momoNumber,
      'momo_code': momoCode,
      'momo_provider': normalizedProvider,
      'country': normalizedCountry,
      'language_code': languageCode,
      'is_driver': isDriver,
      'is_admin': isAdmin,
      'vehicle_type': vehicleType,
      'official_name': officialName ?? fullName,
      'official_phone': officialPhone ?? phone,
      'kyc_status': kycStatus,
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
    String? momoNumber,
    String? momoCode,
    String? momoProvider,
    String? country,
    String? languageCode,
    bool? isDriver,
    bool? isAdmin,
    String? vehicleType,
    String? officialName,
    String? officialPhone,
    String? kycStatus,
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
      momoNumber: momoNumber ?? this.momoNumber,
      momoCode: momoCode ?? this.momoCode,
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
      officialName: officialName ?? this.officialName,
      officialPhone: officialPhone ?? this.officialPhone,
      kycStatus: kycStatus ?? this.kycStatus,
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
