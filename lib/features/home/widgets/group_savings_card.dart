import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/utils/intl_locale.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../models/home_dashboard_data.dart';
import '../../../core/l10n/l10n.dart';

class GroupSavingsCard extends StatelessWidget {
  const GroupSavingsCard({super.key, required this.data});

  final HomeDashboardData? data;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final localeName = resolveIntlLocale(context);
    final totalBalance = data?.totalBalance ?? 0;
    final memberCount = data?.memberCount ?? 0;

    return CoolCard(
      backgroundColor: colors.financialSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.cardSurfaceStrong.withValues(alpha: 0.88),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.md),
                  ),
                  border: Border.all(color: colors.border),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.people_alt_outlined,
                  size: 22,
                  color: colors.accent,
                ),
              ),
              SizedBox(width: space.x3),
              Expanded(
                child: Text(
                  'Group Savings',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Liquidity, member participation, and next action in one block.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              HomeStatPill(
                label: context.l10n.saved,
                value: _formatCurrency(totalBalance, localeName),
                valueColor: colors.accent,
                bgColor: colors.cardSurfaceStrong,
                borderColor: colors.border,
              ),
              HomeStatPill(
                label: context.l10n.groups,
                value: '$memberCount',
                valueColor: colors.primaryText,
                bgColor: colors.cardSurfaceStrong,
                borderColor: colors.border,
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),
          HomeCtaChip(
            label: context.l10n.explore,
            icon: Icons.search_rounded,
            onTap: () => context.push(AppRoutes.groups),
            color: colors.accent,
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
    final text = context.coolText;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: space.x3, vertical: space.x2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: valueColor.withValues(alpha: 0.74),
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(width: space.x2),
            Text(
              value,
              style: text.mono(
                theme.textTheme.labelLarge,
                color: valueColor,
                fontWeight: FontWeight.w800,
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
    final space = context.coolSpace;
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: space.x3,
            vertical: space.x2,
          ),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(
              Radius.circular(CoolRadii.pill),
            ),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              SizedBox(width: space.x1 + space.x0),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
