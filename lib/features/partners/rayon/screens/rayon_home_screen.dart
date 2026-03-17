import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../core/theme/rs_text_styles.dart';
import '../../../../core/theme/cool_layout.dart';
import '../../../../features/auth/models/user_profile.dart';
import '../../../../features/auth/providers/auth_provider.dart';
import '../../../../shared/widgets/cool_button.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../../shared/widgets/cool_card.dart';
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
        final rayon = ref.watch(rayonSportsDataProvider);
        final membership = ref.watch(rayonMembershipProvider);
        final nextMatch = ref.watch(rayonNextMatchProvider);
        final user = ref.watch(currentUserProvider);
        final isRecoveringMembership = ref.watch(rayonActionLoadingProvider);

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
                    const SizedBox(height: 24),
                    _RsSectionTitle(title: context.l10n.explore),
                    const SizedBox(height: 14),
                    rayon.when(
                      data: (data) => Column(
                        children: [
                          _HomeLinkCard(
                            icon: Icons.people_rounded,
                            title: context.l10n.memberRegistry,
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
                            meta: '${data.clubs.length} active',
                            accentColor: AppColors.orange,
                            onTap: () =>
                                context.push('/partners/rayon-sports/clubs'),
                          ),
                          const SizedBox(height: 12),
                          _HomeLinkCard(
                            icon: Icons.shopping_bag_rounded,
                            title: 'Club Shop',
                            meta: '${data.products.length} items',
                            accentColor: AppColors.accent,
                            onTap: () =>
                                context.push('/partners/rayon-sports/shop'),
                          ),
                          const SizedBox(height: 12),
                          _HomeLinkCard(
                            icon: Icons.handshake_rounded,
                            title: 'Support Club',
                            meta: '${data.initiatives.length} causes',
                            accentColor: RsColors.rsGold,
                            onTap: () => context.push(
                              '/partners/rayon-sports/support',
                            ),
                          ),
                          const SizedBox(height: 12),
                          _HomeLinkCard(
                            icon: Icons.confirmation_number_rounded,
                            title: 'Tickets',
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
                      error: (_, stackTrace) => const Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: CoolSkeleton.card()),
                              SizedBox(width: 12),
                              Expanded(child: CoolSkeleton.card()),
                            ],
                          ),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: CoolSkeleton.card()),
                              SizedBox(width: 12),
                              Expanded(child: CoolSkeleton.card()),
                            ],
                          ),
                          SizedBox(height: 12),
                          CoolSkeleton.card(),
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

    return CoolCard(
      borderColor: AppColors.border2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            membership == null
                ? 'Create membership to unlock perks'
                : 'Membership active',
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
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/partners/rs_logo_small.png',
                  width: 48,
                  height: 48,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: tier.color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tier.color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  tier.label.toUpperCase(),
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: tier == FanTier.silver
                        ? AppColors.bg
                        : AppColors.rsWhite,
                  ),
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



class _HomeLinkCard extends StatelessWidget {
  const _HomeLinkCard({
    required this.icon,
    required this.title,
    required this.meta,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String meta;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $meta',
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
      label: 'No match on sale',
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
                  'No match on sale',
                  style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ticket sales will appear',
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