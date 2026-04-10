import 'package:cool_app/core/services/whatsapp_otp_service.dart';
import 'package:cool_app/features/auth/providers/whatsapp_otp_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockWhatsAppOtpService extends Mock implements WhatsAppOtpService {}

void main() {
  late MockWhatsAppOtpService service;
  late WhatsAppOtpNotifier notifier;

  setUp(() {
    service = MockWhatsAppOtpService();
    notifier = WhatsAppOtpNotifier(service: service);
  });

  group('WhatsAppOtpNotifier.sendCode', () {
    test('moves to verify step when send succeeds', () async {
      when(
        () => service.sendOtp('+250788123456'),
      ).thenAnswer((_) async => const OtpSendResult.sent());

      await notifier.sendCode('+250788123456');

      expect(notifier.state.phone, '+250788123456');
      expect(notifier.state.step, WhatsAppOtpStep.verifyCode);
      expect(notifier.state.codeSent, isTrue);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.error, isNull);
      expect(notifier.state.retryAfterSeconds, isNull);
    });

    test('surfaces rate limit details when send is throttled', () async {
      when(() => service.sendOtp('+250788123456')).thenAnswer(
        (_) async => const OtpSendResult.rateLimited(
          'Too many attempts',
          retryAfterSeconds: 42,
        ),
      );

      await notifier.sendCode('+250788123456');

      expect(notifier.state.phone, '+250788123456');
      expect(notifier.state.step, WhatsAppOtpStep.enterPhone);
      expect(notifier.state.codeSent, isFalse);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.error, 'Too many attempts');
      expect(notifier.state.retryAfterSeconds, 42);
    });
  });

  group('WhatsAppOtpNotifier.verifyCode', () {
    test('stores verify result when code is valid', () async {
      notifier.state = notifier.state.copyWith(
        phone: '+250788123456',
        step: WhatsAppOtpStep.verifyCode,
        codeSent: true,
      );

      const result = OtpVerifyResult.verified(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        userId: 'user-123',
        isNewUser: true,
      );
      when(
        () => service.verifyOtp('+250788123456', '123456'),
      ).thenAnswer((_) async => result);

      final value = await notifier.verifyCode('123456');

      expect(value, same(result));
      expect(notifier.state.isVerified, isTrue);
      expect(notifier.state.verifyResult, same(result));
      expect(notifier.state.error, isNull);
      expect(notifier.state.isLoading, isFalse);
    });

    test('keeps user on verify step and exposes invalid code error', () async {
      notifier.state = notifier.state.copyWith(
        phone: '+250788123456',
        step: WhatsAppOtpStep.verifyCode,
        codeSent: true,
      );
      when(() => service.verifyOtp('+250788123456', '000000')).thenAnswer(
        (_) async => const OtpVerifyResult.invalidCode(
          'Invalid code',
          attemptsRemaining: 2,
        ),
      );

      final value = await notifier.verifyCode('000000');

      expect(value.status, OtpVerifyStatus.invalidCode);
      expect(notifier.state.isVerified, isFalse);
      expect(notifier.state.step, WhatsAppOtpStep.verifyCode);
      expect(notifier.state.error, 'Invalid code');
      expect(notifier.state.isLoading, isFalse);
    });

    test('goBackToPhone keeps the phone number but resets the step', () {
      notifier.state = notifier.state.copyWith(
        phone: '+250788123456',
        step: WhatsAppOtpStep.verifyCode,
        codeSent: true,
      );

      notifier.goBackToPhone();

      expect(notifier.state.phone, '+250788123456');
      expect(notifier.state.step, WhatsAppOtpStep.enterPhone);
      expect(notifier.state.codeSent, isFalse);
      expect(notifier.state.error, isNull);
    });
  });
}
