part of 'collect_cloudflare_client.dart';

extension _CollectAuthGoogle on CollectAuthClient {
  Future<CollectAuthResponse> _authorizeGoogle({
    required Future<Map<String, dynamic>> Function(
      Future<Uri> Function(String? returnOrigin) createUrl,
      String state,
      String apiOrigin,
    )
    authorize,
  }) async {
    if (surface != 'member') {
      throw const CollectAuthException(
        'Member sign-in is required.',
        code: 'invalid_surface',
      );
    }
    _requireGuestRestoreSettled();
    if (currentGuest != null) {
      throw const CollectAuthException(
        'Verify an email address or phone number to keep this guest session.',
        code: 'guest_upgrade_required',
      );
    }
    final supabase = _client.supabaseConfiguration;
    final callbackOrigin = supabase == null
        ? _client._base.origin
        : supabase.googleCallbackOrigin;
    if (callbackOrigin == null) {
      throw const CollectAuthException(
        'Google sign-in is unavailable.',
        code: 'invalid_response',
      );
    }
    final generation = _generation;
    final googleGeneration = ++_googleGeneration;
    ++_otpGeneration;
    final random = Random.secure();
    String nonce() => base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    final verifier = nonce(), state = nonce();
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    void checkCurrent() {
      if (_disposed ||
          generation != _generation ||
          googleGeneration != _googleGeneration) {
        throw const CollectAuthException(
          'Your sign-in changed.',
          code: 'session_changed',
        );
      }
    }

    final reply = await authorize(
      (origin) async {
        final captcha = await _transport.captchaToken(null);
        checkCurrent();
        final data = await _transport.request('google/start', {
          'surface': 'member',
          'captcha_token': ?captcha,
          'code_challenge': challenge,
          'client_state': state,
          'return_origin': ?origin,
        });
        checkCurrent();
        final url = data['authorization_url'] is String
            ? Uri.tryParse(data['authorization_url'] as String)
            : null;
        if (!collectGoogleAuthorizationUrlAllowed(
          url,
          usesSupabase: _client.supabaseConfiguration != null,
          supabaseCallbackOrigin: callbackOrigin,
          supabaseConfiguration: supabase,
        )) {
          throw const CollectAuthException(
            'Google sign-in is unavailable.',
            code: 'invalid_response',
          );
        }
        return url!;
      },
      state,
      callbackOrigin,
    );
    checkCurrent();
    if (reply['error'] != null) {
      final code = reply['error'];
      throw CollectAuthException(
        'Google sign-in could not finish.',
        code:
            const {
              'google_cancelled',
              'google_use_email_sign_in',
            }.contains(code)
            ? code as String
            : 'invalid_google_sign_in',
      );
    }
    if (reply['state'] != state ||
        reply['code'] is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(reply['code'] as String)) {
      throw const CollectAuthException(
        'Google sign-in could not finish.',
        code: 'invalid_google_sign_in',
      );
    }
    final data = await _transport.request('google/exchange', {
      'code': reply['code'],
      'code_verifier': verifier,
      if (_client.supabaseConfiguration != null) 'client_state': state,
    });
    checkCurrent();
    final session = _verifiedSession(data);
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

  void _cancelGoogle() {
    ++_googleGeneration;
    _recordInitializationCancellation(google: true);
    _client.cancelCaptcha?.call();
  }
}
