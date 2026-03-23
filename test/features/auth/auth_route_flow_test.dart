import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/providers/supported_countries_provider.dart';
import 'package:cool_app/core/repositories/supported_countries_repository.dart';
import 'package:cool_app/core/router/app_router.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/auth/repositories/auth_repository.dart';
import 'package:cool_app/features/momo/providers/momo_service_provider.dart';
import 'package:cool_app/features/auth/screens/otp_screen.dart';
import 'package:cool_app/features/auth/screens/otp_verify_screen.dart';
import 'package:cool_app/shared/widgets/cool_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../helpers/test_bootstrap.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class TestRouteAuthNotifier extends AuthNotifier {
  TestRouteAuthNotifier({
    required super.repository,
    required super.crashlytics,
    required super.performance,
    required super.momoService,
    required Session? session,
  }) : _repository = repository {
    state = AuthState(
      session: session,
      profileRestoreState: session == null
          ? AuthProfileRestoreState.available
          : AuthProfileRestoreState.pending,
    );
  }

  final AuthRepository _repository;

  @override
  Future<void> restoreCurrentUser() async {
    final session = _repository.currentSession;
    if (session == null) {
      state = state.copyWith(
        session: null,
        user: null,
        profileRestoreState: AuthProfileRestoreState.available,
        error: null,
      );
      return;
    }

    state = state.copyWith(
      session: session,
      profileRestoreState: AuthProfileRestoreState.pending,
      error: null,
    );

    try {
      final user = await _repository.getCurrentProfile();
      state = state.copyWith(
        user: user,
        profileRestoreState: user == null
            ? AuthProfileRestoreState.missing
            : AuthProfileRestoreState.available,
        error: null,
      );
    } catch (error) {
      state = state.copyWith(
        profileRestoreState: AuthProfileRestoreState.failed,
        error: error.toString(),
      );
    }
  }
}

class FakeSupportedCountriesRepository extends SupportedCountriesRepository {
  FakeSupportedCountriesRepository() : super();

  @override
  List<CoolCountry> getSupportedCountries() {
    return CoolCountryCatalog.all;
  }

  @override
  CoolCountry resolveCountry({
    String? countryCode,
    String? phone,
    String? providerId,
  }) {
    return CoolCountryCatalog.resolve(
      country: countryCode,
      phone: phone,
      providerId: providerId,
    );
  }
}

class BlockingResolveSupportedCountriesRepository
    extends SupportedCountriesRepository {
  BlockingResolveSupportedCountriesRepository() : super();

  @override
  List<CoolCountry> getSupportedCountries() {
    return CoolCountryCatalog.all;
  }

  @override
  CoolCountry resolveCountry({
    String? countryCode,
    String? phone,
    String? providerId,
  }) {
    throw StateError('resolveCountry should not be called in the OTP flow.');
  }
}

Session _fakeSession() {
  return Session.fromJson({
    'access_token': 'header.payload.signature',
    'expires_in': 3600,
    'refresh_token': 'refresh-token',
    'token_type': 'bearer',
    'user': {
      'id': 'user-123',
      'app_metadata': {'provider': 'phone'},
      'user_metadata': {'phone': '+250781234567'},
      'aud': 'authenticated',
      'phone': '+250781234567',
      'created_at': '2026-03-11T00:00:00.000Z',
    },
  })!;
}

Future<void> _settleRouter(WidgetTester tester, {int frames = 12}) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (!tester.binding.hasScheduledFrame) {
      break;
    }
  }
}

