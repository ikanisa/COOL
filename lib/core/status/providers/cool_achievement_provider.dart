import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cool_achievement.dart';
import 'cool_status_provider.dart';

/// Provider for all achievements (earned and available) for a user.
final coolAchievementsProvider = FutureProvider.autoDispose
    .family<List<CoolAchievement>, String>((ref, userId) async {
      final repo = ref.watch(coolStatusRepositoryProvider);
      return repo.getAchievements(userId);
    });

/// Provider for only earned achievements for a user.
final earnedAchievementsProvider = Provider.autoDispose
    .family<AsyncValue<List<CoolAchievement>>, String>((ref, userId) {
      final allAsync = ref.watch(coolAchievementsProvider(userId));

      return allAsync.whenData(
        (list) => list.where((a) => a.isEarned).toList(),
      );
    });
