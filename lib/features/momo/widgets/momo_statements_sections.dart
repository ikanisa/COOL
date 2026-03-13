part of '../screens/momo_statements_screen.dart';

class StatementOverviewCard extends StatelessWidget {
  const StatementOverviewCard({
    required this.userName,
    required this.officialPhone,
    required this.periodLabel,
    required this.walletCount,
    required this.savingsCount,
    required this.incomingTotal,
    required this.outgoingTotal,
    required this.moneyFormat,
    super.key,
  });

  final String userName;
  final String officialPhone;
  final String periodLabel;
  final int walletCount;
  final int savingsCount;
  final int incomingTotal;
  final int outgoingTotal;
  final NumberFormat moneyFormat;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CoolCard(
      gradient: AppColors.blueGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.statementOverviewTitle,
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$userName  •  $officialPhone',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            periodLabel,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.text3,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(
                label: l10n.walletEntriesMetric,
                value: '$walletCount',
              ),
              _MetricChip(
                label: l10n.savingsEntriesMetric,
                value: '$savingsCount',
              ),
              _MetricChip(
                label: l10n.incomingLabel,
                value: moneyFormat.format(incomingTotal),
              ),
              _MetricChip(
                label: l10n.outgoingLabel,
                value: moneyFormat.format(outgoingTotal),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StatementControlsCard extends StatelessWidget {
  const StatementControlsCard({
    required this.selectedPeriod,
    required this.selectedParty,
    required this.selectedSort,
    required this.activePartyLabel,
    required this.allPartyLabel,
    required this.partyOptions,
    required this.isExporting,
    required this.canExport,
    required this.onSelectPeriod,
    required this.onPartyChanged,
    required this.onSortChanged,
    required this.onReset,
    required this.onDownloadPdf,
    required this.onDownloadExcel,
    this.customPeriodLabel,
    super.key,
  });

  final StatementPeriodPreset selectedPeriod;
  final String? selectedParty;
  final StatementSortOption selectedSort;
  final String activePartyLabel;
  final String allPartyLabel;
  final List<String> partyOptions;
  final String? customPeriodLabel;
  final bool isExporting;
  final bool canExport;
  final Future<void> Function(StatementPeriodPreset period) onSelectPeriod;
  final ValueChanged<String?> onPartyChanged;
  final ValueChanged<StatementSortOption?> onSortChanged;
  final VoidCallback onReset;
  final VoidCallback onDownloadPdf;
  final VoidCallback onDownloadExcel;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filters and exports',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: StatementPeriodPreset.values
                .map(
                  (period) => ChoiceChip(
                    key: ValueKey<String>('statement-period-${period.name}'),
                    label: Text(_periodLabel(context, period)),
                    selected: selectedPeriod == period,
                    onSelected: (_) => onSelectPeriod(period),
                    labelStyle: GoogleFonts.dmSans(
                      color: selectedPeriod == period
                          ? Colors.black
                          : AppColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                    backgroundColor: AppColors.surface2,
                    selectedColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.border2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          if (selectedPeriod == StatementPeriodPreset.custom &&
              customPeriodLabel != null) ...[
            const SizedBox(height: 10),
            Text(
              customPeriodLabel!,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text3,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  key: const ValueKey<String>('statement-party-filter'),
                  isExpanded: true,
                  initialValue: selectedParty,
                  decoration: _dropdownDecoration(activePartyLabel),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(allPartyLabel),
                    ),
                    ...partyOptions.map(
                      (party) => DropdownMenuItem<String?>(
                        value: party,
                        child: Text(party),
                      ),
                    ),
                  ],
                  onChanged: onPartyChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<StatementSortOption>(
                  key: const ValueKey<String>('statement-sort-filter'),
                  isExpanded: true,
                  initialValue: selectedSort,
                  decoration: _dropdownDecoration('Sort by'),
                  items: StatementSortOption.values
                      .map(
                        (sort) => DropdownMenuItem<StatementSortOption>(
                          value: sort,
                          child: Text(_sortLabel(context, sort)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: onSortChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CoolButton(
                  label: 'Reset',
                  variant: CoolButtonVariant.secondary,
                  onTap: onReset,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CoolButton(
                  label: isExporting ? 'Preparing...' : 'PDF',
                  icon: Icons.picture_as_pdf_rounded,
                  onTap: canExport && !isExporting ? onDownloadPdf : _noop,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CoolButton(
                  label: isExporting ? 'Preparing...' : 'Excel',
                  icon: Icons.table_view_rounded,
                  onTap: canExport && !isExporting ? onDownloadExcel : _noop,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _dropdownDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppColors.surface2,
      labelStyle: GoogleFonts.dmSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.text3,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
    );
  }

  String _periodLabel(BuildContext context, StatementPeriodPreset period) {
    return switch (period) {
      StatementPeriodPreset.day => 'Day',
      StatementPeriodPreset.week => 'Week',
      StatementPeriodPreset.month => 'Month',
      StatementPeriodPreset.custom => 'Custom',
      StatementPeriodPreset.all => 'All time',
    };
  }

  String _sortLabel(BuildContext context, StatementSortOption sort) {
    return switch (sort) {
      StatementSortOption.newestFirst => 'Newest first',
      StatementSortOption.oldestFirst => 'Oldest first',
      StatementSortOption.amountHighToLow => 'Amount high to low',
      StatementSortOption.amountLowToHigh => 'Amount low to high',
      StatementSortOption.nameAz => 'Name A-Z',
      StatementSortOption.nameZa => 'Name Z-A',
    };
  }
}

class WalletStatementTab extends StatelessWidget {
  const WalletStatementTab({
    required this.entries,
    required this.totalCount,
    required this.dateFormat,
    required this.moneyFormat,
    required this.isFilteredView,
    super.key,
  });

  final List<MomoWalletEntry> entries;
  final int totalCount;
  final DateFormat dateFormat;
  final NumberFormat moneyFormat;
  final bool isFilteredView;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return CoolEmptyView(
        message: isFilteredView
            ? 'Try another period, payer, or sort option.'
            : context.l10n.walletEmptyMessage,
        icon: Icons.receipt_long_rounded,
      );
    }

    return ListView.separated(
      itemCount: entries.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SectionLead(
            title: context.l10n.walletLedgerTitle,
            subtitle: context.l10n.walletLedgerSubtitle(
              entries.length,
              totalCount,
            ),
          );
        }

        final entry = entries[index - 1];
        return CoolCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color:
                          (entry.isCredit ? AppColors.accent : AppColors.orange)
                              .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      entry.isCredit
                          ? Icons.south_west_rounded
                          : Icons.north_east_rounded,
                      color: entry.isCredit
                          ? AppColors.accent
                          : AppColors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.label,
                          style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFormat.format(entry.occurredAt),
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${entry.isCredit ? '+' : '-'}${moneyFormat.format(entry.amount)} ${entry.currency}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: entry.isCredit
                          ? AppColors.accent
                          : AppColors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusChip(
                    label: entry.isCredit
                        ? context.l10n.incomingLabel
                        : context.l10n.outgoingLabel,
                    color: entry.isCredit ? AppColors.accent : AppColors.orange,
                  ),
                  _StatusChip(
                    label: _humanizeToken(entry.txCategory),
                    color: AppColors.blue,
                  ),
                  _StatusChip(
                    label: _humanizeToken(entry.cashflowBucket),
                    color: AppColors.yellow,
                  ),
                  _StatusChip(
                    label: _humanizeToken(entry.ledgerStatus),
                    color: AppColors.purple,
                  ),
                ],
              ),
              if (entry.counterpartyName != null)
                _DetailLine(
                  label: context.l10n.counterpartyLabel,
                  value: entry.counterpartyName!,
                ),
              if (entry.reference != null)
                _DetailLine(
                  label: context.l10n.referenceLabel,
                  value: entry.reference!,
                ),
              if (entry.description != null)
                _DetailLine(
                  label: context.l10n.detailsLabel,
                  value: entry.description!,
                ),
            ],
          ),
        );
      },
    );
  }
}

class SavingsStatementTab extends StatelessWidget {
  const SavingsStatementTab({
    required this.entries,
    required this.totalCount,
    required this.dateFormat,
    required this.moneyFormat,
    required this.isFilteredView,
    super.key,
  });

