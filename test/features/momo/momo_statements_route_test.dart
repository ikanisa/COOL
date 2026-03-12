import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/core/l10n/locale_provider.dart';
import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/providers/supported_countries_provider.dart';
import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/momo/models/momo_statement.dart';
import 'package:cool_app/features/momo/providers/momo_statement_providers.dart';
import 'package:cool_app/features/momo/repositories/momo_statement_repository.dart';
import 'package:cool_app/features/momo/screens/momo_screen.dart';
import 'package:cool_app/features/momo/screens/momo_statements_screen.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/test_bootstrap.dart';
import '../../integration_smoke/test_harness.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakeMomoStatementRepository extends MomoStatementRepository {
  FakeMomoStatementRepository(this.bundle)
    : super(client: MockSupabaseClient());

  final MomoStatementBundle bundle;

  @override
  Future<MomoStatementBundle> loadStatementBundle(
    String userId, {
    MomoStatementQuery query = const MomoStatementQuery(),
  }) async {
    return bundle;
  }
}

void main() {
  testWidgets('Open on Mobile Money pushes statements screen', (tester) async {
    final repository = FakeMomoStatementRepository(
      MomoStatementBundle(
        walletEntries: [
          MomoWalletEntry(
            id: 'wallet-1',
            entryType: 'credit',
            ledgerStatus: 'posted',
            amount: 25000,
            currency: 'RWF',
            occurredAt: DateTime(2026, 3, 11, 9, 30),
            txCategory: 'cash_in',
            cashflowBucket: 'income',
            label: 'Cash in',
            counterpartyName: 'MTN Rwanda',
            reference: 'MM-123',
          ),
        ],
        savingsEntries: [
          SavingsStatementEntry(
            id: 'savings-1',
            groupId: 'group-1',
            groupName: 'Diaspora Builders Pool',
            amount: 15000,
            status: 'confirmed',
            createdAt: DateTime(2026, 3, 10),
            reference: 'GCT-123',
          ),
        ],
        walletTotalCount: 1,
        savingsTotalCount: 1,
      ),
    );
    final authRepository = MockAuthRepository();
    final countriesRepository = MockSupportedCountriesRepository();
    final session = fakeSession();
    final user = fakeUser(momoNumber: '788123456');

    when(() => authRepository.currentSession).thenReturn(session);
    when(() => authRepository.currentUserId).thenReturn(session.user.id);
    when(
      () => authRepository.getCurrentProfile(),
    ).thenAnswer((_) async => user);
    when(() => authRepository.getProfile(any())).thenAnswer((_) async => user);

    when(
      () => countriesRepository.getSupportedCountries(
        forceRefresh: any(named: 'forceRefresh'),
      ),
    ).thenAnswer((_) async => CoolCountryCatalog.all);
    when(
      () => countriesRepository.resolveCountry(
        countryCode: any(named: 'countryCode'),
        phone: any(named: 'phone'),
        providerId: any(named: 'providerId'),
      ),
    ).thenAnswer((_) async {
      return CoolCountryCatalog.resolve(country: 'RW');
    });

    final container = createTestContainer(
      overrides: [
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
        momoStatementRepositoryProvider.overrideWithValue(repository),
      ],
    );

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const MomoScreen()),
        GoRoute(
          path: '/momo/statements',
          builder: (context, state) => const MomoStatementsScreen(),
        ),
      ],
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

    await tester.tap(find.text('Statements'));
    await settleTestApp(tester);

    expect(find.byType(MomoStatementsScreen), findsOneWidget);
  });

  testWidgets(
    'tapping the statements card body also pushes statements screen',
    (tester) async {
      final repository = FakeMomoStatementRepository(
        const MomoStatementBundle(),
      );
      final authRepository = MockAuthRepository();
      final countriesRepository = MockSupportedCountriesRepository();
      final session = fakeSession();
      final user = fakeUser(momoNumber: '788123456');

      when(() => authRepository.currentSession).thenReturn(session);
      when(() => authRepository.currentUserId).thenReturn(session.user.id);
      when(
        () => authRepository.getCurrentProfile(),
      ).thenAnswer((_) async => user);
      when(
        () => authRepository.getProfile(any()),
      ).thenAnswer((_) async => user);

      when(
        () => countriesRepository.getSupportedCountries(
          forceRefresh: any(named: 'forceRefresh'),
        ),
      ).thenAnswer((_) async => CoolCountryCatalog.all);
      when(
        () => countriesRepository.resolveCountry(
          countryCode: any(named: 'countryCode'),
          phone: any(named: 'phone'),
          providerId: any(named: 'providerId'),
        ),
      ).thenAnswer((_) async {
        return CoolCountryCatalog.resolve(country: 'RW');
      });

      final container = createTestContainer(
        overrides: [
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
          momoStatementRepositoryProvider.overrideWithValue(repository),
        ],
      );

      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const MomoScreen()),
          GoRoute(
            path: '/momo/statements',
            builder: (context, state) => const MomoStatementsScreen(),
          ),
        ],
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

      await tester.tap(find.text('Statements'));
      await settleTestApp(tester);

      expect(find.byType(MomoStatementsScreen), findsOneWidget);
    },
  );
}
