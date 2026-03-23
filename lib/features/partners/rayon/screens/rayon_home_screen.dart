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

part 'rayon_home_screen_parts.dart';

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
