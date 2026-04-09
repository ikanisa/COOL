part of 'momo_statement_export_service.dart';

extension _MomoStatementExportShared on MomoStatementExportService {
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
      ('Generated At', MomoStatementExportService._dateTimeFormat.format(metadata.generatedAt)),
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
                            size: MomoStatementExportService._pdfFontSizeLogoMark,
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
                  MomoStatementExportService._dateTimeFormat.format(metadata.generatedAt),
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

  String _formatAmount(int amount) =>
      MomoStatementExportService._moneyFormat.format(amount);
}
