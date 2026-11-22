part of 'collect_cloudflare_client.dart';

final class _CollectGuestUpgrade {
  const _CollectGuestUpgrade({
    required this.key,
    required this.challengeId,
    required this.authSubject,
    required this.sessionId,
    this.phone,
    this.email,
    this.channel,
    this.unconfirmed = false,
    this.recoveryRefreshToken,
  });
  final String key, challengeId, authSubject, sessionId;
  final String? phone, email;
  final CollectOtpChannel? channel;
  final bool unconfirmed;
  final String? recoveryRefreshToken;
  _CollectGuestUpgrade uncertain() => _CollectGuestUpgrade(
    key: key,
    challengeId: challengeId,
    authSubject: authSubject,
    sessionId: sessionId,
    phone: phone,
    email: email,
    channel: channel,
    unconfirmed: true,
    recoveryRefreshToken: recoveryRefreshToken,
  );
  _CollectGuestUpgrade withRecoveryToken(String value) => _CollectGuestUpgrade(
    key: key,
    challengeId: challengeId,
    authSubject: authSubject,
    sessionId: sessionId,
    phone: phone,
    email: email,
    channel: channel,
    unconfirmed: true,
    recoveryRefreshToken: value,
  );
  Map<String, dynamic> toJson() => {
    'challenge_id': challengeId,
    'auth_subject': authSubject,
    'session_id': sessionId,
    'phone': phone,
    'email': email,
    'channel': channel?.name,
    'unconfirmed': unconfirmed,
    'recovery_refresh_token': ?recoveryRefreshToken,
  };
}

extension _CollectAuthGuest on CollectAuthClient {
  Future<CollectAuthResponse> _openGuest({String? captchaToken}) async {
    if (!anonymousSignInAvailable) {
      throw const CollectAuthException(
        'Guest access is unavailable.',
        code: 'anonymous_unavailable',
        statusCode: '503',
      );
    }
    _requireGuestRestoreSettled();
    if (_session != null) {
      throw const CollectAuthException(
        'An account is already open.',
        code: 'session_exists',
      );
    }
    final generation = _generation, attempt = ++_anonymousGeneration;
    cancelGoogleSignIn();
    ++_otpGeneration;
    _challenges.clear();
    _challengeChannels.clear();
    captchaToken = await _transport.captchaToken(captchaToken);
    void checkCurrent() {
      if (_disposed ||
          _generation != generation ||
          attempt != _anonymousGeneration ||
          _session != null) {
        throw const CollectAuthException(
          'Your sign-in changed.',
          code: 'session_changed',
        );
      }
    }

    checkCurrent();
    final data = await _transport.request('anonymous', {
      'surface': 'member',
      'captcha_token': ?captchaToken,
    });
    checkCurrent();
    final session = _verifiedSession(data);
    if (!session.user.isAnonymous) {
      throw const CollectAuthException(
        'Guest access could not be verified.',
        code: 'invalid_session',
      );
    }
    _install(session, CollectAuthEvent.signedIn);
    await _persist();
    if (_session?.accessToken != session.accessToken) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    return CollectAuthResponse(session: session);
  }

  Future<CollectAuthResponse> _checkGuestUpgrade() {
    final running = _guestReconcileInFlight;
    if (running != null) return running;
    final operation = _reconcileGuestUpgrade();
    _guestReconcileInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_guestReconcileInFlight, operation)) {
        _guestReconcileInFlight = null;
      }
    });
  }

  Future<CollectAuthResponse> _reconcileGuestUpgrade() async {
    final pending = _guestUpgrade,
        original = _session,
        generation = _generation,
        epoch = _otpGeneration;
    if (pending == null ||
        !pending.unconfirmed ||
        original?.user.isAnonymous != true ||
        original?.authSubject != pending.authSubject ||
        original?.claims['session_id'] != pending.sessionId ||
        original?.refreshToken == null) {
      throw const CollectAuthException(
        'No retained verification is available.',
        code: 'invalid_challenge',
      );
    }
    final data = await _transport.request('upgrade/reconcile', {
      'challenge_id': pending.challengeId,
      'refresh_token': pending.recoveryRefreshToken ?? original!.refreshToken,
    }, bearer: original!.accessToken);
    if (_disposed ||
        generation != _generation ||
        epoch != _otpGeneration ||
        !identical(_guestUpgrade, pending)) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    if (data['upgrade_status'] == 'unconfirmed') {
      final recoveryToken = data['recovery_refresh_token'];
      if (data.length != 5 ||
          data['challenge_id'] != pending.challengeId ||
          data['auth_user_id'] != pending.authSubject ||
          data['initiating_session_id'] != pending.sessionId ||
          recoveryToken is! String ||
          recoveryToken.isEmpty ||
          recoveryToken.length > 4096) {
        throw const CollectAuthException(
          'The retained verification could not be confirmed.',
          code: 'invalid_session',
        );
      }
      // This credential is recovery evidence only. It never changes the
      // current guest/user, activates business work, or permits a code replay.
      _guestUpgrade = pending.withRecoveryToken(recoveryToken);
      await _persist();
      throw const CollectAuthException(
        'The verification is still unconfirmed. Check this request again.',
        code: 'guest_upgrade_unknown',
        statusCode: '503',
      );
    }
    final session = _verifiedSession(data);
    if (session.user.isAnonymous ||
        session.authSubject != pending.authSubject) {
      throw const CollectAuthException(
        'The verified account changed.',
        code: 'verified_identity_mismatch',
      );
    }
    _guestUpgrade = null;
    _guestReconcileInFlight = null;
    _challenges.clear();
    _challengeChannels.clear();
    _install(session, CollectAuthEvent.signedIn);
    await _persist();
    if (_session?.accessToken != session.accessToken) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    return CollectAuthResponse(session: session);
  }
}
