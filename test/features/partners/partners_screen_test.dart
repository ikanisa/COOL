import 'package:cool_app/core/router/app_router.dart';
import 'package:cool_app/features/partners/models/partner.dart';
import 'package:cool_app/features/partners/providers/partner_provider.dart';
import 'package:cool_app/features/partners/repositories/partner_repository.dart';
import 'package:cool_app/features/partners/screens/partners_screen.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class MockPartnerRepository extends Mock implements PartnerRepository {}

void main() {
  late MockPartnerRepository repository;

  setUp(() {
    repository = MockPartnerRepository();

    when(() => repository.fetchAll()).thenAnswer(
      (_) async => const <Partner>[
        Partner(
          id: 'rayon-sports',
          name: 'Rayon Sports',
          slug: 'rayon-sports',
          category: PartnerCategory.football,
          country: 'RW',
          subtitle: 'Club experience',
          fanCount: 23000,
          clubCount: 18,
          gameCount: 4,
        ),
      ],
    );
  });

  Future<void> pumpPartnersScreen(
    WidgetTester tester, {
    required GoRouter router,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [partnerRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(
          routerConfig: router,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  group('PartnersScreen features', () {
    testWidgets('Fan Registry tile opens member registry', (tester) async {
      final router = _buildRouter();

      await pumpPartnersScreen(tester, router: router);

      await _tapFeatureTile(
        tester,
        tileKey: const ValueKey('partner_feature_fan_registry'),
      );
      await tester.pumpAndSettle();

      expect(find.text('registry'), findsOneWidget);
    });

    testWidgets('Fan Clubs tile opens fan clubs', (tester) async {
      final router = _buildRouter();

      await pumpPartnersScreen(tester, router: router);

      await _tapFeatureTile(
        tester,
        tileKey: const ValueKey('partner_feature_fan_clubs'),
      );
      await tester.pumpAndSettle();

      expect(find.text('clubs'), findsOneWidget);
    });

    testWidgets('Ticketing tile opens tickets', (tester) async {
      final router = _buildRouter();

      await pumpPartnersScreen(tester, router: router);

      await _tapFeatureTile(
        tester,
        tileKey: const ValueKey('partner_feature_ticketing'),
      );
      await tester.pumpAndSettle();

      expect(find.text('tickets'), findsOneWidget);
    });

    testWidgets('Club Shop tile opens club shop', (tester) async {
      final router = _buildRouter();

      await pumpPartnersScreen(tester, router: router);

      await _tapFeatureTile(
        tester,
        tileKey: const ValueKey('partner_feature_club_shop'),
      );
      await tester.pumpAndSettle();

      expect(find.text('shop'), findsOneWidget);
    });
  });
}

Future<void> _tapFeatureTile(
  WidgetTester tester, {
  required ValueKey<String> tileKey,
}) async {
  final tile = find.byKey(tileKey);
  await tester.ensureVisible(tile);
  await tester.tap(tile);
}

GoRouter _buildRouter() {
  final router = GoRouter(
    initialLocation: AppRoutes.partners,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const _RouteMarker('home'),
      ),
      GoRoute(
        path: AppRoutes.partners,
        builder: (context, state) => const PartnersScreen(),
      ),
      GoRoute(
        path: AppRoutes.rayonRegistry,
        builder: (context, state) => const _RouteMarker('registry'),
      ),
      GoRoute(
        path: AppRoutes.rayonClubs,
        builder: (context, state) => const _RouteMarker('clubs'),
      ),
      GoRoute(
        path: AppRoutes.rayonTickets,
        builder: (context, state) => const _RouteMarker('tickets'),
      ),
      GoRoute(
        path: AppRoutes.rayonShop,
        builder: (context, state) => const _RouteMarker('shop'),
      ),
    ],
  );
  addTearDown(router.dispose);
  return router;
}

class _RouteMarker extends StatelessWidget {
  const _RouteMarker(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}
