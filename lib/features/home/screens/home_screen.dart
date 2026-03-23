import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/status/providers/home_status_providers.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_layout.dart';

import '../../../shared/widgets/cool_error_boundary.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/quest_card.dart';
import '../../../shared/widgets/season_banner.dart';
import '../../partners/providers/partner_provider.dart';
import '../../partners/providers/rayon_sports_provider.dart';
import '../../admin/providers/special_products_provider.dart';
import '../models/home_dashboard_data.dart';
import '../providers/home_dashboard_provider.dart';
import '../providers/quick_action_provider.dart';
import '../../../core/status/widgets/referral_banner.dart';

import 'package:flutter_animate/flutter_animate.dart';

import '../widgets/group_savings_card.dart';
import '../widgets/home_header.dart';
import '../widgets/home_state_cards.dart';
import '../widgets/nexus_recommendations_section.dart';
import '../widgets/quick_action_section.dart';
import '../widgets/recent_activity_card.dart';
import '../widgets/rayon_sport_card.dart';
import '../widgets/special_product_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

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

    final priorityModule = hasActiveBankPartner
        ? dashboardAsync.when(
            data: (dashboard) => GroupSavingsCard(data: dashboard),
            loading: () => const OverviewLoadingCard(),
            error: (_, _) => OverviewErrorCard(
              onRetry: () => ref.invalidate(homeDashboardProvider),
            ),
          )
        : RayonSportCard(
            membershipAsync: ref.watch(rayonMembershipProvider),
            clubsAsync: ref.watch(rayonFanClubsProvider),
            matchesAsync: ref.watch(rayonMatchesProvider),
            initiativesAsync: ref.watch(rayonInitiativesProvider),
          );

    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CoolErrorBoundary(
          onRetry: () {
            ref.invalidate(homeDashboardProvider);
            ref.invalidate(currentCountryQuickActionsProvider);
            ref.invalidate(activeSeasonProvider);
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
                    const HomeHeader(),
                    const SizedBox(height: CoolSpace.x8),
                    _HomeCommandDeck(dashboardAsync: dashboardAsync),
                    const SizedBox(height: CoolSpace.x8),
                    priorityModule,
                    const SizedBox(height: CoolSpace.x8),
                    const ReferralBanner(),
                    const SizedBox(height: CoolSpace.x6),
                    const NexusRecommendationsSection(),
                    if (hasActiveBankPartner) ...[
                      const SizedBox(height: CoolSpace.x6),
                      RayonSportCard(
                        membershipAsync: ref.watch(rayonMembershipProvider),
                        clubsAsync: ref.watch(rayonFanClubsProvider),
                        matchesAsync: ref.watch(rayonMatchesProvider),
                        initiativesAsync: ref.watch(rayonInitiativesProvider),
                      ),
                    ],
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
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
      ),
    );
  }
}

class _HomeCommandDeck extends ConsumerWidget {
  const _HomeCommandDeck({required this.dashboardAsync});

  final AsyncValue<HomeDashboardData?> dashboardAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return CoolCard(
      useGradient: false,
      backgroundColor: colors.cardSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily Command',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Act fast. Check flow.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CoolSpace.x6),
          _DeckLabel(label: context.l10n.quickActions),
          const SizedBox(height: CoolSpace.x3),
          const QuickActionSection(useCard: false, maxItems: 4),
          const SizedBox(height: CoolSpace.x6),
          _DeckLabel(label: context.l10n.recentActivity),
          const SizedBox(height: CoolSpace.x3),
          dashboardAsync.when(
            data: (dashboard) => RecentActivityCard(
              activityCount: dashboard?.recentTransactions.length ?? 0,
              recentTransactions: dashboard?.recentTransactions ?? const [],
              useCard: false,
              showHeader: false,
            ),
            loading: () => const ActivityLoadingCard(useCard: false),
            error: (_, _) => OverviewErrorCard(
              onRetry: () => ref.invalidate(homeDashboardProvider),
              useCard: false,
            ),
          ),
          const SizedBox(height: CoolSpace.x5),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.push(AppRoutes.momoStatements),
              style: TextButton.styleFrom(
                foregroundColor: colors.accent,
                padding: EdgeInsets.zero,
              ),
              child: Text(
                context.l10n.statementsLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckLabel extends StatelessWidget {
  const _DeckLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: context.coolSemanticColors.secondaryText,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    );
  }
}
