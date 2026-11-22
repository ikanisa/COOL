import 'dart:convert';

import 'collect_cloudflare_types.dart';

const collectChallengeOrigin = 'https://api.collect.ikanisa.com';
const collectChallengePath = '/v1/security/challenge';
const collectChallengeEnvelope = 'collect.turnstile.v1';

Uri collectChallengeUri(
  String attemptId,
  String parentOrigin, {
  Uri? endpoint,
}) {
  final parent = Uri.tryParse(parentOrigin);
  if (!RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(attemptId) ||
      parent == null ||
      parent.scheme != 'https' ||
      parent.host.isEmpty ||
      parent.userInfo.isNotEmpty ||
      parent.path.isNotEmpty ||
      parent.query.isNotEmpty ||
      parent.fragment.isNotEmpty ||
      parent.origin != parentOrigin) {
    throw const CollectAuthException(
      'Security verification is unavailable.',
      code: 'captcha_unavailable',
    );
  }
  final target =
      endpoint ?? Uri.parse('$collectChallengeOrigin$collectChallengePath');
  if (target.scheme != 'https' ||
      target.host.isEmpty ||
      target.userInfo.isNotEmpty ||
      target.query.isNotEmpty ||
      target.fragment.isNotEmpty ||
      !const {
        collectChallengePath,
        '/functions/v1/collect-api/v1/security/challenge',
      }.contains(target.path)) {
    throw const CollectAuthException(
      'Security verification is unavailable.',
      code: 'captcha_unavailable',
    );
  }
  return target.replace(
    queryParameters: {
      'attempt_id': attemptId,
      'parent_origin': parentOrigin,
      'theme': 'auto',
    },
  );
}

/// A message is an untrusted candidate token. The authentication server still
/// verifies Turnstile hostname, action, expiry and single use for every request.
String collectChallengeToken(Object? envelope, String attemptId) {
  try {
    final Object? value;
    if (envelope is String) {
      if (envelope.length > 4096) throw const FormatException();
      value = jsonDecode(envelope);
    } else {
      value = envelope;
    }
    if (value is! Map ||
        value.length != 3 ||
        value['type'] != collectChallengeEnvelope ||
        value['attempt_id'] != attemptId ||
        value.containsKey('error') ||
        !value.keys.toSet().containsAll({'type', 'attempt_id', 'token'})) {
      throw const FormatException();
    }
    final token = value['token'];
    if (token is! String ||
        token.isEmpty ||
        token.length > 2048 ||
        token.contains(RegExp(r'[\x00-\x20\x7f]'))) {
      throw const FormatException();
    }
    return token;
  } catch (_) {
    throw const CollectAuthException(
      'Security verification could not finish.',
      code: 'captcha_unavailable',
    );
  }
}
