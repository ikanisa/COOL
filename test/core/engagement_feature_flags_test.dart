import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/models/engagement_feature_flags.dart';

void main() {
  group('EngagementFeatureFlags', () {
    test('returns expected defaults', () {
      final flags = EngagementFeatureFlags.defaults();

      expect(flags.engagementEnabled, isTrue);
      expect(flags.shareTrackingEnabled, isTrue);
      expect(flags.groupCaptainEnabled, isFalse);
      expect(flags.partnerChapterEnabled, isFalse);
    });

    test('coerces remote config values from strings and numbers', () {
      final flags = EngagementFeatureFlags.fromValues(<String, Object?>{
        'engagement_enabled': 'true',
        'engagement_share_tracking_enabled': 0,
        'engagement_group_captain_enabled': 1,
        'engagement_partner_chapter_enabled': 'false',
      });

      expect(flags.engagementEnabled, isTrue);
      expect(flags.shareTrackingEnabled, isFalse);
      expect(flags.groupCaptainEnabled, isTrue);
      expect(flags.partnerChapterEnabled, isFalse);
    });
  });
}
