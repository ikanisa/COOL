import 'package:collect_app/core/cloudflare/auth_otp_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test-only transport capability; never used by production provider selection.
class FixtureAuthOtpGateway implements AuthOtpGateway {
  FixtureAuthOtpGateway({required this.enabled});

  bool enabled;
  int sends = 0;
  int verifications = 0;

  @override
  bool get whatsAppSignInAvailable => enabled;

  @override
  Future<void> sendWhatsAppOtp({
    required String phone,
    String? captchaToken,
  }) async {
    sends++;
  }

  @override
  Future<void> verifyWhatsAppOtp({
    required String phone,
    required String otp,
    String? captchaToken,
  }) async {
    verifications++;
  }
}

Future<void> selectWhatsAppSignIn(WidgetTester tester) async {
  final switcher = find.byKey(const ValueKey('auth_switch_method'));
  await tester.scrollUntilVisible(
    switcher,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(switcher), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(switcher);
  await tester.pumpAndSettle();
  final phone = find.byKey(const ValueKey('auth_whatsapp_phone_input'));
  await tester.scrollUntilVisible(
    phone,
    -120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}
