import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/core/l10n/locale_provider.dart';
import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/providers/supabase_client_provider.dart';
import 'package:cool_app/core/providers/supported_countries_provider.dart';
import 'package:cool_app/core/repositories/supported_countries_repository.dart';
import 'package:cool_app/core/router/app_router.dart';
import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/auth/repositories/auth_repository.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FlutterAuthClientOptions, Session, SupabaseClient;

import '../helpers/test_bootstrap.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSupportedCountriesRepository extends Mock
    implements SupportedCountriesRepository {}

SupabaseClient _buildTestSupabaseClient() {
  return SupabaseClient(
    'http://127.0.0.1:54321',
    'test-anon-key',
    authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
  );
}

class RoutedTestApp {
  const RoutedTestApp({
    required this.container,
    required this.router,
    required this.authRepository,
    required this.countriesRepository,
  });

  final ProviderContainer container;
  final GoRouter router;
  final MockAuthRepository authRepository;
  final MockSupportedCountriesRepository countriesRepository;
}

class ScopedTestApp {
  const ScopedTestApp({
    required this.container,
    required this.authRepository,
    required this.countriesRepository,
  });

  final ProviderContainer container;
  final MockAuthRepository authRepository;
  final MockSupportedCountriesRepository countriesRepository;
}

class TestAuthNotifier extends AuthNotifier {
  TestAuthNotifier({
    required super.repository,
    required super.crashlytics,
    required super.performance,
    required Session? session,
    required UserProfile? user,
  }) {
    state = AuthState(
      user: user,
      session: session,
      profileRestoreState: session == null
          ? AuthProfileRestoreState.available
          : user == null
          ? AuthProfileRestoreState.missing
          : AuthProfileRestoreState.available,
    );
  }

  @override
  Future<void> restoreCurrentUser() async {}
}

Session fakeSession({
  String userId = 'user-1',
  String phone = '+250788123456',
  String country = 'RW',
}) {
  return Session.fromJson(<String, dynamic>{
    'access_token': 'token-$userId',
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh-$userId',
    'user': <String, dynamic>{
      'id': userId,
      'phone': phone,
      'user_metadata': <String, dynamic>{'phone': phone, 'country': country},
      'app_metadata': const <String, dynamic>{},
      'aud': 'authenticated',
      'created_at': DateTime(2026).toIso8601String(),
    },
  })!;
}

UserProfile fakeUser({
  String id = 'user-1',
  String phone = '+250788123456',
  String fullName = 'Alex Fan',
  String momoNumber = '0788123456',
  String? momoCode = '123456',
  String momoProvider = 'mtn_rwanda',
  String country = 'RW',
  String languageCode = 'en',
  bool isDriver = false,
  bool isAdmin = false,
  String? vehicleType,
}) {
  return UserProfile(
    id: id,
    phone: phone,
    fullName: fullName,
    momoNumber: momoNumber,
    momoCode: momoCode,
    momoProvider: momoProvider,
    country: country,
    languageCode: languageCode,
    isDriver: isDriver,
    isAdmin: isAdmin,
    vehicleType: vehicleType,
  );
}

Future<void> settleTestApp(WidgetTester tester, {int frames = 6}) async {
  for (var index = 0; index < frames * 10; index++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (!tester.binding.hasScheduledFrame) {
      break;
    }
  }
}

void _configureTestViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 2560);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

