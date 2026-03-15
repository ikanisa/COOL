import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/router/app_router.dart';

import 'test_harness.dart';

void main() {
  group('Auth onboarding flow', () {
    testWidgets('Onboarding renders a single primary entry CTA', (
      tester,
    ) async {
      await pumpRouterApp(tester, initialLocation: AppRoutes.onboarding);

      expect(find.text('Welcome to Cool'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
      expect(find.text('I already have an account'), findsNothing);
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

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Enter Code'), findsNothing);
    });

    testWidgets('OTP screen accepts global WhatsApp numbers with +', (
      tester,
    ) async {
      await pumpRouterApp(tester, initialLocation: AppRoutes.otp);

      await tester.enterText(find.byType(TextField), '+256781234567');
      await tester.tap(find.text('Continue'));
      await settleTestApp(tester);

      expect(find.text('Verify code'), findsOneWidget);
    });

    testWidgets('OTP screen explains WhatsApp verification simply', (
      tester,
    ) async {
      await pumpRouterApp(tester, initialLocation: AppRoutes.otp);

      expect(
        find.text('A one-time code will be sent to your WhatsApp.'),
        findsOneWidget,
      );

    });

    testWidgets('OTP screen shows the Rwanda prefix without a picker', (
      tester,
    ) async {
      await pumpRouterApp(tester, initialLocation: AppRoutes.otp);

      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      expect(find.text('+250'), findsOneWidget);
    });
  });
}
