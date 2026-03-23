import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/intl_locale.dart';
import '../../../shared/widgets/cool_card.dart';
import '../models/home_dashboard_data.dart';

class RecentActivityCard extends StatelessWidget {
  const RecentActivityCard({
    required this.activityCount,
    required this.recentTransactions,
    this.useCard = true,
    this.showHeader = true,
    super.key,
  });

  final int activityCount;
  final List<HomeDashboardTransaction> recentTransactions;
  final bool useCard;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final localeName = resolveIntlLocale(context);
    final displayed = recentTransactions.take(3).toList();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Activity',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (activityCount > 3)
                TextButton(
                  onPressed: () => context.push(AppRoutes.momo),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.accent,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(52, CoolTapTargets.minimum),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'See All',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (displayed.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No recent activity',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < displayed.length; i++) ...[
                if (i > 0) const SizedBox(height: CoolSpace.x4),
                _TransactionRow(tx: displayed[i], localeName: localeName),
              ],
            ],
          ),
      ],
    );

    if (!useCard) {
      return content;
    }

    return CoolCard(backgroundColor: colors.cardSurfaceStrong, child: content);
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.tx, required this.localeName});

  final HomeDashboardTransaction tx;
  final String localeName;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final isCredit = tx.isPositive;
    final amountColor = isCredit ? colors.success : colors.primaryText;
    final amountString = signedCurrency(
      tx.signedAmount,
      localeName,
      tx.currency,
    );

    return Semantics(
      label:
          '${tx.title}, ${isCredit ? 'Received' : 'Paid'} ${signedSpokenCurrency(tx.signedAmount, localeName, tx.currency)} on ${DateFormat.yMd(localeName).format(tx.recordedAt)}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: isCredit ? colors.financialSurface : colors.routeSurface,
                borderRadius: const BorderRadius.all(
                  Radius.circular(CoolRadii.md),
                ),
                boxShadow: CoolShadows.floating(
                  Theme.of(context).brightness,
                  strength: 0.2,
                ),
              ),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Icon(
                    isCredit
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    size: 22,
                    color: isCredit ? colors.success : colors.secondaryText,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat.yMd(localeName).format(tx.recordedAt),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amountString,
              style: text.mono(
                theme.textTheme.titleSmall,
                color: amountColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatCurrency(
  int amount,
  String localeName, [
  String currency = 'RWF',
]) {
  return '${NumberFormat.decimalPattern(localeName).format(amount)} $currency';
}

String signedCurrency(
  int amount,
  String localeName, [
  String currency = 'RWF',
]) {
  final prefix = amount >= 0 ? '+' : '-';
  return '$prefix${formatCurrency(amount.abs(), localeName, currency)}';
}

String spokenCurrency(
  int amount,
  String localeName, [
  String currency = 'RWF',
]) {
  final spokenCurrency = switch (currency) {
    'RWF' => 'Rwandan francs',
    _ => currency,
  };
  return '${NumberFormat.decimalPattern(localeName).format(amount)} $spokenCurrency';
}

String signedSpokenCurrency(
  int amount,
  String localeName, [
  String currency = 'RWF',
]) {
  final direction = amount >= 0 ? 'plus' : 'minus';
  return '$direction ${spokenCurrency(amount.abs(), localeName, currency)}';
}
