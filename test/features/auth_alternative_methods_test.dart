import '../fixtures/auth_otp_gateway_fixture.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/cloudflare/auth_alternative_gateway.dart';
import 'package:collect_app/core/cloudflare/auth_otp_gateway.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/features/auth/auth_screen.dart';
import 'package:collect_app/features/auth/widgets/auth_screen_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Gateway implements AuthAlternativeGateway {
  _Gateway({this.googleEnabled = false});
  bool googleEnabled;
  int googleCalls = 0;
  @override
  bool get googleSignInAvailable => googleEnabled;
  final sent = <String>[];
  final verified = <String>[];
  bool uncertain = false;
  bool cancelled = false;
  final google = Completer<void>();
  @override
  Future<CollectOtpRequestReceipt> sendEmailOtp({required String email}) async {
    sent.add(email);
    if (uncertain) {
      throw const CollectOtpDeliveryUnknownException(retryAfterSeconds: 120);
    }
    return const CollectOtpRequestReceipt(retryAfterSeconds: 120);
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String otp,
  }) async {
    verified.add('$email:$otp');
    throw const CollectAuthException(
      'private upstream detail',
      code: 'invalid_credentials',
    );
  }

  @override
  Future<void> signInWithGoogle() {
    googleCalls++;
    return google.future;
  }

  @override
  void cancelGoogleSignIn() {
    cancelled = true;
    if (!google.isCompleted) {
      google.completeError(
        const CollectAuthException('Cancelled', code: 'google_cancelled'),
      );
    }
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  final output = Platform.environment['COLLECT_AUTH_SCREENSHOTS'];
  if (output == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final dark in [true, false]) {
    testWidgets(
      'email input, code, cooldown and recovery in ${dark ? 'dark' : 'light'} theme',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gateway = _Gateway();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              collectBackendClientProvider.overrideWithValue(null),
              authAlternativeGatewayProvider.overrideWithValue(gateway),
            ],
            child: MaterialApp(
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: const RepaintBoundary(
                key: ValueKey('capture'),
                child: AuthScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('auth_email_input')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('auth_whatsapp_phone_input')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('auth_switch_method')), findsNothing);
        expect(find.text('Continue with Google'), findsNothing);
        if (dark) await capture(tester, 'email-options-dark');
        expect(
          tester
              .widget<TextButton>(
                find.descendant(
                  of: find.byKey(const ValueKey('auth_submit_button')),
                  matching: find.byType(TextButton),
                ),
              )
              .onPressed,
          isNull,
        );
        final input = find.byKey(const ValueKey('auth_email_input'));
        await tester.enterText(input, 'Member@Example.com');
        await tester.pump();
        await capture(tester, 'email-input-${dark ? 'dark' : 'light'}');
        await tester.tap(find.text('Send email code'));
        await tester.pumpAndSettle();
        expect(gateway.sent, ['member@example.com']);
        expect(
          find.text('Enter the email code for member@example.com.'),
          findsOneWidget,
        );
        expect(find.text('Change email'), findsOneWidget);
        await capture(tester, 'email-code-${dark ? 'dark' : 'light'}');
        await tester.pump(const Duration(seconds: 61));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('auth_resend_button')));
        await tester.pumpAndSettle();
        expect(gateway.sent, hasLength(1));
        await tester.enterText(
          find.byKey(const ValueKey('auth_otp_digit_0')),
          '123456',
        );
        await tester.pump();
        await tester.tap(find.text('Verify and continue'));
        await tester.pumpAndSettle();
        expect(gateway.verified, ['member@example.com:123456']);
        expect(
          find.text(
            'That email code is invalid or expired. Request a fresh code and try again.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('private upstream'), findsNothing);
        await tester.tap(find.text('Change email'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(input).controller!.text,
          'Member@Example.com',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'uncertain email delivery remains usable with enlarged text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final gateway = _Gateway()..uncertain = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(null),
            authAlternativeGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const RepaintBoundary(
              key: ValueKey('capture'),
              child: AuthScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final form = tester.widget<ListView>(find.byType(ListView)).controller!;
      form.jumpTo(form.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('auth_email_input'));
      form.jumpTo(form.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.enterText(input, 'member@example.com');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Send email code'));
      await tester.tap(find.text('Send email code'));
      await tester.pumpAndSettle();
      expect(find.byType(AuthStatusNotice), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 140);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, 'email-uncertain-large-text');
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'shipping WhatsApp gateway defaults off and blocks every direct operation before HTTP',
    () async {
      var requests = 0;
      final client = CollectCloudflareClient(
        'https://api.collect.example',
        httpClient: MockClient((request) async {
          requests++;
          throw StateError('Disabled WhatsApp must not reach HTTP.');
        }),
      );
      addTearDown(client.dispose);
      final gateway = CollectAuthOtpGateway(client);
      expect(gateway.whatsAppSignInAvailable, isFalse);
      final unavailable = throwsA(
        isA<CollectAuthException>().having(
          (error) => error.code,
          'disabled capability',
          'whatsapp_unavailable',
        ),
      );
      await expectLater(
        gateway.sendWhatsAppOtp(phone: '+250788123456'),
        unavailable,
      );
      await expectLater(
        gateway.requestWhatsAppOtpReceipt(phone: '+250788123456'),
        unavailable,
      );
      await expectLater(
        gateway.verifyWhatsAppOtp(phone: '+250788123456', otp: '123456'),
        unavailable,
      );
      expect(requests, 0);
      expect(client.auth.currentSession, isNull);
    },
  );

  for (final enabled in [false, true]) {
    test(
      'shipping provider injects explicit WhatsApp availability $enabled',
      () async {
        final client = CollectCloudflareClient(
          'https://api.collect.example',
          httpClient: MockClient((request) async => http.Response('{}', 503)),
        );
        addTearDown(client.dispose);
        final container = ProviderContainer(
          overrides: [
            collectBackendClientProvider.overrideWithValue(client),
            collectWhatsAppAuthEnabledProvider.overrideWithValue(enabled),
          ],
        );
        addTearDown(container.dispose);
        expect(
          container.read(authOtpGatewayProvider)!.whatsAppSignInAvailable,
          enabled,
        );
      },
    );
  }

  testWidgets(
    'enabled WhatsApp is an explicit choice and preserves identity drafts',
    (tester) async {
      final phoneGateway = FixtureAuthOtpGateway(enabled: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authAlternativeGatewayProvider.overrideWithValue(_Gateway()),
            authOtpGatewayProvider.overrideWithValue(phoneGateway),
          ],
          child: MaterialApp(theme: AppTheme.dark(), home: const AuthScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth_email_input')), findsOneWidget);
      expect(find.text('Continue with WhatsApp'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('auth_email_input')),
        'member@example.com',
      );
      await selectWhatsAppSignIn(tester);
      await tester.enterText(
        find.byKey(const ValueKey('auth_whatsapp_phone_input')),
        '788123456',
      );
      await tester.ensureVisible(find.text('Continue with email'));
      await tester.tap(find.text('Continue with email'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('auth_email_input')))
            .controller!
            .text,
        'member@example.com',
      );
      await selectWhatsAppSignIn(tester);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('auth_whatsapp_phone_input')),
            )
            .controller!
            .text,
        '788123456',
      );
      expect(phoneGateway.sends, 0);
      expect(phoneGateway.verifications, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'stale WhatsApp choice rechecks capability before changing method',
    (tester) async {
      final phoneGateway = FixtureAuthOtpGateway(enabled: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authAlternativeGatewayProvider.overrideWithValue(_Gateway()),
            authOtpGatewayProvider.overrideWithValue(phoneGateway),
          ],
          child: MaterialApp(theme: AppTheme.dark(), home: const AuthScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final callback = _authCallback(tester, 'auth_switch_method');
      phoneGateway.enabled = false;
      callback();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth_email_input')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('auth_whatsapp_phone_input')),
        findsNothing,
      );
      expect(phoneGateway.sends, 0);
      expect(phoneGateway.verifications, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('WhatsApp capability is rechecked after the confirmation sheet', (
    tester,
  ) async {
    final phoneGateway = FixtureAuthOtpGateway(enabled: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectBackendClientProvider.overrideWithValue(null),
          authOtpGatewayProvider.overrideWithValue(phoneGateway),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await selectWhatsAppSignIn(tester);
    await tester.enterText(
      find.byKey(const ValueKey('auth_whatsapp_phone_input')),
      '788123456',
    );
    await tester.pump();
    await tester.tap(find.text('Send WhatsApp code'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm your number'), findsOneWidget);
    phoneGateway.enabled = false;
    await tester.tap(find.text('Confirm and send'));
    await tester.pumpAndSettle();
    expect(phoneGateway.sends, 0);
    expect(phoneGateway.verifications, 0);
    expect(find.byKey(const ValueKey('auth_otp_digit_0')), findsNothing);
    expect(
      find.text('WhatsApp sign-in is unavailable right now. Try again later.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final verify in [true, false]) {
    testWidgets(
      'stale WhatsApp ${verify ? 'verify' : 'resend'} cannot dispatch after disable',
      (tester) async {
        final phoneGateway = FixtureAuthOtpGateway(enabled: true);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              collectBackendClientProvider.overrideWithValue(null),
              authOtpGatewayProvider.overrideWithValue(phoneGateway),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const AuthScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await selectWhatsAppSignIn(tester);
        await tester.enterText(
          find.byKey(const ValueKey('auth_whatsapp_phone_input')),
          '788123456',
        );
        await tester.pump();
        await tester.tap(find.text('Send WhatsApp code'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm and send'));
        await tester.pumpAndSettle();
        expect(phoneGateway.sends, 1);
        await tester.enterText(
          find.byKey(const ValueKey('auth_otp_digit_0')),
          '123456',
        );
        await tester.pump(const Duration(seconds: 61));
        await tester.pumpAndSettle();
        final callback = _authCallback(
          tester,
          verify ? 'auth_submit_button' : 'auth_resend_button',
        );
        phoneGateway.enabled = false;
        callback();
        await tester.pumpAndSettle();
        expect(phoneGateway.sends, 1);
        expect(phoneGateway.verifications, 0);
        expect(
          find.text(
            'WhatsApp sign-in is unavailable right now. Try again later.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  test(
    'shipping gateway defaults Google off and rejects direct calls before HTTP',
    () async {
      var requests = 0;
      final client = CollectCloudflareClient(
        'https://api.collect.example',
        httpClient: MockClient((request) async {
          requests++;
          throw StateError('Disabled Google must not reach HTTP.');
        }),
      );
      addTearDown(client.dispose);
      final gateway = CollectAuthAlternativeGateway(client);
      expect(gateway.googleSignInAvailable, isFalse);
      await expectLater(
        gateway.signInWithGoogle(),
        throwsA(
          isA<CollectAuthException>().having(
            (error) => error.code,
            'disabled capability',
            'google_unavailable',
          ),
        ),
      );
      expect(requests, 0);
    },
  );

  for (final enabled in [false, true]) {
    test(
      'shipping provider injects explicit Google availability $enabled',
      () async {
        final client = CollectCloudflareClient(
          'https://api.collect.example',
          httpClient: MockClient((request) async => http.Response('{}', 503)),
        );
        addTearDown(client.dispose);
        final container = ProviderContainer(
          overrides: [
            collectBackendClientProvider.overrideWithValue(client),
            collectGoogleAuthEnabledProvider.overrideWithValue(enabled),
          ],
        );
        addTearDown(container.dispose);
        expect(
          container.read(authAlternativeGatewayProvider)!.googleSignInAvailable,
          enabled,
        );
      },
    );
  }

  testWidgets('null gateways do not expose unavailable Google or WhatsApp', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authAlternativeGatewayProvider.overrideWithValue(null),
          authOtpGatewayProvider.overrideWithValue(null),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auth_google_button')), findsNothing);
    expect(
      find.byKey(const ValueKey('auth_whatsapp_phone_input')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('auth_email_input')), findsOneWidget);
    expect(find.text('Continue with WhatsApp'), findsNothing);
    expect(find.byKey(const ValueKey('auth_google_button')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'stale enabled Google callback rechecks current capability before dispatch',
    (tester) async {
      final gateway = _Gateway(googleEnabled: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(null),
            authAlternativeGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(theme: AppTheme.dark(), home: const AuthScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.byKey(const ValueKey('auth_google_button')),
          matching: find.byType(OutlinedButton),
        ),
      );
      final callback = button.onPressed!;
      gateway.googleEnabled = false;
      callback();
      await tester.pumpAndSettle();
      expect(gateway.googleCalls, 0);
      expect(find.text('Connecting to Google'), findsNothing);
      expect(find.byKey(const ValueKey('auth_google_button')), findsNothing);
      expect(find.byKey(const ValueKey('auth_email_input')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('auth_whatsapp_phone_input')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Google browser wait can cancel and return to another sign-in method',
    (tester) async {
      final gateway = _Gateway(googleEnabled: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(null),
            authAlternativeGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const RepaintBoundary(
              key: ValueKey('capture'),
              child: AuthScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      expect(gateway.googleCalls, 1);
      expect(find.text('Connecting to Google'), findsOneWidget);
      expect(find.byKey(const ValueKey('auth_cancel_google')), findsOneWidget);
      // Pump a known frame; the real progress indicator intentionally never settles.
      await tester.pump(const Duration(milliseconds: 300));
      await capture(tester, 'google-browser-wait');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(gateway.cancelled, isTrue);
      expect(find.byKey(const ValueKey('auth_email_input')), findsOneWidget);
      expect(find.byType(AuthStatusNotice), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

VoidCallback _authCallback(WidgetTester tester, String key) {
  return tester
      .widget<TextButton>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(TextButton),
        ),
      )
      .onPressed!;
}
