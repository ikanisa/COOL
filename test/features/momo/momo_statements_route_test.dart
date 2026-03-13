import 'dart:typed_data';

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/core/l10n/locale_provider.dart';
import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/providers/supported_countries_provider.dart';
import 'package:cool_app/core/services/momo_service.dart';
import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/momo/models/momo_statement.dart';
import 'package:cool_app/features/momo/providers/momo_statement_providers.dart';
import 'package:cool_app/features/momo/repositories/momo_statement_repository.dart';
import 'package:cool_app/features/momo/screens/momo_screen.dart';
import 'package:cool_app/features/momo/screens/momo_statements_screen.dart';
import 'package:cool_app/features/momo/services/momo_statement_download_service.dart';
import 'package:cool_app/features/momo/services/momo_statement_export_service.dart';
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
  final List<MomoStatementQuery> queries = <MomoStatementQuery>[];

  @override
  Future<MomoStatementBundle> loadStatementBundle(
    String userId, {
    MomoStatementQuery query = const MomoStatementQuery(),
  }) async {
    queries.add(query);
    return bundle;
  }
}

class FakeStatementExportService extends MomoStatementExportService {
  int walletExportCalls = 0;
  int savingsExportCalls = 0;
  List<MomoWalletEntry> lastWalletEntries = const <MomoWalletEntry>[];
  List<SavingsStatementEntry> lastSavingsEntries =
      const <SavingsStatementEntry>[];
  StatementExportMetadata? lastMetadata;
  StatementExportFormat? lastFormat;

  @override
  Future<StatementExportFile> buildWalletExport({
    required StatementExportFormat format,
    required List<MomoWalletEntry> entries,
    required StatementExportMetadata metadata,
  }) async {
    walletExportCalls += 1;
    lastFormat = format;
    lastWalletEntries = entries;
    lastMetadata = metadata;
    return StatementExportFile(
      bytes: Uint8List.fromList(const <int>[1, 2, 3]),
      fileName: 'wallet_export.pdf',
      mimeType: 'application/pdf',
    );
  }

  @override
  Future<StatementExportFile> buildSavingsExport({
    required StatementExportFormat format,
    required List<SavingsStatementEntry> entries,
    required StatementExportMetadata metadata,
  }) async {
    savingsExportCalls += 1;
    lastFormat = format;
    lastSavingsEntries = entries;
    lastMetadata = metadata;
    return StatementExportFile(
      bytes: Uint8List.fromList(const <int>[1, 2, 3]),
      fileName: 'savings_export.pdf',
      mimeType: 'application/pdf',
    );
  }
}

class FakeStatementDownloadService extends MomoStatementDownloadService {
  FakeStatementDownloadService();

  StatementExportFile? lastExport;

  @override
  Future<StatementDownloadResult> saveExport(
    StatementExportFile exportFile,
  ) async {
    lastExport = exportFile;
    return StatementDownloadResult(
      fileName: exportFile.fileName,
      savedPath: '/tmp/${exportFile.fileName}',
      usedSaveAs: false,
    );
  }
}

