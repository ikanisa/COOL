import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cloudflare/cloudflare_module.dart';

typedef AdminSessionKey = ({String userId, String sessionId});
typedef AdminSessionScope = ({AdminSessionKey key, int generation});

/// Collect clears its local session before a synchronous sign-out event.
/// A paused listener can receive that old event after another login; only the
/// current live getter and token fence distinguish that departed notification.
/// This client receives no browser broadcasts or external Auth event payloads.
bool adminDelayedLocalSignOut(
  CollectCloudflareClient client,
  CollectAuthState event,
) {
  if (event.event != CollectAuthEvent.signedOut) return false;
  final current = client.auth.currentSession;
  final key = adminSessionKey(current);
  return key != null &&
      (event.session == null ||
          adminSessionKey(event.session) != key ||
          current!.accessToken != event.session?.accessToken);
}

AdminSessionKey? adminSessionKey(CollectAuthSession? session) {
  if (session == null) return null;
  try {
    final claims = jsonDecode(
      utf8.decode(
        base64Url.decode(
          base64Url.normalize(session.accessToken.split('.')[1]),
        ),
      ),
    );
    if (claims is! Map ||
        claims['sub'] != session.user.id ||
        claims['session_id'] is! String ||
        (claims['session_id'] as String).isEmpty ||
        claims['exp'] is! int ||
        (claims['exp'] as int) <=
            DateTime.now().millisecondsSinceEpoch ~/ 1000) {
      return null;
    }
    return (userId: session.user.id, sessionId: claims['session_id'] as String);
  } catch (_) {
    return null;
  }
}

/// A new login by the same person is a new data boundary. Same-session token
/// refresh preserves state, while a switch away and back advances generation.
final adminAuthSessionScopeProvider =
    StateNotifierProvider<AdminSessionController, AdminSessionScope?>((ref) {
      return AdminSessionController(ref.watch(collectBackendClientProvider));
    });

class AdminSessionController extends StateNotifier<AdminSessionScope?> {
  AdminSessionController(CollectCloudflareClient? client) : super(null) {
    _update(client?.auth.currentSession);
    _subscription = client?.auth.onAuthStateChange.listen(
      (event) {
        if (event.event == CollectAuthEvent.signedOut) {
          final current = client.auth.currentSession;
          if (adminDelayedLocalSignOut(client, event) &&
              state != null &&
              state!.key == adminSessionKey(current)) {
            _update(current);
          } else {
            _update(null);
          }
        } else {
          _update(event.session);
        }
      },
      onError: (Object _) => _update(null),
      onDone: () => _update(null),
    );
  }
  StreamSubscription<CollectAuthState>? _subscription;
  Timer? _expiry;
  int _generation = 0;

  void _update(CollectAuthSession? session) {
    final key = adminSessionKey(session);
    if (state?.key != key) {
      _generation++;
      state = key == null ? null : (key: key, generation: _generation);
    }
    _expiry?.cancel();
    if (key != null && session?.expiresAt != null) {
      final remaining = DateTime.fromMillisecondsSinceEpoch(
        session!.expiresAt! * 1000,
      ).difference(DateTime.now());
      _expiry = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        () => _update(null),
      );
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

class AdminSessionChanged implements Exception {
  const AdminSessionChanged();
  @override
  String toString() =>
      'Your Admin session changed. Reopen this page before continuing.';
}

/// Per-request sticky invalidation also catches A -> B -> A while awaiting.
/// Token contents are a local fence; server Auth remains the authority.
class AdminRequestSession {
  AdminRequestSession(this.client) {
    key = adminSessionKey(client.auth.currentSession);
    if (key == null) throw const AdminSessionChanged();
    token = client.auth.currentSession!.accessToken;
    _subscription = client.auth.onAuthStateChange.listen(
      (event) {
        if ((event.event == CollectAuthEvent.signedOut &&
                !adminDelayedLocalSignOut(client, event)) ||
            adminSessionKey(event.session) != key) {
          _invalid = true;
        }
      },
      onError: (Object _) => _invalid = true,
      onDone: () => _invalid = true,
    );
  }
  final CollectCloudflareClient client;
  late final AdminSessionKey? key;
  late final String token;
  late final StreamSubscription<CollectAuthState> _subscription;
  bool _invalid = false;
  void checkCurrent() {
    if (_invalid || adminSessionKey(client.auth.currentSession) != key) {
      throw const AdminSessionChanged();
    }
  }

  Future<void> dispose() => _subscription.cancel();
}

final adminAuthStateProvider = StreamProvider<CollectAuthState>((ref) {
  final client = ref.watch(collectBackendClientProvider);
  if (client == null) return const Stream<CollectAuthState>.empty();
  return client.auth.onAuthStateChange;
});

/// Session ownership is a cache key for all Admin data providers. An explicit
/// signed-out event must win over any session still visible during teardown.
final adminAuthUserIdProvider = Provider<String?>((ref) {
  final client = ref.watch(collectBackendClientProvider);
  final streamedState = ref.watch(adminAuthStateProvider).valueOrNull;
  if (streamedState?.event == CollectAuthEvent.signedOut &&
      (client == null || !adminDelayedLocalSignOut(client, streamedState!))) {
    return null;
  }
  return streamedState == null
      ? client?.auth.currentUser?.id
      : streamedState.session?.user.id;
});

final adminAuthGuardProvider = Provider<AdminAuthGuard>((ref) {
  return AdminAuthGuard(
    isAuthorized: ref.watch(adminAuthSessionScopeProvider) != null,
  );
});

class AdminAuthGuard {
  const AdminAuthGuard({required this.isAuthorized});

  final bool isAuthorized;
}
