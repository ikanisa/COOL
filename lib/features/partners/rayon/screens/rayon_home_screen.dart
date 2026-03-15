import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/router/app_routes.dart';
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
                    color: RsColors.rsWhite,
                  ),
                  actions: buildPartnerAppBarActions(
                    context,
                    homeColor: RsColors.rsWhite,
                    actions: const [_NotificationAction(), SizedBox(width: 8)],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Rayon Sports',
                      style: GoogleFonts.dmSans(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: RsColors.rsWhite,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 24, 18, 96),
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
                      const SizedBox(height: 24),
                      const _RsSectionTitle(title: 'Explore'),
                      const SizedBox(height: 14),
                      rayon.when(
                        data: (data) => Column(
                          children: [
                            _HomeLinkCard(
                              icon: Icons.people_rounded,
                              title: 'Member Registry',
                              subtitle: 'View registered supporters.',
                              meta:
                                  '${_formatCount(data.registryMembers.length)} members',
                              accentColor: RsColors.rsBlue,
                              onTap: () => context.push(
                                '/partners/rayon-sports/registry',
                              ),
                            ),
                            const SizedBox(height: 12),
                            _HomeLinkCard(
                              icon: Icons.groups_rounded,
                              title: 'Fan Clubs',
                              subtitle: 'Join a local chapter.',
                              meta: '${data.clubs.length} active clubs',
                              accentColor: AppColors.orange,
                              onTap: () =>
                                  context.push('/partners/rayon-sports/clubs'),
                            ),
                            const SizedBox(height: 12),
                            _HomeLinkCard(
                              icon: Icons.shopping_bag_rounded,
                              title: 'Club Shop',
                              subtitle: 'Official kits and merch.',
                              meta: '${data.products.length} items',
                              accentColor: AppColors.accent,
                              onTap: () =>
                                  context.push('/partners/rayon-sports/shop'),
                            ),
                            const SizedBox(height: 12),
                            _HomeLinkCard(
                              icon: Icons.handshake_rounded,
                              title: 'Support Club',
                              subtitle: 'Back active projects.',
                              meta: '${data.initiatives.length} active causes',
                              accentColor: RsColors.rsGold,
                              onTap: () => context.push(
                                '/partners/rayon-sports/support',
                              ),
                            ),
                            const SizedBox(height: 12),
                            _HomeLinkCard(
                              icon: Icons.confirmation_number_rounded,
                              title: 'Tickets',
                              subtitle: 'Buy match tickets.',
                              meta:
                                  '${data.matches.where((m) => m.isOnSale).length} on sale',
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
        tooltip: 'Notifications',
        icon: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
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
    final fanName =
        membership?.displayName ?? user?.displayUserId ?? 'Rayon Fan';
    final fanId = _displayId(user, membership);
    final tier = membership?.tier ?? FanTier.blue;
    final chapter = membership?.chapter ?? 'Official membership pending';
    final points = membership?.points ?? 0;

    return CoolCard(
      borderColor: AppColors.border2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rayon Sports',
            style: GoogleFonts.barlowCondensed(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: RsColors.rsWhite,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            membership == null
                ? 'Create your official fan membership to unlock supporter perks.'
                : 'Membership ready for matchdays, shop benefits, and club access.',
            style: GoogleFonts.barlow(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fanName,
                      style: GoogleFonts.barlow(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: RsColors.rsWhite,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fanId,
                      style: GoogleFonts.dmMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
              _HomeMetaPill(
                label: tier.label.toUpperCase(),
                foregroundColor: tier == FanTier.silver
                    ? AppColors.bg
                    : AppColors.rsWhite,
                backgroundColor: tier.color.withValues(alpha: 0.2),
                borderColor: tier.color.withValues(alpha: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HomeMetric(
                  value: chapter,
                  label: 'Chapter',
                  mono: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HomeMetric(value: '$points', label: 'Points'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HomeMetric(
                  value: membership == null ? 'Pending' : 'Active',
                  label: 'Status',
                  mono: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (membership == null)
            CoolButton(
              label: 'Create / Restore Membership',
              onTap: () {
                onRecoverMembership();
              },
              isLoading: isRecoveringMembership,
              icon: Icons.verified_user_outlined,
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
                    label: 'View Plans',
                    variant: CoolButtonVariant.secondary,
                    onTap: () {
                      context.push('/partners/rayon-sports/membership');
                    },
                    icon: Icons.layers_outlined,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _HomeMetric extends StatelessWidget {
  const _HomeMetric({
    required this.value,
    required this.label,
    this.mono = true,
  });

  final String value;
  final String label;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: (mono ? GoogleFonts.dmMono : GoogleFonts.barlow)(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: RsColors.rsWhite,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.barlow(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeMetaPill extends StatelessWidget {
  const _HomeMetaPill({
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.borderColor,
  });

  final String label;
  final Color foregroundColor;
  final Color backgroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmMono(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foregroundColor,
        ),
      ),
    );
  }
}

class _HomeLinkCard extends StatelessWidget {
  const _HomeLinkCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String meta;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $subtitle. $meta',
      child: GestureDetector(
        onTap: onTap,
        child: CoolCard(
          borderColor: AppColors.border2,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.28),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 22, color: accentColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.barlow(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: RsColors.rsWhite,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.barlow(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      meta,
                      style: GoogleFonts.dmMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: AppColors.text2,
              ),
            ],
          ),
        ),
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
    return Semantics(
      button: true,
      label: 'No match on sale yet',
      child: Material(
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
