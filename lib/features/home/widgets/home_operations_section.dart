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
            Icons.history_toggle_off_rounded,
            color: colors.secondaryText.withValues(alpha: 0.76),
          ),
        ),
        const SizedBox(height: CoolSpace.x4),
        content,
      ],
    );
  }

  Widget _buildContent(BuildContext context, CoolSemanticColors colors) {
    if (isLoading && transactions.isEmpty) {
      return const Column(
        children: [
          _OperationSkeletonCard(),
          SizedBox(height: CoolSpace.x3),
          _OperationSkeletonCard(),
          SizedBox(height: CoolSpace.x3),
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
        icon: Icons.receipt_long_outlined,
      );
    }

    return Column(
      children: [
        for (final (index, transaction) in transactions.take(5).indexed) ...[
          _OperationCard(transaction: transaction),
          if (index < transactions.take(5).length - 1)
            const SizedBox(height: CoolSpace.x3),
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
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final accent = operationAccentFor(transaction, colors);
    final icon = operationIconFor(transaction);
    final amount = transaction.signedAmount;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x5,
        vertical: CoolSpace.x4,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[colors.cardSurface, colors.elevatedBackground],
        ),
        borderRadius: BorderRadius.circular(CoolRadii.lg),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(CoolRadii.md),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: CoolSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.title.trim().isEmpty
                      ? context.l10n.homeTransactionFallbackTitle
                      : transaction.title.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.coolText.headline(
                    theme.textTheme.titleMedium,
                    color: colors.primaryText,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
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
                  style: context.coolText.mono(
                    theme.textTheme.labelSmall,
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: CoolSpace.x4),
          Text(
            fmtSignedAmt(amount),
            style: context.coolText.display(
              theme.textTheme.titleLarge,
              color: amount >= 0 ? colors.success : colors.primaryText,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
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
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x5,
        vertical: CoolSpace.x4,
      ),
      decoration: BoxDecoration(
        color: colors.elevatedBackground,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
      ),
      child: const Row(
        children: [
          CoolSkeleton(width: 48, height: 48, borderRadius: CoolRadii.md),
          SizedBox(width: CoolSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CoolSkeleton.line(width: 160),
                SizedBox(height: CoolSpace.x2),
                CoolSkeleton.line(width: 120),
              ],
            ),
          ),
          SizedBox(width: CoolSpace.x4),
          CoolSkeleton.line(width: 70),
        ],
      ),
    );
  }
}
