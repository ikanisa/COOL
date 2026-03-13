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

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Enter your code'), findsNothing);
    });

    testWidgets('OTP screen accepts global WhatsApp numbers with +', (
      tester,
    ) async {
      await pumpRouterApp(tester, initialLocation: AppRoutes.otp);

      await tester.enterText(find.byType(TextField), '+256781234567');
      await tester.tap(find.text('Continue'));
      await settleTestApp(tester);

      expect(find.text('Enter your code'), findsOneWidget);
    });

    testWidgets('OTP screen explains Rwanda market and global login', (
      tester,
    ) async {
      await pumpRouterApp(tester, initialLocation: AppRoutes.otp);

      expect(
        find.text(
          'Cool serves Rwanda only. You can still sign in with any WhatsApp number worldwide.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Use your Rwanda number in local format, or paste a full WhatsApp number in E.164 format with +.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('OTP screen does not expose a country picker', (tester) async {
      await pumpRouterApp(tester, initialLocation: AppRoutes.otp);

      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      expect(find.text('+250'), findsNothing);
    });
  });
}
