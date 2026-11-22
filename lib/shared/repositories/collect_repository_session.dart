part of 'collect_repository.dart';

// JWT claims here distinguish local lifecycle operations only; server Auth/RLS
// remains authoritative. Access-token fallback keeps malformed/legacy sessions
// isolated; such tokens do not bypass the server's required session_id check.
typedef _CollectAuthIdentity = ({String userId, String sessionId});
typedef _CollectSessionFence = ({
  _CollectAuthIdentity? identity,
  String? accessToken,
  int generation,
});
_CollectAuthIdentity? _sessionIdentity(CollectAuthSession? session) {
  if (session == null || session.user.isAnonymous) return null;
  var identity = session.accessToken;
  try {
    final parts = session.accessToken.split('.');
    if (parts.length == 3) {
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (claims is Map &&
          claims['session_id'] is String &&
          (claims['session_id'] as String).isNotEmpty) {
        identity = claims['session_id'] as String;
      }
    }
  } catch (_) {
    // Do not expose token contents in exceptions or diagnostics.
  }
  return (userId: session.user.id, sessionId: identity);
}

mixin _CollectRepositorySession
    on
        StateNotifier<CollectState>,
        _CollectRepositorySnapshotSync,
        _CollectMemberHistory,
        _CollectNotificationActions,
        _CollectReceiptSmsActions
    implements MemberAccountRepository {
  PaymentHelpPendingStore get _paymentHelpPendingStore;
  void Function()? get _onSignOutStarted;

  StreamSubscription<CollectAuthState>? _authSubscription;
  _CollectAuthIdentity? _observedAuthIdentity;
  int _profileSaveAuthorityGeneration = 0;
  @override
  _CollectAuthIdentity? _signingOutIdentity;
  @override
  int _authGeneration = 0;
  @override
  int _signOutGeneration = 0;

  @override
  bool get isLive => _backend?.auth.currentUser != null;

  /// A credential-free sticky lifecycle revision for dependent client views.
  @override
  int get sessionGeneration => _authGeneration;

  void _observeAuthSession() {
    _observedAuthIdentity = _sessionIdentity(_backend?.auth.currentSession);
    _paymentHelpPendingStore.bindOwner(_observedAuthIdentity?.userId);
    final backend = _backend;
    _authSubscription = backend?.auth.onAuthStateChange.listen((event) {
      final identity = _sessionIdentity(backend.auth.currentSession);
      if (!mounted) return;
      if (identity == _observedAuthIdentity) {
        // A fresh sign-in is a profile-save boundary even when the same
        // session is reinstalled. Ordinary token refresh is not.
        if (event.event == CollectAuthEvent.signedIn) {
          ++_profileSaveAuthorityGeneration;
        }
        return;
      }
      final sameOwner =
          identity != null && identity.userId == _observedAuthIdentity?.userId;
      if (!sameOwner) _paymentHelpPendingStore.bindOwner(identity?.userId);
      _observedAuthIdentity = identity;
      final generation = ++_authGeneration;
      _resetNotificationAuthority();
      _resetReceiptSmsConsent();
      _signingOutIdentity = null;
      ++_loadGeneration;
      _memberAuthorityDenied = false;
      _stopRealtimeSync();
      // Clear all financial data immediately. Same-owner session renewal is
      // already a pending reread, including the native/cache awaits below.
      state = _emptyCollectState().copyWith(isLoading: sameOwner);
      unawaited(_reloadAfterAccountChange(identity, generation));
    });
  }

  void _stopObservingAuthSession() => unawaited(_authSubscription?.cancel());

  Future<void> _reloadAfterAccountChange(
    _CollectAuthIdentity? identity,
    int generation,
  ) async {
    bool current() =>
        mounted &&
        generation == _authGeneration &&
        identity == _sessionIdentity(_backend?.auth.currentSession);
    final userId = identity?.userId;
    await _syncNativeSmsOwner(userId, isCurrent: current);
    if (!current()) return;
    try {
      await _offlineCache.clear();
      if (current()) _offlineRestoreSuspended = false;
    } catch (_) {
      if (current()) _offlineRestoreSuspended = true;
    }
    if (current() && userId != null) {
      await loadInitial();
    }
  }

  @override
  _CollectSessionFence _captureSession() {
    final session = _backend?.auth.currentSession;
    return (
      identity: _sessionIdentity(session),
      accessToken: session?.accessToken,
      generation: _authGeneration,
    );
  }

  @override
  bool _isCurrentSession(_CollectSessionFence session) =>
      mounted &&
      session.generation == _authGeneration &&
      session.identity == _sessionIdentity(_backend?.auth.currentSession);

  @override
  void _requireCurrentMemberSession(
    _CollectSessionFence session,
    String profileId,
  ) {
    if (!_isCurrentSession(session) ||
        session.identity?.userId != profileId ||
        session.accessToken == null ||
        _signingOutIdentity == session.identity ||
        state.currentProfile?.id != profileId) {
      throw StateError('Account changed. Refresh before continuing.');
    }
  }

  Future<void> _revokeCapturedSession(_CollectSessionFence session) async {
    final backend = _backend;
    final accessToken = session.accessToken;
    if (backend == null || accessToken == null) return;
    try {
      // Revoke only this captured server session; do not mutate a new account.
      await backend.auth.revokeCapturedSession(accessToken);
    } on CollectAuthException catch (error) {
      if (!const {'401', '403', '404'}.contains(error.statusCode)) rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    // Fence privacy verification before native capture, caches or HTTP can
    // await. A completed SDK sign-out event cannot announce this earlier intent.
    _onSignOutStarted?.call();
    final session = _captureSession();
    final operation = ++_signOutGeneration;
    ++_notificationRegistrationGeneration;
    _signingOutIdentity = session.identity;
    _resetReceiptSmsConsent(notify: true);
    final registration = _registeredNotification;
    _registeredNotification = null;
    final profile = state.currentProfile;
    final owner = session.identity?.userId ?? profile?.id;
    _paymentHelpPendingStore.bindOwner(null);
    final backend = _backend;
    bool current() =>
        operation == _signOutGeneration && _isCurrentSession(session);
    ++_loadGeneration;
    _stopRealtimeSync();
    try {
      try {
        _invalidateHistoryForSignOut(session, operation);
      } catch (_) {
        // StateNotifier reports listener errors. Continue native and Auth cleanup.
      }
      if (!current()) return await _revokeCapturedSession(session);
      // Native disable is bound to the original owner; never suspend whichever
      // account happens to be active after an RPC or platform await completes.
      final stopped = owner == null
          ? await _smsAccessChannel.suspendUnlessOwner(null)
          : await _smsAccessChannel.setEnabled(false, ownerUserId: owner);
      if (!current()) return await _revokeCapturedSession(session);
      if (!stopped) {
        final nativeStatus = await _smsAccessChannel.status();
        if (!current()) return await _revokeCapturedSession(session);
        if ((SmsAccessChannel.requiresNativeBridge &&
                !nativeStatus.bridgeAvailable) ||
            nativeStatus.consentEnabled) {
          throw StateError('SMS capture could not be stopped before sign-out.');
        }
      }
      if (backend != null && session.accessToken != null) {
        if (registration != null && registration.identity == session.identity) {
          try {
            await backend
                .rpc<void>(
                  'unregister_notification_device',
                  params: {
                    'p_provider': registration.provider,
                    'p_token': registration.token,
                  },
                )
                .setHeader('Authorization', 'Bearer ${session.accessToken}');
          } catch (_) {
            // Session-bound Auth revocation is still required below. Migration
            // 141 revokes its devices, including a registration completing late.
          }
        }
        if (!current()) return await _revokeCapturedSession(session);
        if (profile != null && profile.id == owner) {
          try {
            await backend
                .rpc<void>(
                  'record_sms_access_consent',
                  params: {
                    'enabled': false,
                    'momo_number_hash': profile.momoNumber.trim().isEmpty
                        ? null
                        : HashUtils.phoneHash(profile.momoNumber),
                    'build_channel': 'android_sms_access',
                    'device_label': 'flutter_app',
                  },
                )
                .setHeader('Authorization', 'Bearer ${session.accessToken}');
          } catch (_) {
            // Offline audit failure does not re-enable native capture. Never
            // retry through a newly active account or mutate its UI state.
          }
        }
      }
      if (!current()) return await _revokeCapturedSession(session);
      // CollectOfflineCache serializes this clear ahead of all later saves.
      // A newer session's reload waits for those cache operations before saving.
      try {
        await _paymentHelpPendingStore.ensureCleanup();
        if (!current()) return await _revokeCapturedSession(session);
        await _offlineCache.clear();
      } catch (_) {
        if (!current()) return await _revokeCapturedSession(session);
        _offlineRestoreSuspended = true;
        throw StateError('Local account data could not be cleared. Try again.');
      }
      if (!current()) return await _revokeCapturedSession(session);
      if (backend != null && session.identity != null) {
        // Collect clears its current session synchronously before its first
        // await and revokes only this captured server session.
        // Check immediately before invoking; do no account cleanup afterward.
        final logout = backend.auth.signOut(scope: CollectSignOutScope.local);
        if (mounted && backend.auth.currentSession == null) {
          state = _emptyCollectState();
        }
        await logout;
      } else {
        state = _emptyCollectState();
      }
    } finally {
      if (operation == _signOutGeneration &&
          _signingOutIdentity == session.identity) {
        _signingOutIdentity = null;
      }
    }
  }
}
