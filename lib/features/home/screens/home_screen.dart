import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/status/providers/home_status_providers.dart';
import '../../../core/theme/cool_palette.dart';
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
    final palette = context.coolPalette;
    final l10n = context.l10n;
    final dashboardAsync = ref.watch(homeDashboardProvider);
    final quests = ref.watch(questsProvider);

    Future<void> refresh() async {
      ref.invalidate(homeDashboardProvider);
      await ref.read(homeDashboardProvider.future);
    }

    return Scaffold(
      backgroundColor: palette.bg,
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
              color: palette.accent,
              backgroundColor: palette.surface2,
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
                children: [
                  Text(
                    l10n.navHome,
                    style: GoogleFonts.dmSans(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: 24),
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
                        data: (actions) => _QuickActionListCard(
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
                        loading: () => _QuickActionListCard(
                          items: _fallbackQuickActions(l10n),
                        ),
                        error: (_, _) => _QuickActionListCard(
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
    final palette = context.coolPalette;
    final l10n = context.l10n;
    final localeName = resolveIntlLocale(context);
    final totalBalance = data?.totalBalance ?? 0;
    final monthlyNetChange = data?.monthlyNetChange ?? 0;
    final memberCount = data?.memberCount ?? 0;
    final recommendation = _buildHomePriorityRecommendation(data, l10n);
    final netColor = monthlyNetChange >= 0 ? palette.accent : palette.orange;

    return Semantics(
      container: true,
      label:
          'Home overview. Total balance ${_spokenCurrency(totalBalance, localeName)}. '
          '${l10n.homeMonthlyNet} ${_signedSpokenCurrency(monthlyNetChange, localeName)}. '
          '${l10n.navGroups} ${l10n.homeActiveCount(memberCount)}.',
      child: CoolCard(
        backgroundColor: palette.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.totalBalance,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.text3,
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
                    color: palette.text,
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
                  valueColor: palette.text,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _HomePriorityStrip(recommendation: recommendation),
          ],
        ),
      ),
    );
  }
}

class _HomePriorityStrip extends StatelessWidget {
  const _HomePriorityStrip({required this.recommendation});

  final _HomePriorityRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label:
          '${l10n.homePriorityLabel}. ${recommendation.title}. ${recommendation.subtitle}. ${recommendation.ctaLabel}.',
      hint: 'Double tap to open ${recommendation.ctaLabel}',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              color: palette.surface2,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => openQuickActionRoute(context, recommendation.route),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: palette.accentGlow,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        recommendation.icon,
                        size: 20,
                        color: palette.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.homePriorityLabel,
                            style: GoogleFonts.dmSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: palette.text3,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            recommendation.title,
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: palette.text,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            recommendation.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: palette.text2,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: palette.surface3,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: palette.border),
                      ),
                      child: Text(
                        recommendation.ctaLabel,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: palette.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomePriorityRecommendation {
  const _HomePriorityRecommendation({
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.route,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String ctaLabel;
  final String route;
  final IconData icon;
}

_HomePriorityRecommendation _buildHomePriorityRecommendation(
  HomeDashboardData? data,
  AppLocalizations l10n,
) {
  final memberCount = data?.memberCount ?? 0;
  final monthlyNetChange = data?.monthlyNetChange ?? 0;
  final hasRecentTransactions = (data?.recentTransactions.isNotEmpty ?? false);

  if (memberCount == 0) {
    return _HomePriorityRecommendation(
      title: l10n.homePriorityGroupsTitle,
      subtitle: l10n.homePriorityGroupsSubtitle,
      ctaLabel: l10n.navGroups,
      route: AppRoutes.groups,
      icon: Icons.people_alt_outlined,
    );
  }

  if (!hasRecentTransactions) {
    return _HomePriorityRecommendation(
      title: l10n.homePriorityMomoTitle,
      subtitle: l10n.homePriorityMomoSubtitle,
      ctaLabel: l10n.homeActionPay,
      route: AppRoutes.momo,
      icon: Icons.account_balance_wallet_outlined,
    );
  }

  if (monthlyNetChange < 0) {
    return _HomePriorityRecommendation(
      title: l10n.homePriorityStatementsTitle,
      subtitle: l10n.homePriorityStatementsSubtitle,
      ctaLabel: l10n.statementsLabel,
      route: AppRoutes.momoStatements,
      icon: Icons.receipt_long_rounded,
    );
  }

  return _HomePriorityRecommendation(
    title: l10n.homePriorityMomentumTitle,
    subtitle: l10n.homePriorityMomentumSubtitle,
    ctaLabel: l10n.navGroups,
    route: AppRoutes.groups,
    icon: Icons.trending_up_rounded,
  );
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
    final palette = context.coolPalette;
    return Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.border),
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
                    color: palette.text3,
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

class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final compactTitle = _shortActionTitle(context, title, route);
    final compactSubtitle = subtitle.trim();

    Widget leadingIcon() {
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: palette.surface2,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Icon(_iconForRoute(route), size: 20, color: palette.accent),
      );
    }

    final trailingIcon = Icon(
      Icons.arrow_forward_rounded,
      size: 18,
      color: palette.text3,
    );

    return Semantics(
      button: true,
      label: compactSubtitle.isEmpty
          ? 'Quick action $compactTitle'
          : 'Quick action $compactTitle. $compactSubtitle',
      hint: 'Double tap to open',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => openQuickActionRoute(context, route),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  leadingIcon(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          compactTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: palette.text,
                          ),
                        ),
                        if (compactSubtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            compactSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: palette.text3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailingIcon,
                ],
              ),
            ),
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

