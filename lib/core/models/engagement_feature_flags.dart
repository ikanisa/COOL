enum FeatureRolloutStage {
  live('live'),
  pilot('pilot'),
  internal('internal'),
  disabled('disabled');

  const FeatureRolloutStage(this.remoteConfigValue);

  final String remoteConfigValue;

  static FeatureRolloutStage fromValue(
    Object? value, {
    required FeatureRolloutStage fallback,
  }) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final stage in FeatureRolloutStage.values) {
      if (stage.remoteConfigValue == normalized) {
        return stage;
      }
    }
    return fallback;
  }
}

class ManagedFeatureRollout {
  const ManagedFeatureRollout({
    required this.key,
    this.stage = FeatureRolloutStage.live,
    this.killSwitch = false,
    this.allowedCountries = const <String>[],
    this.adminOnly = false,
  });

  final String key;
  final FeatureRolloutStage stage;
  final bool killSwitch;
  final List<String> allowedCountries;
  final bool adminOnly;

  bool isEnabled({String? countryCode, bool isAdmin = false}) {
    if (killSwitch || stage == FeatureRolloutStage.disabled) {
      return false;
    }
    if ((adminOnly || stage == FeatureRolloutStage.internal) && !isAdmin) {
      return false;
    }
    if (allowedCountries.isEmpty) {
      return true;
    }

    final normalizedCountry = countryCode?.trim().toUpperCase();
    if (normalizedCountry == null || normalizedCountry.isEmpty) {
      return false;
    }
    return allowedCountries.contains(normalizedCountry);
  }

  ManagedFeatureRollout copyWith({
    FeatureRolloutStage? stage,
    bool? killSwitch,
    List<String>? allowedCountries,
    bool? adminOnly,
  }) {
    return ManagedFeatureRollout(
      key: key,
      stage: stage ?? this.stage,
      killSwitch: killSwitch ?? this.killSwitch,
      allowedCountries: allowedCountries ?? this.allowedCountries,
      adminOnly: adminOnly ?? this.adminOnly,
    );
  }

  Map<String, Object> toRemoteConfigDefaults({required String killSwitchKey}) {
    return <String, Object>{
      killSwitchKey: killSwitch,
      'feature_${key}_stage': stage.remoteConfigValue,
      'feature_${key}_allowed_countries': allowedCountries.join(','),
      'feature_${key}_admin_only': adminOnly,
    };
  }

  static ManagedFeatureRollout fromValues({
    required String key,
    required String killSwitchKey,
    required Map<String, Object?> values,
    required ManagedFeatureRollout fallback,
  }) {
    return ManagedFeatureRollout(
      key: key,
      stage: FeatureRolloutStage.fromValue(
        values['feature_${key}_stage'],
        fallback: fallback.stage,
      ),
      killSwitch: _coerceBool(
        values[killSwitchKey],
        fallback: fallback.killSwitch,
      ),
      allowedCountries: _coerceCountryCodes(
        values['feature_${key}_allowed_countries'],
        fallback: fallback.allowedCountries,
      ),
      adminOnly: _coerceBool(
        values['feature_${key}_admin_only'],
        fallback: fallback.adminOnly,
      ),
    );
  }
}

class EngagementFeatureFlags {
  const EngagementFeatureFlags({
    required this.engagementEnabled,
    required this.shareTrackingEnabled,
    required this.groupCaptainEnabled,
    required this.rayonChapterEnabled,
    required this.momo,
    required this.credit,
    required this.ticketPurchase,
    required this.mobility,
  });

  factory EngagementFeatureFlags.defaults() {
    return const EngagementFeatureFlags(
      engagementEnabled: true,
      shareTrackingEnabled: true,
      groupCaptainEnabled: false,
      rayonChapterEnabled: false,
      momo: ManagedFeatureRollout(key: 'momo'),
      credit: ManagedFeatureRollout(key: 'credit'),
      ticketPurchase: ManagedFeatureRollout(key: 'ticket_purchase'),
      mobility: ManagedFeatureRollout(key: 'mobility'),
    );
  }

