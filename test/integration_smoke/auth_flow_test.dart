import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/brand/app_brand.dart';
import 'package:cool_app/core/router/app_router.dart';
import 'package:cool_app/features/auth/screens/splash_screen.dart';
import 'package:cool_app/shared/widgets/cool_brand_mark.dart';

import 'test_harness.dart';

void main() {
  group('Auth splash flow', () {
    testWidgets('splash screen keeps the current branded shell', (
      tester,
    ) async {
      await pumpScopedApp(tester, child: const SplashScreen());

      expect(find.byType(CoolBrandMark), findsOneWidget);
      expect(find.text(const AppBranding.rayon().splashTitle), findsOneWidget);
      expect(find.text('Get Started'), findsNothing);
      expect(find.text('Continue'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('router boot auto-signs in and redirects to home', (
      tester,
    ) async {
      final app = await pumpRouterApp(
        tester,
        initialLocation: AppRoutes.splash,
      );

      expect(
        app.router.routeInformationProvider.value.uri.path,
        AppRoutes.home,
      );
      expect(find.text(const AppBranding.rayon().splashTitle), findsNothing);
    });

    testWidgets('splash route no longer exposes legacy onboarding fields', (
      tester,
    ) async {
      await pumpScopedApp(tester, child: const SplashScreen());

      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Verify & Continue'), findsNothing);
    });
  });
}
