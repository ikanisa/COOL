import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';

import 'collect_cloudflare_types.dart';

final class GoogleAuthBrowser {
  Completer<Map<String, dynamic>>? _pending;

  Future<Map<String, dynamic>> authorize(
    Future<Uri> Function(String? returnOrigin) createUrl,
    String state,
    String apiOrigin,
  ) async {
    if (_pending != null) {
      throw const CollectAuthException(
        'Sign-in is already open.',
        code: 'google_busy',
      );
    }
    final result = Completer<Map<String, dynamic>>();
    _pending = result;
    final subscription = AppLinks().uriLinkStream.listen((uri) {
      if (uri.scheme != 'collect' ||
          uri.host != 'auth' ||
          uri.path != '/google' ||
          uri.queryParameters['state'] != state ||
          result.isCompleted) {
        return;
      }
      result.complete(Map<String, dynamic>.from(uri.queryParameters));
    }, onError: (_) => cancel());
    try {
      final url = await createUrl(null);
      if (result.isCompleted) return await result.future;
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw const CollectAuthException(
          'The browser could not open.',
          code: 'google_browser_unavailable',
        );
      }
      return await result.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw const CollectAuthException(
            'Google sign-in expired.',
            code: 'google_expired',
          );
        },
      );
    } finally {
      await subscription.cancel();
      if (identical(_pending, result)) _pending = null;
    }
  }

  void cancel() {
    final result = _pending;
    if (result != null && !result.isCompleted) {
      result.complete({'error': 'google_cancelled'});
    }
  }
}
