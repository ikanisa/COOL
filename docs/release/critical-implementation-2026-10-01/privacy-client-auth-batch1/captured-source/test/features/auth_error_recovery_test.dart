import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/supabase/auth_otp_gateway.dart';
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
              overrides: [authOtpGatewayProvider.overrideWithValue(gateway)],
              child: MaterialApp(
                theme: light ? AppTheme.light() : AppTheme.dark(),
                home: const AuthScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
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
  _FailingGateway({required this.failSend});
  final bool failSend;
  int verifications = 0;

  @override
  Future<void> sendWhatsAppOtp({
    required String phone,
    String? captchaToken,
  }) async {
    if (failSend) throw const FormatException('Try again.');
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
