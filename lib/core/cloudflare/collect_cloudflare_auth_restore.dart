part of 'collect_cloudflare_client.dart';

final class _CollectInitializationOwner {
  _CollectInitializationOwner({
    required this.generation,
    required this.otpGeneration,
    required this.googleGeneration,
    required this.anonymousGeneration,
  });

  int generation;
  int otpGeneration, googleGeneration, anonymousGeneration;
  CollectAuthSession? session;
  bool refreshingGuest = false;
  Future<void>? failedPersistClear;
  int? retirementGeneration;
}

extension _CollectAuthRestore on CollectAuthClient {
  Future<void> _restoreSession() {
    if (_disposed) return Future.value();
    final running = _initializationInFlight;
    if (running != null) {
      final owner = _initializationOwner;
      return owner != null && _ownsInitialization(owner)
          ? running
          : Future.value();
    }
    if (_session != null ||
        _generation != 0 ||
        _otpGeneration != 0 ||
        _googleGeneration != 0 ||
        _anonymousGeneration != 0) {
      return Future.value();
    }
    final owner = _CollectInitializationOwner(
      generation: _generation,
      otpGeneration: _otpGeneration,
      googleGeneration: _googleGeneration,
      anonymousGeneration: _anonymousGeneration,
    );
    _initializationOwner = owner;
    late final Future<void> operation;
    operation = _initialize(owner).whenComplete(() {
      if (identical(_initializationInFlight, operation)) {
        _initializationInFlight = null;
        _initializationOwner = null;
      }
    });
    _initializationInFlight = operation;
    return operation;
  }

  bool _ownsInitialization(_CollectInitializationOwner owner) =>
      !_disposed &&
      identical(_initializationOwner, owner) &&
      identical(_session, owner.session) &&
      _generation == owner.generation &&
      (owner.refreshingGuest ||
          (_otpGeneration == owner.otpGeneration &&
              _googleGeneration == owner.googleGeneration &&
              _anonymousGeneration == owner.anonymousGeneration));

  void _requireGuestRestoreSettled() {
    final owner = _initializationOwner;
    if (owner != null && owner.refreshingGuest && _ownsInitialization(owner)) {
      throw const CollectAuthException(
        'Guest sign-in is still starting.',
        code: 'guest_initialization_pending',
        statusCode: '503',
      );
    }
  }

  bool _ownsInitializationCleanup(_CollectInitializationOwner owner) =>
      !_disposed &&
      identical(_initializationOwner, owner) &&
      owner.failedPersistClear != null &&
      owner.retirementGeneration == _generation &&
      _session == null &&
      _otpGeneration == owner.otpGeneration &&
      _googleGeneration == owner.googleGeneration &&
      _anonymousGeneration == owner.anonymousGeneration;

  void _recordInitializationCancellation({
    bool otp = false,
    bool google = false,
  }) {
    final owner = _initializationOwner;
    if (owner == null || _disposed || !identical(_initializationOwner, owner)) {
      return;
    }
    final activeGuest = owner.refreshingGuest && _ownsInitialization(owner);
    final retiring =
        owner.failedPersistClear != null &&
        owner.retirementGeneration == _generation &&
        _session == null;
    if (activeGuest || retiring) {
      if (otp) {
        owner.otpGeneration = _otpGeneration;
        owner.anonymousGeneration = _anonymousGeneration;
      }
      if (google) owner.googleGeneration = _googleGeneration;
    }
  }

