import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cool_app/features/admin/models/bank_admin_models.dart';
import 'package:cool_app/features/admin/providers/bank_admin_providers.dart';
import 'package:cool_app/features/admin/repositories/bank_admin_repository.dart';
import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/admin/screens/bank_admin_workspace_screen.dart';
import 'package:cool_app/features/momo/models/momo_statement.dart';
import 'package:cool_app/features/momo/providers/momo_statement_providers.dart';
import 'package:cool_app/features/momo/repositories/momo_statement_repository.dart';
import 'package:cool_app/features/momo/services/momo_statement_download_service.dart';
import 'package:cool_app/features/momo/services/momo_statement_export_service.dart';
import 'package:cool_app/features/partners/models/partner.dart';
import 'package:cool_app/features/partners/providers/partner_provider.dart';
import 'package:cool_app/features/partners/repositories/partner_repository.dart';

import '../../integration_smoke/test_harness.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakeBankAdminRepository extends BankAdminRepository {
  FakeBankAdminRepository(this.snapshot) : super(client: MockSupabaseClient());

  BankAdminWorkspaceSnapshot snapshot;
  int allocateCalls = 0;
  int rejectCalls = 0;
  String? lastAllocatedReviewId;
  String? lastAllocatedGroupId;
  String? lastAllocatedMemberUserId;
  String? lastRejectedReviewId;

  @override
  Future<BankAdminWorkspaceSnapshot> loadWorkspaceSnapshot(
    String partnerId,
  ) async {
    return snapshot;
  }

  @override
  Future<void> allocateManualReviewToGroupContribution({
    required String partnerId,
    required String reviewId,
    required String groupId,
    required String memberUserId,
    String? note,
  }) async {
    allocateCalls += 1;
    lastAllocatedReviewId = reviewId;
    lastAllocatedGroupId = groupId;
    lastAllocatedMemberUserId = memberUserId;
  }

  @override
  Future<void> rejectManualReviewAllocation({
    required String partnerId,
    required String reviewId,
    String? note,
  }) async {
    rejectCalls += 1;
    lastRejectedReviewId = reviewId;
  }
}

class FakePartnerRepository extends PartnerRepository {
  FakePartnerRepository(this.partner) : super(client: MockSupabaseClient());

  final Partner partner;

  @override
  Future<Partner?> fetchById(String id) async {
    return id.trim() == partner.id ? partner : null;
  }
}

class FakeMomoStatementRepository extends MomoStatementRepository {
  FakeMomoStatementRepository(this.page) : super(client: MockSupabaseClient());

  final MomoStatementPage<PayeePaymentLedgerEntry> page;

  @override
  Future<MomoStatementPage<PayeePaymentLedgerEntry>>
  loadGroupPaymentLedgerEntriesPage(
    String groupId, {
    MomoStatementQuery query = const MomoStatementQuery(),
    String? payerUserId,
  }) async {
    return page;
  }
}

