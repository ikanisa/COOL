import 'package:cool_app/core/models/engagement_feature_flags.dart';
import 'package:cool_app/features/admin/models/admin_feature_rollout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdminFeatureRolloutConfig', () {
    test('parses rollout values from shared and Rwanda app config rows', () {
      final rollouts = AdminFeatureRolloutConfig.fromAppConfigEntries(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'key': 'feature_ticket_purchase_stage',
            'value': 'pilot',
            'country': 'RW',
          },
          <String, dynamic>{
            'key': 'feature_ticket_purchase_admin_only',
            'value': 'true',
            'country': null,
          },
          <String, dynamic>{
            'key': 'kill_ticket_purchase',
            'value': 'false',
            'country': null,
          },
        ],
      );

      final ticketing = rollouts.firstWhere(
        (rollout) => rollout.key == 'ticket_purchase',
      );
      expect(ticketing.rollout.stage, FeatureRolloutStage.pilot);
      expect(ticketing.rollout.adminOnly, isTrue);
      expect(ticketing.rollout.killSwitch, isFalse);
    });

    test('ignores rollout rows scoped outside Rwanda', () {
      final rollouts = AdminFeatureRolloutConfig.fromAppConfigEntries(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'key': 'feature_ticket_purchase_stage',
            'value': 'internal',
            'country': 'UG',
          },
        ],
      );

      final ticketing = rollouts.firstWhere(
        (rollout) => rollout.key == 'ticket_purchase',
      );
      expect(
        ticketing.rollout.stage,
        EngagementFeatureFlags.defaults().ticketPurchase.stage,
      );
    });

    test('serializes rollout values into app config rows', () {
      const config = AdminFeatureRolloutConfig(
        key: 'ticket_purchase',
        label: 'Ticketing',
        description: 'Ticketing rollout',
        killSwitchKey: 'kill_ticket_purchase',
        rollout: ManagedFeatureRollout(
          key: 'ticket_purchase',
          stage: FeatureRolloutStage.internal,
          killSwitch: true,
          adminOnly: true,
        ),
      );

      final rows = config.toAppConfigEntries();

      expect(rows, hasLength(3));
      expect(
        rows.firstWhere((row) => row['key'] == 'kill_ticket_purchase')['value'],
        'true',
      );
      expect(
        rows.firstWhere(
          (row) => row['key'] == 'feature_ticket_purchase_stage',
        )['value'],
        'internal',
      );
      expect(
        rows.firstWhere(
          (row) => row['key'] == 'feature_ticket_purchase_admin_only',
        )['value'],
        'true',
      );
      expect(rows.every((row) => row['country'] == 'RW'), isTrue);
    });
  });
}
