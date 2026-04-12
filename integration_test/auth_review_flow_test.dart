import 'dart:io';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/core/services/crashlytics_service.dart';
import 'package:cool_app/core/services/momo_service.dart';
import 'package:cool_app/core/services/performance_service.dart';
import 'package:cool_app/core/services/whatsapp_otp_service.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart'
    as app_auth;
import 'package:cool_app/features/auth/providers/whatsapp_otp_provider.dart';
import 'package:cool_app/features/auth/repositories/auth_repository.dart';
import 'package:cool_app/features/auth/screens/whatsapp_otp_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test/integration_smoke/test_harness.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _FakeWhatsAppOtpService extends WhatsAppOtpService {
  _FakeWhatsAppOtpService({
    required this.sendResult,
    required this.verifyResult,
  }) : super(client: _MockSupabaseClient());

  final OtpSendResult sendResult;
  final OtpVerifyResult verifyResult;
  final List<String> sendCalls = <String>[];
  final List<Map<String, String>> verifyCalls = <Map<String, String>>[];

  @override
  Future<OtpSendResult> sendOtp(String e164Phone) async {
    sendCalls.add(e164Phone);
    return sendResult;
  }

  @override
  Future<OtpVerifyResult> verifyOtp(String e164Phone, String code) async {
    verifyCalls.add(<String, String>{'phone': e164Phone, 'code': code});
    return verifyResult;
  }
}

class _FakeAuthNotifier extends app_auth.AuthNotifier {
  _FakeAuthNotifier()
    : super(
        repository: _MockAuthRepository(),
        crashlytics: CrashlyticsService(),
        performance: PerformanceService(),
        momoService: MomoService(
          client: _MockSupabaseClient(),
          openBox: _noOpOpenBox,
        ),
        initialState: const app_auth.AuthState(
          profileRestoreState: app_auth.AuthProfileRestoreState.available,
        ),
        autoBootstrapOnInit: false,
      );
  final List<Map<String, String>> signInCalls = <Map<String, String>>[];

  @override
  Future<void> restoreCurrentUser() async {}

  @override
  Future<bool> signInWithOtpSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    signInCalls.add(<String, String>{
      'accessToken': accessToken,
      'refreshToken': refreshToken,
    });

    state = app_auth.AuthState(
      user: const UserProfile(
        id: 'review-user',
        phone: '+250788767816',
        fullName: 'Review User',
        momoNumber: '0788767816',
        momoProvider: 'mtn_momo_rw',
        country: 'RW',
      ),
      session: fakeSession(userId: 'review-user', phone: '+250788767816'),
      profileRestoreState: app_auth.AuthProfileRestoreState.available,
    );
    return true;
  }
}

Future<Box<T>> _noOpOpenBox<T>(String name) =>
    throw UnimplementedError('Hive disabled in integration tests');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await CoolCountryCatalog.initialize(
      await File('assets/countries.json').readAsString(),
    );
  });

  testWidgets(
    'review OTP flow sends the configured phone and opens a session',
    (tester) async {
      final otpService = _FakeWhatsAppOtpService(
        sendResult: const OtpSendResult.sent(),
        verifyResult: const OtpVerifyResult.verified(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
          userId: 'review-user',
          isNewUser: false,
        ),
      );
      final authNotifier = _FakeAuthNotifier();

      await pumpScopedApp(
        tester,
        child: const WhatsAppOtpScreen(initialPhone: '0788767816'),
        overrides: <Override>[
          whatsAppOtpServiceProvider.overrideWithValue(otpService),
          app_auth.authProvider.overrideWith((ref) => authNotifier),
        ],
      );

      expect(find.text('Enter WhatsApp\nNumber'), findsOneWidget);

      await tester.tap(find.text('SEND CODE'));
      await settleTestApp(tester, frames: 12);

      expect(otpService.sendCalls, <String>['+250788767816']);
      expect(find.text('Verify OTP'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '123456');
      await settleTestApp(tester, frames: 14);

      expect(otpService.verifyCalls, <Map<String, String>>[
        <String, String>{'phone': '+250788767816', 'code': '123456'},
      ]);
      expect(authNotifier.signInCalls, hasLength(1));
      expect(authNotifier.signInCalls.single['accessToken'], 'access-token');
      expect(find.text('Verify OTP'), findsNothing);
    },
  );

  testWidgets('review OTP flow preserves retry feedback for invalid codes', (
    tester,
  ) async {
    final otpService = _FakeWhatsAppOtpService(
      sendResult: const OtpSendResult.sent(),
      verifyResult: const OtpVerifyResult.invalidCode(
        'Invalid OTP code',
        attemptsRemaining: 2,
      ),
    );
    final authNotifier = _FakeAuthNotifier();

    await pumpScopedApp(
      tester,
      child: const WhatsAppOtpScreen(initialPhone: '0788767816'),
      overrides: <Override>[
        whatsAppOtpServiceProvider.overrideWithValue(otpService),
        app_auth.authProvider.overrideWith((ref) => authNotifier),
      ],
    );

    await tester.tap(find.text('SEND CODE'));
    await settleTestApp(tester, frames: 12);

    await tester.enterText(find.byType(TextField).first, '654321');
    await settleTestApp(tester, frames: 14);

    expect(find.text('Invalid OTP code'), findsOneWidget);
    expect(find.text('Attempts remaining: 2'), findsOneWidget);
    expect(authNotifier.signInCalls, isEmpty);
  });
}