class _QuickActionListCard extends StatelessWidget {
  const _QuickActionListCard({required this.items});

  final List<_QuickActionData> items;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final visibleItems = items.take(4).toList(growable: false);
    return CoolCard(
      backgroundColor: palette.surface,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (var index = 0; index < visibleItems.length; index++) ...[
            _QuickActionRow(
              title: visibleItems[index].title,
              subtitle: visibleItems[index].subtitle,
              route: visibleItems[index].route,
            ),
            if (index != visibleItems.length - 1)
              Divider(
                color: palette.border,
                height: 1,
                indent: 16,
                endIndent: 16,
              ),
          ],
        ],
      ),
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
    final palette = context.coolPalette;
    final l10n = context.l10n;
    final allTransactions =
        data?.recentTransactions ?? const <HomeDashboardTransaction>[];
    final transactions = allTransactions.take(1).toList(growable: false);

    if (transactions.isEmpty) {
      return CoolCard(
        backgroundColor: palette.surface,
        child: CoolEmptyView(
          message: l10n.homeNoActivityMessage,
          compact: true,
          icon: Icons.receipt_long_rounded,
        ),
      );
    }

    return CoolCard(
      backgroundColor: palette.surface,
      child: Column(
        children: [
          for (var i = 0; i < transactions.length; i++) ...[
            _ActivityRow(transaction: transactions[i]),
            if (i != transactions.length - 1)
              Divider(color: palette.border, height: 22),
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
    final palette = context.coolPalette;
    final localeName = resolveIntlLocale(context);
    final signedAmount = transaction.signedAmount;
    final valueColor = signedAmount >= 0 ? palette.accent : palette.orange;
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
                      color: palette.text,
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
                      color: palette.text3,
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
    final palette = context.coolPalette;
    return CoolCard(
      backgroundColor: palette.surface,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CoolSkeleton(width: 120, height: 14, borderRadius: 7),
          SizedBox(height: 18),
          CoolSkeleton(width: double.infinity, height: 38, borderRadius: 12),
          SizedBox(height: 18),
          CoolSkeleton(width: double.infinity, height: 26, borderRadius: 13),
        ],
      ),
    );
  }
}

class _ActivityLoadingCard extends StatelessWidget {
  const _ActivityLoadingCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return CoolCard(
      backgroundColor: palette.surface,
      child: const Column(
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
    final palette = context.coolPalette;
    return CoolCard(
      backgroundColor: palette.surface,
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
