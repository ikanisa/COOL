import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/router/app_router.dart';

import 'test_harness.dart';

void main() {
  testWidgets('Unauthenticated app boot lands on onboarding', (tester) async {
    final app = await pumpRouterApp(tester);

    expect(find.text('Welcome to COOL'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(
      app.router.routeInformationProvider.value.uri.path,
      AppRoutes.onboarding,
    );
  });
}
