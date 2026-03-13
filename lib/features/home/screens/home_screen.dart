import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/status/providers/home_status_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/intl_locale.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_error_boundary.dart';
import '../../../shared/widgets/cool_error_view.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
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
    final l10n = context.l10n;
    final dashboardAsync = ref.watch(homeDashboardProvider);
    final quests = ref.watch(questsProvider);

    Future<void> refresh() async {
      ref.invalidate(homeDashboardProvider);
      await ref.read(homeDashboardProvider.future);
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CoolScreenBackground(
        child: CoolErrorBoundary(
          onRetry: () {
            ref.invalidate(homeDashboardProvider);
            ref.invalidate(currentCountryQuickActionsProvider);
            ref.invalidate(activeSeasonProvider);
          },
          child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: AppColors.accent,
              backgroundColor: AppColors.surface2,
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
                children: [
                  Text(
                    l10n.navHome,
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
                  SectionTitle(title: l10n.quickActions),
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
                        loading: () => _QuickActionGrid(
                          items: _fallbackQuickActions(l10n),
                        ),
                        error: (_, _) => _QuickActionGrid(
                          items: _fallbackQuickActions(l10n),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  SectionTitle(
                    title: l10n.recentActivity,
                    actionLabel: l10n.statementsLabel,
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
                      title: l10n.homeMissionsTitle,
                      actionLabel: l10n.openAction,
                      onAction: () => context.push(AppRoutes.missions),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 170,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: quests.take(3).length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 10),
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
    final l10n = context.l10n;
    final localeName = resolveIntlLocale(context);
    final totalBalance = data?.totalBalance ?? 0;
    final monthlyNetChange = data?.monthlyNetChange ?? 0;
    final memberCount = data?.memberCount ?? 0;
    final netColor = monthlyNetChange >= 0
        ? AppColors.accent
        : AppColors.orange;

    return Semantics(
      container: true,
      label:
          'Home overview. Total balance ${_spokenCurrency(totalBalance, localeName)}. '
          '${l10n.homeMonthlyNet} ${_signedSpokenCurrency(monthlyNetChange, localeName)}. '
          '${l10n.navGroups} ${l10n.homeActiveCount(memberCount)}.',
      child: CoolCard(
        backgroundColor: AppColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.totalBalance,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text3,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 10),
            Semantics(
              label:
                  '${l10n.totalBalance}: ${_spokenCurrency(totalBalance, localeName)}',
              child: ExcludeSemantics(
                child: Text(
                  _formatCurrency(totalBalance, localeName),
                  style: GoogleFonts.dmMono(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                    height: 1.1,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricPill(
                  label: l10n.homeMonthlyNet,
                  value: _signedCurrency(monthlyNetChange, localeName),
                  valueColor: netColor,
                ),
                _MetricPill(
                  label: l10n.navGroups,
                  value: l10n.homeActiveCount(memberCount),
                  valueColor: AppColors.text,
                ),
              ],
            ),
          ],
        ),
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
    return Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: DecoratedBox(
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
    final compactTitle = _shortActionTitle(context, title, route);
    final compactSubtitle = subtitle.trim();

    Widget leadingIcon() {
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Icon(_iconForRoute(route), size: 20, color: AppColors.accent),
      );
    }

    const trailingIcon = Icon(
      Icons.arrow_forward_rounded,
      size: 18,
      color: AppColors.text3,
    );

    return Semantics(
      button: true,
      label: compactSubtitle.isEmpty
          ? 'Quick action $compactTitle'
          : 'Quick action $compactTitle. $compactSubtitle',
      hint: 'Double tap to open',
      child: ExcludeSemantics(
        child: CoolCard(
          backgroundColor: AppColors.surface,
          onTap: () => openQuickActionRoute(context, route),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 170;

              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [leadingIcon(), const Spacer(), trailingIcon],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      compactTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    if (compactSubtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        compactSubtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.text3,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                );
              }

              return Row(
                children: [
                  leadingIcon(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          compactTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        if (compactSubtitle.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            compactSubtitle,
                            maxLines: 2,
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
                  trailingIcon,
                ],
              );
            },
          ),
        ),
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

  static String _shortActionTitle(
    BuildContext context,
    String title,
    String route,
  ) {
    final l10n = context.l10n;
    final normalized = title.trim();
    if (normalized.isEmpty) {
      return l10n.openAction;
    }
    if (route.startsWith(AppRoutes.momo)) {
      return l10n.homeActionPay;
    }
    if (route.startsWith(AppRoutes.mobility)) {
      return l10n.homeActionTrips;
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
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final crossAxisCount = switch (constraints.maxWidth) {
          < 780 => 2,
          _ => 4,
        };
        final mainAxisExtent = textScale >= 1.4
            ? switch (constraints.maxWidth) {
                >= 780 => 230.0,
                >= 420 => 240.0,
                _ => 268.0,
              }
            : null;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: visibleItems.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: mainAxisExtent,
            childAspectRatio: mainAxisExtent == null
                ? switch (constraints.maxWidth) {
                    >= 780 => 2.2,
                    >= 420 => 1.55,
                    _ => 1.18,
                  }
                : 1,
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

List<_QuickActionData> _fallbackQuickActions(AppLocalizations l10n) {
  return <_QuickActionData>[
    _QuickActionData(
      title: l10n.navGroups,
      subtitle: l10n.homeFallbackGroupsSubtitle,
      route: AppRoutes.groups,
    ),
    _QuickActionData(
      title: l10n.homeActionPay,
      subtitle: l10n.homeFallbackPaySubtitle,
      route: AppRoutes.momo,
    ),
    _QuickActionData(
      title: l10n.partnersTitle,
      subtitle: l10n.homeFallbackPartnersSubtitle,
      route: AppRoutes.partners,
    ),
    _QuickActionData(
      title: l10n.homeActionTrips,
      subtitle: l10n.homeFallbackTripsSubtitle,
      route: AppRoutes.mobility,
    ),
  ];
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.data});

  final HomeDashboardData? data;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final transactions =
        data?.recentTransactions ?? const <HomeDashboardTransaction>[];

    if (transactions.isEmpty) {
      return CoolCard(
        backgroundColor: AppColors.surface,
        child: CoolEmptyView(
          message: l10n.homeNoActivityMessage,
          compact: true,
          icon: Icons.receipt_long_rounded,
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
    final localeName = resolveIntlLocale(context);
    final signedAmount = transaction.signedAmount;
    final valueColor = signedAmount >= 0 ? AppColors.accent : AppColors.orange;
    final meta = [
      if (transaction.groupName?.trim().isNotEmpty == true)
        transaction.groupName!,
      if (transaction.status?.trim().isNotEmpty == true)
        _formatActivityStatus(transaction.status!),
      safeDateFormat(
        'EEE d MMM · HH:mm',
        locale: Localizations.maybeLocaleOf(context),
      ).format(transaction.recordedAt),
    ].join(' · ');

    return Semantics(
      container: true,
      label:
          '${transaction.title}. $meta. ${signedAmount >= 0 ? 'Incoming' : 'Outgoing'} '
          'amount ${_signedSpokenCurrency(signedAmount, localeName)}.',
      child: ExcludeSemantics(
        child: Row(
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
              _signedCurrency(signedAmount, localeName),
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

String _formatActivityStatus(String status) {
  final normalized = status.trim();
  if (normalized.isEmpty) {
    return '';
  }

  return normalized
      .split('_')
      .map((segment) {
        if (segment.isEmpty) {
          return segment;
        }
        return '${segment[0].toUpperCase()}${segment.substring(1)}';
      })
      .join(' ');
}

class _OverviewLoadingCard extends StatelessWidget {
  const _OverviewLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const CoolCard(
      backgroundColor: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CoolSkeleton(width: 120, height: 14, borderRadius: 7),
          SizedBox(height: 18),
          CoolSkeleton(
            width: double.infinity,
            height: 38,
            borderRadius: 12,
          ),
          SizedBox(height: 18),
          CoolSkeleton(
            width: double.infinity,
            height: 26,
            borderRadius: 13,
          ),
        ],
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CoolSkeleton(width: double.infinity, height: 16, borderRadius: 8),
          SizedBox(height: 12),
          CoolSkeleton(width: double.infinity, height: 16, borderRadius: 8),
          SizedBox(height: 12),
          CoolSkeleton(width: 160, height: 16, borderRadius: 8),
        ],
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
      child: CoolErrorView(
        message: context.l10n.homeLoadErrorMessage,
        onRetry: onRetry,
        compact: true,
      ),
    );
  }
}

String _formatCurrency(
  int amount,
  String localeName, [
  String currency = 'RWF',
]) {
  return '${NumberFormat.decimalPattern(localeName).format(amount)} $currency';
}

String _signedCurrency(
  int amount,
  String localeName, [
  String currency = 'RWF',
]) {
  final prefix = amount >= 0 ? '+' : '-';
  return '$prefix${_formatCurrency(amount.abs(), localeName, currency)}';
}

String _spokenCurrency(
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

String _signedSpokenCurrency(
  int amount,
  String localeName, [
  String currency = 'RWF',
]) {
  final direction = amount >= 0 ? 'plus' : 'minus';
  return '$direction ${_spokenCurrency(amount.abs(), localeName, currency)}';
}
