import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

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
    // Open synchronously from the button gesture, before Turnstile/network awaits.
    final popup = web.window.open(
      'about:blank',
      'collect-google-$state',
      'popup,width=500,height=700',
    );
    if (popup == null) {
      throw const CollectAuthException(
        'Allow the Google sign-in window.',
        code: 'google_popup_blocked',
      );
    }
    final result = Completer<Map<String, dynamic>>();
    _pending = result;
    final listener = ((web.Event event) {
      final message = event as web.MessageEvent;
      if (message.origin != apiOrigin ||
          message.source != popup ||
          result.isCompleted) {
        return;
      }
      final data = message.data.dartify();
      if (data is! Map ||
          data['type'] != 'collect-google-auth' ||
          data['state'] != state) {
        return;
      }
      result.complete(Map<String, dynamic>.from(data));
    }).toJS;
    web.window.addEventListener('message', listener);
    final closedTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (popup.closed && !result.isCompleted) cancel();
    });
    try {
      final url = await createUrl(web.window.location.origin);
      if (result.isCompleted) return await result.future;
      popup.location.href = url.toString();
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
      closedTimer.cancel();
      web.window.removeEventListener('message', listener);
      popup.close();
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
