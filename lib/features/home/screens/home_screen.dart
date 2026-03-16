import 'package:flutter/cupertino.dart';
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
import '../../../core/theme/cool_layout.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../core/utils/intl_locale.dart';
import '../../../shared/widgets/cool_assistant_sheet.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_error_boundary.dart';
import '../../../shared/widgets/cool_error_view.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/quest_card.dart';
import '../../../shared/widgets/season_banner.dart';
import '../../../shared/widgets/section_title.dart';
import '../../partners/providers/rayon_sports_provider.dart';
import '../../partners/rayon/models/rs_models.dart';
import '../../admin/providers/special_products_provider.dart';
import '../../mobility/providers/mobility_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/home_dashboard_data.dart';
import '../models/nexus_recommendation.dart';
import '../providers/home_dashboard_provider.dart';
import '../providers/nexus_provider.dart';
import '../widgets/special_product_card.dart';
import '../providers/quick_action_provider.dart';
import '../../../core/status/widgets/referral_banner.dart';

import 'package:flutter_animate/flutter_animate.dart';

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
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: CoolLayout.fabBottomClearance),
        child: FloatingActionButton.extended(
          onPressed: () => CoolAssistantSheet.show(context),
          backgroundColor: AppColors.accent,
          elevation: 12,
          highlightElevation: 4,
          icon: const Icon(Icons.auto_awesome_rounded, color: Colors.black, size: 20),
          label: Text(
            'Cool Assistant',
            style: GoogleFonts.dmSans(
              color: Colors.black,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
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
                    _HomeHeader(ref: ref, palette: palette, l10n: l10n),
                    const SizedBox(height: 20),
                    const _NexusRecommendationsSection(),
                    const SizedBox(height: 14),
                    const ReferralBanner(),
                    const SizedBox(height: 24),
                    _RayonSportCard(
                      membershipAsync: ref.watch(rayonMembershipProvider),
                      clubsAsync: ref.watch(rayonFanClubsProvider),
                      matchesAsync: ref.watch(rayonMatchesProvider),
                      initiativesAsync: ref.watch(rayonInitiativesProvider),
                    ),
                    const SizedBox(height: 14),
                    dashboardAsync.when(
                      data: (dashboard) => _GroupSavingsCard(data: dashboard),
                      loading: () => const _OverviewLoadingCard(),
                      error: (_, _) => _OverviewErrorCard(
                        onRetry: () => ref.invalidate(homeDashboardProvider),
                      ),
                    ),
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
                    const SizedBox(height: 10),
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
                                .toList(),
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
                      action: () => context.push(AppRoutes.momoStatements),
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


// ─── Home Header: Title + Scanner + Driver Toggle ──────────────────────────

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.ref,
    required this.palette,
    required this.l10n,
  });

  final WidgetRef ref;
  final CoolPalette palette;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isDriver = user?.isDriver ?? false;
    final mobilityState = ref.watch(mobilityProvider);
    final locationState = ref.watch(mobilityLocationProvider);
    final isOnline = mobilityState.isDriverOnline;
    final isUpdating = mobilityState.isUpdatingDriverStatus;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            l10n.navHome,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.displayLarge,
          ),
        ),
        const SizedBox(width: 8),

        // ── QR Scanner Icon ──
        Semantics(
          button: true,
          label: 'Scan QR code',
          hint: 'Opens MoMo QR scanner',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.push('${AppRoutes.scanner}?mode=momo'),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: palette.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.border),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 22,
                  color: palette.accent,
                ),
              ),
            ),
          ),
        ),

        // ── Driver On/Off Toggle ──
        if (isDriver) ...[
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: isOnline ? 'Go offline' : 'Go online',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: isUpdating
                    ? null
                    : () {
                        final pos = locationState.position;
                        ref
                            .read(mobilityProvider.notifier)
                            .toggleDriverOnline(
                              pos?.latitude ?? 0,
                              pos?.longitude ?? 0,
                            );
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isOnline
                        ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                        : palette.surface2,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isOnline
                          ? const Color(0xFF22C55E).withValues(alpha: 0.5)
                          : palette.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isUpdating)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CupertinoActivityIndicator(radius: 7),
                        )
                      else
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isOnline
                                ? const Color(0xFF22C55E)
                                : palette.text3,
                          ),
                        ),
                      const SizedBox(width: 6),
                      Text(
                        isOnline ? 'Online' : 'Offline',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isOnline
                              ? const Color(0xFF22C55E)
                              : palette.text2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Card 1: Rayon Sport Fan Card ──────────────────────────────────────────

class _RayonSportCard extends StatelessWidget {
  const _RayonSportCard({
    required this.membershipAsync,
    required this.clubsAsync,
    required this.matchesAsync,
    required this.initiativesAsync,
  });

  final AsyncValue<RsFanMembership?> membershipAsync;
  final AsyncValue<List<RsFanClub>> clubsAsync;
  final AsyncValue<List<RsMatch>> matchesAsync;
  final AsyncValue<List<RsInitiative>> initiativesAsync;

  @override
  Widget build(BuildContext context) {
    final membership = membershipAsync.valueOrNull;
    final clubs = clubsAsync.valueOrNull ?? const <RsFanClub>[];
    final matches = matchesAsync.valueOrNull ?? const <RsMatch>[];
    final initiatives = initiativesAsync.valueOrNull ?? const <RsInitiative>[];

    final isMember = membership != null;
    final totalFans = clubs.fold<int>(0, (sum, c) => sum + c.memberCount);
    final onSaleMatches = matches.where((m) => m.isOnSale).toList();
    final hasOpenTickets = onSaleMatches.isNotEmpty;
    final hasInitiatives = initiatives.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        gradient: RsColors.rsCardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RsColors.rsBlueBorder),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: RsColors.rsBlue.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text('⚽', style: TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Rayon Sports FC',
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: RsColors.rsWhite,
                  ),
                ),
              ),
              if (isMember)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: RsColors.rsGold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: RsColors.rsGold.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    membership.tier.label,
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: RsColors.rsGoldLight,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _HomeStatPill(
                label: 'Fans',
                value: NumberFormat.compact().format(totalFans),
                valueColor: RsColors.rsGoldLight,
                bgColor: RsColors.rsBlue.withValues(alpha: 0.25),
                borderColor: RsColors.rsBlueBorder,
              ),
              if (hasInitiatives)
                _HomeCtaChip(
                  label: 'Contribute',
                  icon: Icons.volunteer_activism_rounded,
                  onTap: () => context.push(AppRoutes.rayonSupport),
                  color: RsColors.rsGoldLight,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!isMember)
                _HomeCtaChip(
                  label: 'Join',
                  icon: Icons.person_add_alt_1_rounded,
                  onTap: () => context.push(AppRoutes.rayonHome),
                  color: RsColors.rsGold,
                ),
              if (isMember && hasOpenTickets)
                _HomeCtaChip(
                  label: 'Buy Tickets',
                  icon: Icons.confirmation_num_outlined,
                  onTap: () => context.push(AppRoutes.rayonTickets),
                  color: RsColors.rsBluePale,
                ),
              if (isMember)
                _HomeCtaChip(
                  label: 'Shop',
                  icon: Icons.shopping_bag_outlined,
                  onTap: () => context.push(AppRoutes.rayonShop),
                  color: RsColors.rsWhite,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Card 2: Group Savings Promotion Card ─────────────────────────────────

class _GroupSavingsCard extends StatelessWidget {
  const _GroupSavingsCard({required this.data});

  final HomeDashboardData? data;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final localeName = resolveIntlLocale(context);
    final totalBalance = data?.totalBalance ?? 0;
    final memberCount = data?.memberCount ?? 0;

    return CoolCard(
      backgroundColor: palette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.accentGlow,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.people_alt_outlined,
                  size: 20,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Group Savings',
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HomeStatPill(
                label: 'Saved',
                value: _formatCurrency(totalBalance, localeName),
                valueColor: palette.accent,
                bgColor: palette.surface2,
                borderColor: palette.border,
              ),
              _HomeStatPill(
                label: 'Groups',
                value: '$memberCount',
                valueColor: palette.text,
                bgColor: palette.surface2,
                borderColor: palette.border,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _HomeCtaChip(
            label: 'Explore',
            icon: Icons.search_rounded,
            onTap: () => context.push(AppRoutes.groups),
            color: palette.accent,
          ),
        ],
      ),
    );
  }
}

