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
    this.adminOnly = false,
  });

  final String key;
  final FeatureRolloutStage stage;
  final bool killSwitch;
  final bool adminOnly;

  /// Rwanda-only: no country gating needed.
  bool isEnabled({bool isAdmin = false}) {
    if (killSwitch || stage == FeatureRolloutStage.disabled) {
      return false;
    }
    if ((adminOnly || stage == FeatureRolloutStage.internal) && !isAdmin) {
      return false;
    }
    return true;
  }

  ManagedFeatureRollout copyWith({
    FeatureRolloutStage? stage,
    bool? killSwitch,
    bool? adminOnly,
  }) {
    return ManagedFeatureRollout(
      key: key,
      stage: stage ?? this.stage,
      killSwitch: killSwitch ?? this.killSwitch,
      adminOnly: adminOnly ?? this.adminOnly,
    );
  }

  Map<String, Object> toRemoteConfigDefaults({required String killSwitchKey}) {
    return <String, Object>{
      killSwitchKey: killSwitch,
      'feature_${key}_stage': stage.remoteConfigValue,
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
    required this.biopayEnabled,
    required this.momo,
    required this.ticketPurchase,
  });

  factory EngagementFeatureFlags.defaults() {
    return const EngagementFeatureFlags(
      engagementEnabled: true,
      shareTrackingEnabled: true,
      groupCaptainEnabled: false,
      rayonChapterEnabled: false,
      biopayEnabled: false,
      momo: ManagedFeatureRollout(key: 'momo'),
      ticketPurchase: ManagedFeatureRollout(key: 'ticket_purchase'),
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
      biopayEnabled: _coerceBool(
        values['feature_biopay_enabled'],
        fallback: defaults.biopayEnabled,
      ),
      momo: ManagedFeatureRollout.fromValues(
        key: 'momo',
        killSwitchKey: 'kill_momo_payments',
        values: values,
        fallback: defaults.momo,
      ),
      ticketPurchase: ManagedFeatureRollout.fromValues(
        key: 'ticket_purchase',
        killSwitchKey: 'kill_ticket_purchase',
        values: values,
        fallback: defaults.ticketPurchase,
      ),
    );
  }

  final bool engagementEnabled;
  final bool shareTrackingEnabled;
  final bool groupCaptainEnabled;
  final bool rayonChapterEnabled;
  final bool biopayEnabled;
  final ManagedFeatureRollout momo;
  final ManagedFeatureRollout ticketPurchase;

  bool get killMomoPayments => momo.killSwitch;
  bool get killTicketPurchase => ticketPurchase.killSwitch;

  bool get momoEnabled => isMomoEnabled();
  bool get biopayAvailable => isBiopayEnabled();
  bool get ticketEnabled => isTicketPurchaseEnabled();

  bool isMomoEnabled({bool isAdmin = false}) {
    return momo.isEnabled(isAdmin: isAdmin);
  }

  bool isBiopayEnabled({bool isAdmin = false}) {
    return biopayEnabled && isMomoEnabled(isAdmin: isAdmin);
  }

  bool isTicketPurchaseEnabled({bool isAdmin = false}) {
    return ticketPurchase.isEnabled(isAdmin: isAdmin);
  }

  Map<String, Object> toRemoteConfigDefaults() {
    return <String, Object>{
      'engagement_enabled': engagementEnabled,
      'engagement_share_tracking_enabled': shareTrackingEnabled,
      'engagement_group_captain_enabled': groupCaptainEnabled,
      'engagement_rayon_chapter_enabled': rayonChapterEnabled,
      'feature_biopay_enabled': biopayEnabled,
      ...momo.toRemoteConfigDefaults(killSwitchKey: 'kill_momo_payments'),
      ...ticketPurchase.toRemoteConfigDefaults(
        killSwitchKey: 'kill_ticket_purchase',
      ),
    };
  }
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
