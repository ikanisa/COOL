import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cool_app/features/momo/models/momo_statement.dart';
import 'package:cool_app/features/momo/providers/momo_statement_providers.dart';
import 'package:cool_app/features/momo/repositories/momo_statement_repository.dart';
import 'package:cool_app/features/momo/services/momo_statement_download_service.dart';
import 'package:cool_app/features/momo/services/momo_statement_export_service.dart';
import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/providers/rs_admin_provider.dart';
import 'package:cool_app/features/partners/rayon/rayon_payment.dart';
import 'package:cool_app/features/partners/rayon/screens/rs_admin_finance_screen.dart';

import '../../integration_smoke/test_harness.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _FakeMomoStatementRepository extends MomoStatementRepository {
  _FakeMomoStatementRepository(this.page)
    : super(client: _MockSupabaseClient());

  final MomoStatementPage<PayeePaymentLedgerEntry> page;

  @override
  Future<MomoStatementPage<PayeePaymentLedgerEntry>>
  loadPartnerPaymentLedgerEntriesPage(
    String partnerId, {
    MomoStatementQuery query = const MomoStatementQuery(),
    String? payerUserId,
  }) async {
    return page;
  }
}

class _FakeStatementExportService extends MomoStatementExportService {
  int ledgerExportCalls = 0;
  List<PayeePaymentLedgerEntry> lastEntries = const <PayeePaymentLedgerEntry>[];

  @override
  Future<StatementExportFile> buildPayeeLedgerExport({
    required StatementExportFormat format,
    required List<PayeePaymentLedgerEntry> entries,
    required StatementExportMetadata metadata,
  }) async {
    ledgerExportCalls += 1;
    lastEntries = entries;
    return StatementExportFile(
      bytes: Uint8List.fromList(const <int>[1, 2, 3]),
      fileName: 'rayon_finance_export.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }
}

class _FakeStatementDownloadService extends MomoStatementDownloadService {
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
  const route = PartnerPaymentRoute(
    id: 'route-1',
    partnerId: 'partner-rayon',
    partnerName: 'Rayon Sports',
    partnerSlug: 'rayon-sports',
    countryCode: 'RW',
    providerId: 'mtn_rwanda',
    recipientCode: '123456',
    reconciliationLabel: 'rayon_sports',
    status: PartnerPaymentRouteStatus.active,
  );

  final ledgerPage = MomoStatementPage<PayeePaymentLedgerEntry>(
    entries: <PayeePaymentLedgerEntry>[
      PayeePaymentLedgerEntry(
        ledgerId: 'ledger-1',
        payerUserId: 'user-1',
        payerName: 'Jean Bosco',
        amount: 15000,
        currency: 'RWF',
        occurredAt: DateTime(2026, 3, 15, 9, 35),
        txCategory: 'ticket',
        cashflowBucket: 'revenue',
        label: 'Matchday ticket',
        targetTable: 'rs_tickets',
        reference: 'MOMO-1001',
      ),
    ],
    totalCount: 1,
  );

  testWidgets('renders payment routes and exports the partner ledger', (
    tester,
  ) async {
    final exportService = _FakeStatementExportService();
    final downloadService = _FakeStatementDownloadService();

    await pumpScopedApp(
      tester,
      child: const RsAdminFinanceScreen(),
      session: fakeSession(
        appMetadata: const <String, dynamic>{
          'partner_admin_ids': ['partner-rayon'],
        },
      ),
      user: fakeUser(fullName: 'Finance Admin'),
      overrides: [
        rayonPartnerIdProvider.overrideWith((ref) async => 'partner-rayon'),
        rsAdminPaymentRoutesProvider.overrideWith(
          (ref) async => const <PartnerPaymentRoute>[route],
        ),
        momoStatementRepositoryProvider.overrideWithValue(
          _FakeMomoStatementRepository(ledgerPage),
        ),
        momoStatementExportServiceProvider.overrideWithValue(exportService),
        momoStatementDownloadServiceProvider.overrideWithValue(downloadService),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('Finance'), findsWidgets);
    expect(find.text('Payment routing'), findsOneWidget);
    expect(find.text('RW · MTN MoMo'), findsOneWidget);
    expect(find.text('Posted partner ledger'), findsOneWidget);
    expect(find.text('Jean Bosco'), findsOneWidget);

    await tester.tap(find.text('Export Excel'));
    await settleTestApp(tester);

    expect(exportService.ledgerExportCalls, 1);
    expect(exportService.lastEntries, ledgerPage.entries);
    expect(downloadService.lastExport?.fileName, 'rayon_finance_export.xlsx');
  });
}
