part of 'bank_admin_workspace_screen.dart';

// ═══════════════════════════════════════════════════════════════
// Tab row
// ═══════════════════════════════════════════════════════════════

class _TabRow extends StatelessWidget {
  const _TabRow({required this.activeTab, required this.onTabChanged});

  final _BankWorkspaceTab activeTab;
  final ValueChanged<_BankWorkspaceTab> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final tab in _BankWorkspaceTab.values) ...[
            ChoiceChip(
              showCheckmark: false,
              label: Text(tab.name.toUpperCase()),
              selected: activeTab == tab,
              onSelected: (_) {
                HapticFeedback.selectionClick();
                onTabChanged(tab);
              },
              backgroundColor: colors.chipBackground,
              selectedColor: colors.chipSelectedBackground,
              labelStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: activeTab == tab
                    ? colors.accentStrong
                    : colors.secondaryText,
              ),
              side: BorderSide.none,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(CoolRadii.pill)),
              ),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Overview tab
// ═══════════════════════════════════════════════════════════════

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.snapshot,
    required this.onViewDetails,
    required this.onOpenLedger,
  });

  final BankAdminWorkspaceSnapshot snapshot;
  final void Function(String groupId) onViewDetails;
  final void Function(String groupId) onOpenLedger;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final group = snapshot.groups.entries.firstOrNull;

    if (group == null) {
      return const CoolEmptyView(
        message: 'No linked groups.',
        icon: CoolIcons.groupOff,
      );
    }

    final members = snapshot.members.entries
        .where((entry) => entry.groupId == group.id)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoolCard(
          backgroundColor: colors.operationalSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.group.name,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: CoolSpace.x2),
              Text(
                '${snapshot.allocations.totalCount} manual review',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: CoolSpace.x4),
              Row(
                children: [
                  _ActionChip(
                    label: 'View details',
                    icon: CoolIcons.visibility,
                    onTap: () => onViewDetails(group.id),
                  ),
                  const SizedBox(width: CoolSpace.x2),
                  _ActionChip(
                    label: 'Open ledger',
                    icon: CoolIcons.receiptOutlined,
                    onTap: () => onOpenLedger(group.id),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (members.isNotEmpty) ...[
          const SizedBox(height: CoolSpace.x5),
          const AdminSectionHeader(title: 'Group Members'),
          const SizedBox(height: CoolSpace.x3),
          for (final member in members) ...[
            CoolCard(
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.info.withValues(alpha: 0.12),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(CoolRadii.xs),
                      ),
                    ),
                    child: Icon(
                      CoolIcons.person,
                      size: 18,
                      color: colors.info,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      member.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CoolSpace.x2),
          ],
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Allocations tab
// ═══════════════════════════════════════════════════════════════

class _AllocationsTab extends StatelessWidget {
  const _AllocationsTab({
    required this.snapshot,
    required this.onAllocate,
    required this.onReject,
  });

  final BankAdminWorkspaceSnapshot snapshot;
  final Future<void> Function(BankAdminAllocationReviewItem item) onAllocate;
  final Future<void> Function(BankAdminAllocationReviewItem item) onReject;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    if (snapshot.allocations.entries.isEmpty) {
      return const CoolEmptyView(
        message: 'No manual review items.',
        icon: CoolIcons.checkCircleOutlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in snapshot.allocations.entries) ...[
          CoolCard(
            backgroundColor: colors.operationalSurface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colors.warning.withValues(alpha: 0.12),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(CoolRadii.xs),
                        ),
                      ),
                      child: Icon(
                        CoolIcons.pendingActions,
                        size: 16,
                        color: colors.warning,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.groupName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CoolSpace.x4),
                Row(
                  children: [
                    _ActionChip(
                      label: 'Allocate',
                      icon: CoolIcons.check,
                      onTap: () => onAllocate(item),
                    ),
                    const SizedBox(width: CoolSpace.x2),
                    _ActionChip(
                      label: 'Reject',
                      icon: CoolIcons.close,
                      isDestructive: true,
                      onTap: () => onReject(item),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Ledgers tab
// ═══════════════════════════════════════════════════════════════

class _LedgersTab extends StatelessWidget {
  const _LedgersTab({
    required this.ledgerAsync,
    required this.onExportPdf,
    required this.onExportExcel,
  });

  final AsyncValue<MomoStatementPage<PayeePaymentLedgerEntry>> ledgerAsync;
  final Future<void> Function() onExportPdf;
  final Future<void> Function() onExportExcel;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return CoolAsyncView<MomoStatementPage<PayeePaymentLedgerEntry>>(
      value: ledgerAsync,
      onRetry: () {},
      loadingWidget: const CoolSkeletonList(itemCount: 4),
      emptyCheck: (page) => page.entries.isEmpty,
      emptyWidget: const CoolEmptyView(
        message: 'No posted payment ledger entries.',
        icon: CoolIcons.receiptOutlined,
      ),
      builder: (page) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Posted payment ledger',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: onExportPdf,
                      tooltip: 'Export PDF',
                      icon: Icon(
                        CoolIcons.pdfRounded,
                        color: colors.primaryText,
                      ),
                    ),
                    IconButton(
                      onPressed: onExportExcel,
                      tooltip: 'Export Excel',
                      icon: Icon(
                        CoolIcons.gridOn,
                        color: colors.primaryText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: CoolSpace.x3),
            for (final entry in page.entries) ...[
              CoolCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.label,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.primaryText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.payerName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.tertiaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${formatWholeMoneyAmount(entry.amount)} RWF',
                      style: context.coolText.mono(
                        theme.textTheme.titleSmall,
                        fontWeight: FontWeight.w800,
                        color: colors.success,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CoolSpace.x2),
            ],
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Action chip (shared)
// ═══════════════════════════════════════════════════════════════

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final color = isDestructive ? colors.danger : colors.accent;

    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(CoolRadii.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(CoolRadii.sm),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
