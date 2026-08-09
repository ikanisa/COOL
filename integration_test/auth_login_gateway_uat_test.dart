import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/core/supabase/auth_otp_gateway.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'server-auth UI completes through an injected test gateway',
    (tester) async {
      const phone = '+250700000001';
      const otp = '135790';
      final router = createAppRouter(initialLocation: '/auth');
      addTearDown(router.dispose);
      final repository = CollectRepository.fixture(seeded: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appRouterProvider.overrideWithValue(router),
            authOtpGatewayProvider.overrideWithValue(
              const _DeviceTestAuthOtpGateway(acceptedOtp: otp),
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

      await tester.enterText(find.byType(TextField).first, phone);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final sendCode = find.text('Send WhatsApp code');
      await tester.ensureVisible(sendCode);
      await tester.tap(sendCode);
      await tester.pumpAndSettle();
      expect(find.text('Confirm your number'), findsOneWidget);
      await tester.tap(find.text('Confirm and send'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, otp);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final verify = find.text('Verify and continue');
      await tester.ensureVisible(verify);
      await tester.tap(verify);
      await tester.pumpAndSettle();

      expect(find.text('Total collected'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/home');
      expect(repository.state.currentProfile?.whatsappPhone, phone);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _DeviceTestAuthOtpGateway implements AuthOtpGateway {
  const _DeviceTestAuthOtpGateway({required this.acceptedOtp});

  final String acceptedOtp;

  @override
  Future<void> sendWhatsAppOtp({
    required String phone,
    String? captchaToken,
  }) async {}

  @override
  Future<void> verifyWhatsAppOtp({
    required String phone,
    required String otp,
    String? captchaToken,
  }) async {
    if (otp != acceptedOtp) throw const FormatException('Invalid OTP');
  }
}
