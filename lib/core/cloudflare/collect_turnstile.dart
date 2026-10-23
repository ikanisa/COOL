import 'dart:async';

import 'package:uuid/uuid.dart';

import 'collect_cloudflare_types.dart';
import 'collect_turnstile_contract.dart';
import 'collect_turnstile_platform_stub.dart'
    if (dart.library.io) 'collect_turnstile_platform_native.dart'
    if (dart.library.js_interop) 'collect_turnstile_platform_web.dart'
    as platform;

/// One fresh, bounded browser challenge for each OTP send or verification.
/// Closing the owning authentication flow cancels only its current attempt.
final class CollectTurnstileChallenge {
  CollectTurnstileChallenge({this.endpoint});
  final Uri? endpoint;
  String? _attemptId;

  Future<String> acquire() async {
    if (_attemptId != null) {
      throw const CollectAuthException(
        'Security verification is already open.',
        code: 'captcha_pending',
      );
    }
    final attempt = const Uuid().v4();
    _attemptId = attempt;
    try {
      final envelope = await platform
          .acquireChallenge(attempt, endpoint: endpoint)
          .timeout(const Duration(seconds: 120));
      if (_attemptId != attempt) {
        throw const CollectAuthException(
          'Security verification was cancelled.',
          code: 'captcha_cancelled',
        );
      }
      return collectChallengeToken(envelope, attempt);
    } on CollectAuthException {
      rethrow;
    } catch (_) {
      throw const CollectAuthException(
        'Security verification could not finish.',
        code: 'captcha_unavailable',
      );
    } finally {
      if (_attemptId == attempt) _attemptId = null;
      unawaited(platform.cancelChallenge(attempt).catchError((Object _) {}));
    }
  }

  void cancel() {
    final attempt = _attemptId;
    _attemptId = null;
    if (attempt != null) {
      unawaited(platform.cancelChallenge(attempt).catchError((Object _) {}));
    }
  }
}
