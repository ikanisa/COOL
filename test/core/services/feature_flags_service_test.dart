import 'package:cool_app/core/models/engagement_feature_flags.dart';
import 'package:cool_app/core/services/feature_flags_service.dart';
import 'package:cool_app/core/services/firebase_bootstrap_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeFirebaseBootstrapService extends FirebaseBootstrapService {
  FakeFirebaseBootstrapService(this.available);

  final bool available;

  @override
  Future<bool> initialize() async => available;
}

void main() {
  group('FeatureFlagsService', () {
    test('app config overrides remote config values for managed keys', () async {
      final service = FeatureFlagsService(
        bootstrapService: FakeFirebaseBootstrapService(true),
        loadRemoteConfigValues: (_) async => <String, Object?>{
          'kill_mobility': false,
          'feature_mobility_stage': 'pilot',
          'feature_mobility_allowed_countries': 'RW',
        },
        loadAppConfigOverrides: (_) async => <String, Object?>{
          'kill_mobility': 'true',
          'feature_mobility_allowed_countries': 'RW, KE',
        },
      );

      final flags = await service.initialize();

      expect(flags.killMobility, isTrue);
      expect(flags.mobility.stage, FeatureRolloutStage.pilot);
      expect(flags.mobility.allowedCountries, <String>['KE', 'RW']);
    });

    test('app config overrides still apply when firebase is unavailable', () async {
      final service = FeatureFlagsService(
        bootstrapService: FakeFirebaseBootstrapService(false),
        loadRemoteConfigValues: (_) async => throw StateError('should not run'),
        loadAppConfigOverrides: (_) async => <String, Object?>{
          'feature_credit_stage': 'internal',
          'feature_credit_admin_only': 'true',
          'kill_credit_features': 'false',
        },
      );

      final flags = await service.initialize();

      expect(flags.credit.stage, FeatureRolloutStage.internal);
      expect(flags.credit.adminOnly, isTrue);
      expect(flags.isCreditEnabled(countryCode: 'RW', isAdmin: false), isFalse);
      expect(flags.isCreditEnabled(countryCode: 'RW', isAdmin: true), isTrue);
    });
  });
}
