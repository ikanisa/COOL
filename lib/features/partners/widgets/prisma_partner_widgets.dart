import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/icon_mapper.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../models/partner.dart';
import 'partner_shared_widgets.dart';
import 'prisma_partner_config.dart';

// ═════════════════════════════════════════════════════════════════════════════
// HERO CARD
// ═════════════════════════════════════════════════════════════════════════════

class PrismaHeroCard extends StatelessWidget {
  const PrismaHeroCard({required this.partner, super.key});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final description = partner.description ?? 'AI professional services';

    final pills = partner.metadata['hero_pills'] as List<dynamic>?;

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (partner.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        partner.subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.inputSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border),
                ),
                alignment: Alignment.center,
                child: Text(
                  partner.emoji,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
              height: 1.5,
            ),
          ),
          if (pills != null && pills.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final pill in pills)
                  if (pill is Map)
                    PartnerHeroPill(
                      icon: IconMapper.from(pill['icon']?.toString() ?? '🔹'),
                      label: pill['label']?.toString() ?? '',
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// QUICK ACTIONS
// ═════════════════════════════════════════════════════════════════════════════

class PrismaQuickActions extends StatelessWidget {
  const PrismaQuickActions({required this.partner, super.key});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    final actions = partner.metadata['quick_actions'] as List<dynamic>?;
    if (actions == null || actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        for (final action in actions)
          if (action is Map)
            PartnerQuickActionTile(
              icon: IconMapper.from(action['icon']?.toString() ?? '🔗'),
              title: action['title']?.toString() ?? '',
              subtitle: action['subtitle']?.toString() ?? '',
              onTap: () => launchPrismaAction(
                context,
                partner,
                action: action['cta_action']?.toString() ?? '',
              ),
            ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// STATS CARD
// ═════════════════════════════════════════════════════════════════════════════

class PrismaStatsCard extends StatelessWidget {
  const PrismaStatsCard({required this.partner, super.key});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final stats = partner.metadata['stats'] as List<dynamic>?;
    if (stats == null || stats.isEmpty) {
      return const SizedBox.shrink();
    }

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            partner.metadata['stats_title']?.toString() ?? 'At a glance',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < stats.length; i++) ...[
                if (stats[i] is Map)
                  PrismaStatTile(
                    value: stats[i]['value']?.toString() ?? '',
                    label: stats[i]['label']?.toString() ?? '',
                  ),
                if (i != stats.length - 1) const SizedBox(width: 10),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// VALUES CARD
// ═════════════════════════════════════════════════════════════════════════════

class PrismaValuesCard extends StatelessWidget {
  const PrismaValuesCard({required this.partner, super.key});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final values = partner.metadata['values'] as List<dynamic>?;
    if (values == null || values.isEmpty) {
      return const SizedBox.shrink();
    }

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            partner.metadata['values_title']?.toString() ?? 'How it works',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < values.length; i++) ...[
            if (values[i] is Map)
              PrismaValueRow(
                icon: IconMapper.from(values[i]['icon']?.toString() ?? '🔹'),
                title: values[i]['title']?.toString() ?? '',
                description: values[i]['description']?.toString() ?? '',
              ),
            if (i != values.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SUPPORT CARD
// ═════════════════════════════════════════════════════════════════════════════

class PrismaSupportCard extends StatelessWidget {
  const PrismaSupportCard({required this.partner, super.key});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final supportLines = partner.metadata['support_lines'] as List<dynamic>?;
    if (supportLines == null || supportLines.isEmpty) {
      return const SizedBox.shrink();
    }

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            partner.metadata['support_title']?.toString() ?? 'Get in touch',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < supportLines.length; i++) ...[
            if (supportLines[i] is Map)
              PartnerSupportLine(
                icon: IconMapper.from(
                  supportLines[i]['icon']?.toString() ?? '📍',
                ),
                label: supportLines[i]['label']?.toString() ?? '',
                value: supportLines[i]['value']?.toString() ?? '',
              ),
            if (i != supportLines.length - 1) const SizedBox(height: 10),
          ],
          if (partner.metadata['support_cta'] != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: 200,
              child: CoolButton(
                label:
                    partner.metadata['support_cta']['label']?.toString() ??
                    'Contact',
                onTap: () => launchPrismaAction(
                  context,
                  partner,
                  action:
                      partner.metadata['support_cta']['action']?.toString() ??
                      '',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PRISMA-SPECIFIC SMALL WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

class PrismaValueRow extends StatelessWidget {
  const PrismaValueRow({
    required this.icon,
    required this.title,
    required this.description,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.operationalSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: colors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colors.secondaryText,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class PrismaStatTile extends StatelessWidget {
  const PrismaStatTile({required this.value, required this.label, super.key});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: colors.analyticsSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.accent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.secondaryText,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
