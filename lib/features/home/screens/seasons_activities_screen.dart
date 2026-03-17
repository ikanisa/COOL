import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/status/models/cool_activity.dart';
import '../../../core/status/models/cool_season.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/icon_mapper.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../admin/providers/admin_gamification_providers.dart';

/// User-facing read-only screen showing seasons & token-earning activities.
class SeasonsActivitiesScreen extends ConsumerWidget {
  const SeasonsActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasonsAsync = ref.watch(adminSeasonsProvider);
    final activitiesAsync = ref.watch(adminActivitiesProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text),
        ),
      ),
      body: seasonsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Something went wrong',
            style: GoogleFonts.dmSans(color: AppColors.text3),
          ),
        ),
        data: (seasons) {
          final activeActivities = activitiesAsync.valueOrNull
                  ?.where((a) => a.isActive)
                  .toList() ??
              [];
          activeActivities.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

          // Split seasons into live/upcoming vs past
          final liveSeasons =
              seasons.where((s) => s.isLive || s.isUpcoming).toList();
          final pastSeasons = seasons.where((s) => s.isExpired).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 48),
            children: [
              // ── Title ──────────────────────────────────────────
              Text(
                'Seasons & Activities',
                style: GoogleFonts.dmSans(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Earn tokens by completing activities during each season',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: AppColors.text3,
                ),
              ),

              // ── Active / Upcoming Seasons ──────────────────────
              if (liveSeasons.isNotEmpty) ...[
                const SizedBox(height: 28),
                const _SectionHeader(
                  icon: Icons.bolt_rounded,
                  label: 'Active Seasons',
                ),
                const SizedBox(height: 12),
                ...liveSeasons.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SeasonCard(season: s),
                    )),
              ],

              // ── Token Activities ───────────────────────────────
              if (activeActivities.isNotEmpty) ...[
                const SizedBox(height: 24),
                const _SectionHeader(
                  icon: Icons.star_rounded,
                  label: 'Earn Tokens',
                ),
                const SizedBox(height: 12),
                ..._buildCategoryGroups(activeActivities),
              ],

              // ── Past Seasons ───────────────────────────────────
              if (pastSeasons.isNotEmpty) ...[
                const SizedBox(height: 28),
                const _SectionHeader(
                  icon: Icons.history_rounded,
                  label: 'Past Seasons',
                ),
                const SizedBox(height: 12),
                ...pastSeasons.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SeasonCard(season: s, dimmed: true),
                    )),
              ],

              // ── Empty state ────────────────────────────────────
              if (liveSeasons.isEmpty &&
                  pastSeasons.isEmpty &&
                  activeActivities.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.emoji_events_rounded,
                            size: 48, color: AppColors.text3),
                        const SizedBox(height: 12),
                        Text(
                          'No seasons or activities yet',
                          style: GoogleFonts.dmSans(
                              color: AppColors.text3, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Groups activities by category and renders each group.
  List<Widget> _buildCategoryGroups(List<CoolActivity> activities) {
    final grouped = <String, List<CoolActivity>>{};
    for (final a in activities) {
      grouped.putIfAbsent(a.category, () => []).add(a);
    }

    final categoryOrder = [
      'groups',
      'rayon',
      'mobility',
      'social',
      'general',
    ];
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        final ai = categoryOrder.indexOf(a);
        final bi = categoryOrder.indexOf(b);
        return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
      });

    final widgets = <Widget>[];
    for (final key in sortedKeys) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          _categoryLabel(key),
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.text2,
          ),
        ),
      ));
      for (final activity in grouped[key]!) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ActivityCard(activity: activity),
        ));
      }
    }
    return widgets;
  }

  static String _categoryLabel(String category) => switch (category) {
        'groups' => '💰 Groups',
        'rayon' => '⚽ Rayon Sports',
        'mobility' => '🚗 Mobility',
        'social' => '📲 Social',
        'general' => '⭐ General',
        _ => category,
      };
}

// ─── Section Header ────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
      ],
    );
  }
}

// ─── Season Card ───────────────────────────────────────────────────

class _SeasonCard extends StatelessWidget {
  const _SeasonCard({required this.season, this.dimmed = false});
  final CoolSeason season;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM');
    final statusLabel = season.isLive
        ? 'Live'
        : season.isUpcoming
            ? 'Upcoming'
            : 'Ended';
    final statusColor = season.isLive
        ? Colors.green
        : season.isUpcoming
            ? Colors.orange
            : AppColors.text3;

    return Opacity(
      opacity: dimmed ? 0.55 : 1.0,
      child: CoolCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    IconMapper.from(season.emoji),
                    size: 20,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        season.title,
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${dateFmt.format(season.startsAt)} – ${dateFmt.format(season.endsAt)}',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: AppColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: GoogleFonts.dmSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            if (season.isLive) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: season.progressThroughSeason,
                  minHeight: 4,
                  backgroundColor: AppColors.surface3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.accent.withValues(alpha: 0.6),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  season.timeRemainingLabel,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
            if (season.rewardsDescription != null &&
                season.rewardsDescription!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                season.rewardsDescription!,
                style:
                    GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Activity Card ─────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity});
  final CoolActivity activity;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Row(
        children: [
          Text(activity.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                if (activity.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    activity.description,
                    style: GoogleFonts.dmSans(
                        fontSize: 11, color: AppColors.text3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded,
                    size: 13, color: AppColors.accent),
                const SizedBox(width: 3),
                Text(
                  '${activity.tokensAwarded}',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