  factory EngagementFeatureFlags.fromValues(Map<String, Object?> values) {
    final defaults = EngagementFeatureFlags.defaults();
    return EngagementFeatureFlags(
      engagementEnabled: _coerceBool(
        values['engagement_enabled'],
        fallback: defaults.engagementEnabled,
      ),
      shareTrackingEnabled: _coerceBool(
        values['engagement_share_tracking_enabled'],
        fallback: defaults.shareTrackingEnabled,
      ),
      groupCaptainEnabled: _coerceBool(
        values['engagement_group_captain_enabled'],
        fallback: defaults.groupCaptainEnabled,
      ),
      rayonChapterEnabled: _coerceBool(
        values['engagement_rayon_chapter_enabled'],
        fallback: defaults.rayonChapterEnabled,
      ),
      momo: ManagedFeatureRollout.fromValues(
        key: 'momo',
        killSwitchKey: 'kill_momo_payments',
        values: values,
        fallback: defaults.momo,
      ),
      credit: ManagedFeatureRollout.fromValues(
        key: 'credit',
        killSwitchKey: 'kill_credit_features',
        values: values,
        fallback: defaults.credit,
      ),
      ticketPurchase: ManagedFeatureRollout.fromValues(
        key: 'ticket_purchase',
        killSwitchKey: 'kill_ticket_purchase',
        values: values,
        fallback: defaults.ticketPurchase,
      ),
      mobility: ManagedFeatureRollout.fromValues(
        key: 'mobility',
        killSwitchKey: 'kill_mobility',
        values: values,
        fallback: defaults.mobility,
      ),
    );
  }

  final bool engagementEnabled;
  final bool shareTrackingEnabled;
  final bool groupCaptainEnabled;
  final bool rayonChapterEnabled;
  final ManagedFeatureRollout momo;
  final ManagedFeatureRollout credit;
  final ManagedFeatureRollout ticketPurchase;
  final ManagedFeatureRollout mobility;

  bool get killMomoPayments => momo.killSwitch;
  bool get killCreditFeatures => credit.killSwitch;
  bool get killTicketPurchase => ticketPurchase.killSwitch;
  bool get killMobility => mobility.killSwitch;

  bool get momoEnabled => isMomoEnabled();
  bool get creditEnabled => isCreditEnabled();
  bool get ticketEnabled => isTicketPurchaseEnabled();
  bool get mobilityEnabled => isMobilityEnabled();

  bool isMomoEnabled({String? countryCode, bool isAdmin = false}) {
    return momo.isEnabled(countryCode: countryCode, isAdmin: isAdmin);
  }

  bool isCreditEnabled({String? countryCode, bool isAdmin = false}) {
    return credit.isEnabled(countryCode: countryCode, isAdmin: isAdmin);
  }

  bool isTicketPurchaseEnabled({String? countryCode, bool isAdmin = false}) {
    return ticketPurchase.isEnabled(countryCode: countryCode, isAdmin: isAdmin);
  }

  bool isMobilityEnabled({String? countryCode, bool isAdmin = false}) {
    return mobility.isEnabled(countryCode: countryCode, isAdmin: isAdmin);
  }

  Map<String, Object> toRemoteConfigDefaults() {
    return <String, Object>{
      'engagement_enabled': engagementEnabled,
      'engagement_share_tracking_enabled': shareTrackingEnabled,
      'engagement_group_captain_enabled': groupCaptainEnabled,
      'engagement_rayon_chapter_enabled': rayonChapterEnabled,
      ...momo.toRemoteConfigDefaults(killSwitchKey: 'kill_momo_payments'),
      ...credit.toRemoteConfigDefaults(killSwitchKey: 'kill_credit_features'),
      ...ticketPurchase.toRemoteConfigDefaults(
        killSwitchKey: 'kill_ticket_purchase',
      ),
      ...mobility.toRemoteConfigDefaults(killSwitchKey: 'kill_mobility'),
    };
  }
}

List<String> _coerceCountryCodes(
  Object? value, {
  required List<String> fallback,
}) {
  if (value is List) {
    final normalized =
        value
            .map((entry) => entry.toString().trim().toUpperCase())
            .where((entry) => entry.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return normalized;
  }
  if (value is String) {
    final normalized =
        value
            .split(',')
            .map((entry) => entry.trim().toUpperCase())
            .where((entry) => entry.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return normalized;
  }
  return fallback;
}

bool _coerceBool(Object? value, {required bool fallback}) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
  }
  return fallback;
}
