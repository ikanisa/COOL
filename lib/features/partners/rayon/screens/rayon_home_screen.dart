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
import '../../../../shared/widgets/rs_match_card.dart';
import '../models/rs_models.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/rayon_screen_scaffold.dart';
import '../../../../core/l10n/l10n.dart';

class RayonHomeScreen extends StatelessWidget {
  const RayonHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final colors = context.coolSemanticColors;
        final rayon = ref.watch(rayonSportsDataProvider);
        final membership = ref.watch(rayonMembershipProvider);
        final nextMatch = ref.watch(rayonNextMatchProvider);
        final user = ref.watch(currentUserProvider);
        final isRecoveringMembership = ref.watch(rayonActionLoadingProvider);
        final activeMembership = membership.asData?.value;
        final useProductionRedesign = ref.watch(
          productionRedesignEnabledProvider(
            const ProductionRedesignScope(
              route: ProductionRedesignRoutes.rayonHome,
              partner: 'rayon',
            ),
          ),
        );

        return RayonScreenScaffold(
          title: context.l10n.rayonSports,
          fallbackLocation: AppRoutes.partners,
          scrollable: false,
          showHomeButton: true,
          actions: const [_NotificationAction(), SizedBox(width: 8)],
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: CoolLayout.rootPagePadding,
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    membership.when(
                      data: (fanMembership) => _HomeOverviewCard(
                        membership: fanMembership,
                        user: user,
                        isRecoveringMembership: isRecoveringMembership,
                        onRecoverMembership: () =>
                            _ensureMembership(context, ref),
                      ),
                      loading: () => const CoolSkeleton.card(),
                      error: (error, _) => _HomeOverviewCard(
                        membership: null,
                        user: user,
                        isRecoveringMembership: isRecoveringMembership,
                        onRecoverMembership: () =>
                            _ensureMembership(context, ref),
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x6),
                    rayon.when(
                      data: (data) {
                        final serviceItems = _buildHomeServiceItems(
                          context: context,
                          colors: colors,
                          data: data,
                          useProductionRedesign: useProductionRedesign,
                        );

                        return _ClubServicesDeck(
                          data: data,
                          membership: activeMembership ?? data.membership,
                          serviceItems: serviceItems,
                        );
                      },
                      loading: () => const CoolSkeletonList(itemCount: 3),
                      error: (_, stackTrace) => const Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: CoolSkeleton.card()),
                              SizedBox(width: 12),
                              Expanded(child: CoolSkeleton.card()),
                            ],
                          ),
                          SizedBox(height: CoolSpace.x3),
                          Row(
                            children: [
                              Expanded(child: CoolSkeleton.card()),
                              SizedBox(width: 12),
                              Expanded(child: CoolSkeleton.card()),
                            ],
                          ),
                          SizedBox(height: CoolSpace.x3),
                          CoolSkeleton.card(),
                        ],
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x6),
                    const _RsSectionTitle(title: 'Matchday Access'),
                    const SizedBox(height: CoolSpace.x3),
                    nextMatch.when(
                      loading: () => const CoolSkeleton.card(),
                      error: (_, stackTrace) => _EmptyMatchCard(
                        onTap: () =>
                            context.push('/partners/rayon-sports/tickets'),
                      ),
                      data: (match) {
                        if (match == null) {
                          return _EmptyMatchCard(
                            onTap: () =>
                                context.push('/partners/rayon-sports/tickets'),
                          );
                        }
                        return Column(
                          children: [
                            if (useProductionRedesign)
                              _MatchdayBriefCard(
                                match: match,
                                membership: activeMembership,
                                onPrimaryTap: () => context.push(
                                  '/partners/rayon-sports/tickets',
                                ),
                                onSecondaryTap: () => context.push(
                                  '/partners/rayon-sports/membership',
                                ),
                              )
                            else
                              RsMatchCard(
                                match: match,
                                onBuyTap: () => context.push(
                                  '/partners/rayon-sports/tickets',
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ]),
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

List<_HomeServiceItem> _buildHomeServiceItems({
  required BuildContext context,
  required CoolSemanticColors colors,
  required RayonSportsData data,
  required bool useProductionRedesign,
}) {
  final items = <_HomeServiceItem>[
    _HomeServiceItem(
      icon: Icons.people_rounded,
      title: context.l10n.memberRegistry,
      meta: '${_formatCount(data.registryMembers.length)} verified supporters',
      detail: 'Official registry, identity checks, and tier validation.',
      accentColor: RsColors.rsBlue,
      route: '/partners/rayon-sports/registry',
    ),
    if (!useProductionRedesign)
      _HomeServiceItem(
        icon: Icons.groups_rounded,
        title: 'Fan Clubs & Chapters',
        meta:
            '${data.clubs.length} active chapters · ${data.joinedClubIds.length} joined',
        detail: 'Regional membership, local events, and chapter ranking.',
        accentColor: colors.warning,
        route: '/partners/rayon-sports/clubs',
      ),
    _HomeServiceItem(
      icon: Icons.shopping_bag_rounded,
      title: 'Club Shop',
      meta: '${data.products.length} premium listings',
      detail: 'Official merchandise, member pricing, and direct fulfilment.',
      accentColor: colors.accent,
      route: '/partners/rayon-sports/shop',
    ),
    _HomeServiceItem(
      icon: Icons.handshake_rounded,
      title: 'Support Club',
      meta: '${data.initiatives.length} active initiatives',
      detail:
          'Transparent causes, disciplined fundraising, and impact reporting.',
      accentColor: RsColors.rsGold,
      route: '/partners/rayon-sports/support',
    ),
    if (!useProductionRedesign)
      _HomeServiceItem(
        icon: Icons.confirmation_number_rounded,
        title: 'Tickets',
        meta:
            '${data.matches.where((match) => match.isOnSale).length} matches live',
        detail:
            'Priority access, digital entry, and official matchday routing.',
        accentColor: colors.danger,
        route: '/partners/rayon-sports/tickets',
      ),
  ];

  return items;
}

class _HomeServiceItem {
  const _HomeServiceItem({
    required this.icon,
    required this.title,
    required this.meta,
    required this.detail,
    required this.accentColor,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String meta;
  final String detail;
  final Color accentColor;
  final String route;
}

class _HomeOverviewCard extends StatelessWidget {
  const _HomeOverviewCard({
    required this.membership,
    required this.user,
    required this.isRecoveringMembership,
    required this.onRecoverMembership,
  });

  final RsFanMembership? membership;
  final UserProfile? user;
  final bool isRecoveringMembership;
  final Future<void> Function() onRecoverMembership;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final fanName =
        membership?.displayName ?? user?.displayUserId ?? 'Rayon Fan';
    final fanId = _displayId(user, membership);
    final tier = membership?.tier ?? FanTier.blue;
    final progress = membership?.progressToNextTier ?? 0;
    final pointsToNextTier = membership?.pointsToNextTier ?? 0;
    final nextTierLabel = membership == null || tier == FanTier.platinum
        ? null
        : _nextTierLabel(tier);

    return CoolGlassCard(
      borderColor: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      membership == null
                          ? 'OFFICIAL MEMBERSHIP'
                          : 'OFFICIAL MEMBER ID',
                      style: GoogleFonts.dmMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: colors.tertiaryText,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x2),
                    Text(
                      fanName,
                      style: context.coolText.rayon(
                        const TextStyle(fontSize: 28),
                        fontWeight: FontWeight.w800,
                        color: RsColors.rsWhite,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x1),
                    Text(
                      fanId,
                      style: GoogleFonts.dmMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: RsColors.rsWhite.withValues(alpha: 0.72),
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x2),
                    Text(
                      membership == null
                          ? 'Create or restore your verified supporter identity to unlock priority access.'
                          : '${tier.label} tier · ${membership!.chapter}',
                      style: context.coolText.rayon(
                        const TextStyle(fontSize: 15),
                        fontWeight: FontWeight.w600,
                        color: RsColors.rsWhite.withValues(alpha: 0.78),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                children: [
                  const _RayonBrandMark(size: 56),
                  const SizedBox(height: CoolSpace.x2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: tier.color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tier.label.toUpperCase(),
                      style: GoogleFonts.dmMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tier == FanTier.silver
                            ? colors.primaryText
                            : RsColors.rsWhite,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MembershipMetricChip(
                label: membership == null ? 'Status' : 'Points',
                value: membership == null
                    ? 'Pending'
                    : _formatCount(membership!.points),
                accentColor: RsColors.rsBlueLight,
              ),
              _MembershipMetricChip(
                label: 'Chapter',
                value: membership?.chapter ?? 'Assign at activation',
                accentColor: colors.warning,
              ),
              _MembershipMetricChip(
                label: 'Privileges',
                value: membership == null
                    ? 'Ticket priority locked'
                    : tier == FanTier.platinum
                    ? 'Highest access'
                    : 'Tier unlocks active',
                accentColor: RsColors.rsGoldLight,
              ),
            ],
          ),
          if (membership != null) ...[
            const SizedBox(height: CoolSpace.x4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(CoolSpace.x4),
              decoration: BoxDecoration(
                color: colors.glassSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          nextTierLabel == null
                              ? 'Top tier privileges active'
                              : '$pointsToNextTier pts to $nextTierLabel',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: RsColors.rsWhite,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${(progress * 100).round()}%',
                        style: GoogleFonts.dmMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CoolSpace.x2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: colors.cardSurfaceStrong,
                      valueColor: AlwaysStoppedAnimation<Color>(tier.color),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: CoolSpace.x5),
          if (membership == null)
            Row(
              children: [
                Expanded(
                  child: CoolButton(
                    label: 'Create / Restore',
                    onTap: () {
                      onRecoverMembership();
                    },
                    isLoading: isRecoveringMembership,
                    icon: Icons.verified_user_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CoolButton(
                    label: 'View Plans',
                    variant: CoolButtonVariant.secondary,
                    onTap: () {
                      context.push('/partners/rayon-sports/membership');
                    },
                    icon: Icons.layers_outlined,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: CoolButton(
                    label: 'Open Profile',
                    onTap: () {
                      context.push('/partners/rayon-sports/profile');
                    },
                    icon: Icons.person_outline_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CoolButton(
                    label: 'Buy Tickets',
                    variant: CoolButtonVariant.secondary,
                    onTap: () {
                      context.push('/partners/rayon-sports/tickets');
                    },
                    icon: Icons.confirmation_number_outlined,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ClubServicesDeck extends StatelessWidget {
  const _ClubServicesDeck({
    required this.data,
    required this.membership,
    required this.serviceItems,
  });

  final RayonSportsData data;
  final RsFanMembership? membership;
  final List<_HomeServiceItem> serviceItems;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final onSaleMatches = data.matches.where((match) => match.isOnSale).length;
    final ranked = [...data.clubs]
      ..sort((a, b) {
        final memberCompare = b.memberCount.compareTo(a.memberCount);
        if (memberCompare != 0) {
          return memberCompare;
        }
        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) {
          return ratingCompare;
        }
        return a.name.compareTo(b.name);
      });

    return CoolCard(
      useGradient: false,
      backgroundColor: colors.cardSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RAYON SPORTS COMMAND',
                      style: GoogleFonts.dmMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: colors.tertiaryText,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x2),
                    Text(
                      membership == null
                          ? 'Official club access, matchday, and commerce in one trusted surface.'
                          : '${membership!.tier.label} tier access is live across ticketing, chapters, and store privileges.',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: RsColors.rsWhite,
                        fontWeight: FontWeight.w800,
                        height: 1.22,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _SurfaceBadge(
                label: membership?.tier.label.toUpperCase() ?? 'OFFICIAL',
                foreground: membership?.tier == FanTier.silver
                    ? colors.primaryText
                    : RsColors.rsGoldLight,
                background: membership == null
                    ? RsColors.rsGold.withValues(alpha: 0.12)
                    : membership!.tier.color.withValues(alpha: 0.14),
                borderColor: Colors.transparent,
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x5),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SignalTile(
                label: 'Verified fans',
                value: _formatCount(data.registryMembers.length),
              ),
              _SignalTile(
                label: 'Active chapters',
                value: '${data.clubs.length}',
              ),
              _SignalTile(label: 'Matches on sale', value: '$onSaleMatches'),
              _SignalTile(
                label: 'Store listings',
                value: '${data.products.length}',
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x6),
          const _RsSectionTitle(title: 'Club Services'),
          const SizedBox(height: CoolSpace.x3),
          for (var index = 0; index < serviceItems.length; index++) ...[
            _HomeLinkCard(
              icon: serviceItems[index].icon,
              title: serviceItems[index].title,
              meta: serviceItems[index].meta,
              detail: serviceItems[index].detail,
              accentColor: serviceItems[index].accentColor,
              onTap: () => context.push(serviceItems[index].route),
            ),
            if (index != serviceItems.length - 1)
              const SizedBox(height: CoolSpace.x3),
          ],
          const SizedBox(height: CoolSpace.x6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Chapter Standings',
                  style: context.coolText.rayon(
                    const TextStyle(fontSize: 20),
                    fontWeight: FontWeight.w800,
                    color: RsColors.rsWhite,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/partners/rayon-sports/clubs'),
                child: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x1),
          Text(
            'Member growth and chapter credibility ranked for fast scanning.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          if (ranked.isEmpty)
            Text(
              'Chapter rankings will appear as clubs start reporting members and events.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.secondaryText,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            )
          else
            Column(
              children: [
                for (var index = 0; index < ranked.take(3).length; index++) ...[
                  _StandingRow(
                    rank: index + 1,
                    club: ranked[index],
                    joined: data.joinedClubIds.contains(ranked[index].id),
                  ),
                  if (index != ranked.take(3).length - 1)
                    const SizedBox(height: CoolSpace.x2),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _ClubCommandCard extends StatelessWidget {
  const _ClubCommandCard({required this.data, required this.membership});

  final RayonSportsData data;
  final RsFanMembership? membership;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSaleMatches = data.matches.where((match) => match.isOnSale).length;

    return CoolCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF041432), Color(0xFF09235A), Color(0xFF15418A)],
      ),
      borderColor: RsColors.rsBlueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RAYON SPORTS COMMAND',
                      style: GoogleFonts.dmMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x2),
                    Text(
                      membership == null
                          ? 'Official club access, matchday, and commerce in one trusted surface.'
                          : '${membership!.tier.label} tier access is live across ticketing, chapters, and store privileges.',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1.22,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _SurfaceBadge(
                label: 'OFFICIAL',
                foreground: RsColors.rsGoldLight,
                background: RsColors.rsGold.withValues(alpha: 0.12),
                borderColor: RsColors.rsGold.withValues(alpha: 0.34),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x5),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SignalTile(
                label: 'Verified fans',
                value: _formatCount(data.registryMembers.length),
              ),
              _SignalTile(
                label: 'Active chapters',
                value: '${data.clubs.length}',
              ),
              _SignalTile(label: 'Matches on sale', value: '$onSaleMatches'),
              _SignalTile(
                label: 'Store listings',
                value: '${data.products.length}',
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),
          Row(
            children: [
              Expanded(
                child: CoolButton(
                  label: 'Buy Tickets',
                  onTap: () {
                    context.push('/partners/rayon-sports/tickets');
                  },
                  icon: Icons.confirmation_number_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CoolButton(
                  label: membership == null ? 'Join Membership' : 'Fan Clubs',
                  variant: CoolButtonVariant.secondary,
                  onTap: () {
                    context.push(
                      membership == null
                          ? '/partners/rayon-sports/membership'
                          : '/partners/rayon-sports/clubs',
                    );
                  },
                  icon: membership == null
                      ? Icons.workspace_premium_outlined
                      : Icons.groups_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClubStandingsCard extends StatelessWidget {
  const _ClubStandingsCard({
    required this.clubs,
    required this.joinedClubIds,
    required this.onViewAll,
  });

  final List<RsFanClub> clubs;
  final Set<String> joinedClubIds;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final ranked = [...clubs]
      ..sort((a, b) {
        final memberCompare = b.memberCount.compareTo(a.memberCount);
        if (memberCompare != 0) {
          return memberCompare;
        }
        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) {
          return ratingCompare;
        }
        return a.name.compareTo(b.name);
      });

    return CoolCard(
      borderColor: colors.borderStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chapter Standings',
                      style: context.coolText.rayon(
                        const TextStyle(fontSize: 20),
                        fontWeight: FontWeight.w800,
                        color: RsColors.rsWhite,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x1),
                    Text(
                      'Member growth, event energy, and chapter credibility ranked for quick scanning.',
                      style: context.coolText.rayon(
                        const TextStyle(fontSize: 13),
                        fontWeight: FontWeight.w500,
                        color: colors.secondaryText,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: onViewAll, child: const Text('View all')),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),
          if (ranked.isEmpty)
            Text(
              'Chapter rankings will appear as clubs start reporting members and events.',
              style: context.coolText.rayon(
                const TextStyle(fontSize: 13),
                fontWeight: FontWeight.w500,
                color: colors.secondaryText,
              ),
            )
          else
            Column(
              children: [
                for (var index = 0; index < ranked.take(4).length; index++) ...[
                  _StandingRow(
                    rank: index + 1,
                    club: ranked[index],
                    joined: joinedClubIds.contains(ranked[index].id),
                  ),
                  if (index != ranked.take(4).length - 1)
                    const SizedBox(height: CoolSpace.x2),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _MatchdayBriefCard extends StatelessWidget {
  const _MatchdayBriefCard({
    required this.match,
    required this.membership,
    required this.onPrimaryTap,
    required this.onSecondaryTap,
  });

  final RsMatch match;
  final RsFanMembership? membership;
  final VoidCallback onPrimaryTap;
  final VoidCallback onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final tier = membership?.tier ?? FanTier.blue;

    return CoolCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF071630), Color(0xFF0D2351), Color(0xFF13356A)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ticket Office',
                      style: context.coolText.rayon(
                        const TextStyle(fontSize: 20),
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x1),
                    Text(
                      'Official allocation, digital entry, and disciplined priority access for supporters.',
                      style: context.coolText.rayon(
                        const TextStyle(fontSize: 13),
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.74),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _SurfaceBadge(
                label: tier.label.toUpperCase(),
                foreground: tier == FanTier.silver
                    ? colors.primaryText
                    : Colors.white,
                background: tier.color.withValues(alpha: 0.16),
                borderColor: tier.color.withValues(alpha: 0.34),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(
                icon: Icons.verified_outlined,
                label: _matchSalesLabel(match),
              ),
              _InfoPill(
                icon: Icons.local_fire_department_outlined,
                label: _ticketDemandLabel(match),
              ),
              _InfoPill(
                icon: Icons.sell_outlined,
                label: '${_formatRwf(match.ticketGeneralPrice)} general',
              ),
              _InfoPill(
                icon: Icons.workspace_premium_outlined,
                label: '${_formatRwf(match.ticketVipPrice)} VIP',
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),
          Row(
            children: [
              Expanded(
                child: CoolButton(
                  label: match.isOnSale ? 'Secure Seats' : 'Open Ticketing',
                  onTap: onPrimaryTap,
                  icon: Icons.confirmation_number_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CoolButton(
                  label: 'Membership Access',
                  variant: CoolButtonVariant.secondary,
                  onTap: onSecondaryTap,
                  icon: Icons.workspace_premium_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeLinkCard extends StatelessWidget {
  const _HomeLinkCard({
    required this.icon,
    required this.title,
    required this.meta,
    required this.detail,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String meta;
  final String detail;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$title. $meta',
      child: CoolCard(
        onTap: onTap,
        useGradient: false,
        backgroundColor: colors.cardSurfaceStrong,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(CoolRadii.md),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 24, color: accentColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: RsColors.rsWhite,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x1),
                  Text(
                    meta,
                    style: GoogleFonts.dmMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x1),
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: colors.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

class _MembershipMetricChip extends StatelessWidget {
  const _MembershipMetricChip({
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 108),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.dmMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          ),
          const SizedBox(height: CoolSpace.x1),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              color: RsColors.rsWhite,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RayonBrandMark extends StatelessWidget {
  const _RayonBrandMark({required this.size});

  static const _assetPath = 'assets/images/partners/rs_logo_small.png';

  final double size;

  Future<bool> _hasAsset(BuildContext context) async {
    final manifest = await AssetManifest.loadFromAssetBundle(
      DefaultAssetBundle.of(context),
    );
    return manifest.listAssets().contains(_assetPath);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return FutureBuilder<bool>(
      future: _hasAsset(context),
      builder: (context, snapshot) {
        if (snapshot.data != true) {
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: colors.cardSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border),
            ),
            alignment: Alignment.center,
            child: Text(
              'RS',
              style: GoogleFonts.dmMono(
                fontSize: size * 0.24,
                fontWeight: FontWeight.w700,
                color: RsColors.rsGoldLight,
              ),
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(
            _assetPath,
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        );
      },
    );
  }
}

class _SignalTile extends StatelessWidget {
  const _SignalTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: GoogleFonts.dmMono(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: CoolSpace.x1),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.rank,
    required this.club,
    required this.joined,
  });

  final int rank;
  final RsFanClub club;
  final bool joined;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return Container(
      padding: const EdgeInsets.all(CoolSpace.x3),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: rank == 1
                  ? RsColors.rsGold.withValues(alpha: 0.16)
                  : RsColors.rsBlue.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: GoogleFonts.dmMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: rank == 1 ? RsColors.rsGoldLight : RsColors.rsWhite,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        club.name,
                        style: context.coolText.rayon(
                          const TextStyle(fontSize: 16),
                          fontWeight: FontWeight.w700,
                          color: RsColors.rsWhite,
                        ),
                      ),
                    ),
                    if (joined)
                      _SurfaceBadge(
                        label: 'MEMBER',
                        foreground: colors.accent,
                        background: colors.accent.withValues(alpha: 0.14),
                        borderColor: colors.accent.withValues(alpha: 0.28),
                      ),
                  ],
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  club.region,
                  style: context.coolText.rayon(
                    const TextStyle(fontSize: 13),
                    fontWeight: FontWeight.w500,
                    color: colors.secondaryText,
                  ),
                ),
                const SizedBox(height: CoolSpace.x2),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoPill(
                      icon: Icons.people_outline_rounded,
                      label: '${_formatCount(club.memberCount)} members',
                    ),
                    _InfoPill(
                      icon: Icons.event_note_rounded,
                      label: '${club.eventCount} events',
                    ),
                    _InfoPill(
                      icon: Icons.star_rounded,
                      label: '${club.rating.toStringAsFixed(1)} rating',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SurfaceBadge extends StatelessWidget {
  const _SurfaceBadge({
    required this.label,
    required this.foreground,
    required this.background,
    required this.borderColor,
  });

  final String label;
  final Color foreground;
  final Color background;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmMono(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.secondaryText),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.coolText.rayon(
              const TextStyle(fontSize: 12),
              fontWeight: FontWeight.w700,
              color: RsColors.rsWhite,
            ),
          ),
        ],
      ),
    );
  }
}

class _RsSectionTitle extends StatelessWidget {
  const _RsSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
    );
  }
}

class _EmptyMatchCard extends StatelessWidget {
  const _EmptyMatchCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return CoolCard(
      onTap: onTap,
      useGradient: false,
      backgroundColor: colors.cardSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No live fixture yet',
            style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Official ticket allocations will appear here as soon as the next match opens for supporters.',
            style: context.coolText.rayon(
              const TextStyle(fontSize: 13),
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
              height: 1.45,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Align(
            alignment: Alignment.centerLeft,
            child: CoolButton(
              label: 'Open Ticket Office',
              onTap: onTap,
              icon: Icons.confirmation_number_outlined,
              fullWidth: false,
            ),
          ),
        ],
      ),
    );
  }
}

String _displayId(UserProfile? user, RsFanMembership? membership) {
  if (membership != null && membership.membershipNumber.isNotEmpty) {
    return membership.membershipNumber;
  }
  return user == null ? 'Membership pending' : 'Official membership pending';
}

String _formatCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(value % 1000000 == 0 ? 0 : 1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k';
  }
  return '$value';
}

String _formatRwf(int value) {
  return '${_formatCount(value)} RWF';
}

String _nextTierLabel(FanTier tier) {
  return switch (tier) {
    FanTier.blue => FanTier.silver.label,
    FanTier.silver => FanTier.gold.label,
    FanTier.gold => FanTier.platinum.label,
    FanTier.platinum => FanTier.platinum.label,
  };
}

String _matchSalesLabel(RsMatch match) {
  if (match.isSoldOut) {
    return 'Sold out';
  }
  if (match.isOnSale) {
    return 'On sale';
  }
  return 'Upcoming';
}

String _ticketDemandLabel(RsMatch match) {
  if (match.isSoldOut) {
    return 'Final allocation exhausted';
  }
  if (match.capacity <= 0) {
    return match.isOnSale
        ? 'Official sale routing active'
        : 'Awaiting allocation';
  }
  final remainingRatio = match.remainingCapacity / match.capacity;
  if (remainingRatio <= 0.15) {
    return 'High demand';
  }
  if (remainingRatio <= 0.4) {
    return '${match.remainingCapacity} seats left';
  }
  return match.isOnSale ? 'Seats available' : 'Allocation pending';
}

Future<void> _ensureMembership(BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(rayonSportsProvider.notifier);

  try {
    final result = await notifier.ensureMembership();
    if (!context.mounted) {
      return;
    }
    CoolToast.info(context, result.message);
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    CoolToast.error(context, error.toString());
  }
}
