part of 'collect_repository.dart';

mixin _CollectMemberHistory on StateNotifier<CollectState>
    implements MemberHistoryRepository {
  CollectCloudflareClient? get _backend;
  _CollectAuthIdentity? get _signingOutIdentity;
  _CollectLiveReader get _liveReader;
  bool get _allowLocalWrites;
  bool get _memberAuthorityDenied;
  bool get isLive;
  int get _authGeneration;
  int get _signOutGeneration;
  int get _loadGeneration;
  set _loadGeneration(int value);
  _CollectSessionFence _captureSession();
  bool _isCurrentSession(_CollectSessionFence session);
  bool _isAccessFailure(Object error);

  ({bool changed, bool accessChanged, bool scopeChanged}) _historyFailure(
    Object error,
  ) {
    final changed =
        (error is FormatException && error is! _InvalidMemberHistoryQuery) ||
        (error is CollectApiException &&
            const {'P0001', 'history_changed'}.contains(error.code));
    final accessChanged =
        _isAccessFailure(error) ||
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
    return (
      changed: changed,
      accessChanged: accessChanged,
      scopeChanged: scopeChanged,
    );
  }

  int? _historySeedInvalidatedAtSession;
  int _historyScopeEpoch = 0;
  // The synchronous hold covers callbacks while the owner marker is persisted.
  bool _historyCacheReadSuppressed = false;
  CollectOfflineCache get _offlineCache;
  Future<void> _cacheDenialPersisted = Future<void>.value();

  Future<void> _holdDeniedCache(_CollectSessionFence session) async {
    final owner = session.identity?.userId;
    if (owner == null) return;
    try {
      await _offlineCache.holdAfterDenial(owner);
    } catch (_) {
      if (!_isCurrentSession(session)) return;
      try {
        await _offlineCache.clear();
      } catch (_) {
        // The current repository continues to suppress reads.
      }
    }
  }

  final _historyInvalidationListeners = <void Function()>{};

  /// Revision of the current member-history authority view.
  int get memberScopeGeneration => _historyScopeEpoch;

  bool get _historySeedInvalidated =>
      _historySeedInvalidatedAtSession == _authGeneration;

  bool _historySignalCurrent(_CollectSessionFence session) =>
      _isCurrentSession(session) &&
      (_signingOutIdentity == null || _signingOutIdentity != session.identity);

  bool _acceptHistorySeedSession(_CollectSessionFence session) =>
      _historySignalCurrent(session) &&
      _backend?.auth.currentSession?.accessToken == session.accessToken;

  void _markHistorySeedInvalidated(_CollectSessionFence session) {
    if (_acceptHistorySeedSession(session)) {
      _historySeedInvalidatedAtSession = _authGeneration;
    }
  }

  bool _fenceHistoryScope(
    _CollectSessionFence session, {
    bool surviveBearerChange = false,
  }) {
    if (surviveBearerChange
        ? !_historySignalCurrent(session)
        : !_acceptHistorySeedSession(session)) {
      return false;
    }
    _historySeedInvalidatedAtSession = _authGeneration;
    ++_historyScopeEpoch;
    ++_loadGeneration;
    _historyCacheReadSuppressed = true;
    _cacheDenialPersisted = _holdDeniedCache(session);
    return true;
  }

  void _maskHistoryScope() {
    state = state.copyWith(
      memberScopeUncertain: true,
      isLoading: false,
      usingStaleCache: false,
      publicDiscoveryLoading: false,
      lastError: 'Refresh to verify your groups and activity.',
    );
  }

  void _invalidateHistorySeed(
    _CollectSessionFence session, {
    void Function()? except,
    bool surviveBearerChange = false,
  }) {
    if (!_fenceHistoryScope(
      session,
      surviveBearerChange: surviveBearerChange,
    )) {
      return;
    }
    Object? firstError;
    StackTrace? firstStack;
    try {
      _maskHistoryScope();
    } catch (error, stack) {
      firstError = error;
      firstStack = stack;
    }
    try {
      _notifyHistoryInvalidation(
        session,
        except: except,
        surviveBearerChange: surviveBearerChange,
      );
    } catch (error, stack) {
      firstError ??= error;
      firstStack ??= stack;
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }

  void _invalidateHistoryForSignOut(
    _CollectSessionFence session,
    int operation,
  ) {
    if (session.identity == null ||
        !_isCurrentSession(session) ||
        _signingOutIdentity != session.identity ||
        operation != _signOutGeneration) {
      return;
    }
    _historySeedInvalidatedAtSession = _authGeneration;
    ++_historyScopeEpoch;
    _notifyHistoryInvalidation(session, signOutOperation: operation);
  }

  void _notifyHistoryInvalidation(
    _CollectSessionFence session, {
    void Function()? except,
    bool surviveBearerChange = false,
    int? signOutOperation,
  }) {
    bool current() => signOutOperation == null
        ? _historySignalCurrent(session)
        : _isCurrentSession(session) &&
              session.identity != null &&
              _signingOutIdentity == session.identity &&
              _signOutGeneration == signOutOperation;
    Object? firstError;
    StackTrace? firstStack;
    for (final listener in List<void Function()>.of(
      _historyInvalidationListeners,
    )) {
      if (!current()) break;
      if (signOutOperation == null &&
          !surviveBearerChange &&
          _backend?.auth.currentSession?.accessToken != session.accessToken) {
        break;
      }
      if (identical(listener, except) ||
          !_historyInvalidationListeners.contains(listener)) {
        continue;
      }
      try {
        listener();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }

  @override
  MemberHistoryController openHistory(MemberHistoryQuery query) =>
      MemberHistoryController._(this, query);

  @override
  Future<MemberHistoryPage> fetchHistoryPage(
    MemberHistoryQuery query, {
    Map<String, dynamic>? cursor,
  }) async {
    if (state.memberScopeUncertain) {
      throw StateError('Refresh your groups before loading history');
    }
    if (_allowLocalWrites && !isLive) return localHistoryPage(query);
    if (_memberAuthorityDenied ||
        state.currentProfile == null ||
        state.usingStaleCache ||
        !isLive) {
      throw StateError('Connect to load history');
    }
    final session = _captureSession();
    final read = await _offlineCache.beginAuthorityRead(
      session.identity!.userId,
    );
    var denied = false;
    try {
      if (!_acceptHistorySeedSession(session)) {
        throw StateError('Account changed');
      }
      final page = await _liveReader.fetchHistoryPage(
        query,
        cursor: cursor,
        accessToken: session.accessToken,
      );
      if (!_isCurrentSession(session)) throw StateError('Account changed');
      return page;
    } catch (error) {
      final failure = _historyFailure(error);
      denied =
          _historySignalCurrent(session) &&
          (failure.scopeChanged ||
              (_acceptHistorySeedSession(session) && failure.accessChanged));
      rethrow;
    } finally {
      await _offlineCache.finishAuthorityRead(read, denied: denied);
    }
  }

  MemberHistoryPage localHistoryPage(MemberHistoryQuery query) {
    final titles = {for (final c in state.collections) c.id: c.title};
    final needle = query.search.toLowerCase();
    final rows = state.contributions
        .where(
          (c) =>
              (query.collectionId == null ||
                  c.collectionId == query.collectionId) &&
              (needle.isEmpty ||
                  c.supporterLabel.toLowerCase().contains(needle) ||
                  (c.transactionId ?? '').toLowerCase().contains(needle) ||
                  (titles[c.collectionId] ?? '').toLowerCase().contains(
                    needle,
                  )),
        )
        .toList();
    rows.sort((a, b) {
      if (query.sort == 'highest' || query.sort == 'lowest') {
        final currency = a.currency.compareTo(b.currency);
        if (currency != 0) return currency;
        final amount = query.sort == 'highest'
            ? b.amountMinor.compareTo(a.amountMinor)
            : a.amountMinor.compareTo(b.amountMinor);
        if (amount != 0) return amount;
      }
      final date = query.sort == 'oldest'
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt);
      return date != 0 ? date : a.id.compareTo(b.id);
    });
    final totals = <String, int>{}, own = <String, int>{};
    final groups = <String>{};
    for (final row in rows) {
      totals.update(
        row.currency,
        (v) => v + row.amountMinor,
        ifAbsent: () => row.amountMinor,
      );
      if (row.isCurrentUserContribution ||
          (state.currentProfile != null &&
              _contributionBelongsToProfile(row, state.currentProfile!))) {
        own.update(
          row.currency,
          (v) => v + row.amountMinor,
          ifAbsent: () => row.amountMinor,
        );
        groups.add(row.collectionId);
      }
    }
    return MemberHistoryPage(
      items: rows,
      totalCount: rows.length,
      totals: totals,
      ownTotals: own,
      ownCollectionIds: groups,
      revision: '00000000000000000000000000000000',
    );
  }
}
