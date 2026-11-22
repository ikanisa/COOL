part of 'collect_repository.dart';

mixin _CollectRepositoryOfflineSnapshot
    on StateNotifier<CollectState>, _CollectMemberHistory {
  bool _offlineRestoreSuspended = false;

  Future<bool> restoreOfflineSnapshot({required String reason}) async {
    if (_memberAuthorityDenied ||
        _offlineRestoreSuspended ||
        _historyCacheReadSuppressed) {
      return false;
    }
    final generation = _loadGeneration;
    final initialUserId = _backend?.auth.currentUser?.id;
    CollectOfflineSnapshot? cached;
    try {
      cached = await _offlineCache.read(ownerUserId: initialUserId);
    } catch (_) {
      // Key unavailable or clear failed: do not expose plaintext or turn a cache
      // problem into a second unhandled failure of the live refresh operation.
      return false;
    }
    if (!mounted ||
        _historyCacheReadSuppressed ||
        generation != _loadGeneration ||
        initialUserId != _backend?.auth.currentUser?.id) {
      return false;
    }
    if (cached == null || !cached.hasReadableData) return false;
    final expectedUserId =
        _backend?.auth.currentUser?.id ?? state.currentProfile?.id;
    if (expectedUserId != null && cached.currentProfile?.id != expectedUserId) {
      await _offlineCache.clear();
      return false;
    }
    state = state.copyWith(
      currentProfile: cached.currentProfile,
      collections: cached.collections,
      paymentIntents: cached.paymentIntents,
      contributions: cached.contributions,
      collectionSummaries: cached.collectionSummaries,
      historyPage: cached.historyPage,
      pendingIntentCount: cached.pendingIntentCount,
      isLoading: false,
      usingStaleCache: true,
      publicDiscoveryLoading: false,
      publicDiscoveryUnavailable: true,
      lastSuccessfulSyncAt: cached.savedAt,
      lastError: reason,
    );
    return true;
  }

  CollectOfflineSnapshot _offlineSnapshotFromState() {
    final owner = state.currentProfile?.id;
    return CollectOfflineSnapshot(
      savedAt: state.lastSuccessfulSyncAt ?? DateTime.now().toUtc(),
      currentProfile: state.currentProfile,
      // Discovery is refreshed from its public source; only the authenticated
      // member scope belongs in this protected offline financial snapshot.
      collections: owner == null
          ? const []
          : state.collections
                .where(
                  (item) =>
                      item.isCurrentUserMember || item.creatorUserId == owner,
                )
                .toList(),
      paymentIntents: state.paymentIntents,
      contributions: state.contributions,
      collectionSummaries: state.collectionSummaries,
      historyPage: state.historyPage,
      pendingIntentCount: state.pendingIntentCount,
    );
  }

  Future<void> _saveOfflineSnapshot() {
    if (_historyCacheReadSuppressed || _offlineRestoreSuspended) {
      return Future<void>.value();
    }
    return _offlineCache.save(_offlineSnapshotFromState());
  }
}
