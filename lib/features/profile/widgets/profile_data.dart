import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_validator.dart';
import '../../mobility/providers/driver_provider.dart';
import '../../mobility/models/subscription_status.dart';

/// Aggregated profile data consumed by profile UI widgets.
class ProfileData {
  const ProfileData({
    required this.name,
    required this.officialName,
    required this.userId,
    required this.phone,
    required this.officialPhone,
    this.momoNumber = '',
    this.momoCode,
    this.momoRouteType,
    this.countryCode = 'RW',
    required this.country,
    required this.currencyCode,
    required this.momoLinked,
    required this.languageCode,
    required this.notificationsEnabled,
    required this.creditScoreLabel,
    required this.kycStatus,
    required this.showCompletionBanner,
    this.setupItems = const <ProfileSetupItem>[],
    required this.isDriver,
    this.vehicleType,
    this.driverVerificationStatus,
    this.driverCadenceLabel,
    this.driverBaseLocation,
    this.driverPlateNumber,
    this.subscriptionLabel,
    this.subscriptionExpiring = false,
  });

  final String name;
  final String officialName;
  final String userId;
  final String phone;
  final String officialPhone;
  final String momoNumber;
  final String? momoCode;
  final MomoRecipientType? momoRouteType;
  final String countryCode;
  final String country;
  final String currencyCode;
  final bool momoLinked;
  final String languageCode;
  final bool notificationsEnabled;
  final String creditScoreLabel;
  final String kycStatus;
  final bool showCompletionBanner;
  final List<ProfileSetupItem> setupItems;

  final bool isDriver;
  final String? vehicleType;
  final String? driverVerificationStatus;
  final String? driverCadenceLabel;
  final String? driverBaseLocation;
  final String? driverPlateNumber;
  final String? subscriptionLabel;
  final bool subscriptionExpiring;

  String get momoDisplayLabel {
    if (!momoLinked) {
      return 'Not linked';
    }

    final routeType = effectiveMomoRouteType;
    if (routeType == MomoRecipientType.code) {
      return momoCode?.trim().isNotEmpty == true
          ? 'Code ${momoCode!.trim()}'
          : 'Code not set';
    }

    if (momoNumber.isEmpty) {
      return 'Not linked';
    }
    final country =
        CoolCountryCatalog.byIsoCode(countryCode) ??
        CoolCountryCatalog.defaultCountry;
    return PhoneValidator.formatMomoDisplay(momoNumber, country);
  }

  MomoRecipientType? get effectiveMomoRouteType {
    if (momoRouteType != null) {
      return momoRouteType;
    }
    if (momoNumber.trim().isNotEmpty) {
      return MomoRecipientType.phoneNumber;
    }
    if (momoCode?.trim().isNotEmpty == true) {
      return MomoRecipientType.code;
    }
    return null;
  }

  String get walletRouteLabel {
    return switch (effectiveMomoRouteType) {
      MomoRecipientType.phoneNumber => 'Phone route',
      MomoRecipientType.code => 'Code route',
      null => 'Wallet route',
    };
  }

  bool get canShowMomoQr =>
      momoLinked &&
      effectiveMomoRouteType == MomoRecipientType.phoneNumber &&
      momoNumber.trim().isNotEmpty;

  String get driverSummary {
    if (!isDriver) {
      return 'Passenger ready';
    }
    if ((vehicleType?.trim().isEmpty ?? true)) {
      return 'Vehicle setup pending';
    }

    final parts = <String>[
      vehicleType!.trim(),
      if (subscriptionLabel?.trim().isNotEmpty == true)
        subscriptionLabel!.trim(),
    ];
    return parts.join(' · ');
  }

  String get initials {
    final compactName = name.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    if (compactName.isNotEmpty) {
      return compactName.characters.take(2).toString().toUpperCase();
    }
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first.characters.take(2).toString();
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }

  String get languageLabel {
    switch (languageCode) {
      case 'fr':
        return 'Français';
      default:
        return 'English';
    }
  }

  String get kycLabel {
    switch (kycStatus) {
      case 'verified':
        return 'Verified';
      case 'pending_review':
        return 'Pending review';
      case 'rejected':
        return 'Needs update';
      default:
        return 'Unverified';
    }
  }

  Color get kycValueColor {
    switch (kycStatus) {
      case 'verified':
        return AppColors.accent;
      case 'pending_review':
        return AppColors.orange;
      case 'rejected':
        return AppColors.red;
      default:
        return AppColors.text3;
    }
  }