void main() {
  testWidgets('direct Mobile Money entry can return home', (tester) async {
    final repository = FakeMomoStatementRepository(const MomoStatementBundle());
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
      () => countriesRepository.getSupportedCountries(),
    ).thenReturn(CoolCountryCatalog.all);
    when(
      () => countriesRepository.resolveCountry(
        countryCode: any(named: 'countryCode'),
        phone: any(named: 'phone'),
        providerId: any(named: 'providerId'),
      ),
    ).thenAnswer((_) {
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
            momoService: MomoService(client: MockSupabaseClient()),
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
          path: '/home',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Home'))),
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

    await tester.tap(find.byTooltip('Back'));
    await settleTestApp(tester);

    expect(find.text('Home'), findsOneWidget);
  });

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
            groupName: 'Western Builders Pool',
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
      () => countriesRepository.getSupportedCountries(),
    ).thenReturn(CoolCountryCatalog.all);
    when(
      () => countriesRepository.resolveCountry(
        countryCode: any(named: 'countryCode'),
        phone: any(named: 'phone'),
        providerId: any(named: 'providerId'),
      ),
    ).thenAnswer((_) {
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
            momoService: MomoService(client: MockSupabaseClient()),
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

  testWidgets('wallet statements render draft ledger entries', (tester) async {
    final repository = FakeMomoStatementRepository(
      MomoStatementBundle(
        walletEntries: [
          MomoWalletEntry(
            id: 'wallet-draft-1',
            entryType: 'credit',
            ledgerStatus: 'draft',
            amount: 500,
            currency: 'RWF',
            occurredAt: DateTime(2026, 3, 7, 13, 53),
            txCategory: 'cash_in',
            cashflowBucket: 'income',
            label: 'Received 500 RWF from Jean Bosco',
            counterpartyName: 'Jean Bosco AHORUKOMEYE',
            reference: '26547384890',
            description: 'Recovered from SMS inbox on device.',
          ),
        ],
        walletTotalCount: 1,
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
      () => countriesRepository.getSupportedCountries(),
    ).thenReturn(CoolCountryCatalog.all);
    when(
      () => countriesRepository.resolveCountry(
        countryCode: any(named: 'countryCode'),
        phone: any(named: 'phone'),
        providerId: any(named: 'providerId'),
      ),
    ).thenAnswer((_) {
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
            momoService: MomoService(client: MockSupabaseClient()),
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

    expect(find.textContaining('Jean Bosco'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Showing 1 of 1 wallet entries.'), findsOneWidget);
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
        () => countriesRepository.getSupportedCountries(),
      ).thenReturn(CoolCountryCatalog.all);
      when(
        () => countriesRepository.resolveCountry(
          countryCode: any(named: 'countryCode'),
          phone: any(named: 'phone'),
          providerId: any(named: 'providerId'),
        ),
      ).thenAnswer((_) {
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
              momoService: MomoService(client: MockSupabaseClient()),
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

  testWidgets('wallet filters and PDF export use the visible payer view', (
    tester,
  ) async {
    final repository = FakeMomoStatementRepository(
      MomoStatementBundle(
        walletEntries: [
          MomoWalletEntry(
            id: 'wallet-alice',
            entryType: 'credit',
            ledgerStatus: 'posted',
            amount: 25000,
            currency: 'RWF',
            occurredAt: DateTime(2026, 3, 11, 9, 30),
            txCategory: 'cash_in',
            cashflowBucket: 'income',
            label: 'Alice transfer',
            counterpartyName: 'Alice',
            reference: 'MM-123',
          ),
          MomoWalletEntry(
            id: 'wallet-bob',
            entryType: 'debit',
            ledgerStatus: 'posted',
            amount: 9000,
            currency: 'RWF',
            occurredAt: DateTime(2026, 3, 10, 9, 30),
            txCategory: 'cash_out',
            cashflowBucket: 'expense',
            label: 'Bob payout',
            counterpartyName: 'Bob',
            reference: 'MM-456',
          ),
        ],
        walletTotalCount: 2,
      ),
    );
    final exportService = FakeStatementExportService();
    final downloadService = FakeStatementDownloadService();
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
      () => countriesRepository.getSupportedCountries(),
    ).thenReturn(CoolCountryCatalog.all);
    when(
      () => countriesRepository.resolveCountry(
        countryCode: any(named: 'countryCode'),
        phone: any(named: 'phone'),
        providerId: any(named: 'providerId'),
      ),
    ).thenAnswer((_) {
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
            momoService: MomoService(client: MockSupabaseClient()),
            session: session,
            user: user,
          ),
        ),
        supportedCountriesRepositoryProvider.overrideWithValue(
          countriesRepository,
        ),
        momoStatementRepositoryProvider.overrideWithValue(repository),
        momoStatementExportServiceProvider.overrideWithValue(exportService),
        momoStatementDownloadServiceProvider.overrideWithValue(downloadService),
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

    final payerField = find.byKey(
      const ValueKey<String>('statement-party-filter'),
    );
    await tester.ensureVisible(payerField);
    await tester.tap(payerField, warnIfMissed: false);
    await settleTestApp(tester);
    await tester.tap(find.text('Alice').last);
    await settleTestApp(tester);

    expect(find.textContaining('Alice'), findsWidgets);
    expect(find.textContaining('Bob payout'), findsNothing);

    await tester.tap(find.text('PDF'));
    await settleTestApp(tester);

    expect(exportService.walletExportCalls, 1);
    expect(downloadService.lastExport, isNotNull);
    expect(exportService.lastFormat, StatementExportFormat.pdf);
    expect(exportService.lastWalletEntries.map((entry) => entry.id), <String>[
      'wallet-alice',
    ]);
    expect(exportService.lastMetadata?.filterLabel, contains('Payer: Alice'));
  });

  testWidgets('day filter updates the statement query window', (tester) async {
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
        walletTotalCount: 1,
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
      () => countriesRepository.getSupportedCountries(),
    ).thenReturn(CoolCountryCatalog.all);
    when(
      () => countriesRepository.resolveCountry(
        countryCode: any(named: 'countryCode'),
        phone: any(named: 'phone'),
        providerId: any(named: 'providerId'),
      ),
    ).thenAnswer((_) {
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
            momoService: MomoService(client: MockSupabaseClient()),
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

    final initialQuery = repository.queries.last;
    expect(initialQuery.startDate, isNotNull);
    expect(initialQuery.endDate, isNotNull);

    final dayChip = find.byKey(const ValueKey<String>('statement-period-day'));
    await tester.ensureVisible(dayChip);
    await tester.tap(dayChip, warnIfMissed: false);
    await settleTestApp(tester);

    final dayQuery = repository.queries.last;
    final today = DateUtils.dateOnly(DateTime.now());
    expect(dayQuery.startDate, today);
    expect(dayQuery.endDate, today);

    final allTimeChip = find.byKey(
      const ValueKey<String>('statement-period-all'),
    );
    await tester.ensureVisible(allTimeChip);
    await tester.tap(allTimeChip, warnIfMissed: false);
    await settleTestApp(tester);

    final allQuery = repository.queries.last;
    expect(allQuery.startDate, isNull);
    expect(allQuery.endDate, isNull);
  });
}
