import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' hide Column;

import '../models/momo_statement.dart';

part 'momo_statement_export_group_ledger.dart';
part 'momo_statement_export_shared.dart';
part 'momo_statement_export_wallet.dart';

enum StatementExportFormat { pdf, excel, csv }

class StatementExportMetadata {
  const StatementExportMetadata({
    required this.statementTitle,
    required this.fileStem,
    required this.userName,
    required this.officialPhone,
    required this.generatedAt,
    required this.periodLabel,
    required this.filterLabel,
    required this.sortLabel,
    this.searchQuery = '',
  });

  final String statementTitle;
  final String fileStem;
  final String userName;
  final String officialPhone;
  final DateTime generatedAt;
  final String periodLabel;
  final String filterLabel;
  final String sortLabel;
  final String searchQuery;
}

class StatementExportFile {
  const StatementExportFile({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

class MomoStatementExportService {
  MomoStatementExportService({AssetBundle? assets})
    : _assets = assets ?? rootBundle;

  final AssetBundle _assets;

  static const String _brandName = 'COOL APP';
  static const String _logoAssetPath = 'assets/images/cool_logo_mark.png';
  static const String _baseFontAssetPath = 'google_fonts/Manrope-Medium.ttf';
  static const String _boldFontAssetPath = 'google_fonts/Manrope-ExtraBold.ttf';
  static final DateFormat _fileStampFormat = DateFormat('yyyyMMdd_HHmm');
  static final DateFormat _dateTimeFormat = DateFormat('dd MMM yyyy, HH:mm');
  static final NumberFormat _moneyFormat = NumberFormat.decimalPattern('en_US');
  static const double _pdfFontSizeCaption = 8;
  static const double _pdfFontSizeLabel = 9;
  static const double _pdfFontSizeValue = 10;
  static const double _pdfFontSizeBody = 11;
  static const double _pdfFontSizeMetric = 13;
  static const double _pdfFontSizeSection = 16;
  static const double _pdfFontSizeLogoMark = 24;
  static const double _pdfFontSizeBrand = 28;

  Future<StatementExportFile> buildWalletExport({
    required StatementExportFormat format,
    required List<MomoWalletEntry> entries,
    required StatementExportMetadata metadata,
  }) async {
    switch (format) {
      case StatementExportFormat.pdf:
        return _buildWalletPdf(entries: entries, metadata: metadata);
      case StatementExportFormat.excel:
        return _buildWalletExcel(entries: entries, metadata: metadata);
      case StatementExportFormat.csv:
        return _buildWalletCsv(entries: entries, metadata: metadata);
    }
  }

  Future<StatementExportFile> buildPayeeLedgerExport({
    required StatementExportFormat format,
    required List<PayeePaymentLedgerEntry> entries,
    required StatementExportMetadata metadata,
  }) async {
    switch (format) {
      case StatementExportFormat.pdf:
        return _buildPayeeLedgerPdf(entries: entries, metadata: metadata);
      case StatementExportFormat.excel:
        return _buildPayeeLedgerExcel(entries: entries, metadata: metadata);
      case StatementExportFormat.csv:
        return _buildPayeeLedgerCsv(entries: entries, metadata: metadata);
    }
  }

  Future<StatementExportFile> buildSavingsExport({
    required StatementExportFormat format,
    required List<SavingsStatementEntry> entries,
    required StatementExportMetadata metadata,
  }) async {
    final contributions = entries
        .map(
          (entry) => GroupContribution(
            id: entry.id,
            groupId: entry.groupId,
            userId: entry.groupId,
            contributorName: entry.groupName,
            amount: entry.amount,
            status: entry.status,
            createdAt: entry.createdAt,
            reference: entry.reference,
          ),
        )
        .toList(growable: false);

    switch (format) {
      case StatementExportFormat.pdf:
        return _buildGroupLedgerPdf(
          this,
          entries: contributions,
          metadata: metadata,
        );
      case StatementExportFormat.excel:
        return _buildGroupLedgerExcel(
          this,
          entries: contributions,
          metadata: metadata,
        );
      case StatementExportFormat.csv:
        return _buildGroupLedgerCsv(
          this,
          entries: contributions,
          metadata: metadata,
        );
    }
  }

  Future<StatementExportFile> buildGroupLedgerExport({
    required StatementExportFormat format,
    required List<GroupContribution> entries,
    required StatementExportMetadata metadata,
  }) async {
    switch (format) {
      case StatementExportFormat.pdf:
        return _buildGroupLedgerPdf(this, entries: entries, metadata: metadata);
      case StatementExportFormat.excel:
        return _buildGroupLedgerExcel(
          this,
          entries: entries,
          metadata: metadata,
        );
      case StatementExportFormat.csv:
        return _buildGroupLedgerCsv(this, entries: entries, metadata: metadata);
    }
  }

  String _titleize(String raw) {
    if (raw.trim().isEmpty) {
      return '-';
    }

    return raw
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
