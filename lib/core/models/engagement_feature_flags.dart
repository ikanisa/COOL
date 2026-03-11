class EngagementFeatureFlags {
  const EngagementFeatureFlags({
    required this.engagementEnabled,
    required this.shareTrackingEnabled,
    required this.groupCaptainEnabled,
    required this.rayonChapterEnabled,
  });

  factory EngagementFeatureFlags.defaults() {
    return const EngagementFeatureFlags(
      engagementEnabled: true,
      shareTrackingEnabled: true,
      groupCaptainEnabled: false,
      rayonChapterEnabled: false,
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
    );
  }

  final bool engagementEnabled;
  final bool shareTrackingEnabled;
  final bool groupCaptainEnabled;
  final bool rayonChapterEnabled;

  Map<String, Object> toRemoteConfigDefaults() {
    return <String, Object>{
      'engagement_enabled': engagementEnabled,
      'engagement_share_tracking_enabled': shareTrackingEnabled,
      'engagement_group_captain_enabled': groupCaptainEnabled,
      'engagement_rayon_chapter_enabled': rayonChapterEnabled,
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
