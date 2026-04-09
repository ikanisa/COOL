import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart' show Box;

import 'package:cool_app/core/config/country_catalog.dart';
import 'package:cool_app/core/l10n/locale_provider.dart';
import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/providers/supported_countries_provider.dart';
import 'package:cool_app/core/services/momo_service.dart';
import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/momo/models/momo_statement.dart';
import 'package:cool_app/features/momo/models/momo_sms_sync_status.dart';
import 'package:cool_app/features/momo/providers/momo_statement_providers.dart';
import 'package:cool_app/features/momo/providers/momo_sms_sync_providers.dart';
import 'package:cool_app/features/momo/repositories/momo_statement_repository.dart';
import 'package:cool_app/features/momo/screens/momo_statements_screen.dart';
import 'package:cool_app/features/momo/services/momo_statement_download_service.dart';
import 'package:cool_app/features/momo/services/momo_statement_export_service.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/test_bootstrap.dart';
import '../../integration_smoke/test_harness.dart';

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

Future<Box<T>> noOpOpenBox<T>(String name) =>
    throw UnimplementedError('Hive disabled in tests');

ProviderContainer createMomoStatementsTestContainer({
  required MomoStatementRepository repository,
  MomoStatementExportService? exportService,
  MomoStatementDownloadService? downloadService,
}) {
  final authRepository = MockAuthRepository();
  final countriesRepository = MockSupportedCountriesRepository();
  final session = fakeSession();
  final user = fakeUser(momoNumber: '788123456');

  when(() => authRepository.currentSession).thenReturn(session);
  when(() => authRepository.currentUserId).thenReturn(session.user.id);
  when(() => authRepository.getCurrentProfile()).thenAnswer((_) async => user);
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

  final overrides = <Override>[
    authRepositoryProvider.overrideWithValue(authRepository),
    authProvider.overrideWith(
      (ref) => TestAuthNotifier(
        repository: ref.watch(authRepositoryProvider),
        crashlytics: ref.read(crashlyticsServiceProvider),
        performance: ref.read(performanceServiceProvider),
        momoService: MomoService(
          client: MockSupabaseClient(),
          openBox: noOpOpenBox,
        ),
        session: session,
        user: user,
      ),
    ),
    supportedCountriesRepositoryProvider.overrideWithValue(countriesRepository),
    momoStatementRepositoryProvider.overrideWithValue(repository),
    momoSmsSyncStatusProvider.overrideWith(
      (ref) async => const MomoSmsSyncStatus(),
    ),
  ];

  if (exportService != null) {
    overrides.add(
      momoStatementExportServiceProvider.overrideWithValue(exportService),
    );
  }
  if (downloadService != null) {
    overrides.add(
      momoStatementDownloadServiceProvider.overrideWithValue(downloadService),
    );
  }

  return createTestContainer(overrides: overrides);
}

Future<void> pumpMomoStatementsRouterApp(
  WidgetTester tester, {
  required ProviderContainer container,
  required GoRouter router,
}) async {
  await setupTestHive();
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
}

Future<void> pumpMomoStatementsHomeApp(
  WidgetTester tester, {
  required ProviderContainer container,
}) async {
  await setupTestHive();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) {
          final locale = ref.watch(localeProvider);
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark,
            home: const MomoStatementsScreen(),
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
          );
        },
      ),
    ),
  );
  await settleTestApp(tester);
}
