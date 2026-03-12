import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/status/providers/home_status_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/quest_card.dart';
import '../../../shared/widgets/season_banner.dart';
import '../../../shared/widgets/section_title.dart';
import '../models/home_dashboard_data.dart';
import '../providers/home_dashboard_provider.dart';
import '../providers/quick_action_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(homeDashboardProvider);
    final quests = ref.watch(questsProvider);

    Future<void> refresh() async {
      ref.invalidate(homeDashboardProvider);
      await ref.read(homeDashboardProvider.future);
    }

    return CoolScreenBackground(
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.surface2,
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
            children: [
              Text(
                'Home',
                style: GoogleFonts.dmSans(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 20),
              dashboardAsync.when(
                data: (dashboard) => _OverviewCard(data: dashboard),
                loading: () => const _OverviewLoadingCard(),
                error: (_, _) => _OverviewErrorCard(
                  onRetry: () => ref.invalidate(homeDashboardProvider),
                ),
              ),
              const SizedBox(height: 24),
              const SectionTitle(title: 'Top actions'),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final actionsAsync = ref.watch(
                    currentCountryQuickActionsProvider,
                  );

                  return actionsAsync.when(
                    data: (actions) => _QuickActionGrid(
                      items: actions
                          .take(4)
                          .map(
                            (action) => _QuickActionData(
                              title: action.title,
                              subtitle: action.subtitle ?? '',
                              route: action.route,
                            ),
                          )
                          .toList(growable: false),
                    ),
                    loading: () =>
                        const _QuickActionGrid(items: _fallbackQuickActions),
                    error: (_, _) =>
                        const _QuickActionGrid(items: _fallbackQuickActions),
                  );
                },
              ),
              const SizedBox(height: 24),
              SectionTitle(
                title: 'Activity',
                actionLabel: 'Statements',
                onAction: () => context.push(AppRoutes.momoStatements),
              ),
              const SizedBox(height: 12),
              dashboardAsync.when(
                data: (dashboard) => _RecentActivityCard(data: dashboard),
                loading: () => const _ActivityLoadingCard(),
                error: (_, _) => _OverviewErrorCard(
                  onRetry: () => ref.invalidate(homeDashboardProvider),
                ),
              ),
              ref
                  .watch(activeSeasonProvider)
                  .when(
                    data: (season) {
                      if (season == null || !season.isLive) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: SeasonBanner(season: season),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
              if (quests.isNotEmpty) ...[
                const SizedBox(height: 24),
                SectionTitle(
                  title: 'Missions',
                  actionLabel: 'Open',
                  onAction: () => context.push(AppRoutes.missions),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: quests.take(3).length,
                    separatorBuilder: (context, index) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      return QuestCard(quest: quests[index]);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.data});

  final HomeDashboardData? data;

  @override
  Widget build(BuildContext context) {
    final totalBalance = data?.totalBalance ?? 0;
    final monthlyNetChange = data?.monthlyNetChange ?? 0;
    final memberCount = data?.memberCount ?? 0;
    final netColor = monthlyNetChange >= 0
        ? AppColors.accent
        : AppColors.orange;

    return CoolCard(
      backgroundColor: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Balance',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text3,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _formatCurrency(totalBalance),
            style: GoogleFonts.dmMono(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
              height: 1.1,
            ),
          ),

          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricPill(
                label: 'Monthly net',
                value: _signedCurrency(monthlyNetChange),
                valueColor: netColor,
              ),
              _MetricPill(
                label: 'Groups',
                value: '$memberCount active',
                valueColor: AppColors.text,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text3,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      backgroundColor: AppColors.surface,
      onTap: () => context.go(route),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              _iconForRoute(route),
              size: 20,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _shortActionTitle(title, route),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.text3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: AppColors.text3,
          ),
        ],
      ),
    );
  }

  static IconData _iconForRoute(String route) {
    if (route.startsWith(AppRoutes.groups)) {
      return Icons.people_alt_outlined;
    }
    if (route.startsWith(AppRoutes.momo)) {
      return Icons.account_balance_wallet_outlined;
    }
    if (route.startsWith(AppRoutes.mobility)) {
      return Icons.directions_car_outlined;
    }
    if (route.startsWith(AppRoutes.partners)) {
      return Icons.storefront_outlined;
    }
    if (route.startsWith(AppRoutes.credit)) {
      return Icons.insights_outlined;
    }
    return Icons.arrow_outward_rounded;
  }

  static String _shortActionTitle(String title, String route) {
    final normalized = title.trim();
    if (normalized.isEmpty) {
      return 'Open';
    }
    if (route.startsWith(AppRoutes.momo)) {
      return 'Pay';
    }
    if (route.startsWith(AppRoutes.mobility)) {
      return 'Trips';
    }
    return normalized;
  }
}

