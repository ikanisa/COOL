import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/icon_mapper.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_error_view.dart';
import '../models/partner.dart';
import '../models/partner_service.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SHARED DATA MODEL
// ═════════════════════════════════════════════════════════════════════════════

/// Shared category metadata used by both bank and prisma partner screens.
class CategoryMeta {
  const CategoryMeta({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
}

// ═════════════════════════════════════════════════════════════════════════════
// SECTION HEADER
// ═════════════════════════════════════════════════════════════════════════════

/// Renders a category section header with an icon badge, title, and
/// description. Works with any [CategoryMeta] map.
class PartnerSectionHeader extends StatelessWidget {
  const PartnerSectionHeader({
    required this.category,
    required this.categoryMeta,
    this.fallbackCategory = 'support',
    super.key,
  });

  final String category;
  final Map<String, CategoryMeta> categoryMeta;
  final String fallbackCategory;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final meta = categoryMeta[category] ?? categoryMeta[fallbackCategory]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: meta.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(meta.icon, size: 18, color: meta.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                meta.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          meta.description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.secondaryText,
            fontWeight: FontWeight.w600,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SERVICE CARD
// ═════════════════════════════════════════════════════════════════════════════

/// Renders a partner service card. Accepts callbacks for category
/// normalization, meta lookup, gradient selection, and CTA launch.
class PartnerServiceCard extends StatelessWidget {
  const PartnerServiceCard({
    required this.service,
    required this.partner,
    required this.categoryMeta,
    required this.normalizeCategory,
    required this.onCtaTap,
    this.fallbackCategory = 'support',
    this.gradientWhen,
    super.key,
  });

  final PartnerService service;
  final Partner partner;
  final Map<String, CategoryMeta> categoryMeta;
  final String Function(String rawCategory) normalizeCategory;
  final void Function(
    BuildContext context, {
    required String action,
    String? topic,
  })
  onCtaTap;
  final String fallbackCategory;

  /// Returns a gradient when the normalized category matches a condition.
  /// If null, no gradient is applied.
  final LinearGradient? Function(String normalizedCategory)? gradientWhen;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final normalizedCategory = normalizeCategory(service.category);
    final meta =
        categoryMeta[normalizedCategory] ?? categoryMeta[fallbackCategory]!;

    return CoolCard(
      gradient: gradientWhen?.call(normalizedCategory),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: meta.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  IconMapper.from(service.emoji),
                  size: 22,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (service.subtitle != null &&
                        service.subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        service.subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.secondaryText,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (service.details.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.inputSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < service.details.length; i++) ...[
                    PartnerDetailRow(
                      detail: service.details[i],
                      accent: meta.accent,
                    ),
                    if (i < service.details.length - 1)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
          if (service.ctaLabel != null &&
              service.ctaAction != null &&
              service.ctaAction!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            CoolButton(
              label: service.ctaLabel!,
              onTap: () => onCtaTap(
                context,
                action: service.ctaAction!,
                topic: service.title,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DETAIL ROW
// ═════════════════════════════════════════════════════════════════════════════

/// A single detail row inside a service card.
/// Renders the detail icon (emoji), label, and value.
class PartnerDetailRow extends StatelessWidget {
  const PartnerDetailRow({
    required this.detail,
    required this.accent,
    super.key,
  });

  final ServiceDetail detail;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(
            IconMapper.from(detail.icon),
            size: 13,
            color: colors.secondaryText,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.tertiaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail.value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// QUICK ACTION TILE
// ═════════════════════════════════════════════════════════════════════════════

/// A tappable card tile used in quick action grids.
class PartnerQuickActionTile extends StatelessWidget {
  const PartnerQuickActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolCard(
      onTap: onTap,
      semanticsLabel: '$title action',
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.accent, size: 22),
          const SizedBox(height: 10),
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// HERO PILL
// ═════════════════════════════════════════════════════════════════════════════

/// A small pill chip used in hero sections to display feature tags.
class PartnerHeroPill extends StatelessWidget {
  const PartnerHeroPill({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.accent),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SUPPORT LINE
// ═════════════════════════════════════════════════════════════════════════════

/// A row showing an icon, label, and value for support info.
class PartnerSupportLine extends StatelessWidget {
  const PartnerSupportLine({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colors.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.tertiaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ERROR CARD
// ═════════════════════════════════════════════════════════════════════════════

/// An inline error card displayed when service loading fails.
class PartnerErrorCard extends StatelessWidget {
  const PartnerErrorCard({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: CoolErrorView(
        message: message,
        compact: true,
        icon: Icons.warning_amber_rounded,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ERROR BODY
// ═════════════════════════════════════════════════════════════════════════════

/// A full-screen centered error with an optional retry button.
class PartnerErrorBody extends StatelessWidget {
  const PartnerErrorBody({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: CoolErrorView(
        message: message,
        onRetry: onRetry,
        icon: Icons.warning_amber_rounded,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// EMPTY SERVICES CARD
// ═════════════════════════════════════════════════════════════════════════════

/// Shown when a partner has no services configured yet.
class PartnerEmptyServicesCard extends StatelessWidget {
  const PartnerEmptyServicesCard({required this.partnerName, super.key});

  final String partnerName;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: CoolEmptyView(
        message: 'Services for $partnerName will appear here once configured.',
        compact: true,
        icon: Icons.assignment_outlined,
      ),
    );
  }
}
