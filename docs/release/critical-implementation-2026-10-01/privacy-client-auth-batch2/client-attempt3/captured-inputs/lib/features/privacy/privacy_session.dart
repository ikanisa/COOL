import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'privacy_contract.dart';

/// JWT decoding is a local ownership fence. Auth and SQL remain authoritative.
final class PrivacySessionSnapshot {
  const PrivacySessionSnapshot._(
    this.session,
    this.subjectId,
    this.sessionId,
    this.generation,
  );
  final Session session;
  final String subjectId;
  final String sessionId;
  final int generation;

  static PrivacySessionSnapshot? parse(Session? session, int generation) {
    if (session == null || session.accessToken.length > 32768) return null;
    try {
      final parts = session.accessToken.split('.');
      if (parts.length != 3) return null;
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (claims is! Map<String, dynamic> ||
          !privacyUuid(session.user.id) ||
          claims['sub'] != session.user.id ||
          !privacyUuid(claims['session_id']) ||
          claims['role'] != 'authenticated' ||
          session.user.isAnonymous ||
          claims['exp'] is! int ||
          (claims['exp'] as int) <=
              DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30 ||
          (claims['exp'] as int) > 253402300799 ||
          session.tokenType.toLowerCase() != 'bearer') {
        return null;
      }
      return PrivacySessionSnapshot._(
        session,
        session.user.id,
        claims['session_id'] as String,
        generation,
      );
    } catch (_) {
      return null;
    }
  }

  bool sameFence(PrivacySessionSnapshot other) =>
      subjectId == other.subjectId &&
      sessionId == other.sessionId &&
      generation == other.generation;
  @override
  String toString() => 'PrivacySessionSnapshot';
}

abstract interface class PrivacySessionAuthority {
  PrivacySessionSnapshot capture();

  /// Synchronous compare-and-adopt. Never awaits before installing the session.
  PrivacySessionSnapshot adopt(
    PrivacySessionSnapshot original,
    Session verified,
  );

  /// Integration must call this before the first await of logout/account reset.
  void invalidate();
}

/// Owns no credentials beyond the live SDK. It creates no second Auth client.
final class GoTruePrivacySessionAuthority implements PrivacySessionAuthority {
  GoTruePrivacySessionAuthority(this._auth) {
    _observed = _identity(_auth.currentSession);
    _observedEvent = _observed;
    // The pinned synchronous stream closes account ABA races before futures
    // complete. An asynchronous Riverpod/profile revision alone is too late.
    // ignore: invalid_use_of_internal_member
    _subscription = _auth.onAuthStateChangeSync.listen((state) {
      // ReplaySubject can initially queue events. Read each event's own
      // identity so a synchronous account switch and return cannot disappear
      // merely because the live getter already points at the original account.
      final eventIdentity = state.event == AuthChangeEvent.signedOut
          ? null
          : _identity(state.session);
      if (eventIdentity != _observedEvent) {
        _observedEvent = eventIdentity;
        if (eventIdentity != _observed) ++_generation;
      }
      final identity = _identity(_auth.currentSession);
      if (identity != _observed) {
        _observed = identity;
        ++_generation;
      }
      if (state.event == AuthChangeEvent.signedOut) {
        ++_generation;
        _blocked = true;
      }
      if ((state.event == AuthChangeEvent.signedIn ||
              state.event == AuthChangeEvent.tokenRefreshed) &&
          identity != null &&
          identity != _invalidatedIdentity &&
          identity == eventIdentity) {
        _blocked = false;
      }
    }, onError: (Object _) => invalidate());
  }

  final GoTrueClient _auth;
  late final StreamSubscription<AuthState> _subscription;
  (String, String)? _observed;
  (String, String)? _observedEvent;
  int _generation = 0;
  bool _disposed = false;
  bool _blocked = false;
  (String, String)? _invalidatedIdentity;

  (String, String)? _identity(Session? session) {
    final snapshot = PrivacySessionSnapshot.parse(session, 0);
    return snapshot == null ? null : (snapshot.subjectId, snapshot.sessionId);
  }

  @override
  PrivacySessionSnapshot capture() {
    final identity = _identity(_auth.currentSession);
    if (identity != _observed) {
      _observed = identity;
      ++_generation;
    }
    final snapshot = PrivacySessionSnapshot.parse(
      _auth.currentSession,
      _generation,
    );
    if (_disposed || _blocked || snapshot == null) {
      throw const PrivacyRequestException(PrivacyFailure.sessionChanged);
    }
    return snapshot;
  }

  @override
  PrivacySessionSnapshot adopt(
    PrivacySessionSnapshot original,
    Session verified,
  ) {
    final current = capture();
    final candidate = PrivacySessionSnapshot.parse(verified, _generation);
    if (!current.sameFence(original)) {
      throw const PrivacyRequestException(PrivacyFailure.sessionChanged);
    }
    if (candidate == null ||
        candidate.subjectId != original.subjectId ||
        candidate.sessionId == original.sessionId ||
        verified.refreshToken?.isNotEmpty != true ||
        verified.isExpired) {
      throw const PrivacyRequestException(
        PrivacyFailure.verificationUnavailable,
      );
    }
    // In gotrue 2.27.1 this nonexpired branch saves synchronously, with no
    // network, refresh or asynchronous gap. Tests bind that installed behavior.
    final recovery = _auth.recoverSession(jsonEncode(verified.toJson()));
    // Same-user recoverSession emits no event. Notify ordinary signedIn so the
    // actual SDK persists the new session and updates member consumers.
    // ignore: invalid_use_of_internal_member
    _auth.notifyAllSubscribers(AuthChangeEvent.signedIn);
    unawaited(recovery.then<void>((_) {}, onError: (Object _) {}));
    final adopted = capture();
    if (adopted.subjectId != candidate.subjectId ||
        adopted.sessionId != candidate.sessionId) {
      throw const PrivacyRequestException(PrivacyFailure.sessionChanged);
    }
    return adopted;
  }

  @override
  void invalidate() {
    ++_generation;
    _blocked = true;
    _invalidatedIdentity = _observed;
  }

  Future<void> dispose() async {
    _disposed = true;
    invalidate();
    await _subscription.cancel();
  }
}
