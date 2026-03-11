import 'dart:io';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/core/providers/supported_countries_provider.dart';
import 'package:cool_app/core/repositories/supported_countries_repository.dart';
import 'package:cool_app/core/router/app_router.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/auth/repositories/auth_repository.dart';
import 'package:cool_app/features/auth/screens/otp_screen.dart';
import 'package:cool_app/features/auth/screens/otp_verify_screen.dart';
import 'package:cool_app/features/auth/screens/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakeSupportedCountriesRepository extends SupportedCountriesRepository {
  FakeSupportedCountriesRepository() : super(client: MockSupabaseClient());

  @override
  Future<List<CoolCountry>> getSupportedCountries({
    bool forceRefresh = false,
  }) async {
    return CoolCountryCatalog.all;
  }

  @override
  Future<CoolCountry> resolveCountry({
    String? countryCode,
    String? phone,
    String? providerId,
  }) async {
    return CoolCountryCatalog.resolve(
      country: countryCode,
      phone: phone,
      providerId: providerId,
    );
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

void main() {
  late Directory hiveDir;

  setUpAll(() {
    hiveDir = Directory.systemTemp.createTempSync('hive_auth_test_');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDir.existsSync()) {
      hiveDir.deleteSync(recursive: true);
    }
  });

  Future<({GoRouter router, MockAuthRepository repository})> pumpRouterApp(
    WidgetTester tester, {
    String initialLocation = AppRoutes.splash,
    Session? session,
    Future<UserProfile?> Function()? getCurrentProfile,
  }) async {
    final repository = MockAuthRepository();
    when(() => repository.currentSession).thenReturn(session);
    when(() => repository.currentUserId).thenReturn(session?.user.id);
    when(
      () => repository.getCurrentProfile(),
    ).thenAnswer((_) => getCurrentProfile?.call() ?? Future.value(null));

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        supportedCountriesRepositoryProvider.overrideWithValue(
          FakeSupportedCountriesRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);
    addTearDown(router.dispose);
    router.go(initialLocation);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    return (router: router, repository: repository);
  }

  group('auth route builders', () {
    testWidgets('otp and follow-up auth routes preserve redirect params', (
      tester,
    ) async {
      final result = await pumpRouterApp(
        tester,
        initialLocation: AppRoutes.otpLocation(redirect: AppRoutes.basket),
      );
      final router = result.router;
      await tester.pumpAndSettle();

      expect(find.byType(OtpScreen), findsOneWidget);
      expect(
        tester.widget<OtpScreen>(find.byType(OtpScreen)).redirectPath,
        AppRoutes.basket,
      );

      router.go(
        AppRoutes.otpVerifyLocation(
          phone: '+250781234567',
          redirect: AppRoutes.basket,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OtpVerifyScreen), findsOneWidget);
      expect(
        tester
            .widget<OtpVerifyScreen>(find.byType(OtpVerifyScreen))
            .redirectPath,
        AppRoutes.basket,
      );

      router.go(
        AppRoutes.registerLocation(
          phone: '+250781234567',
          redirect: AppRoutes.basket,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RegisterScreen), findsOneWidget);
      final registerScreen = tester.widget<RegisterScreen>(
        find.byType(RegisterScreen),
      );
      expect(registerScreen.phone, '+250781234567');
      expect(registerScreen.redirectPath, AppRoutes.basket);
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
      await tester.pumpAndSettle();

      expect(find.text('We could not restore your profile.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();

      verify(() => repository.getCurrentProfile()).called(2);
    });
  });
}
