import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../core/theme/rs_text_styles.dart';
import '../../../../features/auth/models/user_profile.dart';
import '../../../../features/auth/providers/auth_provider.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_screen_background.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../../../shared/widgets/rs_match_card.dart';
import '../models/rs_models.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/partner_navigation.dart';
import '../widgets/rs_hero_banner.dart';
import '../widgets/rs_membership_card.dart';
import '../widgets/rs_service_card.dart';

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

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: CoolScreenBackground(
            primaryColor: RsColors.rsBlue,
            secondaryColor: RsColors.rsGold,
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 0,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  leading: buildPartnerBackButton(
                    context,
                    fallbackLocation: AppRoutes.partners,
                  ),
                  title: Text(
                    'Rayon Sports',
                    style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
                  ),
                  actions: buildPartnerAppBarActions(
                    context,
                    actions: const [_NotificationAction(), SizedBox(width: 8)],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      membership.when(
                        data: (fanMembership) => RsHeroBanner(
                          clubName: 'Rayon Sports',
                          nickname: '★ GIKUNDIRO — The Favorites ★',
                          location: 'Kigali Pelé Stadium',
                          fanId: _displayId(user, fanMembership),
                          tier: fanMembership?.tier ?? FanTier.blue,
                          stats: const [
                            RsHeroStat(value: '--', label: 'League Titles'),
                            RsHeroStat(value: '--', label: 'Fans'),
                            RsHeroStat(value: '1968', label: 'Founded'),
                            RsHeroStat(value: '--', label: 'Current Rank'),
                          ],
                        ),
                        loading: () => const CoolSkeleton.card(),
                        error: (error, _) => RsHeroBanner(
                          clubName: 'Rayon Sports',
                          nickname: '★ GIKUNDIRO — The Favorites ★',
                          location: 'Kigali Pelé Stadium',
                          fanId: _displayId(user, null),
                          tier: FanTier.blue,
                          stats: const [
                            RsHeroStat(value: '--', label: 'League Titles'),
                            RsHeroStat(value: '--', label: 'Fans'),
                            RsHeroStat(value: '1968', label: 'Founded'),
                            RsHeroStat(value: '--', label: 'Current Rank'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      membership.when(
                        data: (fanMembership) => Column(
                          children: [
                            GestureDetector(
                              onTap: () => context.push(
                                '/partners/rayon-sports/profile',
                              ),
                              child: RsMembershipCard(
                                fanName:
                                    fanMembership?.displayName ??
                                    user?.displayUserId ??
                                    '000000',
                                fanId: _displayId(user, fanMembership),
                                tier: fanMembership?.tier ?? FanTier.blue,
                                chapter:
                                    fanMembership?.chapter ??
                                    'Official membership pending',
                                year:
                                    fanMembership?.joinedAt.year ??
                                    DateTime.now().year,
                                perks: fanMembership == null
                                    ? _pendingMembershipPerks
                                    : _membershipPerks(fanMembership.tier),
                              ),
                            ),
                            if (fanMembership == null) ...[
                              const SizedBox(height: 12),
                              _PendingMembershipRecoveryCard(
                                isLoading: isRecoveringMembership,
                                onTap: () => _ensureMembership(context, ref),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: GestureDetector(
                                onTap: () => context.push(
                                  '/partners/rayon-sports/membership',
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'View All Plans',
                                      style: GoogleFonts.barlow(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: RsColors.rsGoldLight,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 16,
                                      color: RsColors.rsGoldLight,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        loading: () => const CoolSkeleton.card(),
                        error: (_, stackTrace) => Column(
                          children: [
                            GestureDetector(
                              onTap: () => context.push(
                                '/partners/rayon-sports/profile',
                              ),
                              child: RsMembershipCard(
                                fanName: user?.displayUserId ?? '000000',
                                fanId: _displayId(user, null),
                                tier: FanTier.blue,
                                chapter: 'Membership unavailable',
                                year: DateTime.now().year,
                                perks: _pendingMembershipPerks,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _PendingMembershipRecoveryCard(
                              isLoading: isRecoveringMembership,
                              onTap: () => _ensureMembership(context, ref),
                              title: 'Restore official membership',
                              message:
                                  'Could not confirm membership. Tap to retry.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const _RsSectionTitle(title: 'Services'),
                      const SizedBox(height: 14),
                      rayon.when(
                        data: (data) => Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: RsServiceCard(
                                    icon: Icons.people_rounded,
                                    name: 'Member Registry',
                                    description: 'View all registered fans',
                                    count:
                                        '${_formatCount(data.registryMembers.length)} members',
                                    accentColor: RsColors.rsBlue,
                                    onTap: () => context.push(
                                      '/partners/rayon-sports/registry',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: RsServiceCard(
                                    icon: Icons.groups_rounded,
                                    name: 'Fan Clubs',
                                    description: 'Join a chapter or local club',
                                    count: '${data.clubs.length} active clubs',
                                    accentColor: AppColors.orange,
                                    onTap: () => context.push(
                                      '/partners/rayon-sports/clubs',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: RsServiceCard(
                                    icon: Icons.shopping_bag_rounded,
                                    name: 'Club Shop',
                                    description: 'Kits, merch & official gear',
                                    count: '${data.products.length} items',
                                    accentColor: AppColors.accent,
                                    onTap: () => context.push(
                                      '/partners/rayon-sports/shop',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: RsServiceCard(
                                    icon: Icons.handshake_rounded,
                                    name: 'Support Club',
                                    description: 'Fund projects & initiatives',
                                    count:
                                        '${data.initiatives.length} active causes',
                                    accentColor: RsColors.rsGold,
                                    onTap: () => context.push(
                                      '/partners/rayon-sports/support',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            RsServiceCard(
                              icon: Icons.confirmation_number_rounded,
                              name: 'Tickets',
                              description:
                                  'Buy match tickets · Member benefits',
                              count:
                                  '${data.matches.where((m) => m.isOnSale).length} matches on sale',
                              isWide: true,
                              accentColor: AppColors.red,
                              onTap: () => context.push(
                                '/partners/rayon-sports/tickets',
                              ),
                            ),
                          ],
                        ),
                        loading: () => const CoolSkeletonList(itemCount: 3),
                        error: (_, stackTrace) => Column(
                          children: [
                            Row(
                              children: const [
                                Expanded(child: CoolSkeleton.card()),
                                SizedBox(width: 12),
                                Expanded(child: CoolSkeleton.card()),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: const [
                                Expanded(child: CoolSkeleton.card()),
                                SizedBox(width: 12),
                                Expanded(child: CoolSkeleton.card()),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const CoolSkeleton.card(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const _RsSectionTitle(title: 'Next Match'),
                      const SizedBox(height: 14),
                      nextMatch.when(
                        loading: () => const CoolSkeleton.card(),
                        error: (_, stackTrace) => _EmptyMatchCard(
                          onTap: () =>
                              context.push('/partners/rayon-sports/tickets'),
                        ),
                        data: (match) {
                          if (match == null) {
                            return _EmptyMatchCard(
                              onTap: () => context.push(
                                '/partners/rayon-sports/tickets',
                              ),
                            );
                          }
                          return RsMatchCard(
                            match: match,
                            onBuyTap: () =>
                                context.push('/partners/rayon-sports/tickets'),
                          );
                        },
                      ),
                    ]),
                  ),
                ),
              ],
            ),
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
          // TODO: Navigate to notifications screen when implemented
        },
        icon: const Icon(Icons.notifications_none_rounded),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border2),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No match on sale yet',
                style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
              ),
              const SizedBox(height: 8),
              Text(
                'Ticket sales will appear here as soon as the next fixture opens.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingMembershipRecoveryCard extends StatelessWidget {
  const _PendingMembershipRecoveryCard({
    required this.onTap,
    required this.isLoading,
    this.title = 'Create official membership',
    this.message = 'Create or restore your fan membership here.',
  });

  final Future<void> Function() onTap;
  final bool isLoading;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      borderColor: AppColors.rsBlueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          CoolButton(
            label: 'Create / Restore Membership',
            onTap: () {
              onTap();
            },
            isLoading: isLoading,
            icon: Icons.verified_user_outlined,
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

const _pendingMembershipPerks = <String>[
  'Browse matches',
  'Follow club updates',
  'Unlock member perks after registration',
];

List<String> _membershipPerks(FanTier tier) {
  return switch (tier) {
    FanTier.blue => const ['Registry Access', 'Club Updates', 'Member Queue'],
    FanTier.silver => const [
      'Priority Tickets',
      'Club Updates',
      'Member Queue',
    ],
    FanTier.gold => const ['Priority Tickets', 'Shop Discount', 'VIP Queue'],
    FanTier.platinum => const [
      'VIP Access',
      'Shop Discount',
      'Exclusive Events',
    ],
  };
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
