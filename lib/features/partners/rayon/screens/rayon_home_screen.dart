import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/providers/production_redesign_provider.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../core/theme/rs_text_styles.dart';
import '../../../../core/theme/cool_layout.dart';
import '../../../../features/auth/models/user_profile.dart';
import '../../../../features/auth/providers/auth_provider.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_glass_card.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../models/rs_models.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../../../shared/widgets/core_app_scaffold.dart';
import '../../../../core/l10n/l10n.dart';

part 'rayon_home_screen_parts.dart';

class RayonHomeScreen extends StatelessWidget {
  const RayonHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final rayon = ref.watch(rayonSportsDataProvider);
        final membership = ref.watch(rayonMembershipProvider);
        final nextMatch = ref.watch(rayonNextMatchProvider);
        final user = ref.watch(currentUserProvider);
        final isRecoveringMembership = ref.watch(rayonActionLoadingProvider);
        final activeMembership = membership.asData?.value;
        ref.watch(
          productionRedesignEnabledProvider(
            const ProductionRedesignScope(
              route: ProductionRedesignRoutes.rayonHome,
              partner: 'rayon',
            ),
          ),
        );

        return CoreAppScaffold(
          title: context.l10n.rayonSports,
          fallbackLocation: AppRoutes.partners,
          scrollable: false,
          showHomeButton: true,
          actions: const [_NotificationAction(), SizedBox(width: 8)],
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: CoolLayout.rootPagePadding,
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DashboardHeroCarousel(
                        user: user,
                        membership: activeMembership,
                        nextMatch: nextMatch.valueOrNull,
                        data: rayon.valueOrNull,
                      ),
                      const SizedBox(height: CoolSpace.x6),
                      membership.when(
                        data: (fanMembership) => _DashboardMembershipStrip(
                          membership: fanMembership,
                          user: user,
                          isRecoveringMembership: isRecoveringMembership,
                          onRecoverMembership: () =>
                              _ensureMembership(context, ref),
                        ),
                        loading: () => const CoolSkeleton.card(),
                        error: (_, _) => _DashboardMembershipStrip(
                          membership: null,
                          user: user,
                          isRecoveringMembership: isRecoveringMembership,
                          onRecoverMembership: () =>
                              _ensureMembership(context, ref),
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x6),
                      const _DashboardQuickActionGrid(
                        items: [
                          _DashboardQuickActionItem(
                            icon: Icons.confirmation_number_rounded,
                            label: 'Tickets',
                            route: AppRoutes.rayonTickets,
                            accentColor: RsColors.rsBlue,
                          ),
                          _DashboardQuickActionItem(
                            icon: Icons.face_retouching_natural_rounded,
                            label: 'BioPay',
                            route: AppRoutes.biopayHome,
                            accentColor: RsColors.rsGold,
                          ),
                          _DashboardQuickActionItem(
                            icon: Icons.account_balance_wallet_rounded,
                            label: 'MoMo',
                            route: AppRoutes.momoTab,
                            accentColor: Color(0xFF4AA4FF),
                          ),
                          _DashboardQuickActionItem(
                            icon: Icons.groups_rounded,
                            label: 'Groups',
                            route: AppRoutes.groups,
                            accentColor: Colors.white,
                          ),
                          _DashboardQuickActionItem(
                            icon: Icons.shopping_bag_rounded,
                            label: 'Shop',
                            route: AppRoutes.rayonShop,
                            accentColor: Colors.white,
                          ),
                          _DashboardQuickActionItem(
                            icon: Icons.person_rounded,
                            label: 'Profile',
                            route: AppRoutes.rayonProfile,
                            accentColor: RsColors.rsGold,
                          ),
                        ],
                      ),
                      const SizedBox(height: CoolSpace.x6),
                      rayon.when(
                        data: (data) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _DashboardPromoStack(data: data),
                            const SizedBox(height: CoolSpace.x6),
                            _DashboardOperationsRail(
                              data: data,
                              membership: activeMembership ?? data.membership,
                            ),
                          ],
                        ),
                        loading: () => const CoolSkeletonList(itemCount: 3),
                        error: (_, stackTrace) =>
                            const CoolSkeletonList(itemCount: 2),
                      ),
                      const SizedBox(height: CoolSpace.x6),
                      Text(
                        'Matchday Access',
                        style: context.coolText.rayonCondensed(
                          Theme.of(context).textTheme.headlineMedium,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x3),
                      nextMatch.when(
                        loading: () => const CoolSkeleton.card(),
                        error: (_, stackTrace) => _DashboardEmptyMatchCard(
                          onTap: () => context.push(AppRoutes.rayonTickets),
                        ),
                        data: (match) => match == null
                            ? _DashboardEmptyMatchCard(
                                onTap: () =>
                                    context.push(AppRoutes.rayonTickets),
                              )
                            : _DashboardMatchCard(
                                match: match,
                                membership: activeMembership,
                                onPrimaryTap: () =>
                                    context.push(AppRoutes.rayonTickets),
                                onSecondaryTap: () =>
                                    context.push(AppRoutes.rayonMembership),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NotificationAction extends StatelessWidget {
  const _NotificationAction();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: IconButton(
        onPressed: () {
          CoolToast.info(context, 'Notifications coming soon');
        },
        tooltip: 'Notifications',
        icon: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}

class _DashboardHeroCarousel extends StatefulWidget {
  const _DashboardHeroCarousel({
    required this.user,
    required this.membership,
    required this.nextMatch,
    required this.data,
  });

  final UserProfile? user;
  final FanMembership? membership;
  final RsMatch? nextMatch;
  final RayonSportsData? data;

  @override
  State<_DashboardHeroCarousel> createState() => _DashboardHeroCarouselState();
}

class _DashboardHeroCarouselState extends State<_DashboardHeroCarousel> {
  late final PageController _controller;
  Timer? _rotationTimer;
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _rotationTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_controller.hasClients) {
        return;
      }
      final pageCount = _slides(context).length;
      if (pageCount <= 1) {
        return;
      }
      final nextIndex = (_activeIndex + 1) % pageCount;
      _controller.animateToPage(
        nextIndex,
        duration: CoolMotion.emphasized,
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  List<_DashboardHeroSlideData> _slides(BuildContext context) {
    final membership = widget.membership;
    final nextMatch = widget.nextMatch;
    final data = widget.data;
    final userName = widget.user?.fullName.trim();

    return <_DashboardHeroSlideData>[
      if (nextMatch != null)
        _DashboardHeroSlideData(
          tag: nextMatch.competition.toUpperCase(),
          title: '${nextMatch.homeTeam} vs ${nextMatch.awayTeam}',
          subtitle: '${nextMatch.venue} • ${nextMatch.kickoffTime}',
          meta: MaterialLocalizations.of(
            context,
          ).formatMediumDate(nextMatch.matchDate),
          icon: Icons.sports_soccer_rounded,
          background: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F1E49), Color(0xFF0047AB), Color(0xFF050505)],
          ),
          actionLabel: 'Open Tickets',
          onTap: () => context.push(AppRoutes.rayonTickets),
        )
      else
        _DashboardHeroSlideData(
          tag: 'RAYON HOME',
          title: 'Supporters move together',
          subtitle: 'Tickets, groups, MoMo, and fan identity',
          meta: userName?.isNotEmpty == true ? 'Welcome back $userName' : null,
          icon: Icons.waves_rounded,
          background: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF111111), Color(0xFF0047AB), Color(0xFF050505)],
          ),
          actionLabel: 'Explore Club',
          onTap: () => context.push(AppRoutes.rayonSupport),
        ),
      _DashboardHeroSlideData(
        tag: 'FAN STATUS',
        title: membership == null
            ? 'Claim your membership'
            : '${membership.tier.label} tier unlocked',
        subtitle: membership == null
            ? 'Recover your profile to unlock tickets and discounts'
            : '${_dashboardCompactCount(membership.points)} points • ${membership.chapter}',
        meta: membership == null
            ? 'Get your digital fan identity'
            : 'Member #${membership.membershipNumber}',
        icon: Icons.workspace_premium_rounded,
        background: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171310), Color(0xFFC9A84C), Color(0xFF050505)],
        ),
        actionLabel: membership == null ? 'Recover Access' : 'View Profile',
        onTap: () => context.push(
          membership == null ? AppRoutes.profile : AppRoutes.rayonProfile,
        ),
      ),
      _DashboardHeroSlideData(
        tag: 'LIVE CHANNELS',
        title: 'MoMo and BioPay ready',
        subtitle:
            '${_dashboardCompactCount(data?.tickets.length ?? 0)} tickets • ${_dashboardCompactCount(data?.products.length ?? 0)} products',
        meta: 'Signed-in fan checkout with face-to-USSD handoff',
        icon: Icons.account_balance_wallet_rounded,
        background: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D111A), Color(0xFF1A1A1A), Color(0xFF050505)],
        ),
        actionLabel: 'Open Wallet',
        onTap: () => context.push(AppRoutes.momoTab),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides(context);

    return Column(
      children: [
        SizedBox(
          height: 320,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (index) => setState(() => _activeIndex = index),
            itemCount: slides.length,
            itemBuilder: (context, index) {
              final slide = slides[index];
              return _DashboardHeroSlide(slide: slide);
            },
          ),
        ),
        const SizedBox(height: CoolSpace.x3),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < slides.length; index++) ...[
              AnimatedContainer(
                duration: CoolMotion.quick,
                width: _activeIndex == index ? 28 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _activeIndex == index
                      ? context.coolSemanticColors.accent
                      : context.coolSemanticColors.borderStrong,
                  borderRadius: BorderRadius.circular(CoolRadii.pill),
                ),
              ),
              if (index != slides.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }
}

