import 'dart:async';
import 'dart:convert';

import '../../core/cloudflare/collect_cloudflare_client.dart';

import 'privacy_contract.dart';

/// JWT decoding is a local ownership fence. Auth and SQL remain authoritative.
final class PrivacySessionSnapshot {
  const PrivacySessionSnapshot._(
    this.session,
    this.subjectId,
    this.sessionId,
    this.generation,
  );
  final CollectAuthSession session;
  final String subjectId;
  final String sessionId;
  final int generation;

  static PrivacySessionSnapshot? parse(
    CollectAuthSession? session,
    int generation,
  ) {
    if (session == null || session.accessToken.length > 32768) return null;
    try {
      final parts = session.accessToken.split('.');
      if (parts.length != 3) return null;
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (claims is! Map<String, dynamic> ||
          !privacyUuid(session.user.id) ||
          claims['sub'] != session.authSubject ||
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
    CollectAuthSession verified,
  );

  /// Integration must call this before the first await of logout/account reset.
  void invalidate();
}

/// Email uses an explicit managed/canonical pair and marks installation in the
/// same synchronous turn, before later account observers can invalidate a view.
abstract interface class PrivacyEmailSessionAuthority
    implements PrivacySessionAuthority {
  PrivacySessionSnapshot adoptEmail(
    PrivacySessionSnapshot original,
    CollectAuthSession verified, {
    required void Function() onInstalled,
  });
}

/// Owns no credentials beyond the live SDK. It creates no second Auth client.
final class CollectPrivacySessionAuthority
    implements PrivacyEmailSessionAuthority {
  CollectPrivacySessionAuthority(this._auth) {
    _observed = _identity(_auth.currentSession);
    _observedEvent = _observed;
    // Collect emits Auth changes synchronously, closing account ABA races
    // before an awaited response can be installed.
    // ignore: invalid_use_of_internal_member
    _subscription = _auth.onAuthStateChangeSync.listen((state) {
      _authEventsObserved = true;
      // ReplaySubject can initially queue events. Read each event's own
      // identity so a synchronous account switch and return cannot disappear
      // merely because the live getter already points at the original account.
      final eventIdentity = state.event == CollectAuthEvent.signedOut
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
      if (state.event == CollectAuthEvent.signedOut) {
        ++_generation;
        _blocked = true;
      }
      if ((state.event == CollectAuthEvent.signedIn ||
              state.event == CollectAuthEvent.tokenRefreshed) &&
          identity != null &&
          identity != _invalidatedIdentity &&
          identity == eventIdentity) {
        _blocked = false;
      }
    }, onError: (Object _) => invalidate());
  }

  final CollectAuthClient _auth;
  late final StreamSubscription<CollectAuthState> _subscription;
  (String, String)? _observed;
  (String, String)? _observedEvent;
  int _generation = 0;
  bool _disposed = false;
  bool _blocked = false;
  bool _authEventsObserved = true;
  (String, String)? _invalidatedIdentity;

  (String, String)? _identity(CollectAuthSession? session) {
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
    CollectAuthSession verified,
  ) => _adopt(original, verified);

  @override
  PrivacySessionSnapshot adoptEmail(
    PrivacySessionSnapshot original,
    CollectAuthSession verified, {
    required void Function() onInstalled,
  }) {
    final managed = original.session.user.authUserId;
    if (!privacyUuid(managed) ||
        original.session.claims['sub'] != managed ||
        verified.user.authUserId != managed ||
        verified.claims['sub'] != managed ||
        !original.session.usesMappedAuthUser ||
        !verified.usesMappedAuthUser) {
      throw const PrivacyRequestException(
        PrivacyFailure.verificationUnavailable,
      );
    }
    final current = capture();
    if (current.session.user.authUserId != managed ||
        current.session.claims['sub'] != managed) {
      throw const PrivacyRequestException(PrivacyFailure.sessionChanged);
    }
    return _adopt(original, verified, onInstalled: onInstalled);
  }

  PrivacySessionSnapshot _adopt(
    PrivacySessionSnapshot original,
    CollectAuthSession verified, {
    void Function()? onInstalled,
  }) {
    // This authority is subscribed before any verification request. Compare
    // the live account generation immediately before session installation.
    if (!_authEventsObserved) {
      throw const PrivacyRequestException(PrivacyFailure.sessionChanged);
    }
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
    // Collect installs this nonexpired candidate synchronously before its
    // protected persistence await; there is no network refresh in this path.
    final recovery = _auth.recoverSession(
      jsonEncode(verified.toJson()),
      onInstalled: onInstalled,
    );
    // The install callback runs after memory installation and before any
    // synchronous observer can cancel or dispose the verification view.
    // Recovery itself publishes the fenced candidate synchronously.
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
