import 'package:cool_app/core/models/engagement_feature_flags.dart';
import 'package:cool_app/features/admin/models/admin_feature_rollout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdminFeatureRolloutConfig', () {
    test('parses rollout values from global app config rows', () {
      final rollouts = AdminFeatureRolloutConfig.fromAppConfigEntries(<Map<String, dynamic>>[
        <String, dynamic>{
          'key': 'feature_mobility_stage',
          'value': 'pilot',
          'country': null,
        },
        <String, dynamic>{
          'key': 'feature_mobility_allowed_countries',
          'value': 'RW, KE, rw',
          'country': null,
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
        <String, dynamic>{
          'key': 'feature_mobility_stage',
          'value': 'disabled',
          'country': 'RW',
        },
      ]);

      final mobility = rollouts.firstWhere((rollout) => rollout.key == 'mobility');
      expect(mobility.rollout.stage, FeatureRolloutStage.pilot);
      expect(mobility.rollout.allowedCountries, <String>['KE', 'RW']);
      expect(mobility.rollout.adminOnly, isTrue);
      expect(mobility.rollout.killSwitch, isFalse);
    });

    test('serializes rollout values into app config rows', () {
      final config = AdminFeatureRolloutConfig(
        key: 'credit',
        label: 'Credit',
        description: 'Credit rollout',
        killSwitchKey: 'kill_credit_features',
        rollout: const ManagedFeatureRollout(
          key: 'credit',
          stage: FeatureRolloutStage.internal,
          killSwitch: true,
          allowedCountries: <String>['RW', 'KE'],
          adminOnly: true,
        ),
      );

      final rows = config.toAppConfigEntries();

      expect(rows, hasLength(4));
      expect(
        rows.firstWhere((row) => row['key'] == 'kill_credit_features')['value'],
        'true',
      );
      expect(
        rows.firstWhere((row) => row['key'] == 'feature_credit_stage')['value'],
        'internal',
      );
      expect(
        rows
            .firstWhere((row) => row['key'] == 'feature_credit_allowed_countries')['value'],
        'RW,KE',
      );
      expect(
        rows.firstWhere((row) => row['key'] == 'feature_credit_admin_only')['value'],
        'true',
      );
    });
  });
}
