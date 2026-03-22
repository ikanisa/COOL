import 'package:cool_app/core/providers/production_redesign_provider.dart';
import 'package:cool_app/core/config/app_config_provider.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  UserProfile user({bool isAdmin = false}) {
    return UserProfile(
      id: isAdmin ? 'admin-1' : 'user-1',
      phone: '250700000000',
      fullName: isAdmin ? 'Admin User' : 'Regular User',
      momoNumber: '250700000000',
      momoProvider: 'mtn',
      country: 'RW',
      isDriver: false,
      isAdmin: isAdmin,
    );
  }

  test('defaults enable redesigned routes for signed-in users', () async {
    final container = ProviderContainer(
      overrides: [
        allAppConfigProvider.overrideWith((ref) async => <String, String>{}),
        currentUserProvider.overrideWith((ref) => user()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(allAppConfigProvider.future);

    final enabled = container.read(
      productionRedesignEnabledProvider(
        const ProductionRedesignScope(
          route: ProductionRedesignRoutes.rayonHome,
          partner: 'rayon',
        ),
      ),
    );

    expect(enabled, isTrue);
  });

  test('route, partner, and cohort controls gate redesign exposure', () async {
    final container = ProviderContainer(
      overrides: [
        allAppConfigProvider.overrideWith(
          (ref) async => <String, String>{
            'production_redesign_routes': 'rayon_shop_checkout',
            'production_redesign_partners': 'rayon',
            'production_redesign_cohort_percent': '0',
            'production_redesign_admin_override': 'false',
          },
        ),
        currentUserProvider.overrideWith((ref) => user()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(allAppConfigProvider.future);

    expect(
      container.read(
        productionRedesignEnabledProvider(
          const ProductionRedesignScope(
            route: ProductionRedesignRoutes.rayonShopCheckout,
            partner: 'rayon',
          ),
        ),
      ),
      isFalse,
    );
    expect(
      container.read(
        productionRedesignEnabledProvider(
          const ProductionRedesignScope(
            route: ProductionRedesignRoutes.rayonTickets,
            partner: 'rayon',
          ),
        ),
      ),
      isFalse,
    );
  });

  test(
    'admin override keeps redesign reachable during constrained rollout',
    () async {
      final container = ProviderContainer(
        overrides: [
          allAppConfigProvider.overrideWith(
            (ref) async => <String, String>{
              'production_redesign_routes': 'mobility_schedule',
              'production_redesign_cohort_percent': '0',
            },
          ),
          currentUserProvider.overrideWith((ref) => user(isAdmin: true)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(allAppConfigProvider.future);

      final enabled = container.read(
        productionRedesignEnabledProvider(
          const ProductionRedesignScope(
            route: ProductionRedesignRoutes.mobilitySchedule,
          ),
        ),
      );

      expect(enabled, isTrue);
    },
  );
}
