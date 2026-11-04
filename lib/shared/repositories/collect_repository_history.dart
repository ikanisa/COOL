part of 'collect_repository.dart';

final memberHistoryProvider = StateNotifierProvider.autoDispose
    .family<MemberHistoryController, MemberHistoryState, MemberHistoryQuery>((
      ref,
      query,
    ) {
      // Replacing the repository must dispose the old controller even when the
      // new repository happens to publish an equal state-selection tuple.
      final repository = ref.watch(collectRepositoryProvider.notifier);
      ref.watch(
        collectRepositoryProvider.select(
          (state) => (
            repository.sessionGeneration,
            state.currentProfile?.id,
            state.lastSuccessfulSyncAt,
            state.usingStaleCache,
          ),
        ),
      );
      return MemberHistoryController(repository, query);
    });

class MemberHistoryState {
  const MemberHistoryState({this.page, this.loading = false, this.error});
  final MemberHistoryPage? page;
  final bool loading;
  final String? error;
}

class MemberHistoryController extends StateNotifier<MemberHistoryState> {
  MemberHistoryController(this.repository, this.query)
    : _ownerProfileId = repository.state.currentProfile?.id,
      _ownerAuthId = repository._backend?.auth.currentUser?.id,
      _ownerSession = repository._captureSession(),
      super(const MemberHistoryState()) {
    _historyInvalidationListener = _onHistoryInvalidated;
    repository._historyInvalidationListeners.add(_historyInvalidationListener);
    try {
      if (!_contextCurrent()) return;
      final initial = repository.state.historyPage;
      if (repository._allowLocalWrites &&
          !repository.isLive &&
          !repository.state.usingStaleCache &&
          initial == null) {
        state = MemberHistoryState(page: repository.localHistoryPage(query));
      } else if (query.isDefault &&
          initial != null &&
          !repository._historySeedInvalidated) {
        state = MemberHistoryState(page: initial);
      } else {
        if (query.search.isNotEmpty && repository.isLive) {
          state = const MemberHistoryState(loading: true);
          _debounce = Timer(const Duration(milliseconds: 300), refresh);
        } else {
          unawaited(refresh());
        }
      }
    } catch (_) {
      repository._historyInvalidationListeners.remove(
        _historyInvalidationListener,
      );
      rethrow;
    }
  }

  final CollectRepository repository;
  final MemberHistoryQuery query;
  final String? _ownerProfileId;
  final String? _ownerAuthId;
  final _CollectSessionFence _ownerSession;
  late final void Function() _historyInvalidationListener;
  int _generation = 0;
  Timer? _debounce;
  bool _refreshing = false;
  bool _refreshRequired = false;

  bool _contextCurrent() {
    if (!mounted) return false;
    if (!repository._isCurrentSession(_ownerSession) ||
        (repository._signingOutIdentity != null &&
            repository._signingOutIdentity == _ownerSession.identity) ||
        repository.state.currentProfile?.id != _ownerProfileId ||
        repository._backend?.auth.currentUser?.id != _ownerAuthId) {
      ++_generation;
      _debounce?.cancel();
      _refreshing = false;
      _refreshRequired = false;
      // Never retain the old account's records in a stale controller.
      state = const MemberHistoryState(
        error: 'Account changed. Reload history.',
      );
      return false;
    }
    return true;
  }

  bool _canPublish(int generation) =>
      mounted && generation == _generation && _contextCurrent();

  void _onHistoryInvalidated() {
    if (!_contextCurrent()) return;
    ++_generation;
    _debounce?.cancel();
    _refreshing = false;
    _refreshRequired = true;
    state = const MemberHistoryState(
      error: 'History changed. Refresh to continue.',
    );
  }

  @override
  void dispose() {
    ++_generation;
    _debounce?.cancel();
    repository._historyInvalidationListeners.remove(
      _historyInvalidationListener,
    );
    super.dispose();
  }

  Future<void> refresh() async {
    if (!_contextCurrent() || _refreshing) return;
    _debounce?.cancel();
    final previousPage = state.page;
    _refreshing = true;
    _refreshRequired = false;
    final generation = ++_generation;
    try {
      try {
        state = const MemberHistoryState(loading: true);
      } catch (error, stack) {
        if (mounted && generation == _generation) {
          try {
            if (_contextCurrent() && generation == _generation) {
              state = MemberHistoryState(
                page: previousPage,
                error: 'Connect to load the complete history.',
              );
            }
          } catch (_) {
            // Preserve the original listener failure after restoring the state.
          }
        }
        Error.throwWithStackTrace(error, stack);
      }
      if (!_canPublish(generation)) return;
      final requestSession = repository._captureSession();
      late final MemberHistoryPage page;
      try {
        page = await repository.fetchHistoryPage(query);
        if (!_canPublish(generation)) return;
        if (repository.isLive) page.validateRequest(query: query);
      } catch (error) {
        _handleFailure(error, generation, requestSession);
        return;
      }
      state = MemberHistoryState(page: page);
    } finally {
      if (mounted && generation == _generation) _refreshing = false;
    }
  }

