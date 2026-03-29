import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cool_app/core/services/hive_runtime.dart';
import 'package:cool_app/core/router/app_routes.dart';

import '../test/integration_smoke/test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeHiveRuntime();
  });

  group('MoMo SMS edge cases', () {
    testWidgets('MoMo screen loads for authenticated user', (tester) async {
      final app = await pumpRouterApp(
        tester,
        initialLocation: '/momo',
        session: fakeSession(),
        user: fakeUser(),
      );

      expect(
        app.router.routeInformationProvider.value.uri.path,
        AppRoutes.biopayHome,
      );
      expect(find.text('BioPay Hub'), findsOneWidget);
    });

    testWidgets('MoMo deep link with amount param lands on MoMo', (
      tester,
    ) async {
      final app = await pumpRouterApp(
        tester,
        initialLocation: '/momo?amount=15000',
        session: fakeSession(),
        user: fakeUser(),
      );

      final uri = app.router.routeInformationProvider.value.uri;
      expect(uri.path, AppRoutes.momo);
      expect(uri.queryParameters['amount'], '15000');
      expect(
        find.byKey(const ValueKey<String>('momo-action-statements')),
        findsOneWidget,
      );
    });

    testWidgets('MoMo deep link without auth redirects to onboarding', (
      tester,
    ) async {
      final app = await pumpRouterApp(
        tester,
        initialLocation: '/momo',
        session: null,
        user: null,
      );

      expect(
        app.router.routeInformationProvider.value.uri.path,
        AppRoutes.biopayHome,
      );
      expect(find.text('BioPay Hub'), findsOneWidget);
    });
  });

  group('BioPay journeys', () {
    testWidgets('BioPay home requires auth', (tester) async {
      await pumpRouterApp(
        tester,
        initialLocation: AppRoutes.biopayHome,
        session: null,
        user: null,
      );

      expect(find.text('BioPay Hub'), findsOneWidget);
    });

    testWidgets('BioPay home loads for authenticated user', (tester) async {
      await pumpRouterApp(
        tester,
        initialLocation: AppRoutes.biopayHome,
        session: fakeSession(),
        user: fakeUser(),
      );

      expect(find.text('BioPay Hub'), findsOneWidget);
    });
  });
}
