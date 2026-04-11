import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/router/app_router.dart';

import 'test_harness.dart';

void main() {
  group('MoMo smoke routing', () {
    testWidgets('Legacy /momo route redirects to the BioPay home surface', (
      tester,
    ) async {
      final app = await pumpRouterApp(
        tester,
        initialLocation: AppRoutes.momo,
        session: fakeSession(),
        user: fakeUser(),
      );

      expect(
        app.router.routeInformationProvider.value.uri.path,
        AppRoutes.biopayHome,
      );
    });

    testWidgets('Wallet route stays reachable for signed-in users', (
      tester,
    ) async {
      final app = await pumpRouterApp(
        tester,
        initialLocation: AppRoutes.momoWallet,
        session: fakeSession(),
        user: fakeUser(),
      );

      expect(
        app.router.routeInformationProvider.value.uri.path,
        AppRoutes.momoWallet,
      );
      expect(find.text('WALLET'), findsOneWidget);
    });
  });
}