class _DashboardHeroSlideData {
  const _DashboardHeroSlideData({
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.background,
    required this.actionLabel,
    required this.onTap,
    this.meta,
  });

  final String tag;
  final String title;
  final String subtitle;
  final String? meta;
  final IconData icon;
  final Gradient background;
  final String actionLabel;
  final VoidCallback onTap;
}

class _DashboardHeroSlide extends StatelessWidget {
  const _DashboardHeroSlide({required this.slide});

  final _DashboardHeroSlideData slide;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: slide.background),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                right: -18,
                top: -12,
                child: Icon(
                  slide.icon,
                  size: 168,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              Positioned(
                left: -20,
                bottom: -28,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.highlightColor.withValues(alpha: 0.06),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(CoolSpace.x7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CoolSpace.x2,
                        vertical: CoolSpace.x1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(CoolRadii.sm),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Text(
                        slide.tag,
                        style: context.coolText.mono(
                          Theme.of(context).textTheme.labelSmall,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.9,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      slide.title.toUpperCase(),
                      style: context.coolText.rayonCondensed(
                        Theme.of(context).textTheme.displaySmall,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.2,
                        height: 0.92,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x3),
                    Text(
                      slide.subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.84),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (slide.meta != null) ...[
                      const SizedBox(height: CoolSpace.x2),
                      Text(
                        slide.meta!,
                        style: context.coolText.mono(
                          Theme.of(context).textTheme.labelSmall,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.58),
                          letterSpacing: 0.7,
                        ),
                      ),
                    ],
                    const SizedBox(height: CoolSpace.x5),
                    CoolButton(
                      label: slide.actionLabel,
                      onTap: slide.onTap,
                      fullWidth: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardMembershipStrip extends StatelessWidget {
  const _DashboardMembershipStrip({
    required this.membership,
    required this.user,
    required this.isRecoveringMembership,
    required this.onRecoverMembership,
  });

  final FanMembership? membership;
  final UserProfile? user;
  final bool isRecoveringMembership;
  final VoidCallback onRecoverMembership;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final membershipLabel = membership?.tier.label ?? 'Guest';
    final points = membership?.points ?? 0;
    final progress = membership?.progressToNextTier ?? 0;
    final membershipSummary = membership == null
        ? 'Recover your membership to unlock matchday priority.'
        : '${membership!.displayName} • ${membership!.chapter}';

    return CoolGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: CoolSpace.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Tier',
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.labelSmall,
                        fontWeight: FontWeight.w700,
                        color: colors.secondaryText,
                        letterSpacing: 0.9,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x1),
                    Text(
                      membershipLabel.toUpperCase(),
                      style: context.coolText.rayonCondensed(
                        Theme.of(context).textTheme.headlineMedium,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${_dashboardCompactCount(points)} pts',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.titleMedium,
                  fontWeight: FontWeight.w800,
                  color: colors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x5),
          ClipRRect(
            borderRadius: BorderRadius.circular(CoolRadii.pill),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress.clamp(0, 1),
              backgroundColor: colors.cardSurfaceStrong,
              color: colors.accent,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Row(
            children: [
              Expanded(
                child: Text(
                  membershipSummary,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (membership == null || user?.isProfileComplete != true)
                TextButton(
                  onPressed: isRecoveringMembership
                      ? null
                      : onRecoverMembership,
                  child: Text(
                    isRecoveringMembership ? 'Working' : 'Recover',
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.labelSmall,
                      fontWeight: FontWeight.w800,
                      color: colors.accent,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardQuickActionItem {
  const _DashboardQuickActionItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final String route;
  final Color accentColor;
}

class _DashboardQuickActionGrid extends StatelessWidget {
  const _DashboardQuickActionGrid({required this.items});

  final List<_DashboardQuickActionItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: CoolSpace.x4,
      runSpacing: CoolSpace.x4,
      children: [
        for (final item in items) _DashboardQuickActionButton(item: item),
      ],
    );
  }
}

class _DashboardQuickActionButton extends StatelessWidget {
  const _DashboardQuickActionButton({required this.item});

  final _DashboardQuickActionItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return SizedBox(
      width: 86,
      child: InkWell(
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        onTap: () => context.push(item.route),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.highlightColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(CoolRadii.lg),
                border: Border.all(color: colors.border),
              ),
              alignment: Alignment.center,
              child: Icon(item.icon, color: item.accentColor, size: 28),
            ),
            const SizedBox(height: CoolSpace.x2),
            Text(
              item.label,
              textAlign: TextAlign.center,
              style: context.coolText.mono(
                Theme.of(context).textTheme.labelSmall,
                fontWeight: FontWeight.w800,
                color: colors.secondaryText,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardPromoStack extends StatelessWidget {
  const _DashboardPromoStack({required this.data});

  final RayonSportsData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DashboardPromoCard(
          icon: Icons.favorite_rounded,
          tag: 'FUNDRAISING',
          title: 'Support club causes',
          subtitle:
              '${_dashboardCompactCount(data.initiatives.length)} active initiatives ready for contributions.',
          actionLabel: 'Open Support',
          onTap: () => context.push(AppRoutes.rayonSupport),
          accent: RsColors.rsGold,
        ),
        const SizedBox(height: CoolSpace.x4),
        _DashboardPromoCard(
          icon: Icons.groups_rounded,
          tag: 'COMMUNITY',
          title: 'Move with fan groups',
          subtitle:
              '${_dashboardCompactCount(data.clubs.length)} chapters and ${_dashboardCompactCount(data.joinedClubIds.length)} joined communities.',
          actionLabel: 'Open Groups',
          onTap: () => context.push(AppRoutes.groups),
          accent: Colors.white,
        ),
        const SizedBox(height: CoolSpace.x4),
        _DashboardPromoCard(
          icon: Icons.badge_rounded,
          tag: 'REGISTRY',
          title: 'Verified supporter registry',
          subtitle:
              '${_dashboardCompactCount(data.registryMembers.length)} supporters ready for identity and access checks.',
          actionLabel: 'Open Registry',
          onTap: () => context.push(AppRoutes.rayonRegistry),
          accent: const Color(0xFF4AA4FF),
        ),
      ],
    );
  }
}

class _DashboardPromoCard extends StatelessWidget {
  const _DashboardPromoCard({
    required this.icon,
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
    required this.accent,
  });

  final IconData icon;
  final String tag;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  border: Border.all(color: accent.withValues(alpha: 0.24)),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: CoolSpace.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tag,
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.labelSmall,
                        fontWeight: FontWeight.w700,
                        color: colors.secondaryText,
                        letterSpacing: 0.9,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x1),
                    Text(
                      title.toUpperCase(),
                      style: context.coolText.rayonCondensed(
                        Theme.of(context).textTheme.headlineMedium,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          CoolButton(
            label: actionLabel,
            onTap: onTap,
            fullWidth: false,
            variant: CoolButtonVariant.secondary,
            icon: Icons.arrow_forward_rounded,
          ),
        ],
      ),
    );
  }
}

class _DashboardOperationsRail extends StatelessWidget {
  const _DashboardOperationsRail({
    required this.data,
    required this.membership,
  });

  final RayonSportsData data;
  final FanMembership? membership;

  @override
  Widget build(BuildContext context) {
    final cards =
        <
          ({
            String label,
            String value,
            IconData icon,
            String route,
            Color accent,
          })
        >[
          (
            label: 'Shop Revenue',
            value: '${_dashboardCompactCount(data.products.length)} items',
            icon: Icons.shopping_bag_rounded,
            route: AppRoutes.rayonShop,
            accent: Colors.white,
          ),
          (
            label: 'Live Sales',
            value:
                '${_dashboardCompactCount(data.matches.where((m) => m.isOnSale).length)} matches',
            icon: Icons.local_activity_rounded,
            route: AppRoutes.rayonTickets,
            accent: RsColors.rsBlue,
          ),
          (
            label: 'Member Tier',
            value: membership?.tier.label ?? 'Guest',
            icon: Icons.workspace_premium_rounded,
            route: AppRoutes.rayonMembership,
            accent: RsColors.rsGold,
          ),
          (
            label: 'Fan Clubs',
            value: '${_dashboardCompactCount(data.clubs.length)} chapters',
            icon: Icons.flag_circle_rounded,
            route: AppRoutes.rayonClubs,
            accent: const Color(0xFF4AA4FF),
          ),
        ];

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 154,
        crossAxisSpacing: CoolSpace.x4,
        mainAxisSpacing: CoolSpace.x4,
      ),
      itemBuilder: (context, index) {
        final card = cards[index];
        return CoolCard(
          onTap: () => context.push(card.route),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: card.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                ),
                alignment: Alignment.center,
                child: Icon(card.icon, color: card.accent),
              ),
              const Spacer(),
              Text(
                card.value,
                style: context.coolText.rayonCondensed(
                  Theme.of(context).textTheme.headlineMedium,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: CoolSpace.x1),
              Text(
                card.label,
                style: context.coolText.mono(
                  Theme.of(context).textTheme.labelSmall,
                  fontWeight: FontWeight.w700,
                  color: context.coolSemanticColors.secondaryText,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardMatchCard extends StatelessWidget {
  const _DashboardMatchCard({
    required this.match,
    required this.membership,
    required this.onPrimaryTap,
    required this.onSecondaryTap,
  });

  final RsMatch match;
  final FanMembership? membership;
  final VoidCallback onPrimaryTap;
  final VoidCallback onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return CoolGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            match.competition.toUpperCase(),
            style: context.coolText.mono(
              Theme.of(context).textTheme.labelSmall,
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            '${match.homeTeam} vs ${match.awayTeam}'.toUpperCase(),
            style: context.coolText.rayonCondensed(
              Theme.of(context).textTheme.displaySmall,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
              height: 0.94,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            '${match.venue} • ${match.kickoffTime}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: CoolSpace.x5),
          Row(
            children: [
              Expanded(
                child: _DashboardStatPill(
                  label: 'General',
                  value:
                      '${_dashboardFormatAmount(match.ticketGeneralPrice)} RWF',
                  accent: Colors.white,
                ),
              ),
              const SizedBox(width: CoolSpace.x3),
              Expanded(
                child: _DashboardStatPill(
                  label: 'VIP',
                  value: '${_dashboardFormatAmount(match.ticketVipPrice)} RWF',
                  accent: RsColors.rsGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),
          if (membership != null)
            Text(
              '${membership!.tier.label} access is ${match.isAccessibleForTier(membership!.tier) ? 'live' : 'upcoming'}.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: CoolSpace.x4),
          Row(
            children: [
              Expanded(
                child: CoolButton(label: 'Open Tickets', onTap: onPrimaryTap),
              ),
              const SizedBox(width: CoolSpace.x3),
              Expanded(
                child: CoolButton(
                  label: 'Membership',
                  onTap: onSecondaryTap,
                  variant: CoolButtonVariant.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardStatPill extends StatelessWidget {
  const _DashboardStatPill({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: colors.highlightColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(CoolRadii.md),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.coolText.mono(
              Theme.of(context).textTheme.labelSmall,
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            value,
            style: context.coolText.mono(
              Theme.of(context).textTheme.titleMedium,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardEmptyMatchCard extends StatelessWidget {
  const _DashboardEmptyMatchCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No live match sale right now',
            style: context.coolText.rayonCondensed(
              Theme.of(context).textTheme.headlineMedium,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            'Ticket sales reopen as soon as the next fixture is published.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          CoolButton(label: 'View Tickets', onTap: onTap, fullWidth: false),
        ],
      ),
    );
  }
}

String _dashboardCompactCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(value % 1000000 == 0 ? 0 : 1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}K';
  }
  return '$value';
}

String _dashboardFormatAmount(int value) {
  final source = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < source.length; index++) {
    if (index > 0 && (source.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(source[index]);
  }
  return buffer.toString();
}
