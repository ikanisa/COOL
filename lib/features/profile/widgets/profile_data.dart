import 'package:flutter/material.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/utils/phone_validator.dart';
import '../../../l10n/app_localizations.dart';

/// Aggregated profile data consumed by profile UI widgets.
class ProfileData {
  const ProfileData({
    required this.name,
    required this.officialName,
    required this.userId,
    required this.phone,
    required this.officialPhone,
    this.dateOfBirth,
    this.nationalIdNumber,
    this.officialGender,
    this.officialNationality,
    this.momoNumber = '',
    this.momoCode,
    this.momoRouteType,
    this.countryCode = 'RW',
    required this.country,
    required this.currencyCode,
    required this.momoLinked,
    String? languageCode = AppMarket.languageCode,
    required this.notificationsEnabled,
    this.momoStatementCount = 0,
    required this.showCompletionBanner,
    this.setupItems = const <ProfileSetupItem>[],
    this.createdAt,
  }) : languageCode = AppMarket.languageCode;

  final String name;
  final String officialName;
  final String userId;
  final String phone;
  final String officialPhone;
  final String? dateOfBirth;
  final String? nationalIdNumber;
  final String? officialGender;
  final String? officialNationality;
  final String momoNumber;
  final String? momoCode;
  final MomoRecipientType? momoRouteType;
  final String countryCode;
  final String country;
  final String currencyCode;
  final bool momoLinked;
  final String languageCode;
  final bool notificationsEnabled;
  final int momoStatementCount;
  final bool showCompletionBanner;
  final List<ProfileSetupItem> setupItems;
  final DateTime? createdAt;

  /// Fraction of setup items completed (0.0–1.0).
  double get completionFraction {
    if (setupItems.isEmpty) return 1.0;
    final done = setupItems.where((i) => i.isComplete).length;
    return done / setupItems.length;
  }

  AppLocalizations get _l10n =>
      lookupAppLocalizations(const Locale(AppMarket.languageCode));

  String get momoDisplayLabel {
    final l10n = _l10n;
    if (!momoLinked) {
      return l10n.profileNotLinked;
    }

    final routeType = effectiveMomoRouteType;
    if (routeType == MomoRecipientType.code) {
      return momoCode?.trim().isNotEmpty == true
          ? '${l10n.momoRouteCodeLabel} ${momoCode!.trim()}'
          : l10n.profileMomoCodeNotSet;
    }

    if (momoNumber.isEmpty) {
      return l10n.profileNotLinked;
    }
    return PhoneValidator.formatMomoDisplay(momoNumber, AppMarket.country);
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
    final l10n = _l10n;
    return switch (effectiveMomoRouteType) {
      MomoRecipientType.phoneNumber => l10n.momoRoutePhoneLabel,
      MomoRecipientType.code => l10n.momoRouteCodeLabel,
      null => l10n.profileWalletLabel,
    };
  }

  bool get hasOfficialIdentity =>
      officialName.trim().isNotEmpty ||
      (dateOfBirth?.trim().isNotEmpty ?? false) ||
      maskedNationalId != null;

  String get officialIdentitySummary {
    if (officialName.trim().isNotEmpty) {
      return officialName.trim();
    }
    if (maskedNationalId != null) {
      return maskedNationalId!;
    }
    if (dateOfBirth?.trim().isNotEmpty ?? false) {
      return 'Date of birth on file';
    }
    return 'Not set';
  }

  String? get maskedNationalId {
    final raw = nationalIdNumber?.replaceAll(RegExp(r'\s+'), '');
    if (raw == null || raw.isEmpty) {
      return null;
    }
    if (raw.length <= 4) {
      return raw;
    }
    return '${'•' * (raw.length - 4)}${raw.substring(raw.length - 4)}';
  }

  String get mobileMoneyActivityLabel {
    if (momoStatementCount > 0) {
      return '$momoStatementCount statements';
    }
    if (momoLinked) {
      return 'Linked';
    }
    return 'Not linked';
  }

  bool get canShowMomoQr =>
      momoLinked &&
      effectiveMomoRouteType == MomoRecipientType.phoneNumber &&
      momoNumber.trim().isNotEmpty;

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

  ProfileData copyWith({String? languageCode, bool? notificationsEnabled}) {
    return ProfileData(
      name: name,
      officialName: officialName,
      userId: userId,
      phone: phone,
      officialPhone: officialPhone,
      dateOfBirth: dateOfBirth,
      nationalIdNumber: nationalIdNumber,
      officialGender: officialGender,
      officialNationality: officialNationality,
      momoNumber: momoNumber,
      momoCode: momoCode,
      momoRouteType: momoRouteType,
      countryCode: countryCode,
      country: country,
      currencyCode: currencyCode,
      momoLinked: momoLinked,
      languageCode: AppMarket.languageCode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      momoStatementCount: momoStatementCount,
      showCompletionBanner: showCompletionBanner,
      setupItems: setupItems,
      createdAt: createdAt,
    );
  }

  static const empty = ProfileData(
    name: '000000',
    officialName: '',
    userId: '000000',
    phone: '',
    officialPhone: '',
    dateOfBirth: null,
    nationalIdNumber: null,
    officialGender: null,
    officialNationality: null,
    country: 'Rwanda',
    currencyCode: 'RWF',
    momoLinked: false,
    languageCode: AppMarket.languageCode,
    notificationsEnabled: true,
    momoStatementCount: 0,
    showCompletionBanner: false,
    createdAt: null,
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
