part of 'collect_cloudflare_client.dart';

extension _CollectAuthOtp on CollectAuthClient {
  Future<CollectOtpRequestReceipt> _startOtp({
    String? phone,
    String? email,
    CollectOtpChannel? channel,
    bool shouldCreateUser = true,
    String? captchaToken,
  }) async {
    _requireGuestRestoreSettled();
    final key = _otpKey(phone, email);
    final guestSession = currentGuest == null ? null : _session;
    if (guestSession != null && _guestUpgrade?.unconfirmed == true) {
      throw const CollectAuthException(
        'Check the existing verification before requesting another code.',
        code: 'guest_upgrade_unknown',
        statusCode: '503',
      );
    }
    if (email != null && channel != null) {
      throw const CollectAuthException(
        'Invalid sign-in channel.',
        code: 'invalid_channel',
      );
    }
    final epoch = ++_otpGeneration;
    final generation = _generation;
    _challenges.remove(key);
    _challengeChannels.remove(key);
    captchaToken = await _transport.captchaToken(captchaToken);
    if (_disposed || epoch != _otpGeneration || generation != _generation) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    Map<String, dynamic> data;
    var deliveryUnconfirmed = false;
    try {
      data = await _transport.request(
        guestSession == null ? 'otp' : 'upgrade/otp',
        {
          'phone': ?phone,
          'email': ?email,
          'surface': surface,
          'captcha_token': ?captchaToken,
          if (_client.supabaseConfiguration != null && guestSession == null)
            'should_create_user': shouldCreateUser,
          if (_client.supabaseConfiguration != null && channel != null)
            'channel': channel.name,
        },
        bearer: guestSession?.accessToken,
      );
    } on _CollectOtpUnconfirmedReply catch (reply) {
      data = reply.payload;
      deliveryUnconfirmed = true;
    }
    if (_disposed || epoch != _otpGeneration || generation != _generation) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    final id = data['challenge_id'];
    if (id is! String || id.isEmpty || id.length > 200) {
      throw const CollectAuthException(
        'Verification is unavailable.',
        code: 'invalid_challenge',
      );
    }
    final retryAfterSeconds = data['retry_after'] ?? 60;
    if (retryAfterSeconds is! int ||
        retryAfterSeconds < 60 ||
        retryAfterSeconds > 3600) {
      throw const CollectAuthException(
        'Verification is unavailable.',
        code: 'invalid_response',
      );
    }
    if (_client.supabaseConfiguration != null &&
        data.containsKey('delivery_status')) {
      final delivery = data['delivery_status'];
      if (delivery != 'accepted' && delivery != 'unknown') {
        throw const CollectAuthException(
          'Verification is unavailable.',
          code: 'invalid_response',
        );
      }
      deliveryUnconfirmed = deliveryUnconfirmed || delivery == 'unknown';
    }
    _challenges[key] = id;
    _challengeChannels[key] = phone == null
        ? null
        : channel ?? CollectOtpChannel.whatsapp;
    if (guestSession != null) {
      _guestUpgrade = _CollectGuestUpgrade(
        key: key,
        challengeId: id,
        authSubject: guestSession.authSubject,
        sessionId: guestSession.claims['session_id'] as String,
        phone: phone,
        email: email,
        channel: _challengeChannels[key],
      );
      await _persist();
      if (_disposed || generation != _generation || epoch != _otpGeneration) {
        throw const CollectAuthException(
          'Your sign-in changed.',
          code: 'session_changed',
        );
      }
    }
    if (deliveryUnconfirmed) {
      throw CollectOtpDeliveryUnknownException(
        retryAfterSeconds: retryAfterSeconds,
      );
    }
    return CollectOtpRequestReceipt(retryAfterSeconds: retryAfterSeconds);
  }