({
  ProviderContainer container,
  MockAuthRepository authRepository,
  MockSupportedCountriesRepository countriesRepository,
})
_buildTestContainer({
  Session? session,
  UserProfile? user,
  List<CoolCountry>? countries,
  List<Override> overrides = const <Override>[],
}) {
  final authRepository = MockAuthRepository();
  final countriesRepository = MockSupportedCountriesRepository();
  final resolvedCountries = countries ?? CoolCountryCatalog.all;
  final supabaseClient = _buildTestSupabaseClient();

  when(() => authRepository.currentSession).thenReturn(session);
  when(() => authRepository.currentUserId).thenReturn(session?.user.id);
  when(() => authRepository.getCurrentProfile()).thenAnswer((_) async => user);
  when(() => authRepository.getProfile(any())).thenAnswer((_) async => user);
  when(() => authRepository.sendOtp(any(), any())).thenAnswer((_) async {});
  when(
    () => authRepository.verifyOtp(any(), any()),
  ).thenAnswer((_) async => session ?? fakeSession());
  when(() => authRepository.signOut()).thenAnswer((_) async {});

  when(
    () => countriesRepository.getSupportedCountries(
      forceRefresh: any(named: 'forceRefresh'),
    ),
  ).thenAnswer((_) async => resolvedCountries);
  when(
    () => countriesRepository.resolveCountry(
      countryCode: any(named: 'countryCode'),
      phone: any(named: 'phone'),
      providerId: any(named: 'providerId'),
    ),
  ).thenAnswer((invocation) async {
    final countryCode = invocation.namedArguments[#countryCode] as String?;
    final phone = invocation.namedArguments[#phone] as String?;
    final providerId = invocation.namedArguments[#providerId] as String?;
    return CoolCountryCatalog.resolve(
      country: countryCode,
      phone: phone,
      providerId: providerId,
      source: resolvedCountries,
    );
  });

  final container = createTestContainer(
    overrides: <Override>[
      supabaseClientProvider.overrideWithValue(supabaseClient),
      authRepositoryProvider.overrideWithValue(authRepository),
      authProvider.overrideWith(
        (ref) => TestAuthNotifier(
          repository: ref.watch(authRepositoryProvider),
          crashlytics: ref.read(crashlyticsServiceProvider),
          performance: ref.read(performanceServiceProvider),
          session: session,
          user: user,
        ),
      ),
      supportedCountriesRepositoryProvider.overrideWithValue(
        countriesRepository,
      ),
      ...overrides,
    ],
  );

  return (
    container: container,
    authRepository: authRepository,
    countriesRepository: countriesRepository,
  );
}

Future<ScopedTestApp> pumpScopedApp(
  WidgetTester tester, {
  required Widget child,
  Session? session,
  UserProfile? user,
  List<CoolCountry>? countries,
  List<Override> overrides = const <Override>[],
}) async {
  _configureTestViewport(tester);

  final testContext = _buildTestContainer(
    session: session,
    user: user,
    countries: countries,
    overrides: overrides,
  );
  final container = testContext.container;
  final router = GoRouter(
    routes: <RouteBase>[GoRoute(path: '/', builder: (context, state) => child)],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) {
          final locale = ref.watch(localeProvider);
          return MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            routerConfig: router,
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
          );
        },
      ),
    ),
  );

  await settleTestApp(tester);

  return ScopedTestApp(
    container: container,
    authRepository: testContext.authRepository,
    countriesRepository: testContext.countriesRepository,
  );
}

Future<RoutedTestApp> pumpRouterApp(
  WidgetTester tester, {
  String initialLocation = AppRoutes.splash,
  Session? session,
  UserProfile? user,
  List<CoolCountry>? countries,
  List<Override> overrides = const <Override>[],
}) async {
  _configureTestViewport(tester);

  final testContext = _buildTestContainer(
    session: session,
    user: user,
    countries: countries,
    overrides: overrides,
  );
  final container = testContext.container;

  final router = container.read(appRouterProvider);

  if (initialLocation != AppRoutes.splash) {
    router.go(initialLocation);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) {
          final locale = ref.watch(localeProvider);
          return MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            routerConfig: router,
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
          );
        },
      ),
    ),
  );

  await settleTestApp(tester);

  return RoutedTestApp(
    container: container,
    router: router,
    authRepository: testContext.authRepository,
    countriesRepository: testContext.countriesRepository,
  );
}
