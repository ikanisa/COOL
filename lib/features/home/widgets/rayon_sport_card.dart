import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/rs_colors.dart';
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
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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