  Future<CollectAuthResponse> _verifyOtp({
    String? phone,
    String? email,
    required String token,
    required CollectOtpType type,
    CollectOtpChannel? channel,
    String? captchaToken,
  }) async {
    final key = _otpKey(phone, email);
    final challenge = _challenges[key];
    final upgrade = _guestUpgrade?.key == key ? _guestUpgrade : null;
    final guestSession = upgrade == null ? null : _session;
    if (upgrade != null &&
        (guestSession?.user.isAnonymous != true ||
            guestSession?.authSubject != upgrade.authSubject ||
            guestSession?.claims['session_id'] != upgrade.sessionId)) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    if (upgrade?.unconfirmed == true) return reconcileGuestUpgrade();
    final generation = _generation;
    final otpGeneration = _otpGeneration;
    if (challenge == null ||
        type != (phone == null ? CollectOtpType.email : CollectOtpType.sms) ||
        (channel != null && _challengeChannels[key] != channel) ||
        !RegExp(r'^[0-9]{6}$').hasMatch(token)) {
      throw const CollectAuthException(
        'Request a fresh verification code.',
        code: 'invalid_challenge',
      );
    }
    captchaToken = await _transport.captchaToken(captchaToken);
    if (_disposed ||
        generation != _generation ||
        otpGeneration != _otpGeneration ||
        _challenges[key] != challenge) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    Map<String, dynamic> data;
    if (upgrade != null) {
      // Journal uncertainty before the network await. Process death, a lost
      // reply or route cancellation cannot turn a provider mutation into a retry.
      _guestUpgrade = upgrade.uncertain();
      _refreshTimer?.cancel();
      _refreshTimer = null;
      await _persist();
      if (_disposed ||
          generation != _generation ||
          otpGeneration != _otpGeneration) {
        throw const CollectAuthException(
          'Your sign-in changed.',
          code: 'session_changed',
        );
      }
    }
    try {
      data = await _transport.request(
        upgrade == null ? 'verify' : 'upgrade/verify',
        {
          'phone': ?phone,
          'email': ?email,
          'code': token,
          'challenge_id': challenge,
          'surface': surface,
          'captcha_token': ?captchaToken,
        },
        bearer: guestSession?.accessToken,
      );
    } on CollectAuthException catch (error) {
      if (upgrade != null &&
          generation == _generation &&
          otpGeneration == _otpGeneration) {
        final knownRejection = error.code == 'guest_otp_rejected';
        _guestUpgrade = knownRejection ? upgrade : upgrade.uncertain();
        await _persist();
        if (!knownRejection) {
          throw const CollectAuthException(
            'Check the existing verification before trying again.',
            code: 'guest_upgrade_unknown',
            statusCode: '503',
          );
        }
      }
      rethrow;
    }
    if (_disposed ||
        generation != _generation ||
        otpGeneration != _otpGeneration ||
        _challenges[key] != challenge) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    final session = _verifiedSession(data);
    if (session.user.isAnonymous ||
        upgrade != null && session.authSubject != upgrade.authSubject) {
      throw const CollectAuthException(
        'The verified account changed.',
        code: 'verified_identity_mismatch',
      );
    }
    _guestUpgrade = null;
    _challenges.remove(key);
    _challengeChannels.remove(key);
    // Capture before synchronous observers can replace and restore a session.
    late final int installedGeneration;
    _install(
      session,
      CollectAuthEvent.signedIn,
      onInstalled: () {
        installedGeneration = _generation;
      },
    );
    await _persist();
    if (_disposed ||
        _generation != installedGeneration ||
        _session?.accessToken != session.accessToken) {
      throw const CollectAuthException(
        'Your sign-in changed.',
        code: 'session_changed',
      );
    }
    return CollectAuthResponse(session: session);
  }

  void _cancelOtp() {
    ++_otpGeneration;
    ++_anonymousGeneration;
    _challenges.clear();
    _challengeChannels.clear();
    if (_guestUpgrade case final pending?) {
      _challenges[pending.key] = pending.challengeId;
      _challengeChannels[pending.key] = pending.channel;
    }
    _recordInitializationCancellation(otp: true);
    _client.cancelCaptcha?.call();
  }

  String _otpKey(String? phone, String? email) {
    if ((phone == null) == (email == null) ||
        (phone != null && !RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone)) ||
        (email != null &&
            (email.length > 254 ||
                !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)))) {
      throw const CollectAuthException(
        'Enter a valid account address.',
        code: 'invalid_identity',
      );
    }
    return '$surface:${phone ?? email}';
  }
}
