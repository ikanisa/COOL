import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/status/models/cool_activity.dart';
import '../../../core/status/models/cool_season.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/icon_mapper.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../admin/providers/admin_gamification_providers.dart';
import '../../../shared/widgets/cool_screen_background.dart';

/// User-facing read-only screen showing reward seasons and activities.
class SeasonsActivitiesScreen extends ConsumerWidget {
  const SeasonsActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final text = context.coolText;
    final theme = Theme.of(context);
    
    final seasonsAsync = ref.watch(adminSeasonsProvider);
    final activitiesAsync = ref.watch(adminActivitiesProvider);

    return CoolScreenBackground(
      showGlow: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: seasonsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              context.l10n.somethingWentWrong,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.tertiaryText,
              ),
            ),
          ),
          data: (seasons) {
            final activeActivities =
                activitiesAsync.valueOrNull
                    ?.where((a) => a.isActive)
                    .toList() ??
                [];
            activeActivities.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

            // Split seasons into live/upcoming vs past
            final liveSeasons = seasons
                .where((s) => s.isLive || s.isUpcoming)
                .toList();
            final pastSeasons = seasons.where((s) => s.isExpired).toList();

            return CustomScrollView(
              slivers: [
                SliverSafeArea(
                  bottom: false,
                  sliver: SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(space.x5, space.x6, space.x5, space.x4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.of(context).pop(),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: colors.cardSurfaceStrong,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: colors.primaryText.withValues(alpha: 0.1),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.arrow_back_rounded,
                                    color: colors.primaryText,
                                    size: 20,
                                  ),
                                ),
                              ),
                              SizedBox(width: space.x4),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'REWARDS & ACTIVITIES',
                                    style: text.rayon(
                                      theme.textTheme.titleMedium,
                                      fontWeight: FontWeight.w800,
                                      color: colors.primaryText,
                                    ),
                                  ),
                                  Text(
                                    'EARN REWARDS',
                                    style: text.mono(
                                      theme.textTheme.labelSmall,
                                      color: colors.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(space.x5, 0, space.x5, space.x12),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // ── Active / Upcoming Seasons ──────────────────────
                      if (liveSeasons.isNotEmpty) ...[
                        SizedBox(height: space.x6),
                        const _SectionHeader(
                          icon: Icons.bolt_rounded,
                          label: 'ACTIVE REWARD SEASONS',
                        ),
                        SizedBox(height: space.x3),
                        ...liveSeasons.map(
                          (s) => Padding(
                            padding: EdgeInsets.only(bottom: space.x3),
                            child: _SeasonCard(season: s),
                          ),
                        ),
                      ],

                      // ── Token Activities ───────────────────────────────
                      if (activeActivities.isNotEmpty) ...[
                        SizedBox(height: space.x6),
                        const _SectionHeader(
                          icon: Icons.star_rounded,
                          label: 'REWARD ACTIVITIES',
                        ),
                        SizedBox(height: space.x3),
                        ..._buildCategoryGroups(context, activeActivities),
                      ],

                      // ── Past Seasons ───────────────────────────────────
                      if (pastSeasons.isNotEmpty) ...[
                        SizedBox(height: space.x7),
                        const _SectionHeader(
                          icon: Icons.history_rounded,
                          label: 'PAST REWARD SEASONS',
                        ),
                        SizedBox(height: space.x3),
                        ...pastSeasons.map(
                          (s) => Padding(
                            padding: EdgeInsets.only(bottom: space.x3),
                            child: _SeasonCard(season: s, dimmed: true),
                          ),
                        ),
                      ],

                      // ── Empty state ────────────────────────────────────
                      if (liveSeasons.isEmpty &&
                          pastSeasons.isEmpty &&
                          activeActivities.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: space.x16),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.emoji_events_rounded,
                                  size: 48,
                                  color: colors.tertiaryText,
                                ),
                                SizedBox(height: space.x3),
                                Text(
                                  'NO ACTIVE REWARDS',
                                  style: text.rayon(
                                    theme.textTheme.bodyMedium,
                                    color: colors.tertiaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Groups activities by category and renders each group.
  List<Widget> _buildCategoryGroups(
    BuildContext context,
    List<CoolActivity> activities,
  ) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final text = context.coolText;
    final theme = Theme.of(context);

    final grouped = <String, List<CoolActivity>>{};
    for (final a in activities) {
      grouped.putIfAbsent(a.category, () => []).add(a);
    }

    final categoryOrder = ['groups', 'rayon', 'social', 'general'];
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        final ai = categoryOrder.indexOf(a);
        final bi = categoryOrder.indexOf(b);
        return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
      });

    final widgets = <Widget>[];
    for (final key in sortedKeys) {
      widgets.add(
        Padding(
          padding: EdgeInsets.only(top: space.x2, bottom: space.x2),
          child: Text(
            _categoryLabel(key).toUpperCase(),
            style: text.rayon(
              theme.textTheme.labelMedium,
              fontWeight: FontWeight.w800,
              color: colors.secondaryText,
            ),
          ),
        ),
      );
      for (final activity in grouped[key]!) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(bottom: space.x2),
            child: _ActivityCard(activity: activity),
          ),
        );
      }
    }
    return widgets;
  }

  static String _categoryLabel(String category) => switch (category) {
    'groups' => 'Groups',
    'rayon' => 'Rayon Sports',
    'social' => 'Social',
    'general' => 'General',
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
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final text = context.coolText;
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 16, color: colors.accent),
        SizedBox(width: space.x1),
        Text(
          label.toUpperCase(),
          style: text.rayon(
            theme.textTheme.titleSmall,
            fontWeight: FontWeight.w800,
            color: colors.primaryText,
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
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final text = context.coolText;
    final theme = Theme.of(context);
    final dateFmt = DateFormat('dd MMM');
    final statusLabel = season.isLive
        ? 'LIVE'
        : season.isUpcoming
        ? 'UPCOMING'
        : 'ENDED';
    final statusColor = season.isLive
        ? colors.success
        : season.isUpcoming
        ? colors.warning
        : colors.tertiaryText;

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
                    color: colors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    IconMapper.from(season.emoji),
                    size: 20,
                    color: colors.secondaryText,
                  ),
                ),
                SizedBox(width: space.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        season.title.toUpperCase(),
                        style: text.rayon(
                          theme.textTheme.bodyLarge,
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                        ),
                      ),
                      SizedBox(height: space.x0),
                      Text(
                        '${dateFmt.format(season.startsAt)} – ${dateFmt.format(season.endsAt)}',
                        style: text.mono(
                          theme.textTheme.labelMedium,
                          color: colors.tertiaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: space.x2,
                    vertical: space.x1,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: const BorderRadius.all(
                      Radius.circular(CoolRadii.pill),
                    ),
                  ),
                  child: Text(
                    statusLabel,
                    style: text.rayon(
                      theme.textTheme.labelSmall,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            if (season.isLive) ...[
              SizedBox(height: space.x3),
              ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(radii.xs)),
                child: LinearProgressIndicator(
                  value: season.progressThroughSeason,
                  minHeight: 4,
                  backgroundColor: colors.cardSurfaceStrong,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colors.accent.withValues(alpha: 0.6),
                  ),
                ),
              ),
              SizedBox(height: space.x1),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  season.timeRemainingLabel.toUpperCase(),
                  style: text.mono(
                    theme.textTheme.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: colors.accent,
                  ),
                ),
              ),
            ],
            if (season.rewardsDescription != null &&
                season.rewardsDescription!.isNotEmpty) ...[
              SizedBox(height: space.x2),
              Text(
                season.rewardsDescription!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.tertiaryText,
                ),
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
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return CoolCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.cardSurfaceStrong,
              borderRadius: BorderRadius.all(Radius.circular(context.coolRadii.sm)),
            ),
            child: Text(
              activity.emoji,
              style: theme.textTheme.titleMedium?.copyWith(height: 1),
            ),
          ),
          SizedBox(width: space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title.toUpperCase(),
                  style: text.rayon(
                    theme.textTheme.bodyMedium,
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
                ),
                if (activity.description.isNotEmpty) ...[
                  SizedBox(height: space.x0),
                  Text(
                    activity.description,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.tertiaryText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: space.x2),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: space.x2,
              vertical: space.x1,
            ),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.all(
                Radius.circular(CoolRadii.pill),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_rounded, size: 14, color: colors.accent),
                SizedBox(width: space.x1),
                Text(
                  '${activity.tokensAwarded}',
                  style: text.mono(
                    theme.textTheme.bodySmall,
                    color: colors.accent,
                    fontWeight: FontWeight.w800,
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
