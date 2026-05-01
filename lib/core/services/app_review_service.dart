import 'package:in_app_review/in_app_review.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/engagement_event.dart';
import '../providers/engagement_providers.dart';
import '../utils/app_logger.dart';
import 'engagement_tracker.dart';

const _log = AppLogger('AppReview');

final appReviewServiceProvider = Provider<AppReviewService>((ref) {
  return AppReviewService(ref.read(engagementTrackerProvider));
});

/// Service for requesting in-app reviews.
class AppReviewService {
  AppReviewService(this._engagementTracker);

  final InAppReview _instance = InAppReview.instance;
  final EngagementTracker _engagementTracker;

  /// Requests a review if conditions are met.
  Future<void> requestReview() async {
    try {
      final isAvailable = await _instance.isAvailable();
      if (!isAvailable) {
        _log.debug('Service not available.');
        return;
      }

      await _instance.requestReview();
      await _engagementTracker.track(
        const EngagementEvent(name: EngagementEventName.appReviewRequested),
      );
    } catch (error) {
      _log.warn('Failed to request review: $error');
    }
  }

  /// Opens the store listing for manual review.
  Future<void> openStoreListing() async {
    try {
      await _instance.openStoreListing();
      await _engagementTracker.track(
        const EngagementEvent(name: EngagementEventName.appStoreListingOpened),
      );
    } catch (error) {
      _log.warn('Failed to open store listing: $error');
    }
  }
}
