part of 'collect_repository.dart';

mixin _CollectRecordReads on StateNotifier<CollectState> {
  bool get _allowLocalWrites;
  CollectCloudflareClient? get _backend;
  _CollectLiveReader get _liveReader;
  _CollectSessionFence _captureSession();
  bool _isCurrentSession(_CollectSessionFence session);

  CollectCollection collectionById(String id) =>
      state.collections.firstWhere((collection) => collection.id == id);

  CollectCollection? maybeCollectionById(String id) {
    for (final collection in state.collections) {
      if (collection.id == id) return collection;
    }
    return null;
  }

  CollectCollection collectionBySlug(String slug) =>
      state.collections.firstWhere((collection) => collection.slug == slug);

  CollectCollection? maybeCollectionBySlug(String slug) {
    for (final collection in state.collections) {
      if (collection.slug == slug) return collection;
    }
    return null;
  }

  PaymentIntentModel intentById(String id) =>
      state.paymentIntents.singleWhere((intent) => intent.id == id);

  PaymentIntentModel? maybeIntentById(String id) {
    final matches = state.paymentIntents
        .where((intent) => intent.id == id)
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  /// A recent history page cannot establish a complete group or own balance.
  CollectionSummary? summaryFor(String collectionId) =>
      state.collectionSummaries[collectionId];

  List<Contribution> contributionsFor(String collectionId) =>
      state.contributions
          .where((item) => item.collectionId == collectionId)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<PaymentIntentModel> refreshPaymentIntent(String id) async {
    final backend = _backend;
    if (backend == null || backend.auth.currentUser == null) {
      if (!_allowLocalWrites) {
        throw StateError('Sign in before refreshing transfer status.');
      }
      return intentById(id);
    }
    final session = _captureSession();
    final prior = maybeIntentById(id);
    final result = await _liveReader.fetchRecentIntents(
      intentId: id,
      accessToken: session.accessToken,
    );
    if (!_isCurrentSession(session)) {
      throw StateError('Account changed');
    }
    final matches = result.items.where((item) => item.id == id).toList();
    if (matches.length != 1) {
      throw StateError('Payment intent is unavailable');
    }
    final intent = matches.single;
    if (prior != null &&
        (intent.collectionId != prior.collectionId ||
            intent.expectedAmountMinor != prior.expectedAmountMinor ||
            intent.rail != prior.rail ||
            intent.currency != prior.currency)) {
      throw const FormatException(
        'Intent identity does not match the existing request',
      );
    }
    state = state.copyWith(
      paymentIntents: [
        intent,
        ...state.paymentIntents.where((old) => old.id != id).take(49),
      ],
      pendingIntentCount: result.pendingCount,
    );
    return intent;
  }
}