  Future<void> loadMore() async {
    if (!_contextCurrent() || _refreshRequired) return;
    final page = state.page;
    if (state.loading || page?.nextCursor == null) return;
    final generation = ++_generation;
    try {
      state = MemberHistoryState(page: page, loading: true);
    } catch (error, stack) {
      // StateNotifier updates its state before reporting listener failures.
      // Restore a retryable page unless an observer started a newer request.
      if (mounted && generation == _generation) {
        try {
          if (_contextCurrent() && generation == _generation) {
            state = MemberHistoryState(
              page: page,
              error: 'Could not load more. Try again.',
            );
          }
        } catch (_) {
          // Preserve the original listener failure after restoring the state.
        }
      }
      Error.throwWithStackTrace(error, stack);
    }
    if (!_canPublish(generation)) return;
    final requestSession = repository._captureSession();
    late final MemberHistoryPage merged;
    try {
      final next = await repository.fetchHistoryPage(
        query,
        cursor: page!.nextCursor,
      );
      if (!_canPublish(generation)) return;
      merged = page.append(next, query: query);
    } catch (error) {
      _handleFailure(error, generation, requestSession, previousPage: page);
      return;
    }
    state = MemberHistoryState(page: merged);
  }

  void _handleFailure(
    Object error,
    int generation,
    _CollectSessionFence requestSession, {
    MemberHistoryPage? previousPage,
  }) {
    final invalidQuery = error is _InvalidMemberHistoryQuery;
    final changed =
        (error is FormatException && !invalidQuery) ||
        (error is CollectApiException &&
            const {'P0001', 'history_changed'}.contains(error.code));
    final accessChanged =
        repository._isAccessFailure(error) ||
        (error is CollectApiException &&
            (error.httpStatusCode == 401 ||
                error.httpStatusCode == 403 ||
                error.code == 'history_scope_unavailable'));
    final scopeChanged =
        changed ||
        (error is CollectApiException &&
            (const {
                  'history_scope_unavailable',
                  'access_revoked',
                }.contains(error.code) ||
                (error.code == 'session_changed' &&
                    error.httpStatusCode == 403)));
    if (!mounted) {
      if ((changed || accessChanged) &&
          repository._isCurrentSession(requestSession)) {
        repository._invalidateHistorySeed(
          scopeChanged ? repository._captureSession() : requestSession,
          surviveBearerChange: scopeChanged,
        );
      }
      return;
    }
    // A later request can finish before an older denial was observed. A
    // request generation does not establish the server's snapshot order.
    if (generation != _generation && !changed && !accessChanged) return;
    if (!_contextCurrent()) return;
    if (accessChanged &&
        !scopeChanged &&
        (!repository._isCurrentSession(requestSession) ||
            repository._backend?.auth.currentSession?.accessToken !=
                requestSession.accessToken)) {
      // A denial for a replaced bearer cannot invalidate a newer response.
      // If no newer request exists, require a read with the current bearer.
      if (generation != _generation) return;
      repository._markHistorySeedInvalidated(repository._captureSession());
      _refreshRequired = true;
      state = const MemberHistoryState(
        error: 'History changed. Refresh to continue.',
      );
      return;
    }
    if (generation != _generation) {
      ++_generation;
      _refreshing = false;
    }
    final shouldInvalidate = changed || accessChanged;
    final invalidationSession = scopeChanged
        ? repository._captureSession()
        : requestSession;
    _refreshRequired = shouldInvalidate;
    if (shouldInvalidate) {
      repository._markHistorySeedInvalidated(invalidationSession);
    }
    try {
      state = MemberHistoryState(
        // A revision change can reflect revoked membership. Do not leave rows
        // or totals from the earlier authority snapshot on screen or seed them.
        page: shouldInvalidate ? null : previousPage,
        error: invalidQuery
            ? 'Check your history search or filter.'
            : changed
            ? 'History changed. Refresh to continue.'
            : accessChanged
            ? 'History access changed. Refresh to continue.'
            : previousPage == null
            ? 'Connect to load the complete history.'
            : 'Could not load more. Try again.',
      );
    } finally {
      if (shouldInvalidate) {
        repository._invalidateHistorySeed(
          invalidationSession,
          except: _historyInvalidationListener,
          surviveBearerChange: scopeChanged,
        );
      }
    }
  }
}
