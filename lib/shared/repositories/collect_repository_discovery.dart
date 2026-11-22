part of 'collect_repository.dart';

mixin _CollectRepositoryDiscovery on StateNotifier<CollectState> {
  _CollectLiveReader get _liveReader;

  Future<void> _loadPublicSnapshot({required bool Function() isCurrent}) async {
    state = state.copyWith(isLoading: true, usingStaleCache: false);
    try {
      final publicCollections = await _liveReader.fetchPublicCollections();
      if (!isCurrent()) return;
      state = state.copyWith(
        currentProfile: null,
        collections: publicCollections,
        paymentIntents: const [],
        contributions: const [],
        collectionSummaries: const {},
        historyPage: null,
        pendingIntentCount: 0,
        isLoading: false,
        usingStaleCache: false,
        publicDiscoveryLoading: false,
        publicDiscoveryUnavailable: false,
        lastSuccessfulSyncAt: DateTime.now().toUtc(),
      );
    } catch (error) {
      if (!isCurrent()) return;
      state = state.copyWith(
        isLoading: false,
        usingStaleCache: false,
        publicDiscoveryLoading: false,
        publicDiscoveryUnavailable: true,
        lastError: error.toString(),
      );
    }
  }

  Future<void> _refreshPublicDiscovery(
    String userId, {
    required bool Function() isCurrent,
  }) async {
    try {
      final publicCollections = await _liveReader.fetchPublicCollections();
      if (!isCurrent()) return;
      final ids = publicCollections.map((item) => item.id).toSet();
      if (ids.length != publicCollections.length ||
          publicCollections.any(
            (item) =>
                !item.isPublic || item.isCurrentUserMember || item.isArchived,
          )) {
        throw const FormatException('Public group data is invalid.');
      }
      // A join can finish while the public request is in flight. Keep current
      // member DTOs and never replace them with redacted public versions.
      final members = state.collections
          .where(
            (item) => item.isCurrentUserMember || item.creatorUserId == userId,
          )
          .toList();
      final memberIds = members.map((item) => item.id).toSet();
      state = state.copyWith(
        collections: [
          ...members,
          ...publicCollections.where((item) => !memberIds.contains(item.id)),
        ],
        publicDiscoveryLoading: false,
        publicDiscoveryUnavailable: false,
        lastError: state.lastError,
      );
    } catch (_) {
      if (!isCurrent()) return;
      // A public-list failure is not evidence that member authority failed.
      state = state.copyWith(
        publicDiscoveryLoading: false,
        publicDiscoveryUnavailable: true,
        lastError: state.lastError,
      );
    }
  }
}
