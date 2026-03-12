import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/router/app_router.dart';

import 'test_harness.dart';

void main() {
  group('Auth onboarding flow', () {
    testWidgets('Onboarding renders both entry CTAs', (tester) async {
      await pumpRouterApp(tester, initialLocation: AppRoutes.onboarding);

      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('I already have an account'), findsOneWidget);
    });

    testWidgets('OTP screen validates empty phone number', (tester) async {
      await pumpRouterApp(tester, initialLocation: AppRoutes.otp);

      await tester.tap(find.text('Continue'));
      await settleTestApp(tester);

      expect(find.text('Enter your phone number'), findsOneWidget);
    });

    testWidgets('OTP screen validates invalid phone format', (tester) async {
      await pumpRouterApp(tester, initialLocation: AppRoutes.otp);

      await tester.enterText(find.byType(TextField), '123');
      await tester.tap(find.text('Continue'));
      await settleTestApp(tester);

      expect(find.text('Enter a 9-digit Rwandan number'), findsOneWidget);
    });

    testWidgets('Country picker shows supported countries', (tester) async {
      await pumpRouterApp(tester, initialLocation: AppRoutes.otp);

      await tester.tap(find.text('+250'));
      await settleTestApp(tester);

      expect(find.textContaining('Rwanda'), findsOneWidget);
      expect(find.textContaining('Benin'), findsOneWidget);
      expect(find.textContaining('Ghana'), findsOneWidget);
    });
  });
}
