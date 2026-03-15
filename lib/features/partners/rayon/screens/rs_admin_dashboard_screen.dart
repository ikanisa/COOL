import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/rs_admin_provider.dart';
import '../widgets/rs_admin_shell.dart';
import '../../../../shared/widgets/cool_card.dart';

/// RS Admin Hub — 7 cards for all RS admin management screens + live stats.
class RsAdminDashboardScreen extends ConsumerWidget {
  const RsAdminDashboardScreen({super.key});

  static const _sections = [
    _Section(
      'Matches',
      Icons.sports_soccer_rounded,
      '/admin/rayon/matches',
      'Schedule & sale control',
    ),
    _Section(
      'Tickets',
      Icons.confirmation_number_rounded,
      '/admin/rayon/tickets',
      'View & validate tickets',
    ),
    _Section(
      'Shop',
      Icons.shopping_bag_rounded,
      '/admin/rayon/shop',
      'Products & stock',
    ),
    _Section(
      'Orders',
      Icons.inventory_2_rounded,
      '/admin/rayon/orders',
      'Shop order pipeline',
    ),
    _Section(
      'Members',
      Icons.people_rounded,
      '/admin/rayon/members',
      'Registry & points',
    ),
    _Section(
      'Packages',
      Icons.workspace_premium_rounded,
      '/admin/rayon/packages',
      'Tier copy & benefits',
    ),
    _Section(
      'Finance',
      Icons.account_balance_wallet_rounded,
      '/admin/rayon/finance',
      'Routes & ledger export',
    ),
    _Section(
      'Initiatives',
      Icons.favorite_rounded,
      '/admin/rayon/initiatives',
      'Community causes',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(rsAdminMatchesProvider);
    final membersAsync = ref.watch(rsAdminMembersProvider);
    final productsAsync = ref.watch(rsAdminProductsProvider);

    return RsAdminShell(
      title: 'Rayon Sports Admin',
      subtitle:
          'Open one workspace at a time for matchday, ticketing, shop, member, and cause operations.',
      fallbackLocation: AppRoutes.admin,
      expandBody: false,
      metrics: [
        RsAdminMetric(
          label: 'matches',
          value:
              matchesAsync.whenOrNull(data: (matches) => '${matches.length}') ??
              '...',
        ),
        RsAdminMetric(
          label: 'members',
          value:
              membersAsync.whenOrNull(data: (members) => '${members.length}') ??
              '...',
        ),
        RsAdminMetric(
          label: 'products',
          value:
              productsAsync.whenOrNull(
                data: (products) => '${products.length}',
              ) ??
              '...',
        ),
      ],
      child: Column(
        children: _sections
            .map(
              (section) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AdminCard(section: section),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _Section {
  const _Section(this.title, this.icon, this.route, this.subtitle);
  final String title;
  final IconData icon;
  final String route;
  final String subtitle;
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({required this.section});
  final _Section section;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${section.title}. ${section.subtitle}',
      hint: 'Double tap to open ${section.title.toLowerCase()} management',
      excludeSemantics: true,
      child: CoolCard(
        onTap: () {
          HapticFeedback.selectionClick();
          context.push(section.route);
        },
        semanticsLabel: '${section.title}. ${section.subtitle}',
        borderColor: AppColors.border2,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.rsBlueGlow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.rsBlueBorder),
              ),
              alignment: Alignment.center,
              child: Icon(section.icon, size: 22, color: AppColors.rsWhite),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.title,
                    style: GoogleFonts.barlow(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.rsWhite,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    section.subtitle,
                    style: GoogleFonts.barlow(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text2,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.text2),
          ],
        ),
      ),
    );
  }
}
