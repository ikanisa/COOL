import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../partners/rayon/models/rs_models.dart';
import 'group_savings_card.dart';
import '../../../core/l10n/l10n.dart';

class RayonSportCard extends StatelessWidget {
  const RayonSportCard({
    super.key,
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
    final text = context.coolText;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    final isMember = membership != null;
    final totalFans = clubs.fold<int>(0, (sum, c) => sum + c.memberCount);
    final onSaleMatches = matches.where((m) => m.isOnSale).toList();
    final hasOpenTickets = onSaleMatches.isNotEmpty;
    final hasInitiatives = initiatives.isNotEmpty;

    return CoolCard(
      gradient: RsColors.rsCardGradient,
      borderRadius: radii.lg,
      borderColor: RsColors.rsBlueBorder,
      padding: EdgeInsets.all(space.x5),
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
                  borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
                ),
                alignment: Alignment.center,
                child: Text(
                  '⚽',
                  style: theme.textTheme.titleMedium?.copyWith(height: 1),
                ),
              ),
              SizedBox(width: space.x3),
              Expanded(
                child: Text(
                  'Rayon Sports FC',
                  style: text.rayonCondensed(
                    theme.textTheme.titleLarge,
                    color: RsColors.rsWhite,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              if (isMember)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: space.x2,
                    vertical: space.x1,
                  ),
                  decoration: BoxDecoration(
                    color: RsColors.rsGold.withValues(alpha: 0.2),
                    borderRadius: const BorderRadius.all(
                      Radius.circular(CoolRadii.pill),
                    ),
                    border: Border.all(
                      color: RsColors.rsGold.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    membership.tier.label,
                    style: text.rayon(
                      theme.textTheme.labelSmall,
                      color: RsColors.rsGoldLight,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: space.x4),
          Wrap(
            spacing: space.x3,
            runSpacing: space.x3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              HomeStatPill(
                label: context.l10n.fans,
                value: NumberFormat.compact().format(totalFans),
                valueColor: RsColors.rsGoldLight,
                bgColor: RsColors.rsBlue.withValues(alpha: 0.25),
                borderColor: RsColors.rsBlueBorder,
              ),
              if (hasInitiatives)
                HomeCtaChip(
                  label: context.l10n.contribute,
                  icon: Icons.volunteer_activism_rounded,
                  onTap: () => context.push(AppRoutes.rayonSupport),
                  color: RsColors.rsGoldLight,
                ),
            ],
          ),
          SizedBox(height: space.x4),
          Wrap(
            spacing: space.x2,
            runSpacing: space.x2,
            children: [
              if (!isMember)
                HomeCtaChip(
                  label: context.l10n.join,
                  icon: Icons.person_add_alt_1_rounded,
                  onTap: () => context.push(AppRoutes.rayonHome),
                  color: RsColors.rsGold,
                ),
              if (isMember && hasOpenTickets)
                HomeCtaChip(
                  label: context.l10n.buyTickets,
                  icon: Icons.confirmation_num_outlined,
                  onTap: () => context.push(AppRoutes.rayonTickets),
                  color: RsColors.rsBluePale,
                ),
              if (isMember)
                HomeCtaChip(
                  label: context.l10n.shop,
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