class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid({required this.items});

  final List<_QuickActionData> items;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(4).toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = switch (constraints.maxWidth) {
          < 780 => 2,
          _ => 4,
        };

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: visibleItems.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: constraints.maxWidth >= 780 ? 2.2 : 1.7,
          ),
          itemBuilder: (context, index) {
            final item = visibleItems[index];
            return _QuickActionCard(
              title: item.title,
              subtitle: item.subtitle,
              route: item.route,
            );
          },
        );
      },
    );
  }
}

class _QuickActionData {
  const _QuickActionData({
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final String title;
  final String subtitle;
  final String route;
}

const _fallbackQuickActions = <_QuickActionData>[
  _QuickActionData(
    title: 'Groups',
    subtitle: 'Savings and invites',
    route: AppRoutes.groups,
  ),
  _QuickActionData(
    title: 'Pay',
    subtitle: 'MoMo and statements',
    route: AppRoutes.momo,
  ),
  _QuickActionData(
    title: 'Partners',
    subtitle: 'Banks and clubs',
    route: AppRoutes.partners,
  ),
  _QuickActionData(
    title: 'Trips',
    subtitle: 'Ride or drive',
    route: AppRoutes.mobility,
  ),
];

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.data});

  final HomeDashboardData? data;

  @override
  Widget build(BuildContext context) {
    final transactions =
        data?.recentTransactions ?? const <HomeDashboardTransaction>[];

    if (transactions.isEmpty) {
      return CoolCard(
        backgroundColor: AppColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No activity yet',
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Activity will appear here.', 
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.text2,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return CoolCard(
      backgroundColor: AppColors.surface,
      child: Column(
        children: [
          for (var i = 0; i < transactions.length; i++) ...[
            _ActivityRow(transaction: transactions[i]),
            if (i != transactions.length - 1)
              Divider(color: AppColors.border, height: 22),
          ],
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.transaction});

  final HomeDashboardTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final signedAmount = transaction.signedAmount;
    final valueColor = signedAmount >= 0 ? AppColors.accent : AppColors.orange;
    final meta = [
      if (transaction.groupName?.trim().isNotEmpty == true)
        transaction.groupName!,
      DateFormat('EEE d MMM · HH:mm').format(transaction.recordedAt),
    ].join(' · ');

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: valueColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(
            signedAmount >= 0
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            size: 18,
            color: valueColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transaction.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _signedCurrency(signedAmount),
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _OverviewLoadingCard extends StatelessWidget {
  const _OverviewLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const CoolCard(
      backgroundColor: AppColors.surface,
      child: SizedBox(
        height: 136,
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.accent,
            strokeWidth: 2.2,
          ),
        ),
      ),
    );
  }
}

class _ActivityLoadingCard extends StatelessWidget {
  const _ActivityLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const CoolCard(
      backgroundColor: AppColors.surface,
      child: SizedBox(
        height: 140,
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.accent,
            strokeWidth: 2.2,
          ),
        ),
      ),
    );
  }
}

class _OverviewErrorCard extends StatelessWidget {
  const _OverviewErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      backgroundColor: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Couldn\'t load this section',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pull to refresh or try again.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: onRetry, child: const Text('Retry')),
          ),
        ],
      ),
    );
  }
}

String _formatCurrency(int amount, [String currency = 'RWF']) {
  return '${NumberFormat.decimalPattern('en').format(amount)} $currency';
}

String _signedCurrency(int amount, [String currency = 'RWF']) {
  final prefix = amount >= 0 ? '+' : '-';
  return '$prefix${_formatCurrency(amount.abs(), currency)}';
}
