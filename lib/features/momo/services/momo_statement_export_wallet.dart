part of 'momo_statement_export_service.dart';

extension _MomoStatementExportWallet on MomoStatementExportService {
  Future<StatementExportFile> _buildWalletPdf({
    required List<MomoWalletEntry> entries,
    required StatementExportMetadata metadata,
  }) async {
    final document = pw.Document();
    final logo = await _loadPdfLogo();
    final fonts = await _loadPdfFonts();
    final incomingTotal = entries
        .where((entry) => entry.isCredit)
        .fold<int>(0, (sum, entry) => sum + entry.amount);
    final outgoingTotal = entries
        .where((entry) => entry.isDebit)
        .fold<int>(0, (sum, entry) => sum + entry.amount);

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(26),
        theme: _pdfTheme(fonts),
        footer: (context) => _pdfFooter(context),
        build: (context) => <pw.Widget>[
          _pdfHeader(metadata: metadata, logo: logo),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              pw.Expanded(
                child: _pdfMetricCard(
                  label: 'Incoming',
                  value: '${_formatAmount(incomingTotal)} RWF',
                  accent: PdfColor.fromHex('#00E5A0'),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _pdfMetricCard(
                  label: 'Outgoing',
                  value: '${_formatAmount(outgoingTotal)} RWF',
                  accent: PdfColor.fromHex('#FF6B35'),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _pdfMetricCard(
                  label: 'Entries',
                  value: entries.length.toString(),
                  accent: PdfColor.fromHex('#4D8EFF'),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: const <String>[
              'Date',
              'Direction',
              'Category',
              'Bucket',
              'Counterparty',
              'Summary',
              'Amount',
              'Currency',
              'Status',
              'Reference',
            ],
            data: entries
                .map(
                  (entry) => <String>[
                    MomoStatementExportService._dateTimeFormat.format(entry.occurredAt),
                    if (entry.isCredit) 'Incoming' else 'Outgoing',
                    _titleize(entry.txCategory),
                    _titleize(entry.cashflowBucket),
                    entry.counterpartyName ?? '-',
                    entry.label,
                    _formatAmount(entry.amount),
                    entry.currency,
                    _titleize(entry.ledgerStatus),
                    entry.reference ?? '-',
                  ],
                )
                .toList(growable: false),
            headerStyle: _pdfTableHeaderTextStyle(),
            headerDecoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#0A0A0F'),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            cellStyle: _pdfTableCellTextStyle(),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 7,
            ),
            rowDecoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColor.fromHex('#DDE3EA')),
              ),
            ),
          ),
        ],
      ),
    );

    return StatementExportFile(
      bytes: Uint8List.fromList(await document.save()),
      fileName: _fileName(metadata.fileStem, metadata.generatedAt, 'pdf'),
      mimeType: 'application/pdf',
    );
  }

  Future<StatementExportFile> _buildPayeeLedgerPdf({
    required List<PayeePaymentLedgerEntry> entries,
    required StatementExportMetadata metadata,
  }) async {
    final document = pw.Document();
    final logo = await _loadPdfLogo();
    final fonts = await _loadPdfFonts();
    final postedTotal = entries.fold<int>(0, (sum, entry) => sum + entry.amount);
    final distinctPayers = entries
        .map((entry) => entry.payerUserId.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .length;

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(26),
        theme: _pdfTheme(fonts),
        footer: (context) => _pdfFooter(context),
        build: (context) => <pw.Widget>[
          _pdfHeader(metadata: metadata, logo: logo),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              pw.Expanded(
                child: _pdfMetricCard(
                  label: 'Posted',
                  value: '${_formatAmount(postedTotal)} RWF',
                  accent: PdfColor.fromHex('#00E5A0'),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _pdfMetricCard(
                  label: 'Payers',
                  value: distinctPayers.toString(),
                  accent: PdfColor.fromHex('#4D8EFF'),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _pdfMetricCard(
                  label: 'Entries',
                  value: entries.length.toString(),
                  accent: PdfColor.fromHex('#9B6DFF'),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: const <String>[
              'Date',
              'Payer',
              'Phone',
              'Category',
              'Bucket',
              'Summary',
              'Amount',
              'Currency',
              'Target',
              'Reference',
            ],
            data: entries
                .map(
                  (entry) => <String>[
                    MomoStatementExportService._dateTimeFormat.format(entry.occurredAt),
                    entry.payerName,
                    entry.payerPhone ?? '-',
                    _titleize(entry.txCategory),
                    _titleize(entry.cashflowBucket),
                    entry.label,
                    _formatAmount(entry.amount),
                    entry.currency,
                    _titleize(entry.targetTable),
                    entry.reference ?? '-',
                  ],
                )
                .toList(growable: false),
            headerStyle: _pdfTableHeaderTextStyle(),
            headerDecoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#0A0A0F'),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            cellStyle: _pdfTableCellTextStyle(),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 7,
            ),
            rowDecoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColor.fromHex('#DDE3EA')),
              ),
            ),
          ),
        ],
      ),
    );

    return StatementExportFile(
      bytes: Uint8List.fromList(await document.save()),
      fileName: _fileName(metadata.fileStem, metadata.generatedAt, 'pdf'),
      mimeType: 'application/pdf',
    );
  }

  Future<StatementExportFile> _buildWalletExcel({
    required List<MomoWalletEntry> entries,
    required StatementExportMetadata metadata,
  }) async {
    final workbook = Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Wallet Statement';
    sheet.showGridlines = false;

    await _configureExcelSheetHeader(
      sheet: sheet,
      metadata: metadata,
      columnEnd: 'J',
    );

    _writeExcelWalletTable(sheet, entries, startRow: 9);

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    return StatementExportFile(
      bytes: Uint8List.fromList(bytes),
      fileName: _fileName(metadata.fileStem, metadata.generatedAt, 'xlsx'),
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  Future<StatementExportFile> _buildPayeeLedgerExcel({
    required List<PayeePaymentLedgerEntry> entries,
    required StatementExportMetadata metadata,
  }) async {
    final workbook = Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Payment Ledger';
    sheet.showGridlines = false;

    await _configureExcelSheetHeader(
      sheet: sheet,
      metadata: metadata,
      columnEnd: 'J',
    );

    _writeExcelPayeeLedgerTable(sheet, entries, startRow: 9);

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    return StatementExportFile(
      bytes: Uint8List.fromList(bytes),
      fileName: _fileName(metadata.fileStem, metadata.generatedAt, 'xlsx'),
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  StatementExportFile _buildWalletCsv({
    required List<MomoWalletEntry> entries,
    required StatementExportMetadata metadata,
  }) {
    final rows = <List<String>>[
      <String>[MomoStatementExportService._brandName],
      <String>[metadata.statementTitle],
      <String>['Official Holder', metadata.userName],
      <String>['Official Phone', metadata.officialPhone],
      <String>['Statement Period', metadata.periodLabel],
      <String>['Generated At', metadata.generatedAt.toIso8601String()],
      <String>['Search Query', metadata.searchQuery],
      <String>['Filter', metadata.filterLabel],
      <String>['Sort', metadata.sortLabel],
      const <String>[],
      const <String>[
        'Date',
        'Direction',
        'Category',
        'Cashflow Bucket',
        'Counterparty',
        'Summary',
        'Amount',
        'Currency',
        'Status',
        'Reference',
      ],
      for (final entry in entries)
        <String>[
          MomoStatementExportService._dateTimeFormat.format(entry.occurredAt),
          if (entry.isCredit) 'Incoming' else 'Outgoing',
          entry.txCategory,
          entry.cashflowBucket,
          entry.counterpartyName ?? '',
          entry.label,
          entry.amount.toString(),
          entry.currency,
          entry.ledgerStatus,
          entry.reference ?? '',
        ],
    ];

    return StatementExportFile(
      bytes: Uint8List.fromList(utf8.encode(rows.map(_csvRow).join('\n'))),
      fileName: _fileName(metadata.fileStem, metadata.generatedAt, 'csv'),
      mimeType: 'text/csv',
    );
  }

  StatementExportFile _buildPayeeLedgerCsv({
    required List<PayeePaymentLedgerEntry> entries,
    required StatementExportMetadata metadata,
  }) {
    final rows = <List<String>>[
      <String>[MomoStatementExportService._brandName],
      <String>[metadata.statementTitle],
      <String>['Official Holder', metadata.userName],
      <String>['Official Phone', metadata.officialPhone],
      <String>['Statement Period', metadata.periodLabel],
      <String>['Generated At', metadata.generatedAt.toIso8601String()],
      <String>['Search Query', metadata.searchQuery],
      <String>['Filter', metadata.filterLabel],
      <String>['Sort', metadata.sortLabel],
      const <String>[],
      const <String>[
        'Date',
        'Payer',
        'Payer Phone',
        'Category',
        'Cashflow Bucket',
        'Summary',
        'Amount',
        'Currency',
        'Target Table',
        'Reference',
      ],
      for (final entry in entries)
        <String>[
          MomoStatementExportService._dateTimeFormat.format(entry.occurredAt),
          entry.payerName,
          entry.payerPhone ?? '',
          entry.txCategory,
          entry.cashflowBucket,
          entry.label,
          entry.amount.toString(),
          entry.currency,
          entry.targetTable,
          entry.reference ?? '',
        ],
    ];

    return StatementExportFile(
      bytes: Uint8List.fromList(utf8.encode(rows.map(_csvRow).join('\n'))),
      fileName: _fileName(metadata.fileStem, metadata.generatedAt, 'csv'),
      mimeType: 'text/csv',
    );
  }

  void _writeExcelWalletTable(
    Worksheet sheet,
    List<MomoWalletEntry> entries, {
    required int startRow,
  }) {
    const headers = <String>[
      'Date',
      'Direction',
      'Category',
      'Bucket',
      'Counterparty',
      'Summary',
      'Amount',
      'Currency',
      'Status',
      'Reference',
    ];

    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(startRow, i + 1);
      cell.setText(headers[i]);
    }

    final headerRange = sheet.getRangeByName('A$startRow:J$startRow');
    headerRange.cellStyle.backColor = '#0A0A0F';
    headerRange.cellStyle.fontColor = '#FFFFFF';
    headerRange.cellStyle.bold = true;

    for (var i = 0; i < entries.length; i++) {
      final row = startRow + i + 1;
      final entry = entries[i];
      sheet
          .getRangeByIndex(row, 1)
          .setText(MomoStatementExportService._dateTimeFormat.format(entry.occurredAt));
      sheet
          .getRangeByIndex(row, 2)
          .setText(entry.isCredit ? 'Incoming' : 'Outgoing');
      sheet.getRangeByIndex(row, 3).setText(_titleize(entry.txCategory));
      sheet.getRangeByIndex(row, 4).setText(_titleize(entry.cashflowBucket));
      sheet.getRangeByIndex(row, 5).setText(entry.counterpartyName ?? '-');
      sheet.getRangeByIndex(row, 6).setText(entry.label);
      sheet.getRangeByIndex(row, 7).setNumber(entry.amount.toDouble());
      sheet.getRangeByIndex(row, 7).numberFormat = '#,##0';
      sheet.getRangeByIndex(row, 8).setText(entry.currency);
      sheet.getRangeByIndex(row, 9).setText(_titleize(entry.ledgerStatus));
      sheet.getRangeByIndex(row, 10).setText(entry.reference ?? '-');
    }

    final bodyEndRow = startRow + entries.length;
    if (bodyEndRow >= startRow + 1) {
      sheet.getRangeByName('A${startRow + 1}:J$bodyEndRow').cellStyle.fontColor =
          '#1C1C26';
    }
  }

  void _writeExcelPayeeLedgerTable(
    Worksheet sheet,
    List<PayeePaymentLedgerEntry> entries, {
    required int startRow,
  }) {
    const headers = <String>[
      'Date',
      'Payer',
      'Phone',
      'Category',
      'Bucket',
      'Summary',
      'Amount',
      'Currency',
      'Target',
      'Reference',
    ];

    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(startRow, i + 1);
      cell.setText(headers[i]);
    }

    final headerRange = sheet.getRangeByName('A$startRow:J$startRow');
    headerRange.cellStyle.backColor = '#0A0A0F';
    headerRange.cellStyle.fontColor = '#FFFFFF';
    headerRange.cellStyle.bold = true;

    for (var i = 0; i < entries.length; i++) {
      final row = startRow + i + 1;
      final entry = entries[i];
      sheet
          .getRangeByIndex(row, 1)
          .setText(MomoStatementExportService._dateTimeFormat.format(entry.occurredAt));
      sheet.getRangeByIndex(row, 2).setText(entry.payerName);
      sheet.getRangeByIndex(row, 3).setText(entry.payerPhone ?? '-');
      sheet.getRangeByIndex(row, 4).setText(_titleize(entry.txCategory));
      sheet.getRangeByIndex(row, 5).setText(_titleize(entry.cashflowBucket));
      sheet.getRangeByIndex(row, 6).setText(entry.label);
      sheet.getRangeByIndex(row, 7).setNumber(entry.amount.toDouble());
      sheet.getRangeByIndex(row, 7).numberFormat = '#,##0';
      sheet.getRangeByIndex(row, 8).setText(entry.currency);
      sheet.getRangeByIndex(row, 9).setText(_titleize(entry.targetTable));
      sheet.getRangeByIndex(row, 10).setText(entry.reference ?? '-');
    }

    final bodyEndRow = startRow + entries.length;
    if (bodyEndRow >= startRow + 1) {
      sheet.getRangeByName('A${startRow + 1}:J$bodyEndRow').cellStyle.fontColor =
          '#1C1C26';
    }
  }
}
