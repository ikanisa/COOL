import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_palette.dart';
import '../models/nexus_recommendation.dart';
import '../providers/nexus_provider.dart';

class NexusRecommendationsSection extends ConsumerWidget {
  const NexusRecommendationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    final recommendationsAsync = ref.watch(nexusRecommendationsProvider);

    return recommendationsAsync.when(
      data: (recommendations) {
        final palette = context.coolPalette;
        if (recommendations.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: palette.accent,
                ),
                const SizedBox(width: 8),
                Text(
                  'OPPORTUNITIES FOR YOU',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: palette.accent,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recommendations.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
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
    final palette = context.coolPalette;

    return GestureDetector(
      onTap: () => openQuickActionRoute(context, recommendation.ctaAction),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.surface, palette.accent.withValues(alpha: 0.03)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    recommendation.contentType.label,
                    style: GoogleFonts.dmSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: palette.accent,
                    ),
                  ),
                ),
                Text(
                  sanitizeEmoji(recommendation.iconEmoji),
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            const Spacer(),
            Text(
              recommendation.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: palette.text,
              ),
            ),
            Text(
              recommendation.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.text2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              recommendation.rationale,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: palette.accent,
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
