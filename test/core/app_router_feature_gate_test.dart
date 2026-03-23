import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/router/app_router.dart';
import 'package:cool_app/core/services/feature_flags_service.dart';
import 'package:cool_app/core/services/firebase_bootstrap_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_smoke/test_harness.dart';

class FakeFirebaseBootstrapService extends FirebaseBootstrapService {
  FakeFirebaseBootstrapService(this.available);

  final bool available;

  @override
  Future<bool> initialize() async => available;
}

Future<FeatureFlagsService> _buildFeatureFlagsService({
  Map<String, Object?> appConfigOverrides = const <String, Object?>{},
}) async {
  final service = FeatureFlagsService(
    bootstrapService: FakeFirebaseBootstrapService(false),
    loadAppConfigOverrides: (knownKeys) async {
      return Map<String, Object?>.fromEntries(
        appConfigOverrides.entries.where(
          (entry) => knownKeys.contains(entry.key),
        ),
      );
    },
  );

  await service.initialize();
  return service;
}

void main() {
  group('appRouter feature gating', () {
    testWidgets(
      'managed app config can block Mobile Money for standard users',
      (tester) async {
        final featureFlagsService = await _buildFeatureFlagsService(
          appConfigOverrides: const <String, Object?>{
            'feature_momo_stage': 'internal',
            'feature_momo_admin_only': 'true',
          },
        );

        final app = await pumpRouterApp(
          tester,
          initialLocation: AppRoutes.momo,
          session: fakeSession(),
          user: fakeUser(),
          overrides: <Override>[
            featureFlagsServiceProvider.overrideWithValue(featureFlagsService),
          ],
        );

        expect(
          app.router.routeInformationProvider.value.uri.path,
          AppRoutes.momo,
        );
        expect(find.text('Temporarily Unavailable'), findsOneWidget);
        expect(
          find.textContaining('Mobile Money is temporarily unavailable.'),
          findsOneWidget,
        );
        expect(find.text('Go Back'), findsOneWidget);
      },
    );

    testWidgets('managed app config still allows admins into Mobile Money', (
      tester,
    ) async {
      final featureFlagsService = await _buildFeatureFlagsService(
        appConfigOverrides: const <String, Object?>{
          'feature_momo_stage': 'internal',
          'feature_momo_admin_only': 'true',
        },
      );

      final app = await pumpRouterApp(
        tester,
        initialLocation: AppRoutes.momo,
        session: fakeSession(),
        user: fakeUser(isAdmin: true),
        overrides: <Override>[
          featureFlagsServiceProvider.overrideWithValue(featureFlagsService),
        ],
      );

      expect(
        app.router.routeInformationProvider.value.uri.path,
        AppRoutes.momo,
      );
      expect(find.text('Temporarily Unavailable'), findsNothing);
      expect(find.text('Mobile Money'), findsOneWidget);
    });

    testWidgets(
      'managed app config also blocks MoMo statements for standard users',
      (tester) async {
        final featureFlagsService = await _buildFeatureFlagsService(
          appConfigOverrides: const <String, Object?>{
            'feature_momo_stage': 'internal',
            'feature_momo_admin_only': 'true',
          },
        );

        final app = await pumpRouterApp(
          tester,
          initialLocation: AppRoutes.momoStatements,
          session: fakeSession(),
          user: fakeUser(),
          overrides: <Override>[
            featureFlagsServiceProvider.overrideWithValue(featureFlagsService),
          ],
        );

        expect(
          app.router.routeInformationProvider.value.uri.path,
          AppRoutes.momoStatements,
        );
        expect(find.text('Temporarily Unavailable'), findsOneWidget);
        expect(
          find.textContaining('Mobile Money is temporarily unavailable.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'managed app config blocks direct BioPay routes when BioPay is disabled',
      (tester) async {
        final featureFlagsService = await _buildFeatureFlagsService(
          appConfigOverrides: const <String, Object?>{
            'feature_biopay_enabled': false,
          },
        );

        final app = await pumpRouterApp(
          tester,
          initialLocation: AppRoutes.biopayHome,
          session: fakeSession(),
          user: fakeUser(),
          overrides: <Override>[
            featureFlagsServiceProvider.overrideWithValue(featureFlagsService),
          ],
        );

        expect(
          app.router.routeInformationProvider.value.uri.path,
          AppRoutes.biopayHome,
        );
        expect(find.text('Temporarily Unavailable'), findsOneWidget);
        expect(
          find.textContaining('BioPay is temporarily unavailable.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'managed app config allows BioPay routes when BioPay is enabled',
      (tester) async {
        final featureFlagsService = await _buildFeatureFlagsService(
          appConfigOverrides: const <String, Object?>{
            'feature_biopay_enabled': true,
          },
        );

        final app = await pumpRouterApp(
          tester,
          initialLocation: AppRoutes.biopayHome,
          session: fakeSession(),
          user: fakeUser(),
          overrides: <Override>[
            featureFlagsServiceProvider.overrideWithValue(featureFlagsService),
          ],
        );

        expect(
          app.router.routeInformationProvider.value.uri.path,
          AppRoutes.biopayHome,
        );
        expect(find.text('Temporarily Unavailable'), findsNothing);
        expect(find.text('BioPay'), findsWidgets);
      },
    );
  });
}