class FakeStatementExportService extends MomoStatementExportService {
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
      fileName: 'ledger_export.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
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

void main() {
  const partner = Partner(
    id: 'bank-1',
    name: 'Custody Bank',
    slug: 'custody-bank',
    category: PartnerCategory.bank,
    country: 'RW',
  );

  final snapshot = BankAdminWorkspaceSnapshot(
    groups: const BankAdminPage<BankAdminGroupSummary>(
      entries: <BankAdminGroupSummary>[
        BankAdminGroupSummary(
          group: Group(
            id: 'group-1',
            creatorId: 'user-1',
            name: 'Kigali Market Circle',
            type: 'saving',
            visibility: 'public',
            amount: 240000,
            targetAmount: 300000,
            country: 'RW',
            memberCount: 3,
            monthlyContribution: 15000,
            description: 'Weekly market vendors savings circle.',
            inviteCode: 'KGLM2026',
            frequency: 'weekly',
          ),
          adminCount: 1,
          contributionCount: 7,
          contributionTotal: 120000,
        ),
      ],
      totalCount: 1,
    ),
    members: const BankAdminPage<BankAdminMemberRecord>(
      entries: <BankAdminMemberRecord>[
        BankAdminMemberRecord(
          groupId: 'group-1',
          groupName: 'Kigali Market Circle',
          userId: 'user-1',
          displayName: 'Jean Bosco',
          contributionAmount: 45000,
          isAdmin: true,
        ),
      ],
      totalCount: 1,
    ),
    contributions: BankAdminPage<BankAdminContributionRecord>(
      entries: <BankAdminContributionRecord>[
        BankAdminContributionRecord(
          id: 'contrib-1',
          groupId: 'group-1',
          groupName: 'Kigali Market Circle',
          userId: 'user-1',
          contributorName: 'Jean Bosco',
          amount: 15000,
          status: 'confirmed',
          createdAt: DateTime(2026, 3, 15, 9, 30),
          reference: 'MOMO-1001',
        ),
      ],
      totalCount: 1,
    ),
    allocations: BankAdminPage<BankAdminAllocationReviewItem>(
      entries: <BankAdminAllocationReviewItem>[
        BankAdminAllocationReviewItem(
          reviewId: 'review-1',
          groupId: 'group-1',
          groupName: 'Kigali Market Circle',
          payerName: 'Aline',
          matchStatus: 'manual_review',
          reason: 'ambiguous_payee_route',
          amount: 15000,
          createdAt: DateTime(2026, 3, 15, 8),
          updatedAt: DateTime(2026, 3, 15, 8, 30),
          reference: 'MOMO-2002',
        ),
      ],
      totalCount: 1,
    ),
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
        txCategory: 'group_contribution',
        cashflowBucket: 'savings',
        label: 'Weekly savings deposit',
        targetTable: 'group_contributions',
        reference: 'MOMO-1001',
      ),
    ],
    totalCount: 1,
  );

  testWidgets('renders bank custody data and exports the selected ledger', (
    tester,
  ) async {
    final bankRepository = FakeBankAdminRepository(snapshot);
    final exportService = FakeStatementExportService();
    final downloadService = FakeStatementDownloadService();

    await pumpScopedApp(
      tester,
      child: const BankAdminWorkspaceScreen(partnerId: 'bank-1'),
      session: fakeSession(
        appMetadata: const <String, dynamic>{
          'bank_admin_ids': ['bank-1'],
        },
      ),
      user: fakeUser(
        fullName: 'Bank Operator',
        phone: '+250788123456',
      ).copyWith(officialPhone: '+250788123456'),
      overrides: [
        bankAdminRepositoryProvider.overrideWithValue(bankRepository),
        partnerRepositoryProvider.overrideWithValue(
          FakePartnerRepository(partner),
        ),
        momoStatementRepositoryProvider.overrideWithValue(
          FakeMomoStatementRepository(ledgerPage),
        ),
        momoStatementExportServiceProvider.overrideWithValue(exportService),
        momoStatementDownloadServiceProvider.overrideWithValue(downloadService),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('Custody Bank Terminal'), findsOneWidget);
    expect(find.text('Kigali Market Circle'), findsOneWidget);
    expect(find.text('1 manual review'), findsOneWidget);

    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Linked group profile'), findsOneWidget);
    expect(find.text('Jean Bosco'), findsAtLeastNWidgets(1));
    expect(find.text('Open ledger'), findsOneWidget);

    await tester.tap(find.text('Open ledger'));
    await tester.pumpAndSettle();

    expect(find.text('Posted payment ledger'), findsOneWidget);

    await tester.tap(find.text('ALLOCATIONS'));
    await tester.pumpAndSettle();

    expect(find.text('Manual Review'), findsOneWidget);

    await tester.tap(find.text('LEDGERS'));
    await tester.pumpAndSettle();

    expect(find.text('Posted payment ledger'), findsOneWidget);
    expect(find.text('15,000 RWF'), findsOneWidget);
    expect(find.text('Export Excel'), findsOneWidget);

    await tester.tap(find.text('Export Excel'));
    await tester.pumpAndSettle();

    expect(exportService.ledgerExportCalls, 1);
    expect(exportService.lastEntries, hasLength(1));
    expect(downloadService.lastExport?.fileName, 'ledger_export.xlsx');
    expect(bankRepository.allocateCalls, 0);
    expect(bankRepository.rejectCalls, 0);
  });

  testWidgets('allocates and rejects manual review items from the bank queue', (
    tester,
  ) async {
    final bankRepository = FakeBankAdminRepository(snapshot);

    await pumpScopedApp(
      tester,
      child: const BankAdminWorkspaceScreen(partnerId: 'bank-1'),
      session: fakeSession(
        appMetadata: const <String, dynamic>{
          'bank_admin_ids': ['bank-1'],
        },
      ),
      user: fakeUser(
        fullName: 'Bank Operator',
        phone: '+250788123456',
      ).copyWith(officialPhone: '+250788123456'),
      overrides: [
        bankAdminRepositoryProvider.overrideWithValue(bankRepository),
        partnerRepositoryProvider.overrideWithValue(
          FakePartnerRepository(partner),
        ),
        momoStatementRepositoryProvider.overrideWithValue(
          FakeMomoStatementRepository(ledgerPage),
        ),
        momoStatementExportServiceProvider.overrideWithValue(
          FakeStatementExportService(),
        ),
        momoStatementDownloadServiceProvider.overrideWithValue(
          FakeStatementDownloadService(),
        ),
      ],
    );

    await settleTestApp(tester);

    await tester.tap(find.text('ALLOCATIONS'));
    await tester.pumpAndSettle();

    expect(find.text('Allocate'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);

    await tester.tap(find.text('Allocate'));
    await tester.pumpAndSettle();

    expect(find.text('Allocate payment'), findsOneWidget);
    expect(find.text('Allocate to member'), findsOneWidget);

    await tester.tap(find.text('Allocate to member'));
    await tester.pumpAndSettle();

    expect(bankRepository.allocateCalls, 1);
    expect(bankRepository.lastAllocatedReviewId, 'review-1');
    expect(bankRepository.lastAllocatedGroupId, 'group-1');
    expect(bankRepository.lastAllocatedMemberUserId, 'user-1');

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();

    expect(find.text('Reject allocation'), findsOneWidget);
    expect(find.text('This removes the pending allocation.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(bankRepository.rejectCalls, 1);
    expect(bankRepository.lastRejectedReviewId, 'review-1');
  });
}
