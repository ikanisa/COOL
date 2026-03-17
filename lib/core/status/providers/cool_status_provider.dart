import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cool_event.dart';
import '../models/cool_status.dart';
import '../models/cool_reward.dart';
import '../repositories/cool_status_repository.dart';
import '../../providers/supabase_client_provider.dart';

// ─── Repository provider ──────────────────────────────────────────

final coolStatusRepositoryProvider = Provider<CoolStatusRepository>((ref) {
  return CoolStatusRepository(client: ref.read(supabaseClientProvider));
});

// ─── Status state ─────────────────────────────────────────────────

final coolStatusProvider =
    StateNotifierProvider<CoolStatusNotifier, AsyncValue<CoolStatus>>((ref) {
      return CoolStatusNotifier(ref);
    });

class CoolStatusNotifier extends StateNotifier<AsyncValue<CoolStatus>> {
  CoolStatusNotifier(this._ref) : super(const AsyncValue.loading());

  final Ref _ref;

  CoolStatusRepository get _repo => _ref.read(coolStatusRepositoryProvider);

  /// Load (or create) the status for the given user.
  Future<void> load(String userId) async {
    state = const AsyncValue.loading();
    try {
      final status = await _repo.getOrCreateStatus(userId);
      state = AsyncValue.data(status);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Log an event and refresh status.
  Future<bool> logEvent(CoolEvent event) async {
    try {
      final updated = await _repo.logEvent(event);
      state = AsyncValue.data(updated);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Award points for a specific action (convenience helper).
  Future<bool> awardPoints({
    required String userId,
    required CoolEventType eventType,
    String? sourceId,
    int? points,
    Map<String, dynamic> metadata = const {},
  }) async {
    return logEvent(
      CoolEvent(
        userId: userId,
        eventType: eventType,
        sourceId: sourceId,
        pointsAwarded: points ?? eventType.defaultPoints,
        metadata: metadata,
      ),
    );
  }

  /// Maintain the user's streak.
  Future<void> maintainStreak(String userId) async {
    try {
      final updated = await _repo.maintainStreak(userId);
      state = AsyncValue.data(updated);
    } catch (_) {
      // Silent — streak maintenance is best-effort
    }
  }

  /// Spend tokens to redeem a reward.
  Future<bool> redeemReward({
    required String userId,
    required String rewardId,
  }) async {
    try {
      final updated = await _repo.redeemReward(
        userId: userId,
        rewardId: rewardId,
      );
      state = AsyncValue.data(updated);
      return true;
    } catch (_) {
      return false;
    }
  }
}

// ─── Marketplace providers ───────────────────────────────────────

final availableRewardsProvider = FutureProvider.autoDispose<List<CoolReward>>((
  ref,
) async {
  final repo = ref.watch(coolStatusRepositoryProvider);
  return repo.getAvailableRewards();
});

// ─── Recent events provider ───────────────────────────────────────

final coolRecentEventsProvider = FutureProvider.family<List<CoolEvent>, String>(
  (ref, userId) async {
    final repo = ref.watch(coolStatusRepositoryProvider);
    return repo.getRecentEvents(userId);
  },
);
