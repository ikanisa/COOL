part of 'momo_statement_export_service.dart';

extension MomoStatementExportServiceExtensions on MomoStatementExportService {
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
                    MomoStatementExportService._dateTimeFormat.format(
                      entry.occurredAt,
                    ),
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

  Future<StatementExportFile> _buildSavingsPdf({
    required List<SavingsStatementEntry> entries,
    required StatementExportMetadata metadata,
  }) async {
    final document = pw.Document();
    final logo = await _loadPdfLogo();
    final fonts = await _loadPdfFonts();
    final confirmedTotal = entries
        .where((entry) => entry.isConfirmed)
        .fold<int>(0, (sum, entry) => sum + entry.amount);
    final activeGroups = entries
        .map((entry) => entry.groupName.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .length;

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
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
                  label: 'Confirmed',
                  value: '${_formatAmount(confirmedTotal)} RWF',
                  accent: PdfColor.fromHex('#00E5A0'),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: _pdfMetricCard(
                  label: 'Groups',
                  value: activeGroups.toString(),
                  accent: PdfColor.fromHex('#9B6DFF'),
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
              'Group Name',
              'Amount',
              'Currency',
              'Status',
              'Reference',
            ],
            data: entries
                .map(
                  (entry) => <String>[
                    MomoStatementExportService._dateTimeFormat.format(
                      entry.createdAt,
                    ),
                    entry.groupName,
                    _formatAmount(entry.amount),
                    'RWF',
                    _titleize(entry.status),
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
    final postedTotal = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.amount,
    );
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
                    MomoStatementExportService._dateTimeFormat.format(
                      entry.occurredAt,
                    ),
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

  Future<StatementExportFile> _buildSavingsExcel({
    required List<SavingsStatementEntry> entries,
    required StatementExportMetadata metadata,
  }) async {
    final workbook = Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Savings Statement';
    sheet.showGridlines = false;

    await _configureExcelSheetHeader(
      sheet: sheet,
      metadata: metadata,
      columnEnd: 'F',
    );

    _writeExcelSavingsTable(sheet, entries, startRow: 9);

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
      <String>[
        'Generated At',
        metadata.generatedAt.toIso8601String(),
      ],
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

  StatementExportFile _buildSavingsCsv({
    required List<SavingsStatementEntry> entries,
    required StatementExportMetadata metadata,
  }) {
    final rows = <List<String>>[
      <String>[MomoStatementExportService._brandName],
      <String>[metadata.statementTitle],
      <String>['Official Holder', metadata.userName],
      <String>['Official Phone', metadata.officialPhone],
      <String>['Statement Period', metadata.periodLabel],
      <String>[
        'Generated At',
        metadata.generatedAt.toIso8601String(),
      ],
      <String>['Search Query', metadata.searchQuery],
      <String>['Filter', metadata.filterLabel],
      <String>['Sort', metadata.sortLabel],
      const <String>[],
      const <String>[
        'Date',
        'Group Name',
        'Amount',
        'Currency',
        'Status',
        'MOMO Reference',
      ],
      for (final entry in entries)
        <String>[
          MomoStatementExportService._dateTimeFormat.format(entry.createdAt),
          entry.groupName,
          entry.amount.toString(),
          'RWF',
          entry.status,
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
      <String>[
        'Generated At',
        metadata.generatedAt.toIso8601String(),
      ],
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

  Future<void> _configureExcelSheetHeader({
    required Worksheet sheet,
    required StatementExportMetadata metadata,
    required String columnEnd,
  }) async {
    final titleRange = sheet.getRangeByName('B1:${columnEnd}2');
    titleRange.merge();
    titleRange.setText(MomoStatementExportService._brandName);
    titleRange.cellStyle.backColor = '#0A0A0F';
    titleRange.cellStyle.fontColor = '#FFFFFF';
    titleRange.cellStyle.bold = true;
    titleRange.cellStyle.fontSize = 18;
    titleRange.cellStyle.vAlign = VAlignType.center;

    final subtitleRange = sheet.getRangeByName('B3:${columnEnd}4');
    subtitleRange.merge();
    subtitleRange.setText(metadata.statementTitle);
    subtitleRange.cellStyle.backColor = '#13131A';
    subtitleRange.cellStyle.fontColor = '#00E5A0';
    subtitleRange.cellStyle.bold = true;
    subtitleRange.cellStyle.fontSize = 14;
    subtitleRange.cellStyle.vAlign = VAlignType.center;

    final metaRows = <(String, String)>[
      ('Official Holder', metadata.userName),
      ('Official Phone', metadata.officialPhone),
      ('Statement Period', metadata.periodLabel),
      (
        'Generated At',
        MomoStatementExportService._dateTimeFormat.format(metadata.generatedAt),
      ),
      (
        'Search Query',
        metadata.searchQuery.isEmpty ? 'None' : metadata.searchQuery,
      ),
      ('Filter / Sort', '${metadata.filterLabel} / ${metadata.sortLabel}'),
    ];

    var row = 5;
    for (final meta in metaRows) {
      final label = sheet.getRangeByName('A$row:B$row');
      label.merge();
      label.setText(meta.$1);
      label.cellStyle.backColor = '#F5F7FA';
      label.cellStyle.bold = true;
      label.cellStyle.fontColor = '#1C1C26';

      final value = sheet.getRangeByName('C$row:$columnEnd$row');
      value.merge();
      value.setText(meta.$2.isEmpty ? '-' : meta.$2);
      value.cellStyle.fontColor = '#1C1C26';
      row += 1;
    }

    sheet.getRangeByName('A1:$columnEnd$row').cellStyle.fontSize = 10;
    sheet.getRangeByName('A9').freezePanes();

    sheet.getRangeByName('A1').columnWidth = 7;
    sheet.getRangeByName('B1').columnWidth = 14;
    sheet.getRangeByName('C1').columnWidth = 18;
    sheet.getRangeByName('D1').columnWidth = 18;
    sheet.getRangeByName('E1').columnWidth = 16;
    sheet.getRangeByName('F1').columnWidth = 16;
    sheet.getRangeByName('G1').columnWidth = 16;
    sheet.getRangeByName('H1').columnWidth = 16;
    sheet.getRangeByName('I1').columnWidth = 14;
    sheet.getRangeByName('J1').columnWidth = 18;

    final logoBytes = await _loadLogoBytes();
    if (logoBytes != null) {
      final picture = sheet.pictures.addStream(1, 1, logoBytes);
      picture.width = 44;
      picture.height = 44;
    }
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
      sheet.getRangeByIndex(row, 1).setText(
        MomoStatementExportService._dateTimeFormat.format(entry.occurredAt),
      );
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
      sheet
              .getRangeByName('A${startRow + 1}:J$bodyEndRow')
              .cellStyle
              .fontColor =
          '#1C1C26';
    }
  }

  void _writeExcelSavingsTable(
    Worksheet sheet,
    List<SavingsStatementEntry> entries, {
    required int startRow,
  }) {
    const headers = <String>[
      'Date',
      'Group Name',
      'Amount',
      'Currency',
      'Status',
      'Reference',
    ];

    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(startRow, i + 1);
      cell.setText(headers[i]);
    }

    final headerRange = sheet.getRangeByName('A$startRow:F$startRow');
    headerRange.cellStyle.backColor = '#0A0A0F';
    headerRange.cellStyle.fontColor = '#FFFFFF';
    headerRange.cellStyle.bold = true;

    for (var i = 0; i < entries.length; i++) {
      final row = startRow + i + 1;
      final entry = entries[i];
      sheet.getRangeByIndex(row, 1).setText(
        MomoStatementExportService._dateTimeFormat.format(entry.createdAt),
      );
      sheet.getRangeByIndex(row, 2).setText(entry.groupName);
      sheet.getRangeByIndex(row, 3).setNumber(entry.amount.toDouble());
      sheet.getRangeByIndex(row, 3).numberFormat = '#,##0';
      sheet.getRangeByIndex(row, 4).setText('Rwf');
      sheet.getRangeByIndex(row, 5).setText(_titleize(entry.status));
      sheet.getRangeByIndex(row, 6).setText(entry.reference ?? '-');
    }

    final bodyEndRow = startRow + entries.length;
    if (bodyEndRow >= startRow + 1) {
      sheet
              .getRangeByName('A${startRow + 1}:F$bodyEndRow')
              .cellStyle
              .fontColor =
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
      sheet.getRangeByIndex(row, 1).setText(
        MomoStatementExportService._dateTimeFormat.format(entry.occurredAt),
      );
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
      sheet
              .getRangeByName('A${startRow + 1}:J$bodyEndRow')
              .cellStyle
              .fontColor =
          '#1C1C26';
    }
  }

  pw.Widget _pdfHeader({
    required StatementExportMetadata metadata,
    required pw.MemoryImage? logo,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 24),
      margin: const pw.EdgeInsets.only(bottom: 24),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 1.5),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logo != null)
                      pw.Container(width: 48, height: 48, child: pw.Image(logo))
                    else
                      pw.Container(
                        width: 48,
                        height: 48,
                        alignment: pw.Alignment.center,
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromHex('#00E5A0'),
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(12),
                          ),
                        ),
                        child: pw.Text(
                          'C',
                          style: _pdfTextStyle(
                            size: MomoStatementExportService
                                ._pdfFontSizeLogoMark,
                            color: PdfColor.fromHex('#0A0A0F'),
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    pw.SizedBox(width: 16),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          MomoStatementExportService._brandName,
                          style: _pdfTextStyle(
                            size: MomoStatementExportService._pdfFontSizeBrand,
                            color: PdfColors.black,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'OFFICIAL STATEMENT',
                          style: _pdfTextStyle(
                            size: MomoStatementExportService._pdfFontSizeValue,
                            color: PdfColors.grey600,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 28),
                pw.Text(
                  metadata.statementTitle.toUpperCase(),
                  style: _pdfTextStyle(
                    size: MomoStatementExportService._pdfFontSizeSection,
                    color: PdfColors.black,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  metadata.periodLabel,
                  style: _pdfTextStyle(
                    size: MomoStatementExportService._pdfFontSizeBody,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
          pw.Container(
            width: 250,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                _pdfMetaRow('ACCOUNT HOLDER', metadata.userName),
                if (metadata.officialPhone.isNotEmpty)
                  _pdfMetaRow('REGISTERED PHONE', metadata.officialPhone),
                _pdfMetaRow(
                  'DATE GENERATED',
                  MomoStatementExportService._dateTimeFormat.format(
                    metadata.generatedAt,
                  ),
                ),
                _pdfMetaRow('FILTER APPLIED', metadata.filterLabel),
                _pdfMetaRow('SORT ORDER', metadata.sortLabel),
                if (metadata.searchQuery.isNotEmpty)
                  _pdfMetaRow('SEARCH QUERY', metadata.searchQuery),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfFooter(pw.Context context) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        'Page ${context.pageNumber} of ${context.pagesCount}',
        style: _pdfTextStyle(
          size: MomoStatementExportService._pdfFontSizeCaption,
          color: PdfColors.grey700,
        ),
      ),
    );
  }

  pw.Widget _pdfMetricCard({
    required String label,
    required String value,
    required PdfColor accent,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F5F7FA'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: PdfColor.fromHex('#DDE3EA')),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: _pdfTextStyle(
              size: MomoStatementExportService._pdfFontSizeLabel,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            value,
            style: _pdfTextStyle(
              size: MomoStatementExportService._pdfFontSizeMetric,
              fontWeight: pw.FontWeight.bold,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfMetaRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: _pdfTextStyle(
              size: MomoStatementExportService._pdfFontSizeLabel,
              color: PdfColors.grey600,
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: _pdfTextStyle(
                size: MomoStatementExportService._pdfFontSizeValue,
                color: PdfColors.black,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<pw.MemoryImage?> _loadPdfLogo() async {
    final logoBytes = await _loadLogoBytes();
    if (logoBytes == null) {
      return null;
    }
    return pw.MemoryImage(logoBytes);
  }

  Future<_PdfFontBundle?> _loadPdfFonts() async {
    try {
      final base = await _assets.load(MomoStatementExportService._baseFontAssetPath);
      final bold = await _assets.load(MomoStatementExportService._boldFontAssetPath);
      return _PdfFontBundle(base: pw.Font.ttf(base), bold: pw.Font.ttf(bold));
    } catch (_) {
      return null;
    }
  }

  pw.ThemeData? _pdfTheme(_PdfFontBundle? fonts) {
    if (fonts == null) {
      return null;
    }

    return pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold);
  }

  pw.TextStyle _pdfTextStyle({
    required double size,
    PdfColor? color,
    pw.FontWeight? fontWeight,
    double? letterSpacing,
  }) {
    return pw.TextStyle(
      fontSize: size,
      color: color,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
    );
  }

  pw.TextStyle _pdfTableHeaderTextStyle() {
    return _pdfTextStyle(
      size: MomoStatementExportService._pdfFontSizeLabel,
      color: PdfColors.white,
      fontWeight: pw.FontWeight.bold,
    );
  }

  pw.TextStyle _pdfTableCellTextStyle() {
    return _pdfTextStyle(size: MomoStatementExportService._pdfFontSizeCaption);
  }

  Future<Uint8List?> _loadLogoBytes() async {
    try {
      final asset = await _assets.load(MomoStatementExportService._logoAssetPath);
      return asset.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  String _fileName(String stem, DateTime timestamp, String extension) {
    return '${stem}_${MomoStatementExportService._fileStampFormat.format(timestamp)}.$extension';
  }

  String _csvRow(List<String> values) {
    return values
        .map(
          (value) =>
              '"${value.replaceAll('"', '""').replaceAll('\n', ' ').trim()}"',
        )
        .join(',');
  }

  String _formatAmount(int amount) => MomoStatementExportService._moneyFormat.format(amount);
}
