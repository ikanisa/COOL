import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/cloudflare/auth_alternative_gateway.dart';
import 'package:collect_app/core/cloudflare/auth_otp_gateway.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/features/auth/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _EmailGuestGateway implements AuthAlternativeGateway, AuthGuestGateway {
  _EmailGuestGateway({this.guest = false, this.pending});
  bool guest;
  CollectGuestUpgradeStatus? pending;
  int starts = 0, reconciles = 0, leaves = 0, sends = 0, verifications = 0;
  @override
  bool get googleSignInAvailable => false;
  @override
  bool get guestSignInAvailable => true;
  @override
  bool get isGuest => guest;
  @override
  CollectGuestUpgradeStatus? get pendingGuestUpgrade => pending;
  @override
  void cancelGoogleSignIn() {}
  @override
  Future<void> signInWithGoogle() async =>
      throw StateError('Google is disabled');
  @override
  Future<CollectOtpRequestReceipt> sendEmailOtp({required String email}) async {
    sends++;
    return const CollectOtpRequestReceipt(retryAfterSeconds: 60);
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String otp,
  }) async {
    verifications++;
    throw const CollectAuthException('Unknown', code: 'guest_upgrade_unknown');
  }

  @override
  Future<void> signInAsGuest() async {
    starts++;
    guest = true;
  }

  @override
  Future<void> reconcileGuestUpgrade() async {
    reconciles++;
    throw const CollectAuthException('Unknown', code: 'guest_upgrade_unknown');
  }

  @override
  Future<void> leaveGuest() async {
    leaves++;
    guest = false;
    pending = null;
  }
}

class _SmsGateway implements AuthOtpGateway, AuthSmsOtpGateway {
  final sent = <String>[], verified = <String>[];
  @override
  bool get whatsAppSignInAvailable => false;
  @override
  bool get smsSignInAvailable => true;
  @override
  Future<void> sendWhatsAppOtp({
    required String phone,
    String? captchaToken,
  }) async => throw StateError('No WhatsApp fallback');
  @override
  Future<void> verifyWhatsAppOtp({
    required String phone,
    required String otp,
    String? captchaToken,
  }) async => throw StateError('No WhatsApp fallback');
  @override
  Future<CollectOtpRequestReceipt> requestSmsOtpReceipt({
    required String phone,
    String? captchaToken,
  }) async {
    sent.add(phone);
    return const CollectOtpRequestReceipt(retryAfterSeconds: 60);
  }

  @override
  Future<void> verifySmsOtp({
    required String phone,
    required String otp,
    String? captchaToken,
  }) async {
    verified.add('$phone:$otp');
    throw const CollectAuthException('Rejected', code: 'invalid_credentials');
  }
}

void main() {
  testWidgets(
    'SMS-only release displays and uses the explicitly selected SMS channel',
    (tester) async {
      final sms = _SmsGateway(), alternative = _EmailGuestGateway();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(null),
            authAlternativeGatewayProvider.overrideWithValue(alternative),
            authOtpGatewayProvider.overrideWithValue(sms),
          ],
          child: MaterialApp(theme: AppTheme.dark(), home: const AuthScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue with WhatsApp'), findsNothing);
      await tester.ensureVisible(find.text('Continue with SMS'));
      await tester.tap(find.text('Continue with SMS'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('auth_sms_phone_input')),
        '788123456',
      );
      await tester.pump();
      await tester.tap(find.text('Send SMS code'));
      await tester.pumpAndSettle();
      expect(
        find.text('We will send a six-digit sign-in code by SMS to'),
        findsOneWidget,
      );
      await tester.tap(find.text('Confirm and send'));
      await tester.pumpAndSettle();
      expect(sms.sent, ['+250788123456']);
      expect(find.textContaining('Enter the SMS code for'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('auth_otp_digit_0')),
        '123456',
      );
      await tester.pump();
      await tester.tap(find.text('Verify and continue'));
      await tester.pumpAndSettle();
      expect(sms.verified, ['+250788123456:123456']);
      expect(alternative.sends, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'retained unknown guest verification exposes recovery without code replay or silent account switch',
    (tester) async {
      final gateway = _EmailGuestGateway(
        guest: true,
        pending: const CollectGuestUpgradeStatus(
          email: 'member@example.test',
          unconfirmed: true,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(null),
            authAlternativeGatewayProvider.overrideWithValue(gateway),
            authOtpGatewayProvider.overrideWithValue(null),
          ],
          child: MaterialApp(theme: AppTheme.dark(), home: const AuthScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Check verification'), findsOneWidget);
      expect(find.byKey(const ValueKey('auth_resend_button')), findsNothing);
      expect(find.byKey(const ValueKey('auth_change_button')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('auth_otp_digit_0')))
            .enabled,
        isFalse,
      );
      await tester.tap(find.text('Check verification'));
      await tester.pumpAndSettle();
      expect(gateway.reconciles, 1);
      expect(gateway.sends, 0);
      expect(gateway.verifications, 0);
      await tester.tap(find.text('Use another account'));
      await tester.pumpAndSettle();
      expect(gateway.leaves, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(gateway.isGuest, isTrue);
      await tester.tap(find.text('Use another account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(gateway.leaves, 1);
      expect(find.text('Check verification'), findsNothing);
      expect(find.byKey(const ValueKey('auth_email_input')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'guest action opens the public groups route without member verification',
    (tester) async {
      final gateway = _EmailGuestGateway();
      final router = GoRouter(
        initialLocation: '/auth',
        routes: [
          GoRoute(path: '/auth', builder: (_, state) => const AuthScreen()),
          GoRoute(
            path: '/groups',
            builder: (_, state) => const Scaffold(body: Text('Public groups')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(null),
            authAlternativeGatewayProvider.overrideWithValue(gateway),
            authOtpGatewayProvider.overrideWithValue(null),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Browse as guest'));
      await tester.tap(find.text('Browse as guest'));
      await tester.pumpAndSettle();
      expect(find.text('Public groups'), findsOneWidget);
      expect(gateway.starts, 1);
      expect(gateway.sends, 0);
      expect(gateway.verifications, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
