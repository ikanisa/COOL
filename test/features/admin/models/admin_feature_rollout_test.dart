import 'package:cool_app/core/models/engagement_feature_flags.dart';
import 'package:cool_app/features/admin/models/admin_feature_rollout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdminFeatureRolloutConfig', () {
    test('parses rollout values from shared and Rwanda app config rows', () {
      final rollouts = AdminFeatureRolloutConfig.fromAppConfigEntries(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'key': 'feature_mobility_stage',
            'value': 'pilot',
            'country': 'RW',
          },
          <String, dynamic>{
            'key': 'feature_mobility_admin_only',
            'value': 'true',
            'country': null,
          },
          <String, dynamic>{
            'key': 'kill_mobility',
            'value': 'false',
            'country': null,
          },
        ],
      );

      final mobility = rollouts.firstWhere(
        (rollout) => rollout.key == 'mobility',
      );
      expect(mobility.rollout.stage, FeatureRolloutStage.pilot);
      expect(mobility.rollout.adminOnly, isTrue);
      expect(mobility.rollout.killSwitch, isFalse);
    });

    test('ignores rollout rows scoped outside Rwanda', () {
      final rollouts = AdminFeatureRolloutConfig.fromAppConfigEntries(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'key': 'feature_mobility_stage',
            'value': 'internal',
            'country': 'UG',
          },
        ],
      );

      final mobility = rollouts.firstWhere(
        (rollout) => rollout.key == 'mobility',
      );
      expect(
        mobility.rollout.stage,
        EngagementFeatureFlags.defaults().mobility.stage,
      );
    });

    test('serializes rollout values into app config rows', () {
      const config = AdminFeatureRolloutConfig(
        key: 'credit',
        label: 'Credit',
        description: 'Credit rollout',
        killSwitchKey: 'kill_credit_features',
        rollout: ManagedFeatureRollout(
          key: 'credit',
          stage: FeatureRolloutStage.internal,
          killSwitch: true,
          adminOnly: true,
        ),
      );

      final rows = config.toAppConfigEntries();

      expect(rows, hasLength(3));
      expect(
        rows.firstWhere((row) => row['key'] == 'kill_credit_features')['value'],
        'true',
      );
      expect(
        rows.firstWhere((row) => row['key'] == 'feature_credit_stage')['value'],
        'internal',
      );
      expect(
        rows.firstWhere(
          (row) => row['key'] == 'feature_credit_admin_only',
        )['value'],
        'true',
      );
      expect(rows.every((row) => row['country'] == 'RW'), isTrue);
    });
  });
}
