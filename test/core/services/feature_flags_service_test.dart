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
            'kill_ticket_purchase': false,
            'feature_ticket_purchase_stage': 'pilot',
          },
          loadAppConfigOverrides: (_) async => <String, Object?>{
            'kill_ticket_purchase': 'true',
          },
        );

        final flags = await service.initialize();

        expect(flags.killTicketPurchase, isTrue);
        expect(flags.ticketPurchase.stage, FeatureRolloutStage.pilot);
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
            'feature_ticket_purchase_stage': 'internal',
            'feature_ticket_purchase_admin_only': 'true',
            'kill_ticket_purchase': 'false',
          },
        );

        final flags = await service.initialize();

        expect(flags.ticketPurchase.stage, FeatureRolloutStage.internal);
        expect(flags.ticketPurchase.adminOnly, isTrue);
        expect(flags.isTicketPurchaseEnabled(isAdmin: false), isFalse);
        expect(flags.isTicketPurchaseEnabled(isAdmin: true), isTrue);
      },
    );
  });
}
