import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../rayon/providers/rayon_sports_provider.dart';
import '../../rayon/models/rs_models.dart';

import '../providers/home_dashboard_provider.dart';
import '../widgets/home_community_cards.dart';
import '../widgets/home_fan_savings_card.dart';
import '../widgets/home_hero_carousel.dart';
import '../widgets/home_membership_strip.dart';
import '../widgets/home_quick_services.dart';
import '../widgets/home_shared.dart';

// ─────────────────────────────────────────────────────────────────────
// HomeScreen — exact replica of the design screenshots
// Sections: Hero Carousel → Membership → Fan Savings → Quick Services →
//   Official Network → Global Fan Network → Fan Missions →
//   Club & Community → Partner Network → Community Impact →
//   Stadium Lighting
// ─────────────────────────────────────────────────────────────────────

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: colors.appBackground,
      body: CoolScreenBackground(
        child: Consumer(
          builder: (context, ref, _) {
            final rayon = ref.watch(rayonSportsDataProvider);
            final membership = ref.watch(rayonMembershipProvider);
            final nextMatch = ref.watch(rayonNextMatchProvider);
            final isRecovering = ref.watch(rayonActionLoadingProvider);
            final dashboard = ref.watch(homeDashboardProvider).asData?.value;

            final mem = membership.valueOrNull ?? rayon.valueOrNull?.membership;
            final match = nextMatch.valueOrNull;
            final data = rayon.valueOrNull;
            final activeInitiatives =
                data?.initiatives
                    .where((initiative) => initiative.isActive)
                    .toList(growable: false) ??
                const <RsInitiative>[];
            final hasInitiativeData = activeInitiatives.isNotEmpty;
            final totalInitiativeRaised = hasInitiativeData
                ? activeInitiatives.fold<int>(
                    0,
                    (sum, initiative) => sum + initiative.raisedAmount,
                  )
                : null;
            final totalInitiativeTarget = hasInitiativeData
                ? activeInitiatives.fold<int>(
                    0,
                    (sum, initiative) => sum + initiative.targetAmount,
                  )
                : null;
            final totalInitiativeSupporters = hasInitiativeData
                ? activeInitiatives.fold<int>(
                    0,
                    (sum, initiative) => sum + initiative.supporterCount,
                  )
                : null;
            RsInitiative? stadiumInitiative;
            for (final initiative in activeInitiatives) {
              if (initiative.category == InitiativeCategory.stadium) {
                stadiumInitiative = initiative;
                break;
              }
            }

            return CustomScrollView(
              slivers: [
                // ── 0. App Bar ──────────────────────────────────────
                SliverAppBar(
                  backgroundColor: colors.appBackground,
                  surfaceTintColor: Colors.transparent,
                  pinned: true,
                  floating: true,
                  elevation: 0,
                  leadingWidth: 72,
                  leading: Padding(
                    padding: const EdgeInsets.only(left: CoolSpace.x5),
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: RsColors.rsRed.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: RsColors.rsRed.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          color: RsColors.rsRed,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ID NUMBER',
                        style: context.coolText.mono(
                          Theme.of(context).textTheme.labelSmall,
                          fontWeight: FontWeight.w700,
                          color: colors.secondaryText,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        mem?.membershipNumber ?? '—',
                        style: context.coolText.mono(
                          Theme.of(context).textTheme.titleMedium,
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── 1. Hero Carousel (Match + Banners) ────────────────
                SliverToBoxAdapter(
                  child: HomeHeroCarousel(
                    match: match,
                    banners: data?.banners ?? const [],
                  ),
                ),

                // ── Content padding ────────────────────────────────
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    CoolSpace.x5,
                    CoolSpace.x3,
                    CoolSpace.x5,
                    CoolSpace.x8 + bottomPad + 80,
                  ),
                  sliver: SliverList.list(
                    children: [
                      // ── 2. Membership Strip ──────────────────────
                      HomeMembershipStrip(
                        membership: mem,
                        isRecovering: isRecovering,
                        onRecover: () => ensureHomeMembership(context, ref),
                      ),
                      const SizedBox(height: CoolSpace.x5),

                      // ── 3. Fan Savings Plan ──────────────────────
                      HomeFanSavingsPlanCard(
                        balance: dashboard?.totalBalance,
                        monthlyNetChange: dashboard?.monthlyNetChange,
                      ),
                      const SizedBox(height: CoolSpace.x5),

                      // ── 4. Quick Services ────────────────────────
                      const HomeQuickServices(),
                      const SizedBox(height: CoolSpace.x5),

                      // ── 5. Official Network Strip ────────────────
                      const HomeOfficialNetworkStrip(),
                      const SizedBox(height: CoolSpace.x5),

                      // ── 6. Global Fan Network ────────────────────
                      HomeGlobalFanNetworkCard(
                        fanCount: data?.registryMembers.length,
                        clubCount: data?.clubs.length,
                        onTap: () => context.push(AppRoutes.rayonRegistry),
                      ),
                      const SizedBox(height: CoolSpace.x5),

                      // ── 7. Fan Missions ──────────────────────────
                      HomeFanMissionsCard(
                        tokens: mem?.points,
                        progress: mem?.progressToNextTier,
                      ),
                      const SizedBox(height: CoolSpace.x5),

                      // ── 8. Club & Community ──────────────────────
                      HomeClubCommunityCard(
                        raisedAmount: totalInitiativeRaised,
                        targetAmount: totalInitiativeTarget,
                        supporterCount: totalInitiativeSupporters,
                      ),
                      const SizedBox(height: CoolSpace.x5),

                      // ── 9. Partner Network ───────────────────────
                      HomePartnerNetworkCard(
                        onTap: () => context.push(AppRoutes.partners),
                      ),
                      const SizedBox(height: CoolSpace.x5),

                      // ── 10. Community Impact header ──────────────
                      Padding(
                        padding: const EdgeInsets.only(bottom: CoolSpace.x4),
                        child: Text(
                          'COMMUNITY IMPACT',
                          style: context.coolText.mono(
                            Theme.of(context).textTheme.labelSmall,
                            fontWeight: FontWeight.w700,
                            color: colors.secondaryText,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),

                      // ── 11. Stadium Lighting ─────────────────────
                      HomeStadiumLightingCard(
                        raisedAmount: stadiumInitiative?.raisedAmount,
                        targetAmount: stadiumInitiative?.targetAmount,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
