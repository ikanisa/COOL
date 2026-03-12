import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_validator.dart';
import '../../mobility/models/subscription_status.dart';
import '../../mobility/providers/driver_provider.dart';

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
    this.countryCode = 'RW',
    required this.country,
    required this.momoProvider,
    required this.momoLinked,
    required this.languageCode,
    required this.notificationsEnabled,
    required this.creditScoreLabel,
    required this.kycStatus,
    required this.isDriver,
    this.vehicleType,
    this.vehicleStatus,
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
  final String countryCode;
  final String country;
  final String momoProvider;
  final bool momoLinked;
  final String languageCode;
  final bool notificationsEnabled;
  final String creditScoreLabel;
  final String kycStatus;

  String get momoDisplayLabel {
    if (momoNumber.isEmpty) return 'Not linked';
    if (countryCode.toUpperCase() == 'RW') {
      return PhoneValidator.formatRwandanDisplay(momoNumber);
    }
    return momoNumber;
  }

  // Driver-only fields
  final bool isDriver;
  final String? vehicleType;
  final String? vehicleStatus;
  final String? subscriptionLabel;
  final bool subscriptionExpiring;

  String get initials {
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
      countryCode: countryCode,
      country: country,
      momoProvider: momoProvider,
      momoLinked: momoLinked,
      languageCode: languageCode ?? this.languageCode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      creditScoreLabel: creditScoreLabel,
      kycStatus: kycStatus,
      isDriver: isDriver,
      vehicleType: vehicleType,
      vehicleStatus: vehicleStatus,
      subscriptionLabel: subscriptionLabel,
      subscriptionExpiring: subscriptionExpiring,
    );
  }

  static const empty = ProfileData(
    name: 'User',
    officialName: 'User',
    userId: '------',
    phone: '',
    officialPhone: '',
    country: 'Rwanda',
    momoProvider: 'RWF',
    momoLinked: false,
    languageCode: 'en',
    notificationsEnabled: true,
    creditScoreLabel: '--',
    kycStatus: 'unverified',
    isDriver: false,
  );
}

/// Snapshot of driver profile data used by the profile screen.
class DriverProfileSnapshot {
  const DriverProfileSnapshot({
    required this.hasProfile,
    this.vehicleType,
    this.vehicleStatus,
    this.credits = 0,
    this.subscriptionLabel,
    this.subscriptionExpiring = false,
  });

  final bool hasProfile;
  final String? vehicleType;
  final String? vehicleStatus;
  final int credits;
  final String? subscriptionLabel;
  final bool subscriptionExpiring;

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
      vehicleType: profile?.vehicleType,
      vehicleStatus: profile == null
          ? null
          : (profile.isRegularDriver ? 'Regular Driver' : 'Occasional Driver'),
      credits: profile?.credits ?? 0,
      subscriptionLabel: _subscriptionLabel(
        subscription,
        profile?.credits ?? 0,
      ),
      subscriptionExpiring: subscriptionExpiring,
    );
  }
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
