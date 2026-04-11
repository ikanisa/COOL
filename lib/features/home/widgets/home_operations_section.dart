part of 'home_sections.dart';

class HomeOperationsSection extends StatelessWidget {
  const HomeOperationsSection({
    required this.transactions,
    required this.isLoading,
    required this.error,
    super.key,
  });

  final List<HomeDashboardTransaction> transactions;
  final bool isLoading;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.coolSemanticColors;
    final content = _buildContent(context, colors);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: l10n.homeOperationsTitle,
          trailing: Icon(
            CoolIcons.historyToggle,
            color: colors.secondaryText.withValues(alpha: 0.76),
          ),
        ),
        const SizedBox(height: CoolSpace.x3),
        content,
      ],
    );
  }

  Widget _buildContent(BuildContext context, CoolSemanticColors colors) {
    if (isLoading && transactions.isEmpty) {
      return const Column(
        children: [
          _OperationSkeletonCard(),
          SizedBox(height: CoolSpace.x2),
          _OperationSkeletonCard(),
          SizedBox(height: CoolSpace.x2),
          _OperationSkeletonCard(),
        ],
      );
    }

    if (error != null && transactions.isEmpty) {
      return CoolErrorView(
        compact: true,
        subtitle: context.l10n.homeOperationsLoadFailed,
      );
    }

    if (transactions.isEmpty) {
      return CoolEmptyView(
        compact: true,
        title: context.l10n.homeNoOperationsYet,
        subtitle: context.l10n.homeOperationsEmptySubtitle,
        icon: CoolIcons.receiptOutlined,
      );
    }

    return Column(
      children: [
        for (final (index, transaction) in transactions.take(5).indexed) ...[
          _OperationCard(transaction: transaction),
          if (index < transactions.take(5).length - 1)
            const SizedBox(height: CoolSpace.x2),
        ],
      ],
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.transaction});

  final HomeDashboardTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final accent = operationAccentFor(transaction, colors);
    final icon = operationIconFor(transaction);
    final amount = transaction.signedAmount;

    return CoolCard(
      cardPadding: CoolCardPadding.md,
      child: Row(
        children: [
          CoolIconBox(icon: icon, accent: accent),
          const SizedBox(width: CoolSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  transaction.title.trim().isEmpty
                      ? context.l10n.homeTransactionFallbackTitle
                      : transaction.title.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.coolText.headline(
                    Theme.of(context).textTheme.titleSmall,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatOperationMeta(
                    context,
                    transaction.recordedAt,
                    transaction.type,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.coolText
                      .mobiLabel(color: colors.secondaryText)
                      .copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: CoolSpace.x3),
          Text(
            fmtSignedAmt(amount),
            style: context.coolText.display(
              Theme.of(context).textTheme.titleMedium,
              color: amount >= 0 ? colors.success : colors.primaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationSkeletonCard extends StatelessWidget {
  const _OperationSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      cardPadding: CoolCardPadding.none,
      padding: const EdgeInsets.all(CoolSpace.x4),
      child: CoolListTile.skeleton(dense: true),
    );
  }
}
