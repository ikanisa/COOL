part of 'group_ledger_screen.dart';

class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.selectedPeriod,
    required this.selectedContributorId,
    required this.members,
    required this.onPeriodChanged,
    required this.onContributorChanged,
  });

  final _LedgerPeriod selectedPeriod;
  final String? selectedContributorId;
  final List<GroupMember> members;
  final ValueChanged<_LedgerPeriod> onPeriodChanged;
  final ValueChanged<String?> onContributorChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CoolSpace.x4,
        CoolSpace.x2,
        CoolSpace.x4,
        CoolSpace.x1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _LedgerPeriod.values.map((period) {
                final isSelected = period == selectedPeriod;
                final label = switch (period) {
                  _LedgerPeriod.week => context.l10n.week,
                  _LedgerPeriod.month => context.l10n.month,
                  _LedgerPeriod.year => context.l10n.year,
                  _LedgerPeriod.all => context.l10n.allTime,
                };
                return Padding(
                  padding: const EdgeInsets.only(right: CoolSpace.x2),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: isSelected,
                    showCheckmark: false,
                    selectedColor: colors.accent,
                    backgroundColor: colors.cardSurface,
                    labelStyle: theme.textTheme.labelMedium?.copyWith(
                      color: isSelected
                          ? colors.accentForeground
                          : colors.secondaryText,
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide.none,
                    onSelected: (_) => onPeriodChanged(period),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          if (members.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: CoolSpace.x3),
              decoration: BoxDecoration(
                color: colors.cardSurface,
                borderRadius: const BorderRadius.all(
                  Radius.circular(CoolRadii.xs),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: selectedContributorId,
                  isExpanded: true,
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colors.tertiaryText,
                  ),
                  dropdownColor: colors.elevatedBackground,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                  hint: Text(
                    context.l10n.allContributors,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.tertiaryText,
                    ),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(context.l10n.allContributors),
                    ),
                    ...members.map(
                      (member) => DropdownMenuItem<String?>(
                        value: member.userId,
                        child: Text(
                          member.displayName ?? _shortUserId(member.userId),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: onContributorChanged,
                ),
              ),
            ),
          const SizedBox(height: CoolSpace.x2),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.entries});

  final List<GroupContribution> entries;

  static final _amountFmt = NumberFormat.decimalPattern('en_US');

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.amount);
    final contributors = entries.map((entry) => entry.userId).toSet().length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CoolSpace.x4,
        0,
        CoolSpace.x4,
        CoolSpace.x2,
      ),
      child: CoolCard(
        backgroundColor: colors.financialSurface,
        borderColor: colors.border,
        padding: const EdgeInsets.all(CoolSpace.x4),
        child: Row(
          children: [
            Expanded(
              child: _MetricColumn(
                label: context.l10n.total,
                value: 'RWF ${_amountFmt.format(total)}',
                color: colors.accent,
              ),
            ),
            Container(width: 1, height: 36, color: colors.cardSurfaceStrong),
            Expanded(
              child: _MetricColumn(
                label: context.l10n.contributorsLabel,
                value: contributors.toString(),
                color: colors.info,
              ),
            ),
            Container(width: 1, height: 36, color: colors.cardSurfaceStrong),
            Expanded(
              child: _MetricColumn(
                label: context.l10n.entries,
                value: entries.length.toString(),
                color: colors.teamSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: text.mono(
            theme.textTheme.titleMedium,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: CoolSpace.x1),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.secondaryText,
          ),
        ),
      ],
    );
  }
}

class _ContributionTile extends StatelessWidget {
  const _ContributionTile({required this.entry});

  final GroupContribution entry;

  static final _dateFmt = DateFormat('dd MMM yyyy, HH:mm');
  static final _amountFmt = NumberFormat.decimalPattern('en_US');

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final statusColor = switch (entry.status) {
      'confirmed' || 'completed' => colors.accent,
      'pending' => colors.warning,
      'failed' => colors.danger,
      _ => colors.tertiaryText,
    };

    return CoolCard(
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x4,
        vertical: CoolSpace.x4 - 2,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: colors.cardSurfaceStrong,
            child: Text(
              (entry.contributorName ?? '?')[0].toUpperCase(),
              style: theme.textTheme.titleSmall?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: CoolSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.contributorName ?? 'Unknown',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: CoolSpace.x1 / 2),
                Text(
                  entry.createdAt != null
                      ? _dateFmt.format(entry.createdAt!)
                      : '-',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.tertiaryText,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'RWF ${_amountFmt.format(entry.amount)}',
                style: text.mono(
                  theme.textTheme.bodyLarge,
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: CoolSpace.x1 / 2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: CoolSpace.x2,
                  vertical: CoolSpace.x1 / 2,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.xs / 2),
                  ),
                ),
                child: Text(
                  _titleize(entry.status),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _titleize(String raw) {
    if (raw.trim().isEmpty) return '-';
    return raw
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

class _ExportFormatSheet extends StatelessWidget {
  const _ExportFormatSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.borderStrong,
              borderRadius: BorderRadius.all(Radius.circular(radii.xs)),
            ),
          ),
        ),
        const SizedBox(height: CoolSpace.x5),
        Text(
          context.l10n.exportLedger,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.primaryText,
          ),
        ),
        const SizedBox(height: CoolSpace.x1),
        Text(
          context.l10n.chooseExportFormat,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.secondaryText),
        ),
        const SizedBox(height: CoolSpace.x5),
        _ExportOption(
          icon: Icons.picture_as_pdf_rounded,
          label: 'PDF',
          subtitle: context.l10n.printReadyStatement,
          color: colors.danger,
          onTap: () => Navigator.pop(context, StatementExportFormat.pdf),
        ),
        const SizedBox(height: CoolSpace.x2),
        _ExportOption(
          icon: Icons.table_chart_rounded,
          label: 'Excel',
          subtitle: context.l10n.spreadsheetHeaders,
          color: colors.accent,
          onTap: () => Navigator.pop(context, StatementExportFormat.excel),
        ),
        const SizedBox(height: CoolSpace.x2),
        _ExportOption(
          icon: Icons.text_snippet_rounded,
          label: 'CSV',
          subtitle: context.l10n.plainTextData,
          color: colors.info,
          onTap: () => Navigator.pop(context, StatementExportFormat.csv),
        ),
      ],
    );
  }
}

class _ExportOption extends StatelessWidget {
  const _ExportOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    return Material(
      color: colors.cardSurface,
      borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
      child: InkWell(
        borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CoolSpace.x4,
            vertical: CoolSpace.x4 - 2,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.xs),
                  ),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: CoolSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.tertiaryText),
            ],
          ),
        ),
      ),
    );
  }
}

String _shortUserId(String userId, [int length = 8]) {
  final end = userId.length < length ? userId.length : length;
  return userId.substring(0, end);
}
