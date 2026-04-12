import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/config/env_config.dart';
import '../../../core/services/momo_service.dart';

class AuthProfileData {
  const AuthProfileData({
    required this.fullName,
    required this.momoNumber,
    this.momoCode,
    this.momoRouteType,
    required this.momoProvider,
    required this.country,
    required this.languageCode,
    this.phone,
  });

  final String fullName;
  final String momoNumber;
  final String? momoCode;
  final MomoRecipientType? momoRouteType;
  final String momoProvider;
  final String country;
  final String languageCode;
  final String? phone;
}

final currentUserCountryCodeProvider = Provider<String>((ref) {
  return AppMarket.countryCode;
});

String resolveAuthStateCountryCode(Object _) {
  return AppMarket.countryCode;
}

typedef NormalizedMomoIdentity = ({
  String momoNumber,
  String? momoCode,
  MomoRecipientType? momoRouteType,
  String momoProvider,
  String country,
});

Future<NormalizedMomoIdentity> normalizeMomoIdentity({
  required MomoService momoService,
  required String momoNumber,
  String? momoCode,
  MomoRecipientType? preferredRouteType,
  String? fallbackCountry,
  String? fallbackProviderId,
}) async {
  final trimmedMomoNumber = momoNumber.trim();
  final trimmedMomoCode = momoCode?.trim() ?? '';
  if (trimmedMomoNumber.isEmpty && trimmedMomoCode.isEmpty) {
    final countryCode = (fallbackCountry ?? AppMarket.countryCode).trim();
    return (
      momoNumber: '',
      momoCode: null,
      momoRouteType: null,
      momoProvider: '',
      country: countryCode.isEmpty ? AppMarket.countryCode : countryCode,
    );
  }

  final seedCountry = await momoService.resolveCountry(
    countryCode: fallbackCountry ?? AppMarket.countryCode,
    phone: trimmedMomoNumber.isEmpty ? null : trimmedMomoNumber,
    providerId: fallbackProviderId,
  );
  final resolvedCountry = await momoService.resolveCountry(
    countryCode: seedCountry.isoCode,
    phone: trimmedMomoNumber.isEmpty ? null : trimmedMomoNumber,
    providerId: fallbackProviderId ?? seedCountry.providerId,
  );
  final normalizedMomoNumber = trimmedMomoNumber.isEmpty
      ? ''
      : resolvedCountry.normalizeNationalPhone(trimmedMomoNumber);
  final normalizedMomoCode = trimmedMomoCode.isEmpty
      ? null
      : resolvedCountry.normalizeMerchantCode(trimmedMomoCode);
  final momoRouteType = switch (preferredRouteType) {
    MomoRecipientType.phoneNumber =>
      normalizedMomoNumber.isEmpty
          ? throw const FormatException(
              'MoMo number is required for the selected default route.',
            )
          : MomoRecipientType.phoneNumber,
    MomoRecipientType.code =>
      normalizedMomoCode == null
          ? throw const FormatException(
              'MoMo code is required for the selected default route.',
            )
          : MomoRecipientType.code,
    null =>
      normalizedMomoNumber.isNotEmpty
          ? MomoRecipientType.phoneNumber
          : normalizedMomoCode == null
          ? null
          : MomoRecipientType.code,
  };

  return (
    momoNumber: normalizedMomoNumber,
    momoCode: normalizedMomoCode,
    momoRouteType: momoRouteType,
    momoProvider: resolvedCountry.providerId,
    country: resolvedCountry.isoCode,
  );
}

String describeAuthError(Object error) {
  final raw = error.toString();
  if (raw.contains('signup_disabled')) {
    return 'Anonymous sign-in is disabled for this Supabase project. '
        'Enable anonymous users or provide an alternate login flow.';
  }

  if (raw.contains('No host specified') && raw.contains('/functions/')) {
    return EnvConfig.criticalConfigurationError ??
        'This build is missing a valid Supabase backend configuration. '
            'Rebuild with a valid SUPABASE_URL and SUPABASE_ANON_KEY.';
  }

  if (raw.startsWith('StateError: ')) {
    return raw.substring('StateError: '.length);
  }

  if (raw.startsWith('Exception: ')) {
    return raw.substring('Exception: '.length);
  }

  return raw;
}
