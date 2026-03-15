import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

import '../models/engagement_event.dart';
import 'engagement_tracker.dart';

/// Service for handling in-app updates (Android only).
class AppUpdateService {
  AppUpdateService(this._engagementTracker);

  final EngagementTracker _engagementTracker;

  /// Checks for updates and prompts the user.
  Future<void> checkForUpdate() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        if (info.immediateUpdateAllowed) {
          await _engagementTracker.track(
            const EngagementEvent(
              name: EngagementEventName.appUpdateImmediateStarted,
            ),
          );
          await InAppUpdate.performImmediateUpdate();
        } else if (info.flexibleUpdateAllowed) {
          await _engagementTracker.track(
            const EngagementEvent(
              name: EngagementEventName.appUpdateFlexibleStarted,
            ),
          );
          await InAppUpdate.startFlexibleUpdate();
          await InAppUpdate.completeFlexibleUpdate();
        }
      }
    } catch (error) {
      debugPrint('[AppUpdate] Update check failed: $error');
    }
  }
}
