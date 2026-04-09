part of '../screens/momo_statements_screen.dart';

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
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    if (entries.isEmpty) {
      return CoolEmptyView(
        subtitle: isFilteredView
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
          backgroundColor: colors.cardSurfaceStrong,
          useGradient: false,
          padding: const EdgeInsets.symmetric(
            horizontal: CoolSpace.x4,
            vertical: CoolSpace.x3,
          ),
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
                          entry.payerName ??
                              entry.counterpartyName ??
                              entry.label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.primaryText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: CoolSpace.x1),
                        Text(
                          entry.momoTxId != null
                              ? 'Tx ID: ${entry.momoTxId}'
                              : 'Tx ID pending',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.secondaryText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CoolSpace.x3,
                      vertical: CoolSpace.x2,
                    ),
                    decoration: BoxDecoration(
                      color: (entry.isCredit ? colors.success : colors.warning)
                          .withValues(alpha: 0.12),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(CoolRadii.sm),
                      ),
                    ),
                    child: Text(
                      '${entry.isCredit ? '+' : '-'}${moneyFormat.format(entry.amount)} ${entry.currency}',
                      style: text.mono(
                        theme.textTheme.bodyMedium,
                        fontWeight: FontWeight.w700,
                        color: entry.isCredit ? colors.success : colors.warning,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.payerPhone != null
                          ? (entry.payerPhone!.length >= 4
                                ? '•••• ${entry.payerPhone!.substring(entry.payerPhone!.length - 4)}'
                                : entry.payerPhone!)
                          : entry.counterpartyName ?? 'MoMo Transfer',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                  const SizedBox(width: CoolSpace.x2),
                  Text(
                    dateFormat.format(entry.occurredAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.tertiaryText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x2 + CoolSpace.x1),
              Wrap(
                spacing: CoolSpace.x1 + CoolSpace.x1,
                runSpacing: CoolSpace.x1 + CoolSpace.x1,
                children: [
                  _StatusChip(
                    label: entry.isCredit
                        ? context.l10n.incomingLabel
                        : context.l10n.outgoingLabel,
                    color: entry.isCredit ? colors.success : colors.warning,
                  ),
                  if (entry.ledgerStatus != 'draft' &&
                      entry.ledgerStatus != 'pending')
                    _StatusChip(
                      label: _humanizeToken(entry.ledgerStatus),
                      color: colors.info,
                    ),
                  if ((entry.reference?.trim().isNotEmpty ?? false))
                    _StatusChip(label: 'Ref ready', color: colors.accent),
                ],
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x1),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x3,
        vertical: CoolSpace.x1 + CoolSpace.x1 / 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: color,
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
