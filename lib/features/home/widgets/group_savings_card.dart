import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_palette.dart';
import '../../../../core/utils/intl_locale.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../models/home_dashboard_data.dart';
import '../../../core/l10n/l10n.dart';

class GroupSavingsCard extends StatelessWidget {
  const GroupSavingsCard({super.key, required this.data});

  final HomeDashboardData? data;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final localeName = resolveIntlLocale(context);
    final totalBalance = data?.totalBalance ?? 0;
    final memberCount = data?.memberCount ?? 0;

    return CoolCard(
      backgroundColor: palette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.accentGlow,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.people_alt_outlined,
                  size: 20,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Group Savings',
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: palette.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              HomeStatPill(
                label: context.l10n.saved,
                value: _formatCurrency(totalBalance, localeName),
                valueColor: palette.accent,
                bgColor: palette.surface2,
                borderColor: palette.border,
              ),
              HomeStatPill(
                label: context.l10n.groups,
                value: '$memberCount',
                valueColor: palette.text,
                bgColor: palette.surface2,
                borderColor: palette.border,
              ),
            ],
          ),
          const SizedBox(height: 16),
          HomeCtaChip(
            label: context.l10n.explore,
            icon: Icons.search_rounded,
            onTap: () => context.push(AppRoutes.groups),
            color: palette.accent,
          ),
        ],
      ),
    );
  }

  String _formatCurrency(int amount, String localeName) {
    if (amount == 0) return '0 RWF';
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1).replaceAll('.0', '')}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}K';
    }
    return '$amount';
  }
}

// ─── Shared: Stat Pill & CTA Chip ─────────────────────────────────────────

class HomeStatPill extends StatelessWidget {
  const HomeStatPill({
    super.key,
    required this.label,
    required this.value,
    required this.valueColor,
    required this.bgColor,
    required this.borderColor,
  });

  final String label;
  final String value;
  final Color valueColor;
  final Color bgColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: valueColor.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeCtaChip extends StatelessWidget {
  const HomeCtaChip({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}