// ─── Shared: Stat Pill & CTA Chip ─────────────────────────────────────────

class _HomeStatPill extends StatelessWidget {
  const _HomeStatPill({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.bgColor,
    required this.borderColor,
  });

  final String label;
  final String value;
  final Color valueColor;
  final Color bgColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
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
                color: valueColor.withValues(alpha: 0.6),
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

class _HomeCtaChip extends StatelessWidget {
  const _HomeCtaChip({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
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

class _NexusRecommendationsSection extends ConsumerWidget {
  const _NexusRecommendationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommendationsAsync = ref.watch(nexusRecommendationsProvider);

    return recommendationsAsync.when(
      data: (recommendations) {
        if (recommendations.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 8),
                Text(
                  'OPPORTUNITIES FOR YOU',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: AppColors.accent,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recommendations.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  return _NexusCard(recommendation: recommendations[index]);
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _NexusCard extends StatelessWidget {
  const _NexusCard({required this.recommendation});

  final NexusRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;

    return GestureDetector(
      onTap: () => openQuickActionRoute(context, recommendation.ctaAction),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.surface,
              AppColors.accent.withValues(alpha: 0.03),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    recommendation.type.label,
                    style: GoogleFonts.dmSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                Text(
                  recommendation.iconEmoji,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            const Spacer(),
            Text(
              recommendation.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: palette.text,
              ),
            ),
            Text(
              recommendation.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.text2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              recommendation.rationale,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.accent,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
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
