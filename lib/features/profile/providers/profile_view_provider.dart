import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../../core/providers/notification_settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_provider.dart';
import '../../momo/models/momo_statement.dart';
import '../../momo/providers/momo_statement_providers.dart';
import '../widgets/profile_data.dart';

final profileViewProvider = Provider<ProfileData>((ref) {
  final authState = ref.watch(authProvider);
  final notificationSettings = ref.watch(notificationSettingsProvider);
  final statementBundle = ref.watch(
    momoStatementBundleProvider(const MomoStatementQuery()),
  );
  const profileLocale = Locale(AppMarket.languageCode);
  final l10n = lookupAppLocalizations(profileLocale);

  final user = authState.user;
  if (user == null) {
    return ProfileData.empty.copyWith(
      languageCode: AppMarket.languageCode,
      notificationsEnabled: notificationSettings.status.preferenceEnabled,
    );
  }

  final country = AppMarket.country;
  final officialName = user.officialName?.trim() ?? '';
  final officialPhone = user.officialPhone?.trim() ?? '';
  final dateOfBirth = user.dateOfBirth?.trim();
  final nationalIdNumber = user.nationalIdNumber?.trim();
  final walletConfigured = user.hasMomoRecipient;
  final statementCount =
      (statementBundle.valueOrNull?.walletTotalCount ?? 0) +
      (statementBundle.valueOrNull?.savingsTotalCount ?? 0);
  final showCompletionBanner =
      !user.hasBasicProfile || !walletConfigured;

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
  ];

  return ProfileData(
    name: user.fullName,
    officialName: officialName,
    userId: user.displayUserId,
    phone: user.phone,
    officialPhone: officialPhone,
    dateOfBirth: dateOfBirth,
    nationalIdNumber: nationalIdNumber,
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
    momoStatementCount: statementCount,
    showCompletionBanner: showCompletionBanner,
    setupItems: setupItems,
    createdAt: user.createdAt,
  );
});
