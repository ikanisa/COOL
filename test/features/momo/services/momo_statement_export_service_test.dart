import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/momo/models/momo_statement.dart';
import 'package:cool_app/features/momo/services/momo_statement_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MomoStatementExportService service;
  const metadata = StatementExportMetadata(
    statementTitle: 'Wallet Statement',
    fileStem: 'cool_wallet_statement',
    userName: 'Jean Bosco',
    officialPhone: '+250788000111',
    generatedAt: DateTime(2026, 3, 11, 14, 30),
    periodLabel: '01 Mar 2026 - 11 Mar 2026',
    filterLabel: 'All',
    sortLabel: 'Newest first',
    searchQuery: 'salary',
  );

  setUpAll(() {
    final logoBytes = Uint8List.fromList(
      File('assets/images/cool_logo_mark.png').readAsBytesSync(),
    );
    service = MomoStatementExportService(
      assets: _TestAssetBundle(<String, Uint8List>{
        'assets/images/cool_logo_mark.png': logoBytes,
      }),
    );
  });

  test('wallet PDF export returns a branded PDF file', () async {
    final export = await service.buildWalletExport(
      format: StatementExportFormat.pdf,
      entries: const <MomoWalletEntry>[
        MomoWalletEntry(
          id: 'wallet-1',
          entryType: 'credit',
          ledgerStatus: 'posted',
          amount: 250000,
          currency: 'RWF',
          occurredAt: DateTime(2026, 3, 10, 9),
          txCategory: 'salary',
          cashflowBucket: 'income',
          label: 'Monthly salary payout',
          counterpartyName: 'Acme Ltd',
          reference: 'SAL-202603',
          description: 'Salary transfer',
        ),
      ],
      metadata: metadata,
    );

    expect(export.fileName, endsWith('.pdf'));
    expect(export.mimeType, 'application/pdf');
    expect(
      ascii.decode(export.bytes.sublist(0, 4), allowInvalid: true),
      '%PDF',
    );
  });

  test('wallet Excel export returns an xlsx workbook', () async {
    final export = await service.buildWalletExport(
      format: StatementExportFormat.excel,
      entries: const <MomoWalletEntry>[
        MomoWalletEntry(
          id: 'wallet-2',
          entryType: 'debit',
          ledgerStatus: 'posted',
          amount: 42000,
          currency: 'RWF',
          occurredAt: DateTime(2026, 3, 9, 16, 20),
          txCategory: 'groceries',
          cashflowBucket: 'expense',
          label: 'Market purchase',
          counterpartyName: 'Kimisagara Market',
          reference: 'MKT-0042',
          description: 'Groceries',
        ),
      ],
      metadata: metadata,
    );

    expect(export.fileName, endsWith('.xlsx'));
    expect(
      export.mimeType,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    expect(ascii.decode(export.bytes.sublist(0, 2), allowInvalid: true), 'PK');
  });

  test('savings CSV export includes branded statement metadata', () async {
    final export = await service.buildSavingsExport(
      format: StatementExportFormat.csv,
      entries: const <SavingsStatementEntry>[
        SavingsStatementEntry(
          id: 'savings-1',
          groupId: 'group-1',
          groupName: 'Kigali Women Traders',
          amount: 12000,
          status: 'confirmed',
          createdAt: DateTime(2026, 3, 8, 11, 15),
          reference: 'MOMO-7788',
        ),
      ],
      metadata: const StatementExportMetadata(
        statementTitle: 'Group Savings Statement',
        fileStem: 'cool_group_savings_statement',
        userName: 'Jean Bosco',
        officialPhone: '+250788000111',
        generatedAt: DateTime(2026, 3, 11, 14, 30),
        periodLabel: '01 Mar 2026 - 11 Mar 2026',
        filterLabel: 'Confirmed',
        sortLabel: 'Newest first',
        searchQuery: '',
      ),
    );

    final text = utf8.decode(export.bytes);
    expect(export.fileName, endsWith('.csv'));
    expect(export.mimeType, 'text/csv');
    expect(text, contains('COOL APP'));
    expect(text, contains('Group Savings Statement'));
    expect(text, contains('01 Mar 2026 - 11 Mar 2026'));
    expect(text, contains('Kigali Women Traders'));
  });
}

class _TestAssetBundle extends CachingAssetBundle {
  _TestAssetBundle(this._assets);

  final Map<String, Uint8List> _assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = _assets[key];
    if (bytes == null) {
      throw FlutterError('Missing asset for test bundle: $key');
    }
    return ByteData.view(bytes.buffer);
  }
}
