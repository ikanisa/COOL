import 'package:flutter/material.dart';

import '../../router/app_routes.dart';
import '../models/cool_status.dart';

/// A suggested "next best action" for the user.
class CoolQuest {
  const CoolQuest({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.priority = 0,
  });

  final String id;
  final IconData icon;
  final String title;
  final String subtitle;

  /// GoRouter route to navigate when CTA is tapped.
  final String route;

  /// Higher = more important (shown first).
  final int priority;
}

/// Pure-Dart client-side engine that reads user state and generates
/// ranked quest suggestions.
///
/// This engine does NOT call any API. It operates entirely on
/// local state already available to the app.
class QuestEngine {
  const QuestEngine._();

  /// Generate quests from current user state. Returns at most [maxQuests].
  static List<CoolQuest> generate({
    required CoolStatus status,
    dynamic membership,
    int groupCount = 0,
    int activeGroupGoalPercent = 0,
    int matchTicketsThisMonth = 0,
    int tripStreakCount = 0,
    int pendingMomoCount = 0,
    bool hasPostedTrip = false,
    int maxQuests = 3,
  }) {
    final quests = <CoolQuest>[];

    // ─── 1. Near next tier ──────────────────────────────────
    if (status.tier != CoolTier.platinum && status.pointsToNextTier <= 50) {
      final nextTier = _nextTierLabel(status.tier);
      quests.add(
        CoolQuest(
          id: 'near_tier',
          icon: Icons.trending_up_rounded,
          title: 'Almost $nextTier!',
          subtitle: '${status.pointsToNextTier} points to unlock',
          route: '/profile',
          priority: 90,
        ),
      );
    }

    // ─── 2. Group at high progress ──────────────────────────
    if (activeGroupGoalPercent >= 70 && activeGroupGoalPercent < 100) {
      quests.add(
        CoolQuest(
          id: 'group_push',
          icon: Icons.gps_fixed_rounded,
          title: 'Your group is close!',
          subtitle: '$activeGroupGoalPercent% of goal contributed',
          route: AppRoutes.contributionCircles,
          priority: 85,
        ),
      );
    }

    // ─── 3. No match tickets this month ─────────────────────
    if (matchTicketsThisMonth == 0) {
      quests.add(
        const CoolQuest(
          id: 'match_attend',
          icon: Icons.sports_soccer_rounded,
          title: 'Attend a match!',
          subtitle: 'Earn 20 points for supporting your team in person.',
          route: AppRoutes.splash,
          priority: 70,
        ),
      );
    }

    // ─── 4. Pending MoMo confirmations ──────────────────────
    if (pendingMomoCount > 0) {
      quests.add(
        CoolQuest(
          id: 'pending_momo',
          icon: Icons.phone_android_rounded,
          title: 'Confirm transaction',
          subtitle: '$pendingMomoCount pending MoMo confirmations',
          route: '/momo',
          priority: 80,
        ),
      );
    }

    // ─── 5. Join a group ────────────────────────────────────
    if (groupCount == 0) {
      quests.add(
        const CoolQuest(
          id: 'join_group',
          icon: Icons.group_rounded,
          title: 'Join a savings group',
          subtitle: 'Earn 20 points per week saved.',
          route: AppRoutes.contributionCircles,
          priority: 60,
        ),
      );
    }

    // ─── 6. No fan club ─────────────────────────────────────
    if (membership == null) {
      quests.add(
        const CoolQuest(
          id: 'join_club',
          icon: Icons.stadium_rounded,
          title: 'Become a fan',
          subtitle: 'Join the club and earn rewards.',
          route: AppRoutes.splash,
          priority: 50,
        ),
      );
    }

    // ─── 7. Streak maintenance ──────────────────────────────
    if (status.currentStreak > 0 && status.streakGraceRemaining == 0) {
      quests.add(
        const CoolQuest(
          id: 'streak_risk',
          icon: Icons.local_fire_department_rounded,
          title: 'Streak at risk!',
          subtitle: 'Do an action today to keep it.',
          route: '/home',
          priority: 95,
        ),
      );
    }

    // Sort by priority descending, take top N
    quests.sort((a, b) => b.priority.compareTo(a.priority));
    return quests.take(maxQuests).toList(growable: false);
  }

  static String _nextTierLabel(CoolTier tier) => switch (tier) {
    CoolTier.member => 'Silver',
    CoolTier.silver => 'Gold',
    CoolTier.gold => 'Platinum',
    CoolTier.platinum => 'Platinum',
  };
}
