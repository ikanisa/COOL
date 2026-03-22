import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../models/home_dashboard_data.dart';
import '../providers/home_dashboard_provider.dart';
import '../providers/quick_action_provider.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';

class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final l10n = context.l10n;
    final dashboard = ref.watch(homeDashboardProvider).valueOrNull;
    final quickActions = ref
        .watch(currentCountryQuickActionsProvider)
        .valueOrNull;

    return CoolCard(
      borderRadius: CoolRadii.xxl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.navHome,
            style: theme.textTheme.displayLarge?.copyWith(
              color: colors.primaryText,
              height: 1.0,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'HOME COMMAND',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            'Money, movement, and partner activity in one executive view.',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.secondaryText,
              height: 1.22,
            ),
          ),
          const SizedBox(height: CoolSpace.x6),
          _MetricGrid(
            metrics: [
              _HeaderMetricData(
                label: 'Tracked balance',
                value: _compactCurrency(dashboard?.totalBalance ?? 0),
                icon: Icons.account_balance_wallet_outlined,
                surfaceColor: colors.financialSurface,
                valueColor: colors.primaryText,
              ),
              _HeaderMetricData(
                label: 'Net this month',
                value: _signedCompactCurrency(dashboard?.monthlyNetChange ?? 0),
                icon: Icons.show_chart_rounded,
                surfaceColor: colors.analyticsSurface,
                valueColor: (dashboard?.monthlyNetChange ?? 0) >= 0
                    ? colors.success
                    : colors.danger,
              ),
              _HeaderMetricData(
                label: 'Live priorities',
                value: '${quickActions?.take(4).length ?? 4} queues',
                icon: Icons.grid_view_rounded,
                surfaceColor: colors.operationalSurface,
                valueColor: colors.primaryText,
              ),
              _HeaderMetricData(
                label: 'Recent signals',
                value: _activityLabel(dashboard),
                icon: Icons.notifications_active_outlined,
                surfaceColor: colors.contactSurface,
                valueColor: colors.primaryText,
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x6),
          Row(
            children: [
              Expanded(
                child: CoolButton(
                  label: l10n.walletLabel,
                  icon: Icons.account_balance_wallet_outlined,
                  onTap: () => context.push(AppRoutes.momo),
                ),
              ),
              const SizedBox(width: CoolSpace.x3),
              Expanded(
                child: CoolButton(
                  label: l10n.navMobility,
                  variant: CoolButtonVariant.secondary,
                  icon: Icons.alt_route_rounded,
                  onTap: () => context.push(AppRoutes.mobility),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<_HeaderMetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth < 420
            ? (constraints.maxWidth - CoolSpace.x3) / 2
            : (constraints.maxWidth - (CoolSpace.x3 * 3)) / 4;

        return Wrap(
          spacing: CoolSpace.x3,
          runSpacing: CoolSpace.x3,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: tileWidth.clamp(150.0, 220.0).toDouble(),
                child: _HeaderMetric(metric: metric),
              ),
          ],
        );
      },
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({required this.metric});

  final _HeaderMetricData metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: metric.surfaceColor,
        borderRadius: BorderRadius.circular(CoolRadii.md),
        border: Border.all(color: colors.border, width: 1.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CoolSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.cardSurfaceStrong.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(CoolRadii.sm),
                border: Border.all(color: colors.border),
              ),
              alignment: Alignment.center,
              child: Icon(metric.icon, size: 20, color: metric.valueColor),
            ),
            const SizedBox(height: CoolSpace.x4),
            Text(
              metric.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.secondaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: CoolSpace.x2),
            Text(
              metric.value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                color: metric.valueColor,
                fontWeight: FontWeight.w800,
                height: 1.12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderMetricData {
  const _HeaderMetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.surfaceColor,
    required this.valueColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color surfaceColor;
  final Color valueColor;
}

String _activityLabel(HomeDashboardData? dashboard) {
  final activityCount = dashboard?.recentTransactions.length ?? 0;
  if (activityCount <= 0) {
    return 'Quiet';
  }
  if (activityCount == 1) {
    return '1 update';
  }
  return '$activityCount updates';
}

String _compactCurrency(int amount) {
  final absolute = amount.abs();
  if (absolute >= 1000000) {
    return '${(absolute / 1000000).toStringAsFixed(1).replaceAll('.0', '')}M RWF';
  }
  if (absolute >= 1000) {
    return '${(absolute / 1000).toStringAsFixed(0)}K RWF';
  }
  return '$absolute RWF';
}

String _signedCompactCurrency(int amount) {
  final prefix = amount >= 0 ? '+' : '-';
  return '$prefix${_compactCurrency(amount)}';
}