  ProfileData copyWith({String? languageCode, bool? notificationsEnabled}) {
    return ProfileData(
      name: name,
      officialName: officialName,
      userId: userId,
      phone: phone,
      officialPhone: officialPhone,
      momoNumber: momoNumber,
      momoCode: momoCode,
      momoRouteType: momoRouteType,
      countryCode: countryCode,
      country: country,
      currencyCode: currencyCode,
      momoLinked: momoLinked,
      languageCode: languageCode ?? this.languageCode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      creditScoreLabel: creditScoreLabel,
      kycStatus: kycStatus,
      showCompletionBanner: showCompletionBanner,
      setupItems: setupItems,
      isDriver: isDriver,
      vehicleType: vehicleType,
      driverVerificationStatus: driverVerificationStatus,
      driverCadenceLabel: driverCadenceLabel,
      driverBaseLocation: driverBaseLocation,
      driverPlateNumber: driverPlateNumber,
      subscriptionLabel: subscriptionLabel,
      subscriptionExpiring: subscriptionExpiring,
    );
  }

  static const empty = ProfileData(
    name: '000000',
    officialName: '',
    userId: '000000',
    phone: '',
    officialPhone: '',
    country: 'Rwanda',
    currencyCode: 'RWF',
    momoLinked: false,
    languageCode: 'en',
    notificationsEnabled: true,
    creditScoreLabel: '--',
    kycStatus: 'unverified',
    showCompletionBanner: false,
    isDriver: false,
  );
}

class ProfileSetupItem {
  const ProfileSetupItem({
    required this.id,
    required this.label,
    required this.isComplete,
  });

  final String id;
  final String label;
  final bool isComplete;
}

/// Snapshot of driver profile data used by the profile screen.
class DriverProfileSnapshot {
  const DriverProfileSnapshot({
    required this.hasProfile,
    this.vehicleType,
    this.vehicleStatus,
    this.cadenceLabel,
    this.baseLocation,
    this.plateNumber,
    this.credits = 0,
    this.subscriptionLabel,
    this.subscriptionExpiring = false,
  });

  final bool hasProfile;
  final String? vehicleType;
  final String? vehicleStatus;
  final String? cadenceLabel;
  final String? baseLocation;
  final String? plateNumber;
  final int credits;
  final String? subscriptionLabel;
  final bool subscriptionExpiring;

  bool get isSetupComplete =>
      (vehicleType?.trim().isNotEmpty ?? false) &&
      (plateNumber?.trim().isNotEmpty ?? false) &&
      (baseLocation?.trim().isNotEmpty ?? false);

  String? get verificationStatusLabel {
    final label = humanizeVehicleStatus(vehicleStatus);
    return label?.trim().isEmpty ?? true ? null : label;
  }

  factory DriverProfileSnapshot.fromState(DriverState state) {
    final profile = state.profile;
    final subscription = state.subscription;
    final now = DateTime.now();

    final subscriptionExpiring =
        subscription?.expiresAt != null &&
        subscription!.expiresAt!.isAfter(now) &&
        subscription.expiresAt!.difference(now).inDays <= 5;

    return DriverProfileSnapshot(
      hasProfile: profile != null,
      vehicleType: _trimmed(profile?.vehicleType),
      vehicleStatus: _trimmed(profile?.vehicleStatus),
      cadenceLabel: profile == null
          ? null
          : (profile.isRegularDriver ? 'Regular Driver' : 'Occasional Driver'),
      baseLocation: _trimmed(profile?.baseLocation),
      plateNumber: _trimmed(profile?.plateNumber),
      credits: profile?.credits ?? 0,
      subscriptionLabel: _subscriptionLabel(
        subscription,
        profile?.credits ?? 0,
      ),
      subscriptionExpiring: subscriptionExpiring,
    );
  }
}

String? humanizeVehicleStatus(String? rawStatus) {
  final normalized = rawStatus?.trim().toLowerCase() ?? '';
  if (normalized.isEmpty) {
    return null;
  }

  return switch (normalized) {
    'verified' => 'Verified',
    'pending_review' => 'Pending review',
    'maintenance' => 'Maintenance',
    _ =>
      normalized
          .split('_')
          .where((part) => part.isNotEmpty)
          .map(
            (part) =>
                '${part.characters.first.toUpperCase()}${part.substring(1)}',
          )
          .join(' '),
  };
}

String? _subscriptionLabel(
  SubscriptionStatus? subscription,
  int creditsBalance,
) {
  if (subscription == null || !subscription.isSubscribed) {
    return 'Mobility credits: $creditsBalance';
  }

  final expiresAt = subscription.expiresAt;
  if (expiresAt == null) {
    return 'Active mobility subscription';
  }

  return 'Active until ${DateFormat('d MMM').format(expiresAt)}';
}

String? _trimmed(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}
