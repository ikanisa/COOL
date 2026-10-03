import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:collect_app/core/supabase/browser_auth_storage_web.dart';
import 'package:gotrue/gotrue.dart';
import 'package:gotrue/src/collect_browser_invalidation.dart';
import 'package:gotrue/src/broadcast_web.dart' as channel;
import 'package:web/web.dart' as web;

/// Explicit synthetic loopback fixture using the real vendored SDK. No release
/// entrypoint imports this file; no credentials are emitted in its status.
class _MemoryBarrier extends GotrueAsyncStorage {
  final values = <String, String>{};
  Completer<void>? barrier;
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    await barrier?.future;
    values.remove(key);
  }
}

Future<void> main() async {
  final origin = web.window.location.origin;
  if (!Uri.parse(origin).host.startsWith('127.0.0.1')) {
    throw StateError('loopback_fixture_required');
  }
  if (web.window.location.search.contains('cleanup')) {
    try {
      await removeOwnedLegacyBrowserCredentials(origin);
    } catch (_) {
      final denied = web.document.createElement('pre')
        ..id = 'status'
        ..textContent = jsonEncode({
          'cleanup_denied': true,
          'authenticated': false,
        });
      web.document.body!.appendChild(denied);
      return;
    }
  }
  final storage = _MemoryBarrier();
  final client = GoTrueClient(
    url: '$origin/auth/v1',
    autoRefreshToken: false,
    asyncStorage: storage,
  );
  final events = <Map<String, Object?>>[];
  final observations = <Map<String, Object?>>[];
  final status = (web.document.createElement('pre') as web.HTMLElement)
    ..id = 'status';
  void paint() {
    final owner = CollectBrowserInvalidation.owner(client.currentSession);
    status.textContent = jsonEncode({
      'authenticated': owner != null,
      'actor': owner?.actor,
      'session': owner?.session,
      'events': events,
      'barrier': storage.barrier != null,
      'web_enabled': const bool.fromEnvironment('dart.library.js_interop'),
      'observations': observations,
    });
  }

  final observer = channel.getBroadcastChannel('sb-127-auth-token');
  observer.onMessage.listen((message) {
    observations.add({
      'keys': message.keys.toList(),
      'accepts': CollectBrowserInvalidation.accepts(
        message,
        client.currentSession,
        '$origin/auth/v1',
      ),
      'issued_type': message['issued'].runtimeType.toString(),
    });
    paint();
  });
  client.onAuthStateChange.listen(
    (event) {
      events.add({
        'event': event.event.name,
        'from_broadcast': event.fromBroadcast,
        'reason': event.signOutReason?.name,
      });
      paint();
    },
    onError: (_) {
      events.add({'error': 'auth_failed'});
      paint();
    },
  );
  void button(String id, FutureOr<void> Function() action) {
    final control = web.HTMLButtonElement()
      ..id = id
      ..textContent = id;
    control.onclick = ((web.MouseEvent _) {
      unawaited(
        Future<void>.sync(action).then(
          (_) {
            paint();
          },
          onError: (_) {
            events.add({'error': 'action_failed'});
            paint();
          },
        ),
      );
    }).toJS;
    web.document.body!.appendChild(control);
  }

  button('sign-in-a', () async {
    await client.verifyOTP(
      phone: '+250788989001',
      token: 'A',
      type: OtpType.sms,
    );
  });
  button('sign-in-b', () async {
    await client.verifyOTP(
      phone: '+250788989001',
      token: 'B',
      type: OtpType.sms,
    );
  });
  button('refresh-a-explicit', () async {
    await client.refreshSession('synthetic-refresh-A');
  });
  button('refresh', () async {
    await client.refreshSession();
  });
  button('logout', () async {
    await client.signOut();
  });
  button('hold-logout', () {
    storage.barrier = Completer<void>();
    unawaited(
      client.signOut().then((_) {
        paint();
      }),
    );
  });
  button('release-logout', () {
    storage.barrier?.complete();
    storage.barrier = null;
  });
  button('snapshot', paint);
  web.document.body!.appendChild(status);
  paint();
}
