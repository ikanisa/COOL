import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cool_app/core/router/app_routes.dart';
import 'package:cool_app/core/services/hive_runtime.dart';
import '../test/integration_smoke/test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeHiveRuntime();
  });

  group('Critical journeys', () {
    testWidgets(
      'signed-out deep links preserve the target after anonymous boot',
      (tester) async {
        final app = await pumpRouterApp(
          tester,
          initialLocation: '/momo?amount=5000',
          session: null,
          user: null,
        );

        final uri = app.router.routeInformationProvider.value.uri;
        expect(uri.path, AppRoutes.momo);
        expect(uri.queryParameters['amount'], '5000');
        expect(
          find.byKey(const ValueKey<String>('momo-action-statements')),
          findsOneWidget,
        );
      },
    );

    testWidgets('signed-in base payments route lands on the BioPay hub', (
      tester,
    ) async {
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

  });
}
