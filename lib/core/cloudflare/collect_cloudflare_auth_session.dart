part of 'collect_cloudflare_client.dart';

extension _CollectAuthSession on CollectAuthClient {
  Future<CollectAuthResponse> _refreshCurrentSession() =>
      _refreshInFlight ??= _refresh().whenComplete(() {
        _refreshInFlight = null;
      });
  Future<CollectAuthResponse> _refresh() async {
    final original = _session;
    final generation = _generation;
    if (original?.user.isAnonymous == true &&
        _guestUpgrade?.unconfirmed == true) {
      throw const CollectAuthException(
        'Check the retained account verification before refreshing.',
        code: 'guest_upgrade_unknown',
        statusCode: '503',
      );
    }
    if (original?.refreshToken == null || _disposed) {
      throw const CollectAuthException(
        'Sign in again.',
        code: 'session_required',
      );
    }
    final data = await _transport.request('refresh', {
      'refresh_token': original!.refreshToken,
    });
    if (_disposed ||
        generation != _generation ||
        _session?.accessToken != original.accessToken) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    final next = _verifiedRefreshSession(data, original);
    _install(next, CollectAuthEvent.tokenRefreshed);
    await _persist();
    return CollectAuthResponse(session: next);
  }

  CollectAuthSession _verifiedRefreshSession(
    Map<String, dynamic> data,
    CollectAuthSession original,
  ) {
    final next = _verifiedSession(
      data,
      allowRetainedGuest: original.user.isAnonymous,
    );
    if (next.user.id != original.user.id ||
        next.authSubject != original.authSubject ||
        next.user.isAnonymous != original.user.isAnonymous ||
        next.claims['session_id'] != original.claims['session_id']) {
      throw const CollectAuthException(
        'Sign in again.',
        code: 'invalid_session',
      );
    }
    return next;
  }

  CollectAuthSession _verifiedSession(
    Map<String, dynamic> data, {
    bool allowRetainedGuest = false,
  }) {
    final session = _decodeSession(
      data,
      allowRetainedGuest: allowRetainedGuest,
    );
    if (session == null || session.isExpired || session.refreshToken == null) {
      throw const CollectAuthException(
        'Verification is unavailable.',
        code: 'invalid_session',
      );
    }
    return session;
  }

  CollectAuthSession? _decodeSession(
    Map<String, dynamic> data, {
    bool allowRetainedGuest = false,
  }) => CollectAuthSession.fromJson(
    data,
    allowMappedAuthUser: _client.supabaseConfiguration != null,
    allowAnonymous:
        anonymousSignInAvailable ||
        allowRetainedGuest &&
            surface == 'member' &&
            _client.supabaseConfiguration != null,
    expectedIssuer: _client.supabaseConfiguration?.authIssuer,
  );

  /// Installs a previously verified response synchronously after its caller's
  /// account fence. It never fetches, refreshes or trusts a browser broadcast.
  Future<CollectAuthResponse> _installRecoveredSession(
    String encoded, {
    CollectAuthEvent event = CollectAuthEvent.signedIn,
    void Function()? onInstalled,
  }) {
    if (_disposed || encoded.length > 131072) {
      throw const CollectAuthException(
        'Verification is unavailable.',
        code: 'invalid_session',
      );
    }
    final data = jsonDecode(encoded);
    if (data is! Map<String, dynamic>) {
      throw const CollectAuthException(
        'Verification is unavailable.',
        code: 'invalid_session',
      );
    }
    final session = _verifiedSession(data);
    _install(session, event, onInstalled: onInstalled);
    return _persist().then((_) => CollectAuthResponse(session: session));
  }

  void _install(
    CollectAuthSession session,
    CollectAuthEvent event, {
    void Function()? onInstalled,
  }) {
    if (_disposed) throw StateError('Collect Auth is disposed');
    ++_generation;
    _session = session;
    // Record ownership before synchronous observers can cancel their view.
    onInstalled?.call();
    _events.add(CollectAuthState(event, session));
    _scheduleRefresh();
  }

