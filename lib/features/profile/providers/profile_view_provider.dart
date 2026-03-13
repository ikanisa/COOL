import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/locale_provider.dart';
import '../../../core/providers/notification_settings_provider.dart';
import '../../../core/providers/supported_countries_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../credit/providers/credit_provider.dart';
import '../../mobility/providers/driver_provider.dart';
import '../widgets/profile_data.dart';

final profileViewProvider = Provider<ProfileData>((ref) {
  final authState = ref.watch(authProvider);
  final locale = ref.watch(localeProvider);
  final notificationSettings = ref.watch(notificationSettingsProvider);
  final countries =
      ref.watch(supportedCountriesProvider).valueOrNull ??
      CoolCountryCatalog.all;
  final creditDashboard = ref.watch(creditDashboardProvider).valueOrNull;
  final driverSnapshot = DriverProfileSnapshot.fromState(
    ref.watch(driverProvider),
  );

  final user = authState.user;
  if (user == null) {
    return ProfileData.empty.copyWith(
      languageCode: locale.languageCode,
      notificationsEnabled: notificationSettings.status.preferenceEnabled,
    );
  }

  final country = CoolCountryCatalog.resolve(
    country: resolveAuthStateCountryCode(authState),
    phone: user.phone,
    providerId: user.momoProvider,
    source: countries,
  );
  final hasDriverRole = user.isDriver || driverSnapshot.hasProfile;
  final officialName = user.officialName?.trim() ?? '';
  final officialPhone = user.officialPhone?.trim() ?? '';
  final walletConfigured = user.hasMomoRecipient;
  final showCompletionBanner =
      !user.hasBasicProfile ||
      !walletConfigured ||
      !user.hasOfficialIdentity ||
      (hasDriverRole && !driverSnapshot.isSetupComplete);

  final setupItems = <ProfileSetupItem>[
    ProfileSetupItem(
      id: 'account',
      label: 'Public profile',
      isComplete: user.hasBasicProfile,
    ),
    ProfileSetupItem(
      id: 'wallet',
      label: 'Wallet',
      isComplete: walletConfigured,
    ),
    ProfileSetupItem(
      id: 'official_identity',
      label: 'Official identity',
      isComplete: officialName.isNotEmpty && officialPhone.isNotEmpty,
    ),
    ProfileSetupItem(
      id: 'travel_role',
      label: 'Travel role',
      isComplete:
          walletConfigured &&
          (!hasDriverRole || driverSnapshot.isSetupComplete),
    ),
  ];

  return ProfileData(
    name: user.displayUserId,
    officialName: officialName,
    userId: user.displayUserId,
    phone: user.phone,
    officialPhone: officialPhone,
    momoNumber: user.momoNumber,
    momoCode: user.momoCode,
    momoRouteType: user.effectiveMomoRouteType,
    countryCode: country.isoCode,
    country: country.displayName,
    currencyCode: country.currencyCode,
    momoLinked: walletConfigured,
    languageCode: locale.languageCode,
    notificationsEnabled: notificationSettings.status.preferenceEnabled,
    creditScoreLabel: creditDashboard?.score?.toString() ?? '--',
    kycStatus: user.kycStatus,
    showCompletionBanner: showCompletionBanner,
    setupItems: setupItems,
    isDriver: hasDriverRole,
    vehicleType: driverSnapshot.vehicleType ?? user.vehicleType,
    driverVerificationStatus: driverSnapshot.verificationStatusLabel,
    driverCadenceLabel: driverSnapshot.cadenceLabel,
    driverBaseLocation: driverSnapshot.baseLocation,
    driverPlateNumber: driverSnapshot.plateNumber,
    subscriptionLabel: driverSnapshot.subscriptionLabel,
    subscriptionExpiring: driverSnapshot.subscriptionExpiring,
  );
});
