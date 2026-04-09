part of '../screens/momo_statements_screen.dart';

class StatementOverviewCard extends StatelessWidget {
  const StatementOverviewCard({
    required this.selectedPeriod,
    required this.periodSummary,
    required this.optionsSummary,
    required this.netBalance,
    required this.inflow,
    required this.outflow,
    required this.onSelectPeriod,
    required this.onOpenOptions,
    super.key,
  });

  final StatementPeriodPreset selectedPeriod;
  final String periodSummary;
  final String optionsSummary;
  final int netBalance;
  final int inflow;
  final int outflow;
  final Future<void> Function(StatementPeriodPreset period) onSelectPeriod;
  final VoidCallback onOpenOptions;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final space = context.coolSpace;
    final moneyFormat = decimalMoneyFormatForLocale(context);
    return CoolCard(
      backgroundColor: colors.financialSurface,
      borderRadius: CoolRadii.lg,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${netBalance >= 0 ? '' : '-'}${moneyFormat.format(netBalance.abs())} ${context.l10n.rwf}',
            style: text.mono(
              theme.textTheme.headlineMedium,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
              height: 1.05,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Wrap(
            spacing: space.x2,
            runSpacing: space.x2,
            children: [
              _SummaryMetric(
                label: 'Inflow',
                value: '${moneyFormat.format(inflow)} ${context.l10n.rwf}',
                accentColor: colors.success,
              ),
              _SummaryMetric(
                label: 'Outflow',
                value: '${moneyFormat.format(outflow)} ${context.l10n.rwf}',
                accentColor: colors.warning,
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),
          Row(
            children: [
              Expanded(
                child: PopupMenuButton<StatementPeriodPreset>(
                  key: const ValueKey<String>('statement-period-selector'),
                  tooltip: context.l10n.changeStatementPeriod,
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
                    height: CoolTapTargets.comfortable,
                    padding: const EdgeInsets.symmetric(
                      horizontal: CoolSpace.x4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.inputSurface,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(CoolRadii.sm),
                      ),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_month_rounded,
                          size: 18,
                          color: colors.primaryText,
                        ),
                        const SizedBox(width: CoolSpace.x2 + CoolSpace.x1),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Period',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colors.secondaryText,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                _statementPeriodLabel(selectedPeriod),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.primaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.expand_more_rounded,
                          color: colors.secondaryText,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: CoolSpace.x3),
              SizedBox(
                width: 128,
                height: CoolTapTargets.comfortable,
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('statement-open-options'),
                  onPressed: onOpenOptions,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(context.l10n.more),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.primaryText,
                    side: BorderSide(color: colors.border),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(CoolRadii.sm),
                      ),
                    ),
                    backgroundColor: colors.inputSurface,
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: CoolSpace.x4,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            periodSummary,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x1),
          Text(
            optionsSummary,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        CoolSpace.x3,
        0,
        CoolSpace.x3,
        bottomInset + CoolSpace.x3,
      ),
      child: Material(
        color: colors.overlaySurface,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.lg)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: CoolSpace.denseSectionPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'View options',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: context.l10n.close,
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x5 - CoolSpace.x1),
              const _OptionsSectionTitle('Filters'),
              const SizedBox(height: CoolSpace.x3),
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
              const SizedBox(height: CoolSpace.x3),
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
              const SizedBox(height: CoolSpace.x4),
              Row(
                children: [
                  Expanded(
                    child: CoolButton(
                      key: const ValueKey<String>('statement-reset-filters'),
                      label: context.l10n.reset,
                      variant: CoolButtonVariant.secondary,
                      onTap: () {
                        widget.onReset();
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                  const SizedBox(width: CoolSpace.x3),
                  Expanded(
                    child: CoolButton(
                      key: const ValueKey<String>('statement-apply-filters'),
                      label: context.l10n.applyFilters,
                      onTap: () {
                        widget.onApply(_selectedParty, _selectedSort);
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x5),
              const _OptionsSectionTitle('Export current results'),
              const SizedBox(height: CoolSpace.x3),
              Row(
                children: [
                  Expanded(
                    child: CoolButton(
                      key: const ValueKey<String>('statement-export-pdf'),
                      label: context.l10n.pdf,
                      icon: Icons.picture_as_pdf_rounded,
                      onTap: widget.canExport
                          ? () {
                              Navigator.of(context).pop();
                              widget.onDownloadPdf();
                            }
                          : _noop,
                    ),
                  ),
                  const SizedBox(width: CoolSpace.x3),
                  Expanded(
                    child: CoolButton(
                      key: const ValueKey<String>('statement-export-excel'),
                      label: context.l10n.excel,
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
  final colors = context.coolSemanticColors;
  final theme = Theme.of(context);
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: colors.inputSurface,
    labelStyle: theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: colors.secondaryText,
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: CoolSpace.x4,
      vertical: CoolSpace.x3,
    ),
    border: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
      borderSide: BorderSide(color: colors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
      borderSide: BorderSide(color: colors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
      borderSide: BorderSide(color: colors.accent),
    ),
  );
}

class _OptionsSectionTitle extends StatelessWidget {
  const _OptionsSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: colors.primaryText,
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final text = context.coolText;
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x3,
        vertical: CoolSpace.x2 + CoolSpace.x1,
      ),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: accentColor,
            ),
          ),
          const SizedBox(height: CoolSpace.x1 + CoolSpace.x1),
          Text(
            value,
            style: text.mono(
              theme.textTheme.bodyMedium,
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }
}
