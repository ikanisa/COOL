import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';
import '../models/nexus_recommendation.dart';
import '../providers/nexus_provider.dart';

class NexusRecommendationsSection extends ConsumerWidget {
  const NexusRecommendationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final recommendationsAsync = ref.watch(nexusRecommendationsProvider);

    return recommendationsAsync.when(
      data: (recommendations) {
        if (recommendations.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: colors.accent,
                ),
                SizedBox(width: space.x2),
                Text(
                  'OPPORTUNITIES FOR YOU',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: colors.accent,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            SizedBox(height: space.x3),
            SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recommendations.length,
                separatorBuilder: (context, index) => SizedBox(width: space.x3),
                itemBuilder: (context, index) {
                  return NexusCard(recommendation: recommendations[index]);
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class NexusCard extends StatelessWidget {
  const NexusCard({super.key, required this.recommendation});

  final NexusRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return SizedBox(
      width: 260,
      child: CoolCard(
        onTap: () => openQuickActionRoute(context, recommendation.ctaAction),
        semanticsLabel: recommendation.title,
        borderRadius: radii.lg,
        padding: EdgeInsets.all(space.x4),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.elevatedBackground,
            colors.accent.withValues(alpha: 0.03),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: space.x2,
                    vertical: space.x1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.all(Radius.circular(radii.xs)),
                  ),
                  child: Text(
                    recommendation.contentType.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: colors.accent,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                Text(
                  sanitizeEmoji(recommendation.iconEmoji),
                  style: theme.textTheme.titleSmall?.copyWith(height: 1),
                ),
              ],
            ),
            const Spacer(),
            Text(
              recommendation.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primaryText,
              ),
            ),
            Text(
              recommendation.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.secondaryText,
              ),
            ),
            SizedBox(height: space.x2),
            Text(
              recommendation.rationale,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.accent,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detects Material icon name strings (e.g. "agriculture_rounded") and
/// returns a fallback emoji. Real emoji characters pass through unchanged.
String sanitizeEmoji(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '✨';
  // Material icon names are ascii-only with underscores; real emoji aren't.
  if (RegExp(r'^[a-z_0-9]+$').hasMatch(trimmed)) return '✨';
  return trimmed;
}