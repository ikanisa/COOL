import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/status/models/cool_mission.dart';
import '../../../core/status/providers/cool_missions_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/mission_progress_card.dart';
import '../../../features/auth/providers/auth_provider.dart';

/// Screen showing active and upcoming cooperative missions.
class MissionsScreen extends ConsumerWidget {
  const MissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authProvider).user?.id ?? '';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CoolScreenBackground(
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // ─── App bar ─────────────────────────────────
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                pinned: true,
                title: Text(
                  'Missions',
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                centerTitle: false,
              ),

              // ─── Active missions ─────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: _SectionLabel(label: 'Active Missions'),
                ),
              ),

              if (userId.isNotEmpty)
                _ActiveMissionsSliver(userId: userId)
              else
                const SliverToBoxAdapter(
                  child: _EmptyState(message: 'Sign in to see missions'),
                ),

              // ─── Upcoming missions ───────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: _SectionLabel(label: 'Coming Soon'),
                ),
              ),

              const _UpcomingMissionsSliver(),

              // Bottom spacing
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Active missions sliver ───────────────────────────────────────

class _ActiveMissionsSliver extends ConsumerWidget {
  const _ActiveMissionsSliver({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionsAsync = ref.watch(activeMissionsProvider(userId));

    return missionsAsync.when(
      data: (missions) {
        if (missions.isEmpty) {
          return const SliverToBoxAdapter(
            child: _EmptyState(message: 'No active missions right now'),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
          sliver: SliverList.separated(
            itemCount: missions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              return MissionProgressCard(mission: missions[index]);
            },
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator.adaptive()),
        ),
      ),
      error: (_, _) => const SliverToBoxAdapter(
        child: _EmptyState(message: 'Couldn\'t load missions'),
      ),
    );
  }
}

// ─── Upcoming missions sliver ─────────────────────────────────────

class _UpcomingMissionsSliver extends ConsumerWidget {
  const _UpcomingMissionsSliver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcomingAsync = ref.watch(upcomingMissionsProvider);

    return upcomingAsync.when(
      data: (missions) {
        if (missions.isEmpty) {
          return const SliverToBoxAdapter(
            child: _EmptyState(message: 'No upcoming missions'),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
          sliver: SliverList.separated(
            itemCount: missions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              return _UpcomingMissionTile(mission: missions[index]);
            },
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator.adaptive()),
        ),
      ),
      error: (_, _) => const SliverToBoxAdapter(
        child: _EmptyState(message: 'Couldn\'t load upcoming missions'),
      ),
    );
  }
}

// ─── Upcoming mission tile ────────────────────────────────────────

class _UpcomingMissionTile extends StatelessWidget {
  const _UpcomingMissionTile({required this.mission});
  final CoolMission mission;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text(mission.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mission.title,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Starts ${_formatDate(mission.startsAt)}',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: AppColors.text3,
                  ),
                ),
              ],
            ),
          ),
          if (mission.rewardPoints > 0)
            Text(
              '🏆 ${mission.rewardPoints} pts',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.yellow,
              ),
            ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = date.difference(now);
    if (diff.inDays < 1) return 'today';
    if (diff.inDays == 1) return 'tomorrow';
    if (diff.inDays < 7) return 'in ${diff.inDays} days';
    return '${date.day}/${date.month}';
  }
}

// ─── Section label ────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.dmSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: AppColors.text3,
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
      child: Center(
        child: Text(
          message,
          style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text3),
        ),
      ),
    );
  }
}
