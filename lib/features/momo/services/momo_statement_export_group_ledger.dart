part of 'momo_statement_export_service.dart';

Future<StatementExportFile> _buildGroupLedgerPdf(
  MomoStatementExportService service, {
  required List<GroupContribution> entries,
  required StatementExportMetadata metadata,
}) async {
  final document = pw.Document();
  final logo = await service._loadPdfLogo();
  final fonts = await service._loadPdfFonts();
  final confirmedTotal = entries
      .where(
        (entry) => entry.status == 'confirmed' || entry.status == 'completed',
      )
      .fold<int>(0, (sum, entry) => sum + entry.amount);
  final contributors = entries
      .map((entry) => entry.contributorName ?? entry.userId)
      .toSet()
      .length;

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(26),
      theme: service._pdfTheme(fonts),
      footer: (context) => service._pdfFooter(context),
      build: (context) => <pw.Widget>[
        service._pdfHeader(metadata: metadata, logo: logo),
        pw.SizedBox(height: 14),
        pw.Row(
          children: [
            pw.Expanded(
              child: service._pdfMetricCard(
                label: 'Total',
                value: '${service._formatAmount(confirmedTotal)} RWF',
                accent: PdfColor.fromHex('#00E5A0'),
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: service._pdfMetricCard(
                label: 'Contributors',
                value: contributors.toString(),
                accent: PdfColor.fromHex('#9B6DFF'),
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: service._pdfMetricCard(
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
            'Contributor',
            'Amount',
            'Currency',
            'Status',
          ],
          data: entries
              .map(
                (entry) => <String>[
                  if (entry.createdAt != null)
                    MomoStatementExportService._dateTimeFormat.format(
                      entry.createdAt!,
                    )
                  else
                    '-',
                  entry.contributorName ?? entry.userId,
                  service._formatAmount(entry.amount),
                  'RWF',
                  service._titleize(entry.status),
                ],
              )
              .toList(growable: false),
          headerStyle: service._pdfTableHeaderTextStyle(),
          headerDecoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#0A0A0F'),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          cellStyle: service._pdfTableCellTextStyle(),
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
    fileName: service._fileName(metadata.fileStem, metadata.generatedAt, 'pdf'),
    mimeType: 'application/pdf',
  );
}

Future<StatementExportFile> _buildGroupLedgerExcel(
  MomoStatementExportService service, {
  required List<GroupContribution> entries,
  required StatementExportMetadata metadata,
}) async {
  final workbook = Workbook();
  final sheet = workbook.worksheets[0];
  sheet.name = 'Group Ledger';
  sheet.showGridlines = false;

  await service._configureExcelSheetHeader(
    sheet: sheet,
    metadata: metadata,
    columnEnd: 'E',
  );

  const headers = <String>[
    'Date',
    'Contributor',
    'Amount',
    'Currency',
    'Status',
  ];
  const startRow = 9;
  for (var index = 0; index < headers.length; index++) {
    sheet.getRangeByIndex(startRow, index + 1).setText(headers[index]);
  }

  final headerRange = sheet.getRangeByName('A$startRow:E$startRow');
  headerRange.cellStyle.backColor = '#0A0A0F';
  headerRange.cellStyle.fontColor = '#FFFFFF';
  headerRange.cellStyle.bold = true;

  for (var index = 0; index < entries.length; index++) {
    final row = startRow + index + 1;
    final entry = entries[index];
    sheet
        .getRangeByIndex(row, 1)
        .setText(
          entry.createdAt != null
              ? MomoStatementExportService._dateTimeFormat.format(
                  entry.createdAt!,
                )
              : '-',
        );
    sheet
        .getRangeByIndex(row, 2)
        .setText(entry.contributorName ?? entry.userId);
    sheet.getRangeByIndex(row, 3).setNumber(entry.amount.toDouble());
    sheet.getRangeByIndex(row, 3).numberFormat = '#,##0';
    sheet.getRangeByIndex(row, 4).setText('RWF');
    sheet.getRangeByIndex(row, 5).setText(service._titleize(entry.status));
  }

  final bytes = workbook.saveAsStream();
  workbook.dispose();

  return StatementExportFile(
    bytes: Uint8List.fromList(bytes),
    fileName: service._fileName(
      metadata.fileStem,
      metadata.generatedAt,
      'xlsx',
    ),
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );
}

StatementExportFile _buildGroupLedgerCsv(
  MomoStatementExportService service, {
  required List<GroupContribution> entries,
  required StatementExportMetadata metadata,
}) {
  final rows = <List<String>>[
    <String>[MomoStatementExportService._brandName],
    <String>[metadata.statementTitle],
    <String>['Group', metadata.userName],
    <String>['Statement Period', metadata.periodLabel],
    <String>['Generated At', metadata.generatedAt.toIso8601String()],
    <String>['Filter', metadata.filterLabel],
    <String>['Sort', metadata.sortLabel],
    const <String>[],
    const <String>['Date', 'Contributor', 'Amount', 'Currency', 'Status'],
    for (final entry in entries)
      <String>[
        if (entry.createdAt != null)
          MomoStatementExportService._dateTimeFormat.format(entry.createdAt!)
        else
          '',
        entry.contributorName ?? entry.userId,
        entry.amount.toString(),
        'RWF',
        entry.status,
      ],
  ];

  return StatementExportFile(
    bytes: Uint8List.fromList(
      utf8.encode(rows.map(service._csvRow).join('\n')),
    ),
    fileName: service._fileName(metadata.fileStem, metadata.generatedAt, 'csv'),
    mimeType: 'text/csv',
  );
}

class _PdfFontBundle {
  const _PdfFontBundle({required this.base, required this.bold});

  final pw.Font base;
  final pw.Font bold;
}
