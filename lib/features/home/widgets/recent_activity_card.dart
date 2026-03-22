import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/cool_palette.dart';
import '../../../../core/utils/intl_locale.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../models/home_dashboard_data.dart';

class RecentActivityCard extends StatelessWidget {
  const RecentActivityCard({
    super.key,
    required this.activityCount,
    required this.recentTransactions,
  });

  final int activityCount;
  final List<HomeDashboardTransaction> recentTransactions;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final localeName = resolveIntlLocale(context);
    final displayed = recentTransactions.take(3).toList();

    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  if (i > 0)
                    Divider(height: 24, thickness: 1, color: palette.border),
                  _TransactionRow(tx: displayed[i], localeName: localeName),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.tx, required this.localeName});

  final HomeDashboardTransaction tx;
  final String localeName;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final colors = context.coolSemanticColors;
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
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isCredit ? colors.financialSurface : colors.routeSurface,
                borderRadius: BorderRadius.circular(CoolRadii.md),
                border: Border.all(color: colors.border),
              ),
              alignment: Alignment.center,
              child: Icon(
                isCredit
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                size: 22,
                color: isCredit ? colors.success : colors.secondaryText,
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
              style: theme.textTheme.titleSmall?.copyWith(
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
