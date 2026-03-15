enum EngagementEventName {
  appOpened,
  sessionStarted,
  deepLinkOpened,
  inviteSent,
  inviteOpened,
  inviteAccepted,
  shareAction,
  tripScheduled,
  driverWentOnline,
  discoverTabSwitch,
  walletAddStarted,
  walletAddCompleted,
  appReviewRequested,
  appStoreListingOpened,
  appUpdateImmediateStarted,
  appUpdateFlexibleStarted,
}

extension EngagementEventNameX on EngagementEventName {
  String get value => switch (this) {
    EngagementEventName.appOpened => 'app_opened',
    EngagementEventName.sessionStarted => 'session_started',
    EngagementEventName.deepLinkOpened => 'deep_link_opened',
    EngagementEventName.inviteSent => 'invite_sent',
    EngagementEventName.inviteOpened => 'invite_opened',
    EngagementEventName.inviteAccepted => 'invite_accepted',
    EngagementEventName.shareAction => 'share_action',
    EngagementEventName.tripScheduled => 'trip_scheduled',
    EngagementEventName.driverWentOnline => 'driver_went_online',
    EngagementEventName.discoverTabSwitch => 'discover_tab_switch',
    EngagementEventName.walletAddStarted => 'wallet_add_started',
    EngagementEventName.walletAddCompleted => 'wallet_add_completed',
    EngagementEventName.appReviewRequested => 'app_review_requested',
    EngagementEventName.appStoreListingOpened => 'app_store_listing_opened',
    EngagementEventName.appUpdateImmediateStarted =>
      'app_update_immediate_started',
    EngagementEventName.appUpdateFlexibleStarted =>
      'app_update_flexible_started',
  };
}

class EngagementEvent {
  const EngagementEvent({
    required this.name,
    this.parameters = const <String, Object?>{},
  });

  final EngagementEventName name;
  final Map<String, Object?> parameters;

  Map<String, Object> get analyticsParameters {
    final sanitized = <String, Object>{};

    parameters.forEach((key, value) {
      final normalizedKey = key.trim();
      if (normalizedKey.isEmpty || value == null) {
        return;
      }

      if (value is bool) {
        sanitized[normalizedKey] = value ? 1 : 0;
        return;
      }

      if (value is num || value is String) {
        sanitized[normalizedKey] = _normalizeScalar(value);
        return;
      }

      if (value is Uri) {
        sanitized[normalizedKey] = value.toString();
        return;
      }

      sanitized[normalizedKey] = value.toString();
    });

    return sanitized;
  }

  Object _normalizeScalar(Object value) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.length <= 100) {
        return trimmed;
      }
      return trimmed.substring(0, 100);
    }

    return value;
  }
}
