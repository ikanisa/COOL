import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const reviewPhone = String.fromEnvironment('APP_REVIEW_AUTH_PHONE');
  const reviewOtp = String.fromEnvironment('APP_REVIEW_AUTH_OTP');

  testWidgets(
    'review auth login completes with configured phone and OTP',
    (tester) async {
      expect(
        reviewPhone.trim(),
        isNotEmpty,
        reason: 'Run with --dart-define=APP_REVIEW_AUTH_PHONE=...',
      );
      expect(
        reviewOtp.trim(),
        isNotEmpty,
        reason: 'Run with --dart-define=APP_REVIEW_AUTH_OTP=...',
      );

      final router = createAppRouter(initialLocation: '/auth');
      addTearDown(router.dispose);
      final repository = CollectRepository.appReviewDemo();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appRouterProvider.overrideWithValue(router),
            appEnvProvider.overrideWithValue(
              const AppEnv(
                supabaseUrl: '',
                supabaseAnonKey: '',
                publicUrl: '',
                adminAppUrl: '',
                enableSmsReader: false,
                enableAndroidSmsAccess: false,
                enableAdminPanel: false,
                enableAdminDevTools: false,
                authCaptchaEnabled: false,
                authCaptchaProvider: '',
                authCaptchaSiteKey: '',
                appReviewAuthEnabled: true,
                appReviewAuthPhone: reviewPhone,
                appReviewAuthOtp: reviewOtp,
              ),
            ),
            collectRepositoryProvider.overrideWith((ref) => repository),
            legalConsentAcceptedProvider.overrideWith((ref) => true),
          ],
          child: const CollectApp(),
        ),
      );

      for (var i = 0; i < 14; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Sign in'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, reviewPhone);
      await tester.tap(find.text('Send WhatsApp code'));
      await tester.pump();

      expect(find.text('Verify WhatsApp'), findsOneWidget);
      expect(find.text('Authentication failed'), findsNothing);

      await tester.enterText(find.byType(TextField).first, reviewOtp);
      await tester.tap(find.text('Verify and continue'));
      await tester.pumpAndSettle();

      expect(find.text('TOTAL COLLECTED'), findsOneWidget);
      expect(find.text('WhatsApp verified.'), findsNothing);
      expect(repository.state.currentProfile?.whatsappPhone, reviewPhone);
      expect(repository.state.collections, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
