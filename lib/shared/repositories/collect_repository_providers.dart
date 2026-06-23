part of 'collect_repository.dart';

final collectRepositoryProvider =
    StateNotifierProvider<CollectRepository, CollectState>((ref) {
      final supabase = ref.watch(supabaseClientProvider);
      final repository = CollectRepository(supabase: supabase);
      if (supabase != null) unawaited(repository.loadInitial());
      return repository;
    });

final collectionSummariesProvider = Provider<Map<String, CollectionSummary>>((
  ref,
) {
  final contributions = ref.watch(
    collectRepositoryProvider.select((state) => state.contributions),
  );
  final totals = <String, ({int amountRaisedRwf, int supporterCount})>{};
  for (final contribution in contributions) {
    final current =
        totals[contribution.collectionId] ??
        (amountRaisedRwf: 0, supporterCount: 0);
    totals[contribution.collectionId] = (
      amountRaisedRwf: current.amountRaisedRwf + contribution.amountRwf,
      supporterCount: current.supporterCount + 1,
    );
  }
  return {
    for (final entry in totals.entries)
      entry.key: CollectionSummary(
        amountRaisedRwf: entry.value.amountRaisedRwf,
        supporterCount: entry.value.supporterCount,
      ),
  };
});

final homeCollectionsProvider = Provider<List<CollectCollection>>((ref) {
  return ref.watch(
    collectRepositoryProvider.select(
      (state) =>
          List<CollectCollection>.unmodifiable(state.collections.take(3)),
    ),
  );
});

final pendingPaymentCountProvider = Provider<int>((ref) {
  return ref.watch(
    collectRepositoryProvider.select(
      (state) =>
          state.paymentIntents.where((item) => item.status == 'pending').length,
    ),
  );
});

final raisedTotalProvider = Provider<int>((ref) {
  return ref.watch(
    collectRepositoryProvider.select(
      (state) =>
          state.contributions.fold<int>(0, (sum, item) => sum + item.amountRwf),
    ),
  );
});

final contributedCollectionIdsProvider = Provider<Set<String>>((ref) {
  final state = ref.watch(collectRepositoryProvider);
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

bool _contributionBelongsToProfile(
  Contribution contribution,
  CollectProfile profile,
) {
  final publicId = profile.publicId.trim();
  if (publicId.isEmpty) return false;
  if (contribution.supporterLabel.contains(publicId)) return true;
  final labelDigits = contribution.supporterLabel.replaceAll(RegExp(r'\D'), '');
  final publicIdDigits = publicId.replaceAll(RegExp(r'\D'), '');
  return publicIdDigits.isNotEmpty && labelDigits.endsWith(publicIdDigits);
}
