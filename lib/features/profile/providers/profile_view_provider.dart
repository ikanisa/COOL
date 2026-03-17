import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../../core/providers/notification_settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_provider.dart';
import '../../credit/providers/credit_provider.dart';
import '../../mobility/providers/driver_provider.dart';
import '../widgets/profile_data.dart';

final profileViewProvider = Provider<ProfileData>((ref) {
  final authState = ref.watch(authProvider);
  final notificationSettings = ref.watch(notificationSettingsProvider);
  final creditDashboard = ref.watch(creditDashboardProvider).valueOrNull;
  const profileLocale = Locale(AppMarket.languageCode);
  final l10n = lookupAppLocalizations(profileLocale);
  final driverSnapshot = DriverProfileSnapshot.fromState(
    ref.watch(driverProvider),
    locale: profileLocale,
  );

  final user = authState.user;
  if (user == null) {
    return ProfileData.empty.copyWith(
      languageCode: AppMarket.languageCode,
      notificationsEnabled: notificationSettings.status.preferenceEnabled,
    );
  }

  final country = AppMarket.country;
  final hasDriverRole = user.isDriver || driverSnapshot.hasProfile;
  final officialName = user.officialName?.trim() ?? '';
  final officialPhone = user.officialPhone?.trim() ?? '';
  final dateOfBirth = user.dateOfBirth?.trim();
  final nationalIdNumber = user.nationalIdNumber?.trim();
  final walletConfigured = user.hasMomoRecipient;
  final showCompletionBanner =
      !user.hasBasicProfile ||
      !walletConfigured ||
      !user.hasOfficialIdentity ||
      (hasDriverRole && !driverSnapshot.isSetupComplete);

  final setupItems = <ProfileSetupItem>[
    ProfileSetupItem(
      id: 'account',
      label: l10n.profilePublicProfileLabel,
      isComplete: user.hasBasicProfile,
    ),
    ProfileSetupItem(
      id: 'wallet',
      label: l10n.profileWalletLabel,
      isComplete: walletConfigured,
    ),
    ProfileSetupItem(
      id: 'official_identity',
      label: l10n.profileOfficialIdentityLabel,
      isComplete: user.hasOfficialIdentity,
    ),
    ProfileSetupItem(
      id: 'travel_role',
      label: l10n.profileTravelRoleLabel,
      isComplete:
          walletConfigured &&
          (!hasDriverRole || driverSnapshot.isSetupComplete),
    ),
  ];

  return ProfileData(
    name: user.fullName,
    officialName: officialName,
    userId: user.displayUserId,
    phone: user.phone,
    officialPhone: officialPhone,
    dateOfBirth: dateOfBirth,
    nationalIdNumber: nationalIdNumber,
    kycDocumentType: user.kycDocumentType,
    officialGender: user.identityData['gender']?.toString(),
    officialNationality: user.identityData['nationality']?.toString(),
    momoNumber: user.momoNumber,
    momoCode: user.momoCode,
    momoRouteType: user.effectiveMomoRouteType,
    countryCode: country.isoCode,
    country: country.displayName,
    currencyCode: country.currencyCode,
    momoLinked: walletConfigured,
    languageCode: AppMarket.languageCode,
    notificationsEnabled: notificationSettings.status.preferenceEnabled,
    creditScoreLabel: creditDashboard?.score?.toString() ?? '--',
    momoStatementCount: creditDashboard?.statementCount ?? 0,
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
    createdAt: user.createdAt,
  );
});
