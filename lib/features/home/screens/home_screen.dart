import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/status/providers/home_status_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/quick_action_provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/quest_card.dart';
import '../../../shared/widgets/season_banner.dart';
import '../../../shared/widgets/section_title.dart';
import '../models/home_dashboard_data.dart';
import '../providers/home_dashboard_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(homeDashboardProvider);

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
              const SizedBox(height: 8),
              Text(
                'Community finance, MoMo activity, and partner actions in one place.',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text2,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),

              // ── Season Banner (when active) ───────────
              ref
                  .watch(activeSeasonProvider)
                  .when(
                    data: (season) {
                      if (season == null || !season.isLive) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: SeasonBanner(season: season),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),

              dashboardAsync.when(
                data: (dashboard) => _OverviewCard(data: dashboard),
                loading: () => const _OverviewLoadingCard(),
                error: (error, _) => _OverviewErrorCard(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(homeDashboardProvider),
                ),
              ),
              const SizedBox(height: 20),
              const SectionTitle(title: 'Quick access'),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final country = ref.watch(authProvider).user?.country;
                  final actionsAsync = ref.watch(quickActionsProvider(country));

                  return actionsAsync.when(
                    data: (actions) => _QuickActionGrid(
                      items: actions
                          .map(
                            (action) => _QuickActionData(
                              title: action.title,
                              subtitle: action.subtitle ?? '',
                              emoji: action.emoji,
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
              const SizedBox(height: 20),

              // ── Quests Carousel ───────────────────────
              Builder(
                builder: (context) {
                  final quests = ref.watch(questsProvider);
                  if (quests.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: QuestCarousel(quests: quests),
                  );
                },
              ),

              const SectionTitle(title: 'Recent activity'),
              const SizedBox(height: 12),
              dashboardAsync.when(
                data: (dashboard) => _RecentActivityCard(data: dashboard),
                loading: () => const _ActivityLoadingCard(),
                error: (error, _) => _OverviewErrorCard(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(homeDashboardProvider),
                ),
              ),
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

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Portfolio snapshot',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 440;
              if (isCompact) {
                return Column(
                  children: [
                    _MetricTile(
                      label: 'Total balance',
                      value: _formatCurrency(totalBalance),
                      valueColor: AppColors.accent,
                    ),
                    const SizedBox(height: 10),
                    _MetricTile(
                      label: 'Monthly net',
                      value: _signedCurrency(monthlyNetChange),
                      valueColor: monthlyNetChange >= 0
                          ? AppColors.blue
                          : AppColors.orange,
                    ),
                    const SizedBox(height: 10),
                    _MetricTile(
                      label: 'Groups',
                      value: '$memberCount',
                      valueColor: AppColors.text,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      label: 'Total balance',
                      value: _formatCurrency(totalBalance),
                      valueColor: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricTile(
                      label: 'Monthly net',
                      value: _signedCurrency(monthlyNetChange),
                      valueColor: monthlyNetChange >= 0
                          ? AppColors.blue
                          : AppColors.orange,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricTile(
                      label: 'Groups',
                      value: '$memberCount',
                      valueColor: AppColors.text,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.text3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.route,
  });

  final String title;
  final String subtitle;
  final String emoji;
  final String route;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      onTap: () => context.go(route),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid({required this.items});

  final List<_QuickActionData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = switch (constraints.maxWidth) {
          < 560 => 2,
          < 900 => 3,
          _ => 4,
        };

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: constraints.maxWidth >= 900 ? 1.5 : 1.35,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return _QuickActionCard(
              title: item.title,
              subtitle: item.subtitle,
              emoji: item.emoji,
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
    required this.emoji,
    required this.route,
  });

  final String title;
  final String subtitle;
  final String emoji;
  final String route;
}

const _fallbackQuickActions = <_QuickActionData>[
  _QuickActionData(
    title: 'Groups',
    subtitle: 'Savings and invites',
    emoji: '👥',
    route: '/groups',
  ),
  _QuickActionData(
    title: 'MoMo',
    subtitle: 'USSD and sync',
    emoji: '📲',
    route: '/momo',
  ),
  _QuickActionData(
    title: 'Partners',
    subtitle: 'Rayon and clubs',
    emoji: '💙',
    route: '/partners',
  ),
  _QuickActionData(
    title: 'Mobility',
    subtitle: 'Drivers and trips',
    emoji: '🛺',
    route: '/mobility',
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
        child: Column(
          children: [
            const Text('📭', style: TextStyle(fontSize: 34)),
            const SizedBox(height: 10),
            Text(
              'No recent activity yet',
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Payments, contributions, and member transactions will appear here once they sync.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return CoolCard(
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

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: valueColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            signedAmount >= 0 ? '↗' : '↘',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transaction.title,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('EEE d MMM · HH:mm').format(transaction.recordedAt),
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
      child: SizedBox(
        height: 120,
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
      child: SizedBox(
        height: 160,
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
  const _OverviewErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 30)),
          const SizedBox(height: 10),
          Text(
            'Unable to load dashboard',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
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