  Future<void> _persist() {
    final session = _session;
    final generation = _generation;
    final pending = _guestUpgrade;
    final operation = _storageTail.catchError((Object _) {}).then((_) async {
      if (_disposed || generation != _generation || session == null) return;
      await _storage.write(
        jsonEncode({
          ...session.toJson(),
          if (session.user.isAnonymous && pending != null)
            'guest_upgrade': pending.toJson(),
        }),
      );
    });
    _storageTail = operation;
    return operation.catchError((Object _) {
      if (generation == _generation && !_disposed) {
        final initialization = _initializationOwner;
        final ownsInitialization =
            initialization != null &&
            _ownsInitialization(initialization) &&
            identical(initialization.session, session);
        final clear = _storageTail
            .catchError((Object _) {})
            .then((_) => _storage.clear());
        _storageTail = clear;
        if (ownsInitialization) {
          initialization.failedPersistClear = clear;
          initialization.retirementGeneration = _generation + 1;
          initialization.otpGeneration = _otpGeneration + 1;
          initialization.googleGeneration = _googleGeneration;
          initialization.anonymousGeneration = _anonymousGeneration + 1;
        }
        // Reserve clear ordering before synchronous sign-out observers run, so
        // a later account write cannot be erased by this failed installation.
        _clearLocal();
        unawaited(clear.catchError((Object _) {}));
      }
      throw const CollectAuthException(
        'Protected sign-in storage is unavailable.',
        code: 'protected_storage_unavailable',
      );
    });
  }

  Future<void> _revokeSession(String accessToken) async {
    await _transport.request('logout', const {}, bearer: accessToken);
  }

  Future<void> _clearSession() {
    _client.cancelPendingRequests();
    _clearLocal();
    final clear = _storageTail
        .catchError((Object _) {})
        .then((_) => _storage.clear());
    _storageTail = clear;
    return clear;
  }

  Future<void> _signOut({
    CollectSignOutScope scope = CollectSignOutScope.local,
  }) async {
    final original = _session;
    if (scope != CollectSignOutScope.local) {
      throw const CollectAuthException(
        'Use the device revocation workflow.',
        code: 'global_revocation_unavailable',
      );
    }
    final clear = clearLocalSession();
    Object? failure;
    if (original != null) {
      try {
        await _transport.request('logout', {
          'refresh_token': original.refreshToken,
        }, bearer: original.accessToken);
      } catch (error) {
        failure = error;
      }
    }
    await clear;
    if (failure != null) throw failure;
  }

  void _clearLocal() {
    _client.cancelCaptcha?.call();
    ++_generation;
    ++_otpGeneration;
    ++_anonymousGeneration;
    _session = null;
    _guestUpgrade = null;
    _guestReconcileInFlight = null;
    _challenges.clear();
    _challengeChannels.clear();
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (!_disposed) {
      _events.add(const CollectAuthState(CollectAuthEvent.signedOut, null));
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    final session = _session;
    if (session?.user.isAnonymous == true &&
        _guestUpgrade?.unconfirmed == true) {
      return;
    }
    final expiration = session?.claims['exp'];
    if (_disposed || session?.refreshToken == null || expiration is! int) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final seconds = (expiration - now - 60).clamp(1, 86400);
    _refreshTimer = Timer(Duration(seconds: seconds), () async {
      try {
        await refreshSession();
      } catch (error) {
        if (_disposed || _session?.accessToken != session!.accessToken) return;
        if (session.isExpired ||
            (error is CollectAuthException &&
                const {'401', '403'}.contains(error.statusCode))) {
          try {
            await clearLocalSession();
          } catch (_) {}
        } else {
          _refreshTimer = Timer(const Duration(seconds: 15), _scheduleRefresh);
        }
      }
    });
  }
}
