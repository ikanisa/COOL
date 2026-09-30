import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_module.dart';

typedef AdminSessionKey = ({String userId, String sessionId});
typedef AdminSessionScope = ({AdminSessionKey key, int generation});

AdminSessionKey? adminSessionKey(Session? session) {
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
      return AdminSessionController(ref.watch(supabaseClientProvider));
    });

class AdminSessionController extends StateNotifier<AdminSessionScope?> {
  AdminSessionController(SupabaseClient? client) : super(null) {
    _update(client?.auth.currentSession);
    _subscription = client?.auth.onAuthStateChange.listen(
      (event) => _update(
        event.event == AuthChangeEvent.signedOut ? null : event.session,
      ),
      onError: (Object _) => _update(null),
      onDone: () => _update(null),
    );
  }
  StreamSubscription<AuthState>? _subscription;
  Timer? _expiry;
  int _generation = 0;

  void _update(Session? session) {
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
        if (event.event == AuthChangeEvent.signedOut ||
            adminSessionKey(event.session) != key) {
          _invalid = true;
        }
      },
      onError: (Object _) => _invalid = true,
      onDone: () => _invalid = true,
    );
  }
  final SupabaseClient client;
  late final AdminSessionKey? key;
  late final String token;
  late final StreamSubscription<AuthState> _subscription;
  bool _invalid = false;
  void checkCurrent() {
    if (_invalid || adminSessionKey(client.auth.currentSession) != key) {
      throw const AdminSessionChanged();
    }
  }

  Future<void> dispose() => _subscription.cancel();
}

final adminAuthStateProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const Stream<AuthState>.empty();
  return client.auth.onAuthStateChange;
});

/// Session ownership is a cache key for all Admin data providers. An explicit
/// signed-out event must win over any session still visible during teardown.
final adminAuthUserIdProvider = Provider<String?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final streamedState = ref.watch(adminAuthStateProvider).valueOrNull;
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
