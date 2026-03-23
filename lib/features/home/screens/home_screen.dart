import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/status/providers/home_status_providers.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_layout.dart';

import '../../../shared/widgets/cool_error_boundary.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/quest_card.dart';
import '../../../shared/widgets/season_banner.dart';
import '../../../shared/widgets/section_title.dart';
import '../../partners/providers/partner_provider.dart';
import '../../partners/providers/rayon_sports_provider.dart';
import '../../admin/providers/special_products_provider.dart';
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
    final l10n = context.l10n;
    final dashboardAsync = ref.watch(homeDashboardProvider);
    final quests = ref.watch(questsProvider);

    Future<void> refresh() async {
      ref.invalidate(homeDashboardProvider);
      await ref.read(homeDashboardProvider.future);
    }

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
                    const SizedBox(height: 24),

                    SectionTitle(title: l10n.quickActions),
                    const SizedBox(height: 12),
                    const QuickActionSection(),
                    const SizedBox(height: 24),

                    SectionTitle(
                      title: l10n.recentActivity,
                      actionLabel: l10n.statementsLabel,
                      action: () => context.push(AppRoutes.momoStatements),
                    ),
                    const SizedBox(height: 12),
                    dashboardAsync.when(
                      data: (dashboard) => RecentActivityCard(
                        activityCount:
                            dashboard?.recentTransactions.length ?? 0,
                        recentTransactions:
                            dashboard?.recentTransactions ?? const [],
                      ),
                      loading: () => const ActivityLoadingCard(),
                      error: (_, _) => OverviewErrorCard(
                        onRetry: () => ref.invalidate(homeDashboardProvider),
                      ),
                    ),

                    RayonSportCard(
                      membershipAsync: ref.watch(rayonMembershipProvider),
                      clubsAsync: ref.watch(rayonFanClubsProvider),
                      matchesAsync: ref.watch(rayonMatchesProvider),
                      initiativesAsync: ref.watch(rayonInitiativesProvider),
                    ),
                    if (ref.watch(hasActiveBankPartnerProvider)) ...[
                      const SizedBox(height: 14),
                      dashboardAsync.when(
                        data: (dashboard) => GroupSavingsCard(data: dashboard),
                        loading: () => const OverviewLoadingCard(),
                        error: (_, _) => OverviewErrorCard(
                          onRetry: () => ref.invalidate(homeDashboardProvider),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const ReferralBanner(),
                    const SizedBox(height: 20),
                    const NexusRecommendationsSection(),
                    const SizedBox(height: 14),
                    ...ref
                        .watch(activeSpecialProductsProvider)
                        .maybeWhen(
                          data: (products) => products.map(
                            (p) => Padding(
                              padding: const EdgeInsets.only(bottom: 14),
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
                              padding: const EdgeInsets.only(top: 32),
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
                      const SizedBox(height: 32),
                      SectionTitle(
                        title: l10n.homeMissionsTitle,
                        actionLabel: l10n.openAction,
                        action: () => context.push(AppRoutes.missions),
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
                    const SizedBox(height: 40),
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
