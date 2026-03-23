import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../momo/models/momo_statement.dart';
import '../../../momo/services/momo_statement_export_service.dart';
import '../../models/bank_admin_models.dart';
import 'bank_admin_helpers.dart';

OutlineInputBorder _bankLedgerDropdownBorder(
  CoolSemanticColors colors, {
  Color? borderColor,
  double width = 1,
}) {
  return OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.lg)),
    borderSide: BorderSide(color: borderColor ?? colors.border, width: width),
  );
}

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
  )?
  onExport;
  final bool isExporting;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    if (groups.isEmpty) {
      return const CoolEmptyView(message: 'Link at least one', compact: true);
    }

    final selected = selectedGroupId;
    final selectedExists = groups.any((group) => group.id == selected);
    final resolvedValue = selectedExists ? selected : groups.first.id;

    return Column(
      children: [
        CoolCard(
          backgroundColor: colors.operationalSurface,
          useGradient: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Posted payment ledger',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a group to review and export posted payments',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: resolvedValue,
                decoration: InputDecoration(
                  labelText: 'Custodial group',
                  labelStyle: theme.textTheme.bodySmall?.copyWith(
                    color: colors.tertiaryText,
                    fontWeight: FontWeight.w700,
                  ),
                  filled: true,
                  fillColor: colors.inputSurface,
                  border: _bankLedgerDropdownBorder(colors),
                  enabledBorder: _bankLedgerDropdownBorder(colors),
                  focusedBorder: _bankLedgerDropdownBorder(
                    colors,
                    borderColor: colors.accent,
                    width: 1.4,
                  ),
                ),
                dropdownColor: colors.inputSurface,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w600,
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
          child: CoolAsyncView<MomoStatementPage<PayeePaymentLedgerEntry>>(
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
                      CoolButton(
                        label: isExporting ? 'Exporting...' : 'Export PDF',
                        variant: CoolButtonVariant.secondary,
                        fullWidth: false,
                        isLoading: isExporting,
                        onTap:
                            isExporting ||
                                onExport == null ||
                                page.entries.isEmpty
                            ? null
                            : () => onExport!(
                                StatementExportFormat.pdf,
                                page.entries,
                              ),
                        icon: Icons.picture_as_pdf_outlined,
                      ),
                      CoolButton(
                        label: isExporting ? 'Exporting...' : 'Export Excel',
                        fullWidth: false,
                        isLoading: isExporting,
                        onTap:
                            isExporting ||
                                onExport == null ||
                                page.entries.isEmpty
                            ? null
                            : () => onExport!(
                                StatementExportFormat.excel,
                                page.entries,
                              ),
                        icon: Icons.table_view_rounded,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: page.entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _LedgerEntryCard(entry: page.entries[index]);
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return CoolCard(
      backgroundColor: colors.financialSurface,
      useGradient: false,
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
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(entry.occurredAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${moneyFormat.format(entry.amount)} ${entry.currency}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
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
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
