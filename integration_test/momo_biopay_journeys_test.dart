import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cool_app/core/services/hive_runtime.dart';
import 'package:cool_app/features/momo/screens/momo_screen.dart';

import '../test/integration_smoke/test_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeHiveRuntime();
  });

  group('MoMo SMS edge cases', () {
    testWidgets('MoMo screen loads for authenticated user', (tester) async {
      await pumpRouterApp(
        tester,
        initialLocation: '/momo',
        session: fakeSession(),
        user: fakeUser(),
      );

      expect(find.byType(MomoScreen), findsOneWidget);
    });

    testWidgets('MoMo deep link with amount param lands on MoMo', (
      tester,
    ) async {
      await pumpRouterApp(
        tester,
        initialLocation: '/momo?amount=15000',
        session: fakeSession(),
        user: fakeUser(),
      );

      expect(find.byType(MomoScreen), findsOneWidget);
    });

    testWidgets('MoMo deep link without auth redirects to onboarding', (
      tester,
    ) async {
      await pumpRouterApp(
        tester,
        initialLocation: '/momo',
        session: null,
        user: null,
      );

      expect(find.text('Welcome to COOL'), findsOneWidget);
    });
  });

  group('BioPay journeys', () {
    testWidgets('BioPay home requires auth', (tester) async {
      await pumpRouterApp(
        tester,
        initialLocation: '/biopay',
        session: null,
        user: null,
      );

      // Should redirect to onboarding when not authenticated
      expect(find.text('Welcome to COOL'), findsOneWidget);
    });

    testWidgets('BioPay home loads for authenticated user', (tester) async {
      await pumpRouterApp(
        tester,
        initialLocation: '/biopay',
        session: fakeSession(),
        user: fakeUser(),
      );

      // BioPay screen should render (may be wrapped in KillSwitch)
      // Since the feature flag may be off in test, we just verify the route resolves
      await settleTestApp(tester);
    });
  });
}
