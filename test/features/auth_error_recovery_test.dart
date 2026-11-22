import '../fixtures/auth_otp_gateway_fixture.dart';

import 'dart:convert';

import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/cloudflare/auth_otp_gateway.dart';
import 'package:collect_app/features/auth/auth_screen.dart';
import 'package:collect_app/features/auth/widgets/auth_screen_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
  });

  for (final deliveryUnconfirmed in [true, false]) {
    testWidgets(
      '${deliveryUnconfirmed ? 'uncertain' : 'accepted'} delivery keeps code entry usable and honors server timing at 200 percent text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        const challenge = '22222222-2222-4222-8222-222222222222';
        final requests = <http.Request>[];
        final client = CollectCloudflareClient(
          'https://api.example.com',
          httpClient: MockClient((request) async {
            requests.add(request);
            final body = request.url.path.endsWith('/otp')
                ? {
                    if (deliveryUnconfirmed)
                      'error': {
                        'code': 'otp_delivery_unknown',
                        'message': 'private upstream value',
                      }
                    else
                      'accepted': true,
                    'challenge_id': challenge,
                    'request_id': challenge,
                    'retry_after': 120,
                  }
                : {
                    'error': {'code': 'invalid_credentials'},
                  };
            return http.Response(
              jsonEncode(body),
              request.url.path.endsWith('/otp')
                  ? (deliveryUnconfirmed ? 503 : 202)
                  : 401,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                collectBackendClientProvider.overrideWithValue(null),
                authOtpGatewayProvider.overrideWithValue(
                  CollectAuthOtpGateway(client, whatsAppSignInEnabled: true),
                ),
              ],
              child: MaterialApp(
                theme: AppTheme.dark(),
                home: const AuthScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          debugPrint('collect_otp_recovery:before-request');
          await _requestCode(tester);
          debugPrint('collect_otp_recovery:request-finished');
          await tester.scrollUntilVisible(
            find.text('Enter the WhatsApp code for +250 *** 3456.'),
            -120,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            find.text('Enter the WhatsApp code for +250 *** 3456.'),
            findsOneWidget,
          );
          expect(find.textContaining('code sent to'), findsNothing);
          if (deliveryUnconfirmed) {
            final notice = tester.widget<AuthStatusNotice>(
              find.byType(AuthStatusNotice),
            );
            expect(notice.title, 'Delivery not confirmed');
            expect(
              notice.message,
              'Delivery could not be confirmed. If a code arrives, enter it here before requesting another.',
            );
            expect(
              tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('auth_otp_digit_0')),
                  )
                  .autofocus,
              isFalse,
            );
            tester.view.viewInsets = const FakeViewPadding(bottom: 140);
            await tester.pumpAndSettle();
            final viewport = tester.getRect(find.byType(ListView));
            expect(
              tester.getRect(find.byType(AuthStatusNotice)).top,
              greaterThanOrEqualTo(viewport.top),
            );
            tester.view.resetViewInsets();
            await tester.pumpAndSettle();
          } else {
            expect(find.byType(AuthStatusNotice), findsNothing);
          }
          expect(find.textContaining('private upstream'), findsNothing);
          expect(client.auth.currentSession, isNull);
          final countdown = find.textContaining('Resend code in ');
          await tester.scrollUntilVisible(
            countdown,
            120,
            scrollable: find.byType(Scrollable).first,
          );
          final initialCountdown = tester.widget<Text>(countdown).data!;
          expect(
            initialCountdown,
            matches(RegExp(r'^Resend code in (02:00|01:5[0-9])$')),
          );
          await tester.pump(const Duration(seconds: 61));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const ValueKey('auth_resend_button')),
          );
          await tester.tap(find.byKey(const ValueKey('auth_resend_button')));
          await tester.pumpAndSettle();
          expect(
            requests.where((r) => r.url.path.endsWith('/otp')),
            hasLength(1),
            reason:
                'The server 120-second cooldown must still block a resend after61 seconds.',
          );
          final otp = find.byKey(const ValueKey('auth_otp_digit_0'));
          await tester.scrollUntilVisible(
            otp,
            120,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.enterText(otp, '123456');
          await tester.pump();
          await tester.tap(find.text('Verify and continue'));
          await tester.pumpAndSettle();
          expect(
            requests.where((r) => r.url.path.endsWith('/otp')),
            hasLength(1),
          );
          expect(
            requests.where((r) => r.url.path.endsWith('/verify')),
            hasLength(1),
          );
          expect(
            (jsonDecode(requests.last.body) as Map)['challenge_id'],
            challenge,
          );
          expect(
            tester
                .widget<AuthStatusNotice>(find.byType(AuthStatusNotice))
                .message,
            'That WhatsApp code is invalid or expired. Request a fresh code and try again.',
          );
          expect(client.auth.currentSession, isNull);
          debugPrint('collect_otp_recovery:verification-finished');
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          final disposing = client.dispose();
          await tester.pump();
          await disposing;
          debugPrint('collect_otp_recovery:disposal-finished');
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
  for (final scenario in [
    (
      'auth_configuration_missing',
      '503',
      'WhatsApp sign-in is unavailable right now. Try again later.',
    ),
    ('auth_rate_limited', '429', 'Too many sign-in attempts. Try again later.'),
    (
      'captcha_failed',
      '400',
      'Security verification could not finish. Try again.',
    ),
  ]) {
    testWidgets(
      'typed auth recovery uses the actual reason without upstream text: ${scenario.$1}',
      (tester) async {
        final gateway = _FailingGateway(
          failSend: true,
          error: CollectAuthException(
            'invalid OTP private@example.invalid',
            code: scenario.$1,
            statusCode: scenario.$2,
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              collectBackendClientProvider.overrideWithValue(null),
              authOtpGatewayProvider.overrideWithValue(gateway),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const AuthScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _requestCode(tester);
        expect(
          tester
              .widget<AuthStatusNotice>(find.byType(AuthStatusNotice))
              .message,
          scenario.$3,
        );
        expect(find.textContaining('private@example.invalid'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
  for (final light in [false, true]) {
    for (final failSend in [false, true]) {
      testWidgets(
        '${failSend ? 'send' : 'OTP'} error is revealed at 320dp / 200% in ${light ? 'light' : 'dark'} mode',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final gateway = _FailingGateway(failSend: failSend);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                collectBackendClientProvider.overrideWithValue(null),
                authOtpGatewayProvider.overrideWithValue(gateway),
              ],
              child: MaterialApp(
                theme: light ? AppTheme.light() : AppTheme.dark(),
                home: const AuthScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await selectWhatsAppSignIn(tester);
          final phone = find.byKey(const ValueKey('auth_whatsapp_phone_input'));
          await tester.scrollUntilVisible(
            phone,
            120,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.enterText(phone, '788123456');
          await tester.pump();
          await tester.tap(find.text('Send WhatsApp code'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Confirm and send'));
          await tester.tap(find.text('Confirm and send'));
          await tester.pumpAndSettle();
          if (!failSend) {
            final otp = find.byKey(const ValueKey('auth_otp_digit_0'));
            await tester.scrollUntilVisible(
              otp,
              120,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.enterText(otp, '000000');
            await tester.pump();
            await tester.tap(find.text('Verify and continue'));
            await tester.pumpAndSettle();
            expect(gateway.verifications, 1);
          }
          final notice = find.byType(AuthStatusNotice);
          expect(notice, findsOneWidget);
          final bounds = tester.getRect(notice);
          final viewport = tester.getRect(find.byType(ListView));
          expect(bounds.top, greaterThanOrEqualTo(viewport.top));
          expect(
            find.text('Authentication failed').hitTestable(),
            findsOneWidget,
          );
          final message = find.text(
            tester.widget<AuthStatusNotice>(notice).message,
          );
          expect(
            tester.renderObject<RenderParagraph>(message).didExceedMaxLines,
            isFalse,
            reason: 'Recovery guidance must not be truncated at enlarged text.',
          );
          final position = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(message).bottom,
            lessThanOrEqualTo(viewport.bottom),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        },
      );
    }
  }
}

class _FailingGateway implements AuthOtpGateway {
  _FailingGateway({required this.failSend, this.error});
  final Object? error;
  final bool failSend;
  int verifications = 0;

  @override
  bool get whatsAppSignInAvailable => true;

  @override
  Future<void> sendWhatsAppOtp({
    required String phone,
    String? captchaToken,
  }) async {
    if (failSend) throw error ?? const FormatException('Try again.');
  }

  @override
  Future<void> verifyWhatsAppOtp({
    required String phone,
    required String otp,
    String? captchaToken,
  }) async {
    verifications++;
    throw const FormatException('Invalid OTP');
  }
}

Future<void> _requestCode(WidgetTester tester) async {
  await selectWhatsAppSignIn(tester);
  final phone = find.byKey(const ValueKey('auth_whatsapp_phone_input'));
  await tester.scrollUntilVisible(
    phone,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.enterText(phone, '788123456');
  await tester.pump();
  await tester.tap(find.text('Send WhatsApp code'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Confirm and send'));
  await tester.tap(find.text('Confirm and send'));
  await tester.pumpAndSettle();
}
