import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/router/app_router.dart';

import 'test_harness.dart';

void main() {
  group('Deep link routing', () {
    testWidgets('Invite deep link keeps redirect target while signed out', (
      tester,
    ) async {
      final app = await pumpRouterApp(
        tester,
        initialLocation: AppRoutes.inviteLocation('abcd1234'),
      );

      final uri = app.router.routeInformationProvider.value.uri;

      expect(uri.path, AppRoutes.groups);
      expect(uri.queryParameters['invite_code'], 'ABCD1234');
      expect(uri.queryParameters['redirect'], isNull);
    });

    testWidgets(
      'Register deep link preserves its phone query on the public route',
      (tester) async {
        const registerLink = '/register?phone=%2B250788123456';
        final app = await pumpRouterApp(tester, initialLocation: registerLink);

        final uri = app.router.routeInformationProvider.value.uri;

        expect(uri.path, AppRoutes.register);
        expect(uri.queryParameters['phone'], '+250788123456');
        expect(uri.queryParameters['redirect'], isNull);
      },
    );
  });
}
