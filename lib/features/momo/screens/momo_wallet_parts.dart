part of 'momo_wallet_screen.dart';

// ═══════════════════════════════════════════════════════════════
// Transaction tile
// ═══════════════════════════════════════════════════════════════

class _WalletTransactionTile extends StatelessWidget {
  const _WalletTransactionTile({required this.entry});

  final MomoWalletEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final isCredit = entry.isCredit;
    final amountColor = isCredit ? colors.success : colors.danger;
    final iconColor = isCredit ? colors.success : colors.danger;
    final amountPrefix = isCredit ? '+' : '-';

    return Container(
      padding: const EdgeInsets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: CoolShadows.ambientFloat(strength: 0.3),
      ),
      child: Row(
        children: [
          // Direction icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(CoolRadii.md),
            ),
            alignment: Alignment.center,
            child: Icon(
              isCredit ? CoolIcons.arrowDown : CoolIcons.arrowUp,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: CoolSpace.x4),

          // Label + metadata
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
                  _buildSubtitle(),
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.labelSmall,
                    fontWeight: FontWeight.w500,
                    color: colors.secondaryText,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                _ClassificationChip(entry: entry),
                if (entry.reference != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.walletRefPrefix(entry.reference!),
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.labelSmall,
                      fontWeight: FontWeight.w500,
                      color: colors.tertiaryText,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: CoolSpace.x3),

          // Amount + status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$amountPrefix${formatWholeMoneyAmount(entry.amount)} ${entry.currency}',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.titleSmall,
                  fontWeight: FontWeight.w800,
                  color: amountColor,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              TransactionStatusChip(status: entry.ledgerStatus),
            ],
          ),
        ],
      ),
    );
  }

  String _buildSubtitle() {
    final parts = <String>[];
    final counterparty = entry.counterpartyName ?? entry.payerName;
    if (counterparty != null && counterparty.isNotEmpty) {
      parts.add(counterparty);
    }
    parts.add(formatTransactionDate(entry.occurredAt));
    return parts.join(' • ');
  }
}

class _ClassificationChip extends StatelessWidget {
  const _ClassificationChip({required this.entry});

  final MomoWalletEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final isGroupRelated = entry.isGroupRelated;
    final label = isGroupRelated ? 'GROUP RELATED' : 'WALLET';
    final chipColor = isGroupRelated ? colors.accent : colors.info;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(CoolRadii.pill),
      ),
      child: Text(
        label,
        style: context.coolText.mono(
          Theme.of(context).textTheme.labelSmall,
          fontWeight: FontWeight.w800,
          color: chipColor,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _WalletScopeFilterBar extends StatelessWidget {
  const _WalletScopeFilterBar({
    required this.selected,
    required this.onSelected,
  });

  final _WalletScopeFilter selected;
  final ValueChanged<_WalletScopeFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return Wrap(
      spacing: CoolSpace.x2,
      runSpacing: CoolSpace.x2,
      children: [
        for (final option in _WalletScopeFilter.values)
          ChoiceChip(
            showCheckmark: false,
            label: Text(_walletScopeFilterLabel(option)),
            selected: selected == option,
            onSelected: (_) => onSelected(option),
            backgroundColor: colors.chipBackground,
            selectedColor: colors.chipSelectedBackground,
            labelStyle: context.coolText.mono(
              Theme.of(context).textTheme.labelLarge,
              fontWeight: FontWeight.w700,
              color: selected == option
                  ? colors.primaryText
                  : colors.secondaryText,
            ),
            side: BorderSide.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CoolRadii.pill),
            ),
          ),
      ],
    );
  }
}

class _FilteredEmptyState extends StatelessWidget {
  const _FilteredEmptyState({required this.scopeFilter});

  final _WalletScopeFilter scopeFilter;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.all(CoolSpace.x6),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: CoolShadows.ambientFloat(strength: 0.3),
      ),
      child: Text(
        'No ${_walletScopeFilterLabel(scopeFilter).toLowerCase()} transactions in this range.',
        textAlign: TextAlign.center,
        style: context.coolText.mono(
          Theme.of(context).textTheme.bodyMedium,
          fontWeight: FontWeight.w500,
          color: colors.secondaryText,
        ),
      ),
    );
  }
}

String _walletScopeFilterLabel(_WalletScopeFilter value) {
  switch (value) {
    case _WalletScopeFilter.all:
      return 'ALL';
    case _WalletScopeFilter.wallet:
      return 'WALLET';
    case _WalletScopeFilter.groupRelated:
      return 'GROUP RELATED';
  }
}

// ═══════════════════════════════════════════════════════════════
// Empty + Error states
// ═══════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.colors);

  final CoolSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(CoolSpace.x6),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: CoolShadows.ambientFloat(strength: 0.3),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(CoolIcons.history, color: colors.accent, size: 32),
          ),
          const SizedBox(height: CoolSpace.x4),
          Text(
            context.l10n.walletNoTransactionsYetTitle,
            style: context.coolText.displayCondensed(
              Theme.of(context).textTheme.titleLarge,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            context.l10n.walletNoTransactionsYetMessage,
            textAlign: TextAlign.center,
            style: context.coolText.mono(
              Theme.of(context).textTheme.bodySmall,
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.colors,
    required this.message,
    this.onRetry,
  });

  final CoolSemanticColors colors;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(CoolSpace.x5),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: CoolShadows.ambientFloat(strength: 0.3),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CoolIcons.error, color: colors.danger, size: 32),
          const SizedBox(height: CoolSpace.x3),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.coolText.mono(
              Theme.of(context).textTheme.bodyMedium,
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: CoolSpace.x4),
            TextButton.icon(
              onPressed: onRetry,
              icon: Icon(CoolIcons.refresh, size: 16, color: colors.accent),
              label: Text(
                l10n.retry,
                style: context.coolText.headline(
                  Theme.of(context).textTheme.labelLarge,
                  fontWeight: FontWeight.w700,
                  color: colors.accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
