import 'package:cool_app/core/models/engagement_feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EngagementFeatureFlags', () {
    group('defaults', () {
      test('engagement flags default ON', () {
        final flags = EngagementFeatureFlags.defaults();
        expect(flags.engagementEnabled, isTrue);
        expect(flags.shareTrackingEnabled, isTrue);
      });

      test('kill-switches default to false (features ON)', () {
        final flags = EngagementFeatureFlags.defaults();
        expect(flags.biopayEnabled, isTrue);
        expect(flags.killMomoPayments, isFalse);
        expect(flags.killTicketPurchase, isFalse);
      });

      test('convenience getters reflect kill-switch state', () {
        final flags = EngagementFeatureFlags.defaults();
        expect(flags.momoEnabled, isTrue);
        expect(flags.biopayAvailable, isTrue);
        expect(flags.ticketEnabled, isTrue);
      });
    });

    group('fromValues', () {
      test('MoMo kill-switch still blocks BioPay availability', () {
        final flags = EngagementFeatureFlags.fromValues(<String, Object?>{
          'engagement_enabled': true,
          'engagement_share_tracking_enabled': true,
          'engagement_group_captain_enabled': false,
          'engagement_rayon_chapter_enabled': false,
          'feature_biopay_enabled': true,
          'kill_momo_payments': true,
          'kill_ticket_purchase': true,
        });

        expect(flags.biopayEnabled, isTrue);
        expect(flags.killMomoPayments, isTrue);
        expect(flags.momoEnabled, isFalse);
        expect(flags.biopayAvailable, isFalse);
        expect(flags.killTicketPurchase, isTrue);
        expect(flags.ticketEnabled, isFalse);
      });

      test('missing kill-switch keys default to false (features ON)', () {
        final flags = EngagementFeatureFlags.fromValues(<String, Object?>{
          'engagement_enabled': true,
          'engagement_share_tracking_enabled': true,
          'engagement_group_captain_enabled': false,
          'engagement_rayon_chapter_enabled': false,
          // Note: no kill_ keys present
        });

        expect(flags.killMomoPayments, isFalse);
        expect(flags.momoEnabled, isTrue);
      });

      test('coerces string kill-switch values', () {
        final flags = EngagementFeatureFlags.fromValues(<String, Object?>{
          'engagement_enabled': true,
          'engagement_share_tracking_enabled': true,
          'engagement_group_captain_enabled': false,
          'engagement_rayon_chapter_enabled': false,
          'kill_momo_payments': 'true',
          'kill_ticket_purchase': '1',
        });

        expect(flags.killMomoPayments, isTrue);
        expect(flags.killTicketPurchase, isTrue);
      });

      test('applies rollout governance by stage and admin context', () {
        final flags = EngagementFeatureFlags.fromValues(<String, Object?>{
          'engagement_enabled': true,
          'engagement_share_tracking_enabled': true,
          'engagement_group_captain_enabled': false,
          'engagement_rayon_chapter_enabled': false,
          'feature_ticket_purchase_stage': 'internal',
          'feature_ticket_purchase_admin_only': true,
        });

        expect(flags.isTicketPurchaseEnabled(isAdmin: false), isFalse);
        expect(flags.isTicketPurchaseEnabled(isAdmin: true), isTrue);
      });

      test('falls back on invalid stages', () {
        final flags = EngagementFeatureFlags.fromValues(<String, Object?>{
          'feature_momo_stage': 'unexpected-stage',
        });

        expect(flags.momo.stage, FeatureRolloutStage.live);
        expect(flags.isMomoEnabled(), isTrue);
      });
    });

    group('toRemoteConfigDefaults', () {
      test('includes kill-switch and rollout-governance keys', () {
        final defaults = EngagementFeatureFlags.defaults();
        final map = defaults.toRemoteConfigDefaults();

        expect(map.containsKey('feature_biopay_enabled'), isTrue);
        expect(map.containsKey('kill_momo_payments'), isTrue);
        expect(map.containsKey('kill_ticket_purchase'), isTrue);
        expect(map.containsKey('feature_momo_stage'), isTrue);
        expect(map.containsKey('feature_ticket_purchase_admin_only'), isTrue);
        expect(map.containsKey('feature_ticket_purchase_stage'), isTrue);
        expect(map['feature_biopay_enabled'], isTrue);
        expect(map['kill_momo_payments'], isFalse);
        expect(map['feature_ticket_purchase_stage'], 'live');
      });
    });
  });
}
