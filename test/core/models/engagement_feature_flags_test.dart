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
        expect(flags.killMomoPayments, isFalse);
        expect(flags.killCreditFeatures, isFalse);
        expect(flags.killTicketPurchase, isFalse);
        expect(flags.killMobility, isFalse);
      });

      test('convenience getters reflect kill-switch state', () {
        final flags = EngagementFeatureFlags.defaults();
        expect(flags.momoEnabled, isTrue);
        expect(flags.creditEnabled, isTrue);
        expect(flags.ticketEnabled, isTrue);
        expect(flags.mobilityEnabled, isTrue);
      });
    });

    group('fromValues', () {
      test('parses kill-switch values from Remote Config', () {
        final flags = EngagementFeatureFlags.fromValues(<String, Object?>{
          'engagement_enabled': true,
          'engagement_share_tracking_enabled': true,
          'engagement_group_captain_enabled': false,
          'engagement_rayon_chapter_enabled': false,
          'kill_momo_payments': true,
          'kill_credit_features': false,
          'kill_ticket_purchase': true,
          'kill_mobility': false,
        });

        expect(flags.killMomoPayments, isTrue);
        expect(flags.momoEnabled, isFalse);
        expect(flags.killCreditFeatures, isFalse);
        expect(flags.creditEnabled, isTrue);
        expect(flags.killTicketPurchase, isTrue);
        expect(flags.ticketEnabled, isFalse);
        expect(flags.killMobility, isFalse);
        expect(flags.mobilityEnabled, isTrue);
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
        expect(flags.killCreditFeatures, isFalse);
        expect(flags.killMobility, isFalse);
      });

      test('coerces string kill-switch values', () {
        final flags = EngagementFeatureFlags.fromValues(<String, Object?>{
          'engagement_enabled': true,
          'engagement_share_tracking_enabled': true,
          'engagement_group_captain_enabled': false,
          'engagement_rayon_chapter_enabled': false,
          'kill_momo_payments': 'true',
          'kill_credit_features': '0',
          'kill_ticket_purchase': '1',
          'kill_mobility': 'false',
        });

        expect(flags.killMomoPayments, isTrue);
        expect(flags.killCreditFeatures, isFalse);
        expect(flags.killTicketPurchase, isTrue);
        expect(flags.killMobility, isFalse);
      });

      test('applies rollout governance by country and admin context', () {
        final flags = EngagementFeatureFlags.fromValues(<String, Object?>{
          'engagement_enabled': true,
          'engagement_share_tracking_enabled': true,
          'engagement_group_captain_enabled': false,
          'engagement_rayon_chapter_enabled': false,
          'feature_mobility_stage': 'pilot',
          'feature_mobility_allowed_countries': 'RW, KE',
          'feature_credit_stage': 'internal',
          'feature_credit_admin_only': true,
        });

        expect(flags.isMobilityEnabled(countryCode: 'RW'), isTrue);
        expect(flags.isMobilityEnabled(countryCode: 'CD'), isFalse);
        expect(
          flags.isCreditEnabled(countryCode: 'RW', isAdmin: false),
          isFalse,
        );
        expect(flags.isCreditEnabled(countryCode: 'RW', isAdmin: true), isTrue);
      });

      test('normalizes rollout countries and falls back on invalid stages', () {
        final flags = EngagementFeatureFlags.fromValues(<String, Object?>{
          'feature_momo_stage': 'unexpected-stage',
          'feature_momo_allowed_countries': ' rw, KE, rw,cd ',
        });

        expect(flags.momo.stage, FeatureRolloutStage.live);
        expect(flags.momo.allowedCountries, <String>['CD', 'KE', 'RW']);
        expect(flags.isMomoEnabled(countryCode: 'RW'), isTrue);
        expect(flags.isMomoEnabled(countryCode: 'UG'), isFalse);
      });
    });

    group('toRemoteConfigDefaults', () {
      test('includes kill-switch and rollout-governance keys', () {
        final defaults = EngagementFeatureFlags.defaults();
        final map = defaults.toRemoteConfigDefaults();

        expect(map.containsKey('kill_momo_payments'), isTrue);
        expect(map.containsKey('kill_credit_features'), isTrue);
        expect(map.containsKey('kill_ticket_purchase'), isTrue);
        expect(map.containsKey('kill_mobility'), isTrue);
        expect(map.containsKey('feature_momo_stage'), isTrue);
        expect(map.containsKey('feature_credit_allowed_countries'), isTrue);
        expect(map.containsKey('feature_ticket_purchase_admin_only'), isTrue);
        expect(map.containsKey('feature_mobility_stage'), isTrue);
        expect(map['kill_momo_payments'], isFalse);
        expect(map['kill_credit_features'], isFalse);
        expect(map['feature_mobility_stage'], 'live');
      });
    });
  });
}
