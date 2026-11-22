import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/cloudflare/auth_alternative_gateway.dart';
import 'package:collect_app/core/cloudflare/auth_otp_gateway.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_types.dart';
import 'package:collect_app/features/auth/auth_screen.dart';
import 'package:collect_app/features/auth/widgets/auth_screen_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/auth_otp_gateway_fixture.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final useEmail in [true, false]) {
    final method = useEmail ? 'email' : 'WhatsApp';
    final identity = useEmail ? 'member@example.com' : '+250788123456';

    testWidgets(
      '$method resend failure discards stale code and requires an explicit fresh send',
      (tester) async {
        final gateway = _ResendGateway(
          resendError: const CollectAuthException(
            'private upstream detail',
            code: 'auth_transport_unavailable',
            statusCode: '503',
          ),
        );
        await _pumpAuth(tester, gateway);
        await _requestInitialCode(tester, useEmail: useEmail);
        expect(gateway.requests, [identity]);
        _expectCodeStep();

        await _enterCode(tester, '123456');
        expect(
          _actionButton(tester, 'auth_submit_button').onPressed,
          isNotNull,
        );
        await tester.pump(const Duration(seconds: 61));
        await tester.pumpAndSettle();
        expect(
          _actionButton(tester, 'auth_resend_button').onPressed,
          isNotNull,
        );
        await _tap(tester, _key('auth_resend_button'));

        expect(gateway.requests, [identity, identity]);
        expect(gateway.verifications, isEmpty);
        _expectIdentityStep(tester, useEmail: useEmail);
        final notice = tester.widget<AuthStatusNotice>(
          find.byType(AuthStatusNotice),
        );
        expect(notice.title, 'Authentication failed');
        expect(
          notice.message,
          '${useEmail ? 'Email' : 'WhatsApp'} sign-in is unavailable right now. Try again later.',
        );
        expect(find.textContaining('private upstream'), findsNothing);

        await tester.pump(const Duration(seconds: 121));
        await tester.pumpAndSettle();
        _expectIdentityStep(tester, useEmail: useEmail);
        expect(gateway.requests, hasLength(2));
        expect(gateway.verifications, isEmpty);

        await _tap(tester, _key('auth_submit_button'));
        if (!useEmail) await _confirmPhoneRequest(tester);
        expect(gateway.requests, [identity, identity, identity]);
        expect(gateway.verifications, isEmpty);
        _expectCodeStep();
        expect(
          tester.widget<TextField>(_key('auth_otp_digit_0')).controller!.text,
          isEmpty,
          reason:
              'The failed resend must not carry a stale code into recovery.',
        );
        expect(_actionButton(tester, 'auth_submit_button').onPressed, isNull);

        await _enterCode(tester, '654321');
        await _tap(tester, _key('auth_submit_button'));
        expect(gateway.verifications, ['$identity:654321']);
        _expectCodeStep();
        expect(
          tester
              .widget<AuthStatusNotice>(find.byType(AuthStatusNotice))
              .message,
          'That $method code is invalid or expired. Request a fresh code and try again.',
          reason: 'A verification error must keep the current code-entry step.',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$method unconfirmed resend retains code entry and server cooldown',
      (tester) async {
        final gateway = _ResendGateway(
          resendError: const CollectOtpDeliveryUnknownException(
            retryAfterSeconds: 120,
          ),
        );
        await _pumpAuth(tester, gateway);
        await _requestInitialCode(tester, useEmail: useEmail);
        await _enterCode(tester, '123456');
        await tester.pump(const Duration(seconds: 61));
        await tester.pumpAndSettle();
        await _tap(tester, _key('auth_resend_button'));

        expect(gateway.requests, [identity, identity]);
        expect(gateway.verifications, isEmpty);
        _expectCodeStep();
        final notice = tester.widget<AuthStatusNotice>(
          find.byType(AuthStatusNotice),
        );
        expect(notice.title, 'Delivery not confirmed');
        expect(
          notice.message,
          'Delivery could not be confirmed. If a code arrives, enter it here before requesting another.',
        );
        expect(
          tester.widget<TextField>(_key('auth_otp_digit_0')).controller!.text,
          isEmpty,
        );
        expect(_actionButton(tester, 'auth_submit_button').onPressed, isNull);
        expect(_actionButton(tester, 'auth_resend_button').onPressed, isNull);
        await _tap(tester, _key('auth_resend_button'));
        expect(gateway.requests, hasLength(2));

        await tester.pump(const Duration(seconds: 61));
        await tester.pumpAndSettle();
        expect(_actionButton(tester, 'auth_resend_button').onPressed, isNull);
        expect(find.textContaining('Resend code in '), findsOneWidget);
        await _tap(tester, _key('auth_resend_button'));
        expect(
          gateway.requests,
          hasLength(2),
          reason: 'The 120-second server cooldown must outlast 61 seconds.',
        );

        await _enterCode(tester, '654321');
        await _tap(tester, _key('auth_submit_button'));
        expect(gateway.verifications, ['$identity:654321']);
        _expectCodeStep();
        expect(_actionButton(tester, 'auth_resend_button').onPressed, isNull);

        await tester.pump(const Duration(seconds: 61));
        await tester.pumpAndSettle();
        expect(
          _actionButton(tester, 'auth_resend_button').onPressed,
          isNotNull,
        );
        expect(gateway.requests, hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _ResendGateway
    implements
        AuthAlternativeGateway,
        AuthOtpGateway,
        AuthOtpRequestReceiptGateway {
  _ResendGateway({required this.resendError});

  final Object resendError;
  final requests = <String>[];
  final verifications = <String>[];

  @override
  bool get googleSignInAvailable => false;

  @override
  bool get whatsAppSignInAvailable => true;

  Future<CollectOtpRequestReceipt> _request(String identity) async {
    requests.add(identity);
    if (requests.length == 2) throw resendError;
    return const CollectOtpRequestReceipt(retryAfterSeconds: 60);
  }

  Future<void> _verify(String identity, String otp) async {
    verifications.add('$identity:$otp');
    throw const CollectAuthException(
      'private verification detail',
      code: 'invalid_credentials',
    );
  }

  @override
  Future<CollectOtpRequestReceipt> sendEmailOtp({required String email}) =>
      _request(email);

  @override
  Future<void> verifyEmailOtp({required String email, required String otp}) =>
      _verify(email, otp);

  @override
  Future<CollectOtpRequestReceipt> requestWhatsAppOtpReceipt({
    required String phone,
    String? captchaToken,
  }) => _request(phone);

  @override
  Future<void> sendWhatsAppOtp({
    required String phone,
    String? captchaToken,
  }) async {
    await requestWhatsAppOtpReceipt(phone: phone, captchaToken: captchaToken);
  }

  @override
  Future<void> verifyWhatsAppOtp({
    required String phone,
    required String otp,
    String? captchaToken,
  }) => _verify(phone, otp);

  @override
  Future<void> signInWithGoogle() async {
    throw StateError('Google is unavailable in this resend fixture.');
  }

  @override
  void cancelGoogleSignIn() {}
}

Future<void> _pumpAuth(WidgetTester tester, _ResendGateway gateway) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authAlternativeGatewayProvider.overrideWithValue(gateway),
        authOtpGatewayProvider.overrideWithValue(gateway),
      ],
      child: MaterialApp(theme: AppTheme.dark(), home: const AuthScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _requestInitialCode(
  WidgetTester tester, {
  required bool useEmail,
}) async {
  if (!useEmail) await selectWhatsAppSignIn(tester);
  final input = _key(
    useEmail ? 'auth_email_input' : 'auth_whatsapp_phone_input',
  );
  await tester.ensureVisible(input);
  await tester.enterText(input, useEmail ? 'Member@Example.com' : '788123456');
  await tester.pump();
  await _tap(tester, _key('auth_submit_button'));
  if (!useEmail) await _confirmPhoneRequest(tester);
}

Future<void> _confirmPhoneRequest(WidgetTester tester) =>
    _tap(tester, find.text('Confirm and send'));

Future<void> _enterCode(WidgetTester tester, String code) async {
  final input = _key('auth_otp_digit_0');
  await tester.ensureVisible(input);
  await tester.enterText(input, code);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _key(String value) => find.byKey(ValueKey(value));

TextButton _actionButton(WidgetTester tester, String key) =>
    tester.widget<TextButton>(
      find.descendant(of: _key(key), matching: find.byType(TextButton)),
    );

void _expectCodeStep() {
  expect(_key('auth_otp_digit_0'), findsOneWidget);
  expect(_key('auth_email_input'), findsNothing);
  expect(_key('auth_whatsapp_phone_input'), findsNothing);
  expect(find.text('Verify and continue'), findsOneWidget);
}

void _expectIdentityStep(WidgetTester tester, {required bool useEmail}) {
  final input = _key(
    useEmail ? 'auth_email_input' : 'auth_whatsapp_phone_input',
  );
  expect(input, findsOneWidget);
  expect(
    tester.widget<TextField>(input).controller!.text,
    useEmail ? 'Member@Example.com' : '788123456',
  );
  expect(_key('auth_otp_digit_0'), findsNothing);
  expect(_key('auth_resend_button'), findsNothing);
  expect(_key('auth_otp_recovery_message'), findsNothing);
  expect(find.text('Verify and continue'), findsNothing);
  expect(
    find.text('Send ${useEmail ? 'email' : 'WhatsApp'} code'),
    findsOneWidget,
  );
  expect(_actionButton(tester, 'auth_submit_button').onPressed, isNotNull);
}
