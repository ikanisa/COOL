part of '../screens/momo_statements_screen.dart';

class StatementOverviewCard extends StatelessWidget {
  const StatementOverviewCard({
    required this.selectedPeriod,
    required this.periodSummary,
    required this.optionsSummary,
    required this.onSelectPeriod,
    required this.onOpenOptions,
    super.key,
  });

  final StatementPeriodPreset selectedPeriod;
  final String periodSummary;
  final String optionsSummary;
  final Future<void> Function(StatementPeriodPreset period) onSelectPeriod;
  final VoidCallback onOpenOptions;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: PopupMenuButton<StatementPeriodPreset>(
                  key: const ValueKey<String>('statement-period-selector'),
                  tooltip: 'Change statement period',
                  onSelected: (period) => unawaited(onSelectPeriod(period)),
                  itemBuilder: (context) => StatementPeriodPreset.values
                      .map(
                        (period) => PopupMenuItem<StatementPeriodPreset>(
                          value: period,
                          child: Text(_statementPeriodLabel(period)),
                        ),
                      )
                      .toList(growable: false),
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: palette.surface2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_month_rounded,
                          size: 18,
                          color: palette.text,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Period',
                                style: GoogleFonts.dmSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: palette.text3,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                _statementPeriodLabel(selectedPeriod),
                                style: GoogleFonts.dmSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: palette.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.expand_more_rounded, color: palette.text2),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 112,
                height: 52,
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('statement-open-options'),
                  onPressed: onOpenOptions,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('More'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.text,
                    side: BorderSide(color: palette.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    backgroundColor: palette.surface2,
                    textStyle: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            periodSummary,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            optionsSummary,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: palette.text3,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class StatementOptionsSheet extends StatefulWidget {
  const StatementOptionsSheet({
    required this.activePartyLabel,
    required this.allPartyLabel,
    required this.partyOptions,
    required this.initialParty,
    required this.initialSort,
    required this.canExport,
    required this.onApply,
    required this.onReset,
    required this.onDownloadPdf,
    required this.onDownloadExcel,
    super.key,
  });

  final String activePartyLabel;
  final String allPartyLabel;
  final List<String> partyOptions;
  final String? initialParty;
  final StatementSortOption initialSort;
  final bool canExport;
  final void Function(String? party, StatementSortOption sort) onApply;
  final VoidCallback onReset;
  final VoidCallback onDownloadPdf;
  final VoidCallback onDownloadExcel;

  @override
  State<StatementOptionsSheet> createState() => _StatementOptionsSheetState();
}

class _StatementOptionsSheetState extends State<StatementOptionsSheet> {
  late String? _selectedParty = widget.initialParty;
  late StatementSortOption _selectedSort = widget.initialSort;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomInset + 12),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'View options',
                      style: GoogleFonts.dmSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: palette.text,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
              Text(
                'Adjust the visible list',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: palette.text2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              const _OptionsSectionTitle('Filters'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const ValueKey<String>('statement-party-filter'),
                isExpanded: true,
                initialValue: _selectedParty,
                decoration: _optionsDropdownDecoration(
                  context,
                  widget.activePartyLabel,
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(widget.allPartyLabel),
                  ),
                  ...widget.partyOptions.map(
                    (party) => DropdownMenuItem<String?>(
                      value: party,
                      child: Text(party),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _selectedParty = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<StatementSortOption>(
                key: const ValueKey<String>('statement-sort-filter'),
                isExpanded: true,
                initialValue: _selectedSort,
                decoration: _optionsDropdownDecoration(context, 'Sort by'),
                items: StatementSortOption.values
                    .map(
                      (sort) => DropdownMenuItem<StatementSortOption>(
                        value: sort,
                        child: Text(_statementSortLabel(sort)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => _selectedSort = value);
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: CoolButton(
                      label: 'Reset',
                      variant: CoolButtonVariant.secondary,
                      onTap: () {
                        widget.onReset();
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CoolButton(
                      label: 'Apply filters',
                      onTap: () {
                        widget.onApply(_selectedParty, _selectedSort);
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _OptionsSectionTitle('Export current results'),
              const SizedBox(height: 6),
              Text(
                'PDF and Excel use',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: palette.text3,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: CoolButton(
                      label: 'PDF',
                      icon: Icons.picture_as_pdf_rounded,
                      onTap: widget.canExport
                          ? () {
                              Navigator.of(context).pop();
                              widget.onDownloadPdf();
                            }
                          : _noop,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CoolButton(
                      label: 'Excel',
                      icon: Icons.table_view_rounded,
                      onTap: widget.canExport
                          ? () {
                              Navigator.of(context).pop();
                              widget.onDownloadExcel();
                            }
                          : _noop,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _optionsDropdownDecoration(BuildContext context, String label) {
  final palette = context.coolPalette;
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: palette.surface2,
    labelStyle: GoogleFonts.dmSans(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: palette.text3,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: palette.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: palette.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: palette.accent),
    ),
  );
}

class _OptionsSectionTitle extends StatelessWidget {
  const _OptionsSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Text(
      label,
      style: GoogleFonts.dmSans(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: palette.text,
      ),
    );
  }
}

String _statementPeriodLabel(StatementPeriodPreset period) {
  return switch (period) {
    StatementPeriodPreset.day => 'Day',
    StatementPeriodPreset.week => 'Week',
    StatementPeriodPreset.month => 'Month',
    StatementPeriodPreset.year => 'Year',
    StatementPeriodPreset.custom => 'Custom',
    StatementPeriodPreset.all => 'All time',
  };
}

String _statementSortLabel(StatementSortOption sort) {
  return switch (sort) {
    StatementSortOption.newestFirst => 'Newest first',
    StatementSortOption.oldestFirst => 'Oldest first',
    StatementSortOption.amountHighToLow => 'Amount high to low',
    StatementSortOption.amountLowToHigh => 'Amount low to high',
    StatementSortOption.nameAz => 'Name A-Z',
    StatementSortOption.nameZa => 'Name Z-A',
  };
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
    final palette = context.coolPalette;
    if (entries.isEmpty) {
      return CoolEmptyView(
        message: isFilteredView
            ? 'Adjust filters'
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
                      color: (entry.isCredit ? palette.accent : palette.orange)
                          .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      entry.isCredit
                          ? Icons.south_west_rounded
                          : Icons.north_east_rounded,
                      color: entry.isCredit ? palette.accent : palette.orange,
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
                            color: palette.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFormat.format(entry.occurredAt),
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: palette.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${entry.isCredit ?'+' : '-'}${moneyFormat.format(entry.amount)} ${entry.currency}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: entry.isCredit ? palette.accent : palette.orange,
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
                    color: entry.isCredit ? palette.accent : palette.orange,
                  ),
                  _StatusChip(
                    label: _humanizeToken(entry.txCategory),
                    color: palette.blue,
                  ),
                  _StatusChip(
                    label: _humanizeToken(entry.cashflowBucket),
                    color: palette.yellow,
                  ),
                  _StatusChip(
                    label: _humanizeToken(entry.ledgerStatus),
                    color: palette.purple,
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
    final palette = context.coolPalette;
    if (entries.isEmpty) {
      return CoolEmptyView(
        message: isFilteredView
            ? 'Adjust filters'
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
                      color: palette.blueGlow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.groups_2_rounded, color: palette.blue),
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
                            color: palette.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateFormat.format(entry.createdAt),
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: palette.text3,
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
                      color: palette.accent,
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
                    color: entry.isConfirmed ? palette.accent : palette.yellow,
                  ),
                  _StatusChip(
                    label: context.l10n.savingsLabel,
                    color: palette.blue,
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
    final palette = context.coolPalette;
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
              color: palette.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: palette.text3,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewMetricTile extends StatelessWidget {
  const _OverviewMetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: palette.text3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
        ],
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
    final palette = context.coolPalette;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: palette.text3,
            height: 1.45,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: palette.text2,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

String _humanizeToken(String raw) {
  return raw
      .split('_')
      .where((part) => part.trim().isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

void _noop() {}
