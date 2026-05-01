part of 'group_statements_screen.dart';

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.colors);

  final CoolSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      borderRadius: CoolRadii.xl,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colors.cardSurfaceStrong,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(CoolIcons.history, color: colors.accent, size: 32),
          ),
          const SizedBox(height: CoolSpace.x4),
          Text(
            context.l10n.groupStatementsNoTransactionsYetUpper,
            style: context.coolText.displayCondensed(
              Theme.of(context).textTheme.titleLarge,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            context.l10n.groupStatementsEmptyMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.secondaryText,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedState extends StatelessWidget {
  const _LockedState(this.colors);

  final CoolSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderRadius: CoolRadii.xl,
      child: Center(
        child: Icon(CoolIcons.lock, color: colors.tertiaryText, size: 28),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.colors, required this.message});

  final CoolSemanticColors colors;
  final String message;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderRadius: CoolRadii.xl,
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: colors.secondaryText),
      ),
    );
  }
}

class _StatementTile extends StatelessWidget {
  const _StatementTile({
    required this.entry,
    this.canManageAllocations = false,
    this.groupId = '',
  });

  final PayeePaymentLedgerEntry entry;
  final bool canManageAllocations;
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final isAllocated = entry.payerUserId.trim().isNotEmpty;
    final statusLabel = isAllocated ? 'confirmed' : 'pending_review';

    return CoolCard(
      borderRadius: CoolRadii.xl,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                ),
                alignment: Alignment.center,
                child: Icon(
                  CoolIcons.arrowDown,
                  color: colors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: CoolSpace.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.label,
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.titleSmall,
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${entry.payerName} • ${formatTransactionDate(entry.occurredAt)}',
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.labelSmall,
                        fontWeight: FontWeight.w500,
                        color: colors.secondaryText,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${formatWholeMoneyAmount(entry.amount)} ${entry.currency}',
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.titleSmall,
                      fontWeight: FontWeight.w800,
                      color: colors.accentGold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TransactionStatusChip(status: statusLabel),
                ],
              ),
              if (canManageAllocations) ...[
                const SizedBox(width: CoolSpace.x2),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    onPressed: () => TransactionAllocationSheet.show(
                      context,
                      entry: entry,
                      groupId: groupId,
                    ),
                    icon: Icon(CoolIcons.settings, color: colors.secondaryText),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
