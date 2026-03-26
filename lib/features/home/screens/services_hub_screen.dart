import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/status/providers/home_status_providers.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_layout.dart';
import '../../../core/theme/rs_colors.dart';

import '../../../shared/widgets/cool_error_boundary.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/core_tab_root_scaffold.dart';
import '../../../shared/widgets/quest_card.dart';
import '../../../shared/widgets/season_banner.dart';
import '../../partners/providers/partner_provider.dart';
import '../../partners/providers/rayon_sports_provider.dart';
import '../../admin/providers/special_products_provider.dart';
import '../models/home_dashboard_data.dart';
import '../providers/home_dashboard_provider.dart';
import '../../../core/status/widgets/referral_banner.dart';

import 'package:flutter_animate/flutter_animate.dart';

import '../widgets/group_savings_card.dart';
import '../widgets/services_header.dart';
import '../widgets/home_state_cards.dart';
import '../widgets/nexus_recommendations_section.dart';
import '../widgets/recent_activity_card.dart';
import '../widgets/special_product_card.dart';

class ServicesHubScreen extends ConsumerWidget {
  const ServicesHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final dashboardAsync = ref.watch(homeDashboardProvider);
    final quests = ref.watch(questsProvider);
    final hasActiveBankPartner = ref.watch(hasActiveBankPartnerProvider);

    Future<void> refresh() async {
      ref.invalidate(homeDashboardProvider);
      await ref.read(homeDashboardProvider.future);
    }

    return CoreTabRootScaffold(
      primaryColor: RsColors.rsBlue,
      secondaryColor: RsColors.rsGold,
      child: CoolErrorBoundary(
        onRetry: () {
          ref.invalidate(homeDashboardProvider);
          ref.invalidate(activeSeasonProvider);
          ref.invalidate(rayonSportsProvider);
          ref.invalidate(rayonMembershipProvider);
          ref.invalidate(rayonMatchesProvider);
          ref.invalidate(rayonFanClubsProvider);
          ref.invalidate(rayonInitiativesProvider);
        },
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: colors.accent,
            backgroundColor: colors.cardSurfaceStrong,
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: CoolLayout.rootPagePadding,
              children: AnimateList(
                interval: 40.ms,
                effects: [
                  FadeEffect(duration: 400.ms, curve: Curves.easeOut),
                  SlideEffect(
                    begin: const Offset(0, 0.05),
                    end: Offset.zero,
                    duration: 400.ms,
                    curve: Curves.easeOutCubic,
                  ),
                ],
                children: [
                  const ServicesHeader(),
                  const SizedBox(height: CoolSpace.x8),
                  const SizedBox(height: CoolSpace.x8),
                  _SecondaryServiceDeck(
                    dashboardAsync: dashboardAsync,
                    hasActiveBankPartner: hasActiveBankPartner,
                  ),
                  if (hasActiveBankPartner) ...[
                    const SizedBox(height: CoolSpace.x6),
                    const _QuietSectionLabel(label: 'Banking'),
                    const SizedBox(height: CoolSpace.x3),
                    dashboardAsync.when(
                      data: (dashboard) => GroupSavingsCard(data: dashboard),
                      loading: () => const OverviewLoadingCard(),
                      error: (_, _) => OverviewErrorCard(
                        onRetry: () => ref.invalidate(homeDashboardProvider),
                      ),
                    ),
                  ],
                  const SizedBox(height: CoolSpace.x8),
                  const ReferralBanner(),
                  const SizedBox(height: CoolSpace.x6),
                  const NexusRecommendationsSection(),
                  const SizedBox(height: CoolSpace.x3),
                  ...ref
                      .watch(activeSpecialProductsProvider)
                      .maybeWhen(
                        data: (products) => products.map(
                          (p) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: CoolSpace.x3,
                            ),
                            child: SpecialProductCard(product: p),
                          ),
                        ),
                        orElse: () => [const SizedBox.shrink()],
                      ),

                  // ── Lower Priority ──────────────────────
                  ref
                      .watch(activeSeasonProvider)
                      .when(
                        data: (season) {
                          if (season == null || !season.isLive) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: CoolSpace.x7),
                            child: SeasonBanner(
                              season: season,
                              onTap: () => context.push(AppRoutes.seasons),
                            ),
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                  if (quests.isNotEmpty) ...[
                    const SizedBox(height: CoolSpace.x7),
                    Text(
                      context.l10n.homeMissionsTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x4),
                    SizedBox(
                      height: 170,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: quests.take(3).length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: CoolSpace.x3),
                        itemBuilder: (context, index) {
                          return QuestCard(quest: quests[index]);
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: CoolSpace.x8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryServiceDeck extends StatelessWidget {
  const _SecondaryServiceDeck({
    required this.dashboardAsync,
    required this.hasActiveBankPartner,
  });

  final AsyncValue<HomeDashboardData?> dashboardAsync;
  final bool hasActiveBankPartner;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return CoolCard(
      useGradient: false,
      backgroundColor: colors.cardSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Utilities',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'MoMo, groups, partners, and profile stay within easy reach.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CoolSpace.x5),
          const _SecondaryServiceRow(
            title: 'Mobile Money',
            subtitle: 'Pay and review statements',
            icon: Icons.account_balance_wallet_outlined,
            route: AppRoutes.momo,
          ),
          const SizedBox(height: CoolSpace.x3),
          const _SecondaryServiceRow(
            title: 'Groups',
            subtitle: 'Track savings and invites',
            icon: Icons.people_alt_outlined,
            route: AppRoutes.groups,
          ),
          const SizedBox(height: CoolSpace.x3),
          const _SecondaryServiceRow(
            title: 'Profile',
            subtitle: 'Identity, wallet, and settings',
            icon: Icons.person_outline_rounded,
            route: AppRoutes.profile,
          ),
          const SizedBox(height: CoolSpace.x5),
          Row(
            children: [
              Text(
                'Recent activity',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (hasActiveBankPartner)
                Text(
                  'Banking active',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),
          dashboardAsync.when(
            data: (dashboard) => RecentActivityCard(
              activityCount: dashboard?.recentTransactions.length ?? 0,
              recentTransactions: dashboard?.recentTransactions ?? const [],
              useCard: false,
              showHeader: false,
            ),
            loading: () => const ActivityLoadingCard(useCard: false),
            error: (_, _) => const Text('Recent activity unavailable'),
          ),
        ],
      ),
    );
  }
}

class _SecondaryServiceRow extends StatelessWidget {
  const _SecondaryServiceRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String route;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.md)),
        onTap: () => openQuickActionRoute(context, route),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CoolSpace.x2),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.operationalSurface,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.md),
                  ),
                ),
                child: Icon(icon, color: colors.secondaryText),
              ),
              const SizedBox(width: CoolSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x1),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CoolSpace.x2),
              Icon(Icons.arrow_forward_rounded, color: colors.secondaryText),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuietSectionLabel extends StatelessWidget {
  const _QuietSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: colors.secondaryText,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }
}
