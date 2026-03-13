import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../widgets/partner_navigation.dart';
import '../providers/rs_admin_provider.dart';

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
      'Tier & points mgmt',
    ),
    _Section(
      'Fan Clubs',
      Icons.groups_rounded,
      '/admin/rayon/fan-clubs',
      'Regional fan clubs',
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

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.rsBlue,
        elevation: 0,
        leading: buildPartnerBackButton(
          context,
          fallbackLocation: AppRoutes.admin,
          color: Colors.white,
        ),
        title: Text(
          'Rayon Sports Admin',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: buildPartnerAppBarActions(context, homeColor: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Quick stats row ──
              Row(
                children: [
                  _StatChip(
                    Icons.sports_soccer_rounded,
                    matchesAsync.whenOrNull(data: (m) => '${m.length}') ?? '…',
                    'Matches',
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    Icons.people_rounded,
                    membersAsync.whenOrNull(data: (m) => '${m.length}') ?? '…',
                    'Members',
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    Icons.shopping_bag_rounded,
                    productsAsync.whenOrNull(data: (p) => '${p.length}') ?? '…',
                    'Products',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // ── Grid ──
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.2,
                ),
                itemCount: _sections.length,
                itemBuilder: (context, index) {
                  final s = _sections[index];
                  return _AdminCard(section: s);
                },
              ),
            ],
          ),
        ),
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
      child: GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        context.push(section.route);
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.rsBlueBorder, width: 1),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(section.icon, size: 28, color: AppColors.text),
            const SizedBox(height: 8),
            Text(
              section.title,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              section.subtitle,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: AppColors.text3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(this.icon, this.value, this.label);
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: AppColors.text),
                const SizedBox(width: 4),
                Text(
                  value,
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.text3),
            ),
          ],
        ),
      ),
    );
  }
}
