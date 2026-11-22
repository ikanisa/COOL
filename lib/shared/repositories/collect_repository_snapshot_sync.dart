part of 'collect_repository.dart';

mixin _CollectRepositorySnapshotSync
    on
        StateNotifier<CollectState>,
        _CollectMemberHistory,
        _CollectNotificationActions,
        _CollectRecordReads,
        _CollectRepositoryDiscovery,
        _CollectRepositoryOfflineSnapshot
    implements MemberAccountRepository {
  SmsAccessChannel get _smsAccessChannel;
  set _authGeneration(int value);

  @override
  int _loadGeneration = 0;
  @override
  bool _memberAuthorityDenied = false;
  CollectSyncInvalidationSubscription? _realtimeSync;
  String? _realtimeOwnerId;

  @override
  Future<void> loadInitial() => _loadMemberSnapshot(readNotifications: true);

  Future<void> refreshContributionScope() =>
      _loadMemberSnapshot(readNotifications: false);

  Future<void> _loadMemberSnapshot({required bool readNotifications}) async {
    final generation = ++_loadGeneration;
    final preferencesSession = _captureSession();
    final preferencesGeneration = _notificationPreferencesGeneration;
    final backend = _backend;
    final user = backend?.auth.currentUser;
    if (backend == null) return;
    bool readStillCurrent() =>
        _acceptLoad(generation, user?.id) &&
        _isCurrentSession(preferencesSession);
    await _syncNativeSmsOwner(user?.id, isCurrent: readStillCurrent);
    if (!readStillCurrent()) return;
    if (_realtimeOwnerId != null && _realtimeOwnerId != user?.id) {
      _stopRealtimeSync();
    }
    if (state.currentProfile != null && state.currentProfile!.id != user?.id) {
      state = _emptyCollectState();
    }

    if (user == null) return _loadPublicSnapshot(isCurrent: readStillCurrent);

    state = state.copyWith(isLoading: true);
    int? preferencesReadAttempt;
    var historyReadInFlight = false;
    MemberCacheAuthorityRead? cacheRead;
    try {
      try {
        cacheRead = await _offlineCache.beginAuthorityRead(user.id);
      } catch (_) {
        if (readStillCurrent()) {
          state = state.copyWith(
            isLoading: false,
            lastError:
                'Member cache protection is unavailable. Reconnect and refresh.',
          );
        }
        return;
      }
      if (!readStillCurrent()) return;
      final profile = await _liveReader.fetchProfile(
        user.id,
        accessToken: preferencesSession.accessToken,
      );
      if (!readStillCurrent()) return;
      final memberCollections = await _liveReader.fetchCollections(
        accessToken: preferencesSession.accessToken,
      );
      if (!readStillCurrent()) return;
      final memberCollectionIds = memberCollections
          .map((item) => item.id)
          .toSet();
      if (memberCollectionIds.length != memberCollections.length ||
          memberCollections.any((item) => !item.isCurrentUserMember)) {
        throw const _CollectAccessMismatch();
      }
      final intentReadRevision = _nextIntentRead();
      final intents = await _liveReader.fetchRecentIntents(
        accessToken: preferencesSession.accessToken,
      );
      if (!readStillCurrent()) return;
      historyReadInFlight = true;
      final history = await _liveReader.fetchHistoryPage(
        const MemberHistoryQuery(),
        accessToken: preferencesSession.accessToken,
      );
      historyReadInFlight = false;
      if (!readStillCurrent()) return;
      final collectionSummaries = await _liveReader.fetchCollectionSummaries(
        accessToken: preferencesSession.accessToken,
      );
      if (!readStillCurrent()) return;
      if (collectionSummaries.keys.any(
        (id) => !memberCollectionIds.contains(id),
      )) {
        throw const _CollectAccessMismatch();
      }
      var notificationEvents = state.notificationEvents;
      NotificationPreferenceRead? notificationPreferences;
      var acceptPreferences = false;
      if (readNotifications) {
        final preferencesRead = ++_notificationPreferencesReadGeneration;
        preferencesReadAttempt = preferencesRead;
        try {
          notificationPreferences = await _liveReader
              .fetchNotificationPreferences(
                profile,
                accessToken: preferencesSession.accessToken,
              );
          if (!readStillCurrent()) return;
          notificationEvents = await _liveReader.fetchNotificationEvents(
            profile,
            accessToken: preferencesSession.accessToken,
          );
          if (!readStillCurrent()) return;
          acceptPreferences =
              !_notificationPreferencesNeedsRefresh &&
              _acceptNotificationPreferencesRead(
                preferencesSession,
                preferencesGeneration,
                preferencesRead,
              );
        } catch (error) {
          final status = error is CollectApiException
              ? error.httpStatusCode ?? 0
              : 0;
          final unavailable =
              error is TimeoutException ||
              (status == 429 || (status >= 500 && status < 600));
          if (!unavailable || _isAccessFailure(error)) rethrow;
          if (!readStillCurrent()) return;
          // A transient notification failure cannot invalidate verified
          // member data or authorize a save from an unverified revision.
          notificationEvents = state.notificationEvents;
          if (_acceptNotificationPreferencesRead(
            preferencesSession,
            preferencesGeneration,
            preferencesRead,
          )) {
            _notificationPreferencesRevision = null;
            _notificationPreferencesNeedsRefresh = true;
          }
        }
        if (acceptPreferences) {
          _notificationPreferencesRevision = notificationPreferences?.revision;
        }
      }
      final priorMemberCollectionIds = state.collections
          .where(
            (item) => item.isCurrentUserMember || item.creatorUserId == user.id,
          )
          .map((item) => item.id)
          .toSet();
      final accessReduced = priorMemberCollectionIds.any(
        (id) => !memberCollectionIds.contains(id),
      );
      if (state.memberScopeUncertain && profile == null) {
        state = state.copyWith(
          isLoading: false,
          lastError: 'Refresh to verify your groups and activity.',
        );
        return;
      }
      final historyCacheRecovery = _historyCacheReadSuppressed;
      _historySeedInvalidatedAtSession = null;
      state = state.copyWith(
        currentProfile: profile,
        collections: memberCollections,
        paymentIntents: _acceptRecentIntentWindow(
          intentReadRevision,
          intents.items,
        ),
        pendingIntentCount: _acceptPendingIntentCount(
          intentReadRevision,
          intents.pendingCount,
        ),
        contributions: history.items,
        historyPage: history,
        collectionSummaries: collectionSummaries,
        notificationEvents: notificationEvents,
        notificationPreferences: acceptPreferences
            ? notificationPreferences?.preferences ??
                  NotificationPreferences.defaults
            : state.notificationPreferences,
        isLoading: false,
        usingStaleCache: false,
        publicDiscoveryLoading: true,
        publicDiscoveryUnavailable: false,
        lastSuccessfulSyncAt: DateTime.now().toUtc(),
        financialObservationUncertain: false,
        memberScopeUncertain: false,
      );
      if (!readStillCurrent()) return;
      try {
        final deniedCache = cacheRead.requiresRevalidation;
        if (!readStillCurrent()) return;
        if (deniedCache ||
            historyCacheRecovery ||
            accessReduced ||
            profile == null ||
            _offlineRestoreSuspended) {
          if (deniedCache && profile != null) {
            await _offlineCache.clearForConfirmedOwner(
              user.id,
              readStillCurrent,
              confirmed: cacheRead,
            );
          } else {
            await _offlineCache.clear();
          }
          if (!readStillCurrent()) return;
          _offlineRestoreSuspended = false;
          _historyCacheReadSuppressed = false;
        }
      } catch (_) {
        if (!readStillCurrent()) return;
        _offlineRestoreSuspended = true;
      }
      if (profile != null) _memberAuthorityDenied = false;
      if (profile != null &&
          !_offlineRestoreSuspended &&
          !_historyCacheReadSuppressed) {
        unawaited(_saveOfflineSnapshot().catchError((Object _) {}));
      }
      _ensureRealtimeSync();
      // Public discovery must not delay a valid member financial refresh. Its
      // result is independently fenced to this exact load and session.
      unawaited(_refreshPublicDiscovery(user.id, isCurrent: readStillCurrent));
    } catch (error) {
      if (historyReadInFlight) {
        final (:changed, :accessChanged, :scopeChanged) = _historyFailure(
          error,
        );
        if (changed || accessChanged) {
          if (!scopeChanged &&
              _isCurrentSession(preferencesSession) &&
              backend.auth.currentSession?.accessToken !=
                  preferencesSession.accessToken) {
            // A refusal for an older bearer cannot revoke the newer one.
            if (readStillCurrent()) {
              state = state.copyWith(
                isLoading: false,
                financialObservationUncertain: true,
                lastError: 'Refresh to verify your groups and activity.',
              );
            }
          } else if (scopeChanged
              ? _historySignalCurrent(preferencesSession)
              : _acceptHistorySeedSession(preferencesSession)) {
            cacheRead?.retainAfterDenial();
            _invalidateHistorySeed(
              preferencesSession,
              surviveBearerChange: scopeChanged,
            );
            await _cacheDenialPersisted;
          }
          return;
        }
      }
      if (!readStillCurrent()) {
        // A superseded read can still carry a real denial for this exact
        // bearer. Do not let a newer but stalled refresh expose old authority.
        // A replacement bearer or an active sign-out has its own lifecycle and
        // must not be disturbed by this earlier response.
        if (preferencesSession.identity != null &&
            preferencesSession.accessToken != null &&
            _signingOutIdentity != preferencesSession.identity &&
            _isCurrentSession(preferencesSession) &&
            _isAccessFailure(error)) {
          if (backend.auth.currentSession?.accessToken ==
              preferencesSession.accessToken) {
            cacheRead?.retainAfterDenial();
          }
          try {
            await _memberSyncAuthorityDenied(
              preferencesSession,
              preferencesSession.accessToken!,
            );
          } catch (_) {
            // The helper has already latched the in-memory denial. A failed
            // follow-up read does not restore authority.
          }
        }
        return;
      }
      if (!_isAccessFailure(error) &&
          (preferencesGeneration != _notificationPreferencesGeneration ||
              (preferencesReadAttempt != null &&
                  preferencesReadAttempt !=
                      _notificationPreferencesReadGeneration))) {
        // This generation race preserves the newer preference operation. The
        // freshly fetched financial data was not installed, even when failure
        // happened during preferences. Deny until a complete load succeeds.
        state = state.copyWith(
          isLoading: false,
          financialObservationUncertain: true,
        );
        return;
      }
      _notificationPreferencesRevision = null;
      _notificationPreferencesNeedsRefresh = true;
      if (_isAccessFailure(error)) {
        cacheRead?.retainAfterDenial();
        _stopRealtimeSync();
        state = _emptyCollectState().copyWith(
          lastError:
              'Member access could not be verified. Reconnect and refresh.',
        );
        _offlineRestoreSuspended = true;
        await _holdDeniedCache(preferencesSession);
        if (!readStillCurrent()) return;
        try {
          await _offlineCache.clear();
        } catch (_) {
          // Retain the in-memory deny even when protected storage is locked.
        }
        return;
      }
      final restored = await restoreOfflineSnapshot(reason: error.toString());
      if (!readStillCurrent()) return;
      if (!restored) {
        state = state.copyWith(
          isLoading: false,
          usingStaleCache: state.hasOfflineReadableData,
          lastError: error.toString(),
        );
      }
    } finally {
      if (cacheRead != null) {
        await _offlineCache.finishAuthorityRead(cacheRead);
      }
    }
  }

  Future<void> _syncNativeSmsOwner(
    String? userId, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return;
    final ownerSynced = await _smsAccessChannel.suspendUnlessOwner(userId);
    if (!isCurrent() || ownerSynced) return;
    final status = await _smsAccessChannel.status();
    if (isCurrent() &&
        (status.consentEnabled ||
            (SmsAccessChannel.requiresNativeBridge &&
                !status.bridgeAvailable))) {
      state = state.copyWith(smsSyncNeedsAttention: true);
    }
  }

  bool _acceptLoad(int generation, String? userId) =>
      mounted &&
      generation == _loadGeneration &&
      _backend?.auth.currentUser?.id == userId;

  @override
  bool _isAccessFailure(Object error) =>
      error is _CollectAccessMismatch ||
      (error is CollectApiException &&
          (error.httpStatusCode == 401 ||
              error.httpStatusCode == 403 ||
              const {
                '42501',
                '401',
                '403',
                'authentication_required',
                'invalid_token',
                'access_revoked',
                'unauthenticated',
                'session_changed',
                'fresh_auth_required',
                'mfa_required',
                'admin_required',
                'permission_denied',
                'origin_denied',
              }.contains(error.code))) ||
      (error is CollectAuthException &&
          (const {'401', '403'}.contains(error.statusCode) ||
              const {
                'invalid_session',
                'session_required',
                'session_changed',
                'invalid_token',
                'invalid_identity',
                'access_revoked',
                'authentication_required',
                'unauthenticated',
                'refresh_replay',
              }.contains(error.code)));

  void _ensureRealtimeSync() {
    final backend = _backend;
    final userId = backend?.auth.currentUser?.id;
    if (backend == null || userId == null) return;
    if (_realtimeSync != null && _realtimeOwnerId == userId) return;
    _stopRealtimeSync();
    _realtimeOwnerId = userId;
    final session = _captureSession();
    _realtimeSync = CollectSyncInvalidationSubscription(
      client: backend,
      // The locked SDK matches channel messages by topic. A departed join's
      // frame must not be routed into a replacement Auth scope's callback.
      topic: 'collect:mobile:invalidation:${const Uuid().v4()}',
      areas: collectMobileRealtimeAreas,
      ownerUserId: userId,
      beginAuthorityRead: () async {
        final read = await _offlineCache.beginAuthorityRead(userId);
        return (bool denied) =>
            _offlineCache.finishAuthorityRead(read, denied: denied);
      },
      onAuthorityDenied: (bearer) =>
          _memberSyncAuthorityDenied(session, bearer),
      onInvalidate: () async {
        if (_isCurrentSession(session) &&
            backend.auth.currentUser?.id == userId) {
          await loadInitial();
        }
      },
    )..start();
  }

  Future<void> _memberSyncAuthorityDenied(
    _CollectSessionFence captured,
    String deniedBearer,
  ) async {
    if (!_isCurrentSession(captured) ||
        _backend?.auth.currentSession?.accessToken != deniedBearer) {
      return;
    }
    // Advance the existing session revision used by history/roster/providers,
    // not merely the load counter. This fences same-account and A→B→A replies.
    ++_authGeneration;
    ++_loadGeneration;
    _memberAuthorityDenied = true;
    _offlineRestoreSuspended = true;
    _stopRealtimeSync();
    final current = _captureSession();
    state = _emptyCollectState().copyWith(
      lastError: 'Member access could not be verified. Reconnect and refresh.',
    );
    // clear() advances its write epoch synchronously. Enqueue it only while the
    // captured bearer/scope is current; the store itself serializes older saves.
    if (!_isCurrentSession(current) ||
        _backend?.auth.currentSession?.accessToken != deniedBearer) {
      return;
    }
    await _holdDeniedCache(current);
    if (!_isCurrentSession(current)) return;
    final clearing = _offlineCache.clear();
    try {
      await clearing;
    } catch (_) {
      /* Keep the in-memory denial latched. */
    }
    if (!_isCurrentSession(current)) return;
    await loadInitial();
  }

  void _stopRealtimeSync() {
    final subscription = _realtimeSync;
    _realtimeSync = null;
    _realtimeOwnerId = null;
    if (subscription != null) unawaited(subscription.dispose());
  }
}
