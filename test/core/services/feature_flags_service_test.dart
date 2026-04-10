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
    test(
      'app config overrides remote config values for managed keys',
      () async {
        final service = FeatureFlagsService(
          bootstrapService: FakeFirebaseBootstrapService(true),
          loadRemoteConfigValues: (_) async => <String, Object?>{
            'kill_momo_payments': false,
            'feature_momo_stage': 'pilot',
          },
          loadAppConfigOverrides: (_) async => <String, Object?>{
            'kill_momo_payments': 'true',
          },
        );

        final flags = await service.initialize();

        expect(flags.killMomoPayments, isTrue);
        expect(flags.momo.stage, FeatureRolloutStage.pilot);
      },
    );

    test(
      'app config overrides still apply when firebase is unavailable',
      () async {
        final service = FeatureFlagsService(
          bootstrapService: FakeFirebaseBootstrapService(false),
          loadRemoteConfigValues: (_) async =>
              throw StateError('should not run'),
          loadAppConfigOverrides: (_) async => <String, Object?>{
            'feature_momo_stage': 'internal',
            'feature_momo_admin_only': 'true',
            'kill_momo_payments': 'false',
          },
        );

        final flags = await service.initialize();

        expect(flags.momo.stage, FeatureRolloutStage.internal);
        expect(flags.momo.adminOnly, isTrue);
        expect(flags.isMomoEnabled(isAdmin: false), isFalse);
        expect(flags.isMomoEnabled(isAdmin: true), isTrue);
      },
    );
  });
}
