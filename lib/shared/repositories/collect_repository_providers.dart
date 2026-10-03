part of 'collect_repository.dart';

final collectRepositoryProvider =
    StateNotifierProvider<CollectRepository, CollectState>((ref) {
      final supabase = ref.watch(supabaseClientProvider);
      final repository = CollectRepository(
        supabase: supabase,
        onSignOutStarted: () =>
            ref.read(privacySessionAuthorityProvider)?.invalidate(),
      );
      if (supabase != null) unawaited(repository.loadInitial());
      return repository;
    });

final collectPublicRuntimeConfigProvider = FutureProvider<CollectRuntimeConfig>(
  (ref) async {
    final supabase = ref.watch(supabaseClientProvider);
    if (supabase == null) return CollectRuntimeConfig.defaults;
    try {
      final payload = await supabase.rpc<dynamic>('get_public_runtime_config');
      if (payload is Map) {
        return CollectRuntimeConfig.fromJson(
          Map<String, dynamic>.from(payload),
        );
      }
    } catch (_) {
      return CollectRuntimeConfig.defaults;
    }
    return CollectRuntimeConfig.defaults;
  },
);

final collectRuntimeConfigProvider = Provider<CollectRuntimeConfig>((ref) {
  return ref.watch(collectPublicRuntimeConfigProvider).valueOrNull ??
      CollectRuntimeConfig.defaults;
});

final collectPolicyDocumentProvider =
    FutureProvider.family<CollectPolicyDocument, String>((ref, kind) async {
      final fallback = CollectPolicyDocument.defaults(kind);
      final supabase = ref.watch(supabaseClientProvider);
      if (supabase == null) return fallback;
      try {
        final payload = await supabase.rpc<dynamic>(
          'get_active_policy_document',
          params: {'p_kind': fallback.kind, 'p_locale': fallback.locale},
        );
        if (payload is Map) {
          return CollectPolicyDocument.fromJson(
            Map<String, dynamic>.from(payload),
            fallbackKind: fallback.kind,
          );
        }
      } catch (_) {
        return fallback;
      }
      return fallback;
    });

final collectAccountDeletionReasonsProvider =
    FutureProvider<List<AccountRequestReasonOption>>((ref) async {
      final supabase = ref.watch(supabaseClientProvider);
      if (supabase == null) return collectDefaultAccountDeletionReasons;
      try {
        final payload = await supabase.rpc<dynamic>(
          'list_account_request_reasons',
          params: {'p_request_type': 'account_deletion', 'p_locale': 'en'},
        );
        if (payload is List) {
          final reasons = [
            for (final item in payload)
              if (item is Map)
                AccountRequestReasonOption.fromJson(
                  Map<String, dynamic>.from(item),
                ),
          ].where((item) => item.key.isNotEmpty).toList(growable: false);
          if (reasons.isNotEmpty) return reasons;
        }
      } catch (_) {
        return collectDefaultAccountDeletionReasons;
      }
      return collectDefaultAccountDeletionReasons;
    });

final collectCollectionTypeCatalogProvider =
    FutureProvider<CollectionTypeCatalogConfig>((ref) async {
      const fallback = CollectionTypeCatalogConfig.defaults;
      final profileCountry = ref.watch(
        collectRepositoryProvider.select(
          (state) => state.currentProfile?.countryCode,
        ),
      );
      final countryCode =
          CollectProfileCountryRules.isSupportedCountry(profileCountry)
          ? CollectProfileCountryRules.normalizeCountryCode(profileCountry)
          : fallback.countryCode;
      final supabase = ref.watch(supabaseClientProvider);
      if (supabase == null) return fallback;
      try {
        final payload = await supabase.rpc<dynamic>(
          'get_collection_type_catalog',
          params: {'p_country_code': countryCode, 'p_locale': 'en'},
        );
        if (payload is Map) {
          return CollectionTypeCatalogConfig.fromJson(
            Map<String, dynamic>.from(payload),
          );
        }
      } catch (_) {
        return fallback;
      }
      return fallback;
    });

final collectionSummariesProvider = Provider<Map<String, CollectionSummary>>((
  ref,
) {
  final state = ref.watch(collectRepositoryProvider);
  // Missing server summaries stay missing; callers render an unavailable state.
  // Never derive apparent complete balances from a bounded transaction window.
  return Map<String, CollectionSummary>.unmodifiable(state.collectionSummaries);
});

final activeCollectionsProvider = Provider<List<CollectCollection>>((ref) {
  final collections = ref.watch(
    collectRepositoryProvider.select((state) => state.collections),
  );
  return List<CollectCollection>.unmodifiable(
    collections.where((collection) => !collection.isArchived),
  );
});

final memberCollectionsProvider = Provider<List<CollectCollection>>((ref) {
  final collections = ref.watch(activeCollectionsProvider);
  final profile = ref.watch(
    collectRepositoryProvider.select((state) => state.currentProfile),
  );
  if (profile == null) return const <CollectCollection>[];
  return List<CollectCollection>.unmodifiable(
    collections.where(
      (collection) =>
          collection.creatorUserId == profile.id ||
          collection.isCurrentUserMember,
    ),
  );
});

final homeCollectionsProvider = Provider<List<CollectCollection>>((ref) {
  return List<CollectCollection>.unmodifiable(
    ref.watch(memberCollectionsProvider).take(3),
  );
});

final featuredCollectionsProvider = Provider<List<CollectCollection>>((ref) {
  final collections = ref.watch(activeCollectionsProvider);
  // Public approval is owned by Supabase. Joining or owning a featured group
  // must not remove it from Home's public selection.
  return List<CollectCollection>.unmodifiable(
    collections.where((collection) => collection.isPublic),
  );
});

// A recent window cannot establish a complete pending count or money total.
// Absence stays unknown even when the locally visible rows happen to be empty.
final pendingPaymentCountProvider = Provider<int?>(
  (ref) => ref.watch(
    collectRepositoryProvider.select((state) => state.pendingIntentCount),
  ),
);

final raisedTotalsByCurrencyProvider = Provider<Map<String, int>?>(
  (ref) => ref.watch(collectRepositoryProvider).historyPage?.ownTotals,
);

final contributedCollectionIdsProvider = Provider<Set<String>>((ref) {
  final state = ref.watch(collectRepositoryProvider);
  if (state.historyPage != null) return state.historyPage!.ownCollectionIds;
  final profile = state.currentProfile;
  if (profile == null) return const <String>{};
  return Set<String>.unmodifiable({
    for (final contribution in state.contributions)
      if (_contributionBelongsToProfile(contribution, profile))
        contribution.collectionId,
  });
});

final contributionsForCollectionProvider =
    Provider.family<List<Contribution>, String>((ref, collectionId) {
      final contributions = ref.watch(
        collectRepositoryProvider.select(
          (state) => [
            for (final item in state.contributions)
              if (item.collectionId == collectionId) item,
          ]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        ),
      );
      return List<Contribution>.unmodifiable(contributions);
    });

final confirmedContributionActivityProvider = Provider<List<Contribution>>((
  ref,
) {
  final contributions = ref.watch(
    collectRepositoryProvider.select(
      (state) =>
          [...state.contributions]
            ..sort((left, right) => right.createdAt.compareTo(left.createdAt)),
    ),
  );
  return List<Contribution>.unmodifiable(contributions);
});

bool _contributionBelongsToProfile(
  Contribution contribution,
  CollectProfile profile,
) {
  // A display label is never an authorization or ownership identifier.
  return contribution.isCurrentUserContribution;
}
