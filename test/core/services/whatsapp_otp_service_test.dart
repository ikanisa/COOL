import 'package:cool_app/core/services/whatsapp_otp_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

void main() {
  late MockSupabaseClient client;
  late MockFunctionsClient functionsClient;
  late WhatsAppOtpService service;

  setUp(() {
    client = MockSupabaseClient();
    functionsClient = MockFunctionsClient();
    service = WhatsAppOtpService(client: client);

    when(() => client.functions).thenReturn(functionsClient);
  });

  group('WhatsAppOtpService.sendOtp', () {
    test(
      'surfaces structured rate limit details from function exceptions',
      () async {
        when(
          () => functionsClient.invoke(any(), body: any(named: 'body')),
        ).thenThrow(
          const FunctionException(
            status: 429,
            details: <String, dynamic>{
              'message': 'Too many OTP requests',
              'details': <String, dynamic>{'retryAfterSeconds': 60},
            },
            reasonPhrase: 'Too Many Requests',
          ),
        );

        final result = await service.sendOtp('+250781234567');

        expect(result.status, OtpSendStatus.rateLimited);
        expect(result.message, 'Too many OTP requests');
        expect(result.retryAfterSeconds, 60);
      },
    );
  });

  group('WhatsAppOtpService.verifyOtp', () {
    test('reads session tokens from nested session payloads', () async {
      when(
        () => functionsClient.invoke(any(), body: any(named: 'body')),
      ).thenAnswer(
        (_) async => FunctionResponse(
          status: 200,
          data: <String, dynamic>{
            'success': true,
            'session': <String, dynamic>{
              'access_token': 'access-token',
              'refresh_token': 'refresh-token',
              'user': <String, dynamic>{'id': 'user-123'},
            },
            'isNewUser': false,
          },
        ),
      );

      final result = await service.verifyOtp('+250781234567', '123456');

      expect(result.status, OtpVerifyStatus.verified);
      expect(result.accessToken, 'access-token');
      expect(result.refreshToken, 'refresh-token');
      expect(result.userId, 'user-123');
      expect(result.isNewUser, isFalse);
    });

    test(
      'surfaces attempts remaining from structured verification errors',
      () async {
        when(
          () => functionsClient.invoke(any(), body: any(named: 'body')),
        ).thenThrow(
          const FunctionException(
            status: 400,
            details: <String, dynamic>{
              'message': 'Invalid OTP code',
              'details': <String, dynamic>{'attemptsRemaining': 2},
            },
            reasonPhrase: 'Bad Request',
          ),
        );

        final result = await service.verifyOtp('+250781234567', '000000');

        expect(result.status, OtpVerifyStatus.invalidCode);
        expect(result.message, 'Invalid OTP code');
        expect(result.attemptsRemaining, 2);
      },
    );

    test('rejects success payloads without session tokens', () async {
      when(
        () => functionsClient.invoke(any(), body: any(named: 'body')),
      ).thenAnswer(
        (_) async => FunctionResponse(
          status: 200,
          data: <String, dynamic>{
            'success': true,
            'session': <String, dynamic>{
              'user': <String, dynamic>{'id': 'user-123'},
            },
          },
        ),
      );

      final result = await service.verifyOtp('+250781234567', '123456');

      expect(result.status, OtpVerifyStatus.error);
      expect(
        result.message,
        'Verification succeeded but session setup data was incomplete.',
      );
    });
  });
}
