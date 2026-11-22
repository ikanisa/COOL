part of 'collect_repository.dart';

mixin _CollectRecordReads on StateNotifier<CollectState> {
  bool get _allowLocalWrites;
  CollectCloudflareClient? get _backend;
  _CollectLiveReader get _liveReader;
  _CollectAuthIdentity? get _signingOutIdentity;
  bool get _historySeedInvalidated;
  int get memberScopeGeneration;
  _CollectSessionFence _captureSession();
  bool _isCurrentSession(_CollectSessionFence session);

  int _intentReadRevision = 0;
  int _intentWindowRevision = 0;
  int _pendingIntentCountRevision = 0;
  final _currentIntentReads = <String, int>{};
  final _detailedIntentRevisions = <String, int>{};

  int _nextIntentRead() => ++_intentReadRevision;

  int? _acceptPendingIntentCount(int revision, int count) {
    if (revision < _pendingIntentCountRevision) {
      return state.pendingIntentCount;
    }
    _pendingIntentCountRevision = revision;
    return count;
  }

  List<PaymentIntentModel> _acceptRecentIntentWindow(
    int revision,
    List<PaymentIntentModel> items,
  ) {
    _intentWindowRevision = revision;
    _detailedIntentRevisions.removeWhere((_, detail) => detail < revision);
    if (_detailedIntentRevisions.isEmpty) return items;

    // A later exact read may finish while the older member refresh is still
    // assembling its other fields. Keep that observation and fill the window
    // with the remaining rows from the accepted snapshot.
    final newerDetails = state.paymentIntents
        .where((intent) => _detailedIntentRevisions.containsKey(intent.id))
        .toList();
    final newerIds = newerDetails.map((intent) => intent.id).toSet();
    _detailedIntentRevisions.removeWhere((id, _) => !newerIds.contains(id));
    return List.unmodifiable(
      [
        ...newerDetails,
        ...items.where((intent) => !newerIds.contains(intent.id)),
      ].take(50),
    );
  }

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
    final scopeGeneration = memberScopeGeneration;
    void requireCurrentScope() {
      if (!_isCurrentSession(session) ||
          _signingOutIdentity == session.identity) {
        throw StateError('Account changed');
      }
      if (memberScopeGeneration != scopeGeneration ||
          _historySeedInvalidated ||
          state.memberScopeUncertain) {
        throw StateError('Refresh your groups before checking payment status.');
      }
    }

    requireCurrentScope();
    final prior = maybeIntentById(id);
    final revision = _nextIntentRead();
    _currentIntentReads[id] = revision;
    try {
      final result = await _liveReader.fetchRecentIntents(
        intentId: id,
        accessToken: session.accessToken,
      );
      requireCurrentScope();
      if (_currentIntentReads[id] != revision ||
          revision < _intentWindowRevision) {
        throw StateError('A newer payment status check superseded this one.');
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

      final window = [
        intent,
        ...state.paymentIntents.where((old) => old.id != id).take(49),
      ];
      final visibleIds = window.map((item) => item.id).toSet();
      _detailedIntentRevisions.removeWhere(
        (itemId, _) => !visibleIds.contains(itemId),
      );
      _detailedIntentRevisions[id] = revision;
      state = state.copyWith(
        paymentIntents: window,
        pendingIntentCount: _acceptPendingIntentCount(
          revision,
          result.pendingCount,
        ),
      );
      // A synchronous observer may invalidate scope while state is published.
      requireCurrentScope();
      return intent;
    } finally {
      if (_currentIntentReads[id] == revision) _currentIntentReads.remove(id);
    }
  }
}