  final List<SavingsStatementEntry> entries;
  final int totalCount;
  final DateFormat dateFormat;
  final NumberFormat moneyFormat;
  final bool isFilteredView;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return CoolEmptyView(
        message: isFilteredView
            ? 'Try another period, group, or sort option.'
            : context.l10n.savingsEmptyMessage,
        icon: Icons.groups_2_rounded,
      );
    }

    return ListView.separated(
      itemCount: entries.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SectionLead(
            title: context.l10n.savingsStatementTitle,
            subtitle: context.l10n.savingsStatementSubtitle(
              entries.length,
              totalCount,
            ),
          );
        }

        final entry = entries[index - 1];
        return CoolCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.blueGlow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.groups_2_rounded,
                      color: AppColors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.groupName,
                          style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFormat.format(entry.createdAt),
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${moneyFormat.format(entry.amount)} ${context.l10n.rwf}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusChip(
                    label: entry.isConfirmed
                        ? context.l10n.confirmed
                        : context.l10n.pending,
                    color: entry.isConfirmed
                        ? AppColors.accent
                        : AppColors.yellow,
                  ),
                  _StatusChip(
                    label: context.l10n.savingsLabel,
                    color: AppColors.blue,
                  ),
                ],
              ),
              if (entry.reference != null)
                _DetailLine(
                  label: context.l10n.referenceLabel,
                  value: entry.reference!,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLead extends StatelessWidget {
  const _SectionLead({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.dmSans(color: AppColors.text),
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: label,
              style: const TextStyle(
                color: AppColors.text3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.text3,
            height: 1.45,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

String _humanizeToken(String value) {
  return value
      .split('_')
      .where((part) => part.trim().isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

void _noop() {}
