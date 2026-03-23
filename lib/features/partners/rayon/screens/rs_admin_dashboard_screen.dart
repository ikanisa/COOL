import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/rs_models.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../providers/rs_admin_provider.dart';
import '../widgets/rs_admin_shell.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../core/l10n/l10n.dart';

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
      'Registry & Tokens',
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
    _Section(
      'Analytics',
      Icons.analytics_rounded,
      '/admin/rayon/analytics',
      'Fan engagement overview',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(rsAdminMatchesProvider);
    final membersAsync = ref.watch(rsAdminMembersProvider);
    final productsAsync = ref.watch(rsAdminProductsProvider);
    final analyticsAsync = ref.watch(rsAdminFanAnalyticsProvider);

    return RsAdminShell(
      title: context.l10n.rayonSportsAdmin,
      subtitle: 'Manage matches, shop, members & community',
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
        children: [
          // ── Revenue Summary Row ──
          analyticsAsync.whenOrNull(
                data: (analytics) {
                  final moneyFmt = NumberFormat.compact();
                  final ticketRev = (analytics['ticket_revenue'] as num?) ?? 0;
                  final shopRev = (analytics['shop_revenue'] as num?) ?? 0;
                  final totalRev = ticketRev + shopRev;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        _RevenueCard(
                          label: 'Ticket Revenue',
                          value: '${moneyFmt.format(ticketRev)} RWF',
                          icon: Icons.confirmation_number_outlined,
                        ),
                        const SizedBox(width: 8),
                        _RevenueCard(
                          label: 'Shop Revenue',
                          value: '${moneyFmt.format(shopRev)} RWF',
                          icon: Icons.shopping_bag_outlined,
                        ),
                        const SizedBox(width: 8),
                        _RevenueCard(
                          label: 'Total',
                          value: '${moneyFmt.format(totalRev)} RWF',
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                      ],
                    ),
                  );
                },
              ) ??
              const SizedBox.shrink(),

          // ── Tier Breakdown Row ──
          membersAsync.whenOrNull(
                data: (members) {
                  final tierCounts = <FanTier, int>{};
                  for (final m in members) {
                    tierCounts[m.tier] = (tierCounts[m.tier] ?? 0) + 1;
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        _TierChip('💙', 'Blue', tierCounts[FanTier.blue] ?? 0),
                        const SizedBox(width: 6),
                        _TierChip(
                          '🥈',
                          'Silver',
                          tierCounts[FanTier.silver] ?? 0,
                        ),
                        const SizedBox(width: 6),
                        _TierChip('🥇', 'Gold', tierCounts[FanTier.gold] ?? 0),
                        const SizedBox(width: 6),
                        _TierChip(
                          '💎',
                          'Plat',
                          tierCounts[FanTier.platinum] ?? 0,
                        ),
                      ],
                    ),
                  );
                },
              ) ??
              const SizedBox.shrink(),

          // ── Quick Actions ──
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _QuickAction(
                    icon: Icons.sports_soccer_rounded,
                    label: 'Add Match',
                    onTap: () => context.push('/admin/rayon/matches'),
                  ),
                  const SizedBox(width: 8),
                  _QuickAction(
                    icon: Icons.add_shopping_cart_rounded,
                    label: 'Add Product',
                    onTap: () => context.push('/admin/rayon/shop'),
                  ),
                  const SizedBox(width: 8),
                  _QuickAction(
                    icon: Icons.campaign_rounded,
                    label: 'Send Notification',
                    onTap: () => context.push('/admin/rayon/analytics'),
                  ),
                ],
              ),
            ),
          ),

          // ── Navigation Cards ──
          ..._sections.map(
            (section) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AdminCard(section: section),
            ),
          ),
        ],
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
    final palette = context.coolPalette;
    return Semantics(
      button: true,
      label: '${section.title}. ${section.subtitle}',
      hint: 'Open ${section.title.toLowerCase()}',
      excludeSemantics: true,
      child: CoolCard(
        onTap: () {
          HapticFeedback.selectionClick();
          context.push(section.route);
        },
        semanticsLabel: '${section.title}. ${section.subtitle}',
        borderColor: palette.border2,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: RsColors.rsBlueGlow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: RsColors.rsBlueBorder),
              ),
              alignment: Alignment.center,
              child: Icon(section.icon, size: 22, color: RsColors.rsBlueLight),
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
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    section.subtitle,
                    style: GoogleFonts.barlow(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: palette.text2,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.arrow_forward_rounded, size: 18, color: palette.text2),
          ],
        ),
      ),
    );
  }
}

class _RevenueCard extends StatelessWidget {
  const _RevenueCard({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: palette.accent),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.dmSans(fontSize: 10, color: palette.text3),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: RsColors.rsBlue.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: RsColors.rsBlue.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: RsColors.rsBlue),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: RsColors.rsBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip(this.emoji, this.label, this.count);
  final String emoji;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 2),
            Text(
              '$count',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: palette.text,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.dmSans(fontSize: 10, color: palette.text3),
            ),
          ],
        ),
      ),
    );
  }
}
