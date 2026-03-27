import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/router/app_router.dart';

import 'test_harness.dart';

void main() {
  testWidgets('Unauthenticated app boot auto-signs in and leaves splash', (
    tester,
  ) async {
    final app = await pumpRouterApp(tester);

    expect(app.router.routeInformationProvider.value.uri.path, AppRoutes.home);
    expect(find.text('Get Started'), findsNothing);
    expect(find.text('Continue'), findsNothing);
  });
}
