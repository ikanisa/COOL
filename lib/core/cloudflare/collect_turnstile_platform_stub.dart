import 'collect_cloudflare_types.dart';

Future<Object?> acquireChallenge(String attemptId, {Uri? endpoint}) async =>
    throw const CollectAuthException(
      'Security verification is unavailable.',
      code: 'captcha_unavailable',
    );
Future<void> cancelChallenge(String attemptId) async {}