  Future<void> _initialize(_CollectInitializationOwner owner) async {
    bool ownsRestore() => owner.session == null && _ownsInitialization(owner);

    // Existing writes and clears finish before this read. Do not add the read
    // itself to the write tail: a stuck read must not block disposal or a new
    // account's protected write.
    await _storageTail.catchError((Object _) {});
    if (!ownsRestore()) return;
    String? stored;
    try {
      stored = await _storage.read();
    } catch (_) {
      if (!ownsRestore()) return;
      rethrow;
    }
    if (!ownsRestore() || stored == null) return;
    CollectAuthSession? session;
    _CollectGuestUpgrade? restoredUpgrade;
    try {
      if (stored.length > 131072) throw const FormatException();
      final decoded = jsonDecode(stored);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      session = _decodeSession(
        decoded,
        allowRetainedGuest: decoded['guest_upgrade'] != null,
      );
      if (session == null || session.refreshToken == null) {
        throw const FormatException();
      }
      final pending = decoded['guest_upgrade'];
      if (pending != null) {
        if (!session.user.isAnonymous ||
            pending is! Map<String, dynamic> ||
            pending['auth_subject'] != session.authSubject ||
            pending['session_id'] != session.claims['session_id'] ||
            pending['unconfirmed'] is! bool ||
            pending['challenge_id'] is! String ||
            !RegExp(
              r'^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$',
            ).hasMatch(pending['challenge_id'] as String) ||
            (pending['channel'] != null &&
                !const {'sms', 'whatsapp'}.contains(pending['channel'])) ||
            (pending['recovery_refresh_token'] != null &&
                (pending['recovery_refresh_token'] is! String ||
                    (pending['recovery_refresh_token'] as String).isEmpty ||
                    (pending['recovery_refresh_token'] as String).length >
                        4096 ||
                    pending['unconfirmed'] != true))) {
          throw const FormatException();
        }
        final phone = pending['phone'] as String?,
            email = pending['email'] as String?;
        final key = _otpKey(phone, email);
        final channel = pending['channel'] == null
            ? null
            : CollectOtpChannel.values.byName(pending['channel'] as String);
        if ((phone == null) != (channel == null)) throw const FormatException();
        restoredUpgrade = _CollectGuestUpgrade(
          key: key,
          challengeId: pending['challenge_id'] as String,
          authSubject: session.authSubject,
          sessionId: pending['session_id'] as String,
          phone: phone,
          email: email,
          channel: channel,
          unconfirmed: pending['unconfirmed'] as bool,
          recoveryRefreshToken: pending['recovery_refresh_token'] as String?,
        );
      }
    } catch (_) {
      if (!ownsRestore()) return;
      // A clear already in progress must precede any later account write.
      // Recheck ownership after earlier queued storage operations complete.
      final clear = _storageTail.catchError((Object _) {}).then((_) async {
        if (ownsRestore()) await _storage.clear();
      });
      _storageTail = clear;
      try {
        await clear;
      } catch (_) {
        if (!ownsRestore()) return;
        rethrow;
      }
      return;
    }
    final restoredSession = session;
    if (!ownsRestore()) return;
    if (restoredSession.isExpired && restoredUpgrade?.unconfirmed != true) {
      // Keep an expired restore private until its refresh succeeds. While a
      // retained guest is refreshing, its upgrade must not become ordinary OTP.
      owner.refreshingGuest = restoredSession.user.isAnonymous;
      await _initializeExpired(owner, restoredSession, restoredUpgrade);
      return;
    }
    final installedGeneration = ++_generation;
    _session = restoredSession;
    owner.generation = installedGeneration;
    owner.session = restoredSession;
    _guestUpgrade = restoredUpgrade;
    if (restoredUpgrade != null) {
      _challenges[restoredUpgrade.key] = restoredUpgrade.challengeId;
      _challengeChannels[restoredUpgrade.key] = restoredUpgrade.channel;
    }
    if (restoredUpgrade?.unconfirmed == true) {
      // The original guest credential and challenge are recovery evidence.
      // Refreshing an identity that GoTrue may already have converted could
      // replace them before the application projection is acknowledged.
      _events.add(
        CollectAuthState(CollectAuthEvent.initialSession, restoredSession),
      );
      return;
    }
    _events.add(
      CollectAuthState(CollectAuthEvent.initialSession, restoredSession),
    );
    _scheduleRefresh();
  }

  Future<void> _initializeExpired(
    _CollectInitializationOwner owner,
    CollectAuthSession original,
    _CollectGuestUpgrade? restoredUpgrade,
  ) async {
    try {
      final data = await _transport.request('refresh', {
        'refresh_token': original.refreshToken,
      });
      if (!_ownsInitialization(owner) || owner.session != null) return;
      final next = _verifiedRefreshSession(data, original);
      _guestUpgrade = restoredUpgrade;
      if (restoredUpgrade != null) {
        _challenges[restoredUpgrade.key] = restoredUpgrade.challengeId;
        _challengeChannels[restoredUpgrade.key] = restoredUpgrade.channel;
      }
      _install(
        next,
        CollectAuthEvent.tokenRefreshed,
        onInstalled: () {
          owner.generation = _generation;
          owner.session = next;
          owner.otpGeneration = _otpGeneration;
          owner.googleGeneration = _googleGeneration;
          owner.anonymousGeneration = _anonymousGeneration;
        },
      );
      await _persist();
    } catch (_) {
      if (_ownsInitialization(owner)) {
        await clearLocalSession();
      } else if (_ownsInitializationCleanup(owner)) {
        // Await only the clear owned by this failed protected write. A later
        // account or sign-out must not inherit a stale cleanup failure.
        try {
          await owner.failedPersistClear!;
        } catch (_) {
          if (_ownsInitializationCleanup(owner)) rethrow;
        }
      }
    }
  }
}
