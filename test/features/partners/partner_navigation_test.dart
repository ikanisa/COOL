import 'package:cool_app/core/router/app_router.dart';
import 'package:cool_app/features/partners/screens/fans_screen.dart';
import 'package:cool_app/features/partners/widgets/rayon_screen_scaffold.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('partner navigation', () {
    testWidgets(
      'fans screen back falls back to partners when opened directly',
      (tester) async {
        final router = _buildRouter(
          initialLocation: '/partners/apr-fc/fans',
          routes: <RouteBase>[
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const _RouteMarker('home'),
            ),
            GoRoute(
              path: AppRoutes.partners,
              builder: (context, state) => const _RouteMarker('partners'),
              routes: <RouteBase>[
                GoRoute(
                  path: ':id/fans',
                  builder: (context, state) =>
                      FansScreen(partnerId: state.pathParameters['id'] ?? ''),
                ),
              ],
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp.router(
            routerConfig: router,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();

        expect(
          router.routeInformationProvider.value.uri.path,
          AppRoutes.partners,
        );
        expect(find.text('partners'), findsOneWidget);
      },
    );

    testWidgets('fans screen home action always returns to home', (
      tester,
    ) async {
      final router = _buildRouter(
        initialLocation: '/partners/apr-fc/fans',
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const _RouteMarker('home'),
          ),
          GoRoute(
            path: AppRoutes.partners,
            builder: (context, state) => const _RouteMarker('partners'),
            routes: <RouteBase>[
              GoRoute(
                path: ':id/fans',
                builder: (context, state) =>
                    FansScreen(partnerId: state.pathParameters['id'] ?? ''),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Partners Home'));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, AppRoutes.home);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('rayon scaffold back falls back to configured route', (
      tester,
    ) async {
      final router = _buildRouter(
        initialLocation: AppRoutes.rayonShop,
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const _RouteMarker('home'),
          ),
          GoRoute(
            path: AppRoutes.rayonHome,
            builder: (context, state) => const _RouteMarker('rayon-home'),
          ),
          GoRoute(
            path: AppRoutes.rayonShop,
            builder: (context, state) => const _RayonHarnessScreen(),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutes.rayonHome,
      );
      expect(find.text('rayon-home'), findsOneWidget);
    });
  });
}

GoRouter _buildRouter({
  required String initialLocation,
  required List<RouteBase> routes,
}) {
  final router = GoRouter(initialLocation: initialLocation, routes: routes);
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

class _RayonHarnessScreen extends StatelessWidget {
  const _RayonHarnessScreen();

  @override
  Widget build(BuildContext context) {
    return const RayonScreenScaffold(
      title: 'Harness',
      fallbackLocation: AppRoutes.rayonHome,
      child: SizedBox.shrink(),
    );
  }
}
