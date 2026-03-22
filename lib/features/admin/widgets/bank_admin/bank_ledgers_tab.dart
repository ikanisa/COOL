import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/cool_palette.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../momo/models/momo_statement.dart';
import '../../../momo/services/momo_statement_export_service.dart';
import '../../models/bank_admin_models.dart';
import 'bank_admin_helpers.dart';

class BankLedgersTab extends StatelessWidget {
  const BankLedgersTab({
    required this.groups,
    required this.selectedGroupId,
    required this.onSelectedGroupChanged,
    required this.ledgerAsync,
    required this.onRetry,
    required this.onExport,
    required this.isExporting,
    super.key,
  });

  final List<BankAdminGroupSummary> groups;
  final String? selectedGroupId;
  final ValueChanged<String?> onSelectedGroupChanged;
  final AsyncValue<MomoStatementPage<PayeePaymentLedgerEntry>> ledgerAsync;
  final VoidCallback? onRetry;
  final Future<void> Function(
    StatementExportFormat format,
    List<PayeePaymentLedgerEntry> entries,
  )? onExport;
  final bool isExporting;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    if (groups.isEmpty) {
      return const CoolEmptyView(
        message: 'Link at least one',
        compact: true,
      );
    }

    final selected = selectedGroupId;
    final selectedExists = groups.any((group) => group.id == selected);
    final resolvedValue = selectedExists ? selected : groups.first.id;

    return Column(
      children: [
        CoolCard(
          backgroundColor: palette.surface,
          borderColor: palette.border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Posted payment ledger',
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a group to',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: palette.text2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: resolvedValue,
                decoration: const InputDecoration(
                  labelText: 'Custodial group',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: groups
                    .map(
                      (group) => DropdownMenuItem<String>(
                        value: group.id,
                        child: Text(group.group.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: onSelectedGroupChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child:
              CoolAsyncView<MomoStatementPage<PayeePaymentLedgerEntry>>(
            value: ledgerAsync,
            onRetry: onRetry,
            emptyCheck: (page) => page.entries.isEmpty,
            emptyWidget: const CoolEmptyView(
              message: 'No posted ledger entries',
              compact: true,
            ),
            builder: (page) => Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: isExporting ||
                                onExport == null ||
                                page.entries.isEmpty
                            ? null
                            : () => onExport!(
                                  StatementExportFormat.pdf,
                                  page.entries,
                                ),
                        icon: isExporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf_outlined),
                        label: Text(
                          isExporting ? 'Exporting...' : 'Export PDF',
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: isExporting ||
                                onExport == null ||
                                page.entries.isEmpty
                            ? null
                            : () => onExport!(
                                  StatementExportFormat.excel,
                                  page.entries,
                                ),
                        icon: isExporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.table_view_rounded),
                        label: Text(
                          isExporting ? 'Exporting...' : 'Export Excel',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: page.entries.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final entry = page.entries[index];
                      return _LedgerEntryCard(entry: entry);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LedgerEntryCard extends StatelessWidget {
  const _LedgerEntryCard({required this.entry});

  final PayeePaymentLedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return CoolCard(
      backgroundColor: palette.surface,
      borderColor: palette.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.payerName,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(entry.occurredAt),
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: palette.text2,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${moneyFormat.format(entry.amount)} ${entry.currency}',
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              BankInfoPill(
                label: 'Category',
                value: bankTitle(entry.txCategory),
              ),
              BankInfoPill(
                label: 'Bucket',
                value: bankTitle(entry.cashflowBucket),
              ),
              BankInfoPill(
                label: 'Target',
                value: bankTitle(entry.targetTable),
              ),
              BankInfoPill(
                label: 'Reference',
                value: entry.reference?.trim().isNotEmpty == true
                    ? entry.reference!
                    : '-',
              ),
            ],
          ),
          if ((entry.payerPhone?.trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: 8),
            Text(
              'Phone: ${entry.payerPhone}',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: palette.text2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
