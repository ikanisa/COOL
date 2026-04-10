import 'package:cool_app/core/models/engagement_feature_flags.dart';
import 'package:cool_app/features/admin/models/admin_feature_rollout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdminFeatureRolloutConfig', () {
    test('parses rollout values from shared and Rwanda app config rows', () {
      final rollouts = AdminFeatureRolloutConfig.fromAppConfigEntries(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'key': 'feature_momo_stage',
            'value': 'pilot',
            'country': 'RW',
          },
          <String, dynamic>{
            'key': 'feature_momo_admin_only',
            'value': 'true',
            'country': null,
          },
          <String, dynamic>{
            'key': 'kill_momo_payments',
            'value': 'false',
            'country': null,
          },
        ],
      );

      final momo = rollouts.firstWhere(
        (rollout) => rollout.key == 'momo',
      );
      expect(momo.rollout.stage, FeatureRolloutStage.pilot);
      expect(momo.rollout.adminOnly, isTrue);
      expect(momo.rollout.killSwitch, isFalse);
    });

    test('ignores rollout rows scoped outside Rwanda', () {
      final rollouts = AdminFeatureRolloutConfig.fromAppConfigEntries(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'key': 'feature_momo_stage',
            'value': 'internal',
            'country': 'UG',
          },
        ],
      );

      final momo = rollouts.firstWhere(
        (rollout) => rollout.key == 'momo',
      );
      expect(
        momo.rollout.stage,
        EngagementFeatureFlags.defaults().momo.stage,
      );
    });

    test('serializes rollout values into app config rows', () {
      const config = AdminFeatureRolloutConfig(
        key: 'momo',
        label: 'Mobile Money',
        description: 'MoMo payments rollout',
        killSwitchKey: 'kill_momo_payments',
        rollout: ManagedFeatureRollout(
          key: 'momo',
          stage: FeatureRolloutStage.internal,
          killSwitch: true,
          adminOnly: true,
        ),
      );

      final rows = config.toAppConfigEntries();

      expect(rows, hasLength(3));
      expect(
        rows.firstWhere((row) => row['key'] == 'kill_momo_payments')['value'],
        'true',
      );
      expect(
        rows.firstWhere(
          (row) => row['key'] == 'feature_momo_stage',
        )['value'],
        'internal',
      );
      expect(
        rows.firstWhere(
          (row) => row['key'] == 'feature_momo_admin_only',
        )['value'],
        'true',
      );
      expect(rows.every((row) => row['country'] == 'RW'), isTrue);
    });
  });
}