void main() {
  Future<({GoRouter router, MockAuthRepository repository})> pumpRouterApp(
    WidgetTester tester, {
    String initialLocation = AppRoutes.splash,
    Session? session,
    Future<UserProfile?> Function()? getCurrentProfile,
    SupportedCountriesRepository? supportedCountriesRepository,
  }) async {
    final repository = MockAuthRepository();
    when(() => repository.currentSession).thenReturn(session);
    when(() => repository.currentUserId).thenReturn(session?.user.id);
    when(
      () => repository.getCurrentProfile(),
    ).thenAnswer((_) => getCurrentProfile?.call() ?? Future.value(null));

    final container = createTestContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        authProvider.overrideWith(
          (ref) => TestRouteAuthNotifier(
            repository: ref.watch(authRepositoryProvider),
            crashlytics: ref.read(crashlyticsServiceProvider),
            performance: ref.read(performanceServiceProvider),
            momoService: ref.read(momoServiceProvider),
            session: session,
          ),
        ),
        supportedCountriesRepositoryProvider.overrideWithValue(
          supportedCountriesRepository ?? FakeSupportedCountriesRepository(),
        ),
      ],
    );

    final router = container.read(appRouterProvider);
    router.go(initialLocation);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
        ),
      ),
    );
    await tester.pump();

    return (router: router, repository: repository);
  }

  group('auth route builders', () {
    testWidgets('onboarding primary CTA opens the OTP route', (tester) async {
      await pumpRouterApp(tester, initialLocation: AppRoutes.onboarding);
      await _settleRouter(tester);

      expect(find.text('Welcome to COOL'), findsOneWidget);
      expect(find.text('Pay, save, and move.'), findsOneWidget);

      await tester.tap(find.text('Get Started'));
      await tester.pump();
      await _settleRouter(tester);

      expect(find.byType(OtpScreen), findsOneWidget);
    });

    testWidgets('otp routes preserve redirect params while signed out', (
      tester,
    ) async {
      final result = await pumpRouterApp(
        tester,
        initialLocation: AppRoutes.otpLocation(redirect: AppRoutes.momo),
      );
      final router = result.router;
      await _settleRouter(tester);

      expect(find.byType(OtpScreen), findsOneWidget);
      expect(
        tester.widget<OtpScreen>(find.byType(OtpScreen)).redirectPath,
        AppRoutes.momo,
      );

      router.go(
        AppRoutes.otpVerifyLocation(
          phone: '+250781234567',
          redirect: AppRoutes.momo,
        ),
      );
      await _settleRouter(tester);

      expect(find.byType(OtpVerifyScreen), findsOneWidget);
      expect(
        tester
            .widget<OtpVerifyScreen>(find.byType(OtpVerifyScreen))
            .redirectPath,
        AppRoutes.momo,
      );
    });

    testWidgets('otp submit does not block on repository country resolution', (
      tester,
    ) async {
      final result = await pumpRouterApp(
        tester,
        initialLocation: AppRoutes.otp,
        supportedCountriesRepository:
            BlockingResolveSupportedCountriesRepository(),
      );
      final repository = result.repository;
      when(
        () => repository.sendOtp('+250700000001', 'en'),
      ).thenAnswer((_) async {});

      await _settleRouter(tester);

      expect(find.byType(OtpScreen), findsOneWidget);
      final otpScreen = find.byType(OtpScreen);
      final phoneField = find.descendant(
        of: otpScreen,
        matching: find.byType(TextField),
      );
      final continueButton = find.descendant(
        of: otpScreen,
        matching: find.byType(CoolButton),
      );

      await tester.enterText(phoneField, '700000001');
      await tester.pump();
      await tester.tap(continueButton);
      await tester.pump();
      await _settleRouter(tester);

      verify(() => repository.sendOtp('+250700000001', 'en')).called(1);
      expect(find.byType(OtpVerifyScreen), findsOneWidget);
      expect(
        tester
            .widget<OtpVerifyScreen>(find.byType(OtpVerifyScreen))
            .phoneNumber,
        '+250700000001',
      );
    });

    testWidgets('failed profile restoration shows a retry state on splash', (
      tester,
    ) async {
      final session = _fakeSession();
      final result = await pumpRouterApp(
        tester,
        session: session,
        getCurrentProfile: () async {
          throw StateError('temporary profile fetch failure');
        },
      );
      final repository = result.repository;

      await tester.pump(const Duration(milliseconds: 900));
      await _settleRouter(tester);

      expect(find.text('We could not restore'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 900));
      await _settleRouter(tester);

      verify(() => repository.getCurrentProfile()).called(2);
    });
  });
}
