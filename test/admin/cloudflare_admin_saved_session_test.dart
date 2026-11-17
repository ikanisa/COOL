import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/admin_logout_intent_storage.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../core/supabase_backend_test.dart' as fixtures;

const _origin = 'https://admin.saved-session.example.invalid';
const _publicSession = '00000000-0000-4000-8000-000000000001';
const _adminId = '00000000-0000-4000-8000-000000000002';
const _principalId = '00000000-0000-4000-8000-000000000003';
final _csrf = 'a' * 64;

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

/// Models the server-side cookie session. It does not emulate browser cookies.
class _Server {
  bool signedIn = true;
  bool available = true;
  bool failLogout = false;
  String publicSession = _publicSession;
  String csrf = _csrf;
  void Function()? afterSessionRead;
  String role = 'owner';
  List<String> permissions = ['overview.read', 'admin_users.manage'];
  DateTime expiry = DateTime.now().toUtc().add(const Duration(minutes: 30));
  int sessionReads = 0;
  int loginRequests = 0;
  int logoutRequests = 0;
  Completer<http.Response>? pendingRead;
  final logoutIntents = MemoryAdminLogoutIntentStorage();

  Map<String, Object?> session() => {
    'user': signedIn
        ? {
            'id': _adminId,
            'principalId': _principalId,
            'email': 'info@ikanisa.com',
            'role': role,
            'sessionId': publicSession,
            'permissions': permissions,
            'assuranceLevel': 1,
            'mfaAt': null,
            'financialModel': 'canonical_evidence_ledger',
          }
        : null,
    'expiresAt': signedIn ? expiry.toIso8601String() : null,
    'ownerEmail': 'info@ikanisa.com',
    'csrfToken': signedIn ? csrf : null,
  };

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/auth/session')) {
      sessionReads++;
      if (!available) return _json({'error': 'offline'}, 503);
      final result = _json(session());
      afterSessionRead?.call();
      return result;
    }
    if (path.endsWith('/auth/email-verification')) {
      return _json({
        'contractVersion': 1,
        'sessionId': publicSession,
        'emailVerifiedAt': null,
      });
    }
    if (path.endsWith('/auth/logout')) {
      logoutRequests++;
      if (failLogout) throw http.ClientException('Synthetic offline logout');
      if (request.headers['X-Collect-CSRF'] != csrf) {
        return _json({'error': 'csrf_rejected'}, 403);
      }
      signedIn = false;
      return _json({'ok': true});
    }
    if (path.endsWith('/auth/login') || path.endsWith('/auth/verify')) {
      loginRequests++;
      throw StateError('Session restoration must not sign in again.');
    }
    if (path.endsWith('/fixture/read') || path.contains('/evidence/')) {
      return pendingRead!.future;
    }
    throw StateError('Unexpected synthetic request: $path');
  }

  CloudflareAdminSession client({AdminLogoutIntentStorage? storage}) =>
      CloudflareAdminSession(
        MockClient(handle),
        origin: Uri.parse(_origin),
        environment: fixtures.environment(api: _origin, admin: _origin),
        logoutIntentStorage: storage ?? logoutIntents,
      );
}

class _FailingStorage implements AdminLogoutIntentStorage {
  bool failRead = false;
  bool failAdd = false;
  final inner = MemoryAdminLogoutIntentStorage();

  @override
  Set<String> readPending() {
    if (failRead) throw StateError('Synthetic storage failure');
    return inner.readPending();
  }

  @override
  void add(String sessionFingerprint) {
    if (failAdd) throw StateError('Synthetic storage failure');
    inner.add(sessionFingerprint);
  }

  @override
  void remove(String sessionFingerprint) => inner.remove(sessionFingerprint);
}

class _InterleavingStorage implements AdminLogoutIntentStorage {
  _InterleavingStorage(this.inner);
  final AdminLogoutIntentStorage inner;
  void Function()? afterFourthRead;
  int reads = 0;

  @override
  Set<String> readPending() {
    final snapshot = inner.readPending();
    if (afterFourthRead != null && ++reads == 4) {
      afterFourthRead!();
    }
    return snapshot;
  }

  @override
  void add(String sessionFingerprint) => inner.add(sessionFingerprint);

  @override
  void remove(String sessionFingerprint) => inner.remove(sessionFingerprint);
}

void main() {
  test('long saved sessions use a browser-safe expiry timer', () {
    final now = DateTime.utc(2026, 11, 13);
    expect(
      cloudflareAdminExpiryDelay(now.add(const Duration(days: 30)), now: now),
      const Duration(days: 1),
    );
    expect(
      cloudflareAdminExpiryDelay(
        now.add(const Duration(seconds: 20)),
        now: now,
      ),
      const Duration(seconds: 20),
    );
    expect(
      cloudflareAdminExpiryDelay(
        now.subtract(const Duration(seconds: 1)),
        now: now,
      ),
      Duration.zero,
    );
  });

  test(
    'a recreated controller restores the server session without login',
    () async {
      final server = _Server();
      final first = server.client();
      await first.refresh();
      expect(first.user?.id, _adminId);
      first.dispose();

      final reopened = server.client();
      addTearDown(reopened.dispose);
      await reopened.refresh();
      expect(reopened.user?.id, _adminId);
      expect(reopened.user?.sessionId, _publicSession);
      expect(server.loginRequests, 0);
      expect(server.sessionReads, 2);
    },
  );

  testWidgets('scheduled session checks adopt a renewal without login', (
    tester,
  ) async {
    final server = _Server();
    final client = server.client();
    await client.refresh();
    final originalFence = client.authorityFence;
    final previousExpiry = client.user!.expiresAt;
    server.expiry = previousExpiry.add(const Duration(minutes: 30));

    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    expect(server.sessionReads, 2);
    expect(client.user?.expiresAt, server.expiry);
    expect(client.authorityFence, originalFence);
    expect(server.loginRequests, 0);
    client.dispose();
  });

  test('confirmed logout stays signed out after a controller reopen', () async {
    final server = _Server();
    final client = server.client();
    await client.refresh();
    await client.signOut();
    expect(client.user, isNull);
    expect(client.logoutUnconfirmed, isFalse);
    client.dispose();

    final reopened = server.client();
    addTearDown(reopened.dispose);
    await reopened.refresh();
    expect(reopened.user, isNull);
    expect(server.logoutRequests, 1);
    expect(server.loginRequests, 0);
  });

  test('unconfirmed logout remains fenced after a controller reopen', () async {
    final server = _Server()..failLogout = true;
    final client = server.client();
    await client.refresh();
    await expectLater(client.signOut(), throwsA(isA<AdminAccountException>()));
    expect(client.logoutUnconfirmed, isTrue);
    client.dispose();

    final reopened = server.client();
    addTearDown(reopened.dispose);
    await reopened.refresh();
    expect(reopened.user, isNull);
    expect(reopened.logoutUnconfirmed, isTrue);
    expect(server.logoutIntents.readPending(), hasLength(1));
    expect(server.loginRequests, 0);
  });

  test(
    'logout from an unavailable session remains fenced after reopen',
    () async {
      final server = _Server();
      final client = server.client();
      await client.refresh();
      server.available = false;
      await client.refresh();
      expect(client.user, isNull);
      server.available = true;
      server.failLogout = true;
      await expectLater(
        client.signOut(),
        throwsA(isA<AdminAccountException>()),
      );
      client.dispose();

      expect(server.logoutIntents.readPending(), hasLength(1));
      final reopened = server.client();
      addTearDown(reopened.dispose);
      await reopened.refresh();
      expect(reopened.user, isNull);
      expect(reopened.logoutUnconfirmed, isTrue);
    },
  );

  test(
    'retry after reopening revokes only the original cookie session',
    () async {
      final server = _Server()..failLogout = true;
      final client = server.client();
      await client.refresh();
      await expectLater(
        client.signOut(),
        throwsA(isA<AdminAccountException>()),
      );
      client.dispose();

      final marker = server.logoutIntents.readPending().single;
      expect(marker, matches(r'^[0-9a-f]{64}$'));
      expect(marker, isNot(contains(_publicSession)));
      server.failLogout = false;
      final reopened = server.client();
      addTearDown(reopened.dispose);
      await reopened.signOut();
      expect(reopened.user, isNull);
      expect(reopened.logoutUnconfirmed, isFalse);
      expect(server.signedIn, isFalse);
      expect(server.logoutIntents.readPending(), isEmpty);
      expect(server.logoutRequests, 2);
    },
  );

  test('retry never signs out a different current session', () async {
    final server = _Server()..failLogout = true;
    final client = server.client();
    await client.refresh();
    await expectLater(client.signOut(), throwsA(isA<AdminAccountException>()));
    client.dispose();

    server.failLogout = false;
    server.publicSession = '00000000-0000-4000-8000-000000000099';
    final reopened = server.client();
    addTearDown(reopened.dispose);
    await expectLater(
      reopened.signOut(),
      throwsA(isA<AdminAccountSecurityOutcomeUnknown>()),
    );
    expect(server.signedIn, isTrue);
    expect(server.logoutRequests, 1);
    expect(server.logoutIntents.readPending(), hasLength(1));
    expect(reopened.logoutUnconfirmed, isTrue);
  });

  test(
    'a cookie change after the retry read cannot revoke the newer session',
    () async {
      final server = _Server()..failLogout = true;
      final client = server.client();
      await client.refresh();
      await expectLater(
        client.signOut(),
        throwsA(isA<AdminAccountException>()),
      );
      client.dispose();

      server.failLogout = false;
      server.afterSessionRead = () {
        server.publicSession = '00000000-0000-4000-8000-000000000099';
        server.csrf = 'b' * 64;
      };
      final reopened = server.client();
      addTearDown(reopened.dispose);
      await expectLater(
        reopened.signOut(),
        throwsA(isA<AdminAccountException>()),
      );
      expect(server.signedIn, isTrue);
      expect(server.logoutIntents.readPending(), hasLength(1));
      expect(reopened.logoutUnconfirmed, isTrue);
    },
  );

  test('unreadable intent storage cannot silently restore a session', () async {
    final server = _Server();
    final storage = _FailingStorage()..failRead = true;
    final client = server.client(storage: storage);
    addTearDown(client.dispose);
    await client.refresh();
    expect(client.user, isNull);
    expect(client.logoutUnconfirmed, isTrue);
    expect(server.sessionReads, 0);
  });

  test('a failed intent write does not dispatch logout', () async {
    final server = _Server();
    final storage = _FailingStorage()..failAdd = true;
    final client = server.client(storage: storage);
    addTearDown(client.dispose);
    await client.refresh();
    await expectLater(client.signOut(), throwsA(isA<StateError>()));
    expect(client.logoutUnconfirmed, isTrue);
    expect(server.logoutRequests, 0);
    expect(server.signedIn, isTrue);
  });

  test('a confirmed absent cookie resolves a pending local sign-out', () async {
    final server = _Server()..failLogout = true;
    final client = server.client();
    await client.refresh();
    await expectLater(client.signOut(), throwsA(isA<AdminAccountException>()));
    client.dispose();

    server.signedIn = false;
    final reopened = server.client();
    addTearDown(reopened.dispose);
    await reopened.signOut();
    expect(reopened.logoutUnconfirmed, isFalse);
    expect(server.logoutIntents.readPending(), isEmpty);
    expect(server.logoutRequests, 1);
  });

  test(
    'another tab fences an in-flight response when logout is pending',
    () async {
      final server = _Server()..pendingRead = Completer<http.Response>();
      final first = server.client();
      final second = server.client();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.refresh();
      await second.refresh();
      final staleRead = second.request('fixture/read', authenticated: true);
      await Future<void>.delayed(Duration.zero);
      server.failLogout = true;
      await expectLater(first.signOut(), throwsA(isA<AdminAccountException>()));
      server.pendingRead!.complete(_json({'ok': true}));
      await expectLater(staleRead, throwsA(isA<AdminAccountException>()));
      expect(second.logoutUnconfirmed, isTrue);
      expect(second.user, isNull);
    },
  );

  test('another tab fences an in-flight retained-evidence response', () async {
    const raw = 'synthetic evidence';
    final server = _Server()
      ..permissions = ['overview.read', 'payments.evidence.read']
      ..pendingRead = Completer<http.Response>();
    final first = server.client();
    final second = server.client();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await first.refresh();
    await second.refresh();
    final staleRead = second.retainedEvidence(
      '00000000-0000-4000-8000-000000000022',
      sha256Hex: sha256.convert(utf8.encode(raw)).toString(),
      sizeBytes: utf8.encode(raw).length,
      sourceSensitivity: 'ordinary',
    );
    await Future<void>.delayed(Duration.zero);
    server.failLogout = true;
    await expectLater(first.signOut(), throwsA(isA<AdminAccountException>()));
    server.pendingRead!.complete(
      http.Response(
        raw,
        200,
        headers: {
          'content-type': 'text/plain',
          'x-collect-evidence-sensitivity': 'ordinary',
        },
      ),
    );
    await expectLater(staleRead, throwsA(isA<AdminAccountException>()));
    expect(second.logoutUnconfirmed, isTrue);
  });

  test(
    'a late logout marker prevents refreshed authority from being installed',
    () async {
      final server = _Server();
      final first = server.client();
      final interleaving = _InterleavingStorage(server.logoutIntents);
      final second = server.client(storage: interleaving);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.refresh();
      await second.refresh();
      server.failLogout = true;
      Future<void>? failedLogout;
      interleaving.afterFourthRead = () {
        failedLogout = expectLater(
          first.signOut(),
          throwsA(isA<AdminAccountException>()),
        );
      };
      await second.refresh();
      expect(interleaving.reads, greaterThanOrEqualTo(4));
      expect(failedLogout, isNotNull);
      await failedLogout;
      expect(second.user, isNull);
      expect(second.logoutUnconfirmed, isTrue);
    },
  );

  test(
    'role revocation fences a delayed response from the prior authority',
    () async {
      final server = _Server()..pendingRead = Completer<http.Response>();
      final client = server.client();
      addTearDown(client.dispose);
      await client.refresh();
      final oldFence = client.authorityFence;
      final oldRead = client.request('fixture/read', authenticated: true);
      await Future<void>.delayed(Duration.zero);

      server.role = 'staff';
      server.permissions = ['overview.read'];
      await client.refresh();
      expect(client.user?.role, AdminAccountRole.staff);
      expect(client.authorityFence, isNot(oldFence));
      server.pendingRead!.complete(_json({'ok': true}));
      await expectLater(oldRead, throwsA(isA<AdminAccountException>()));
    },
  );

  test('a revoked server session is not restored', () async {
    final server = _Server();
    final client = server.client();
    addTearDown(client.dispose);
    await client.refresh();
    final oldFence = client.authorityFence;
    server.signedIn = false;
    await client.refresh();
    expect(client.user, isNull);
    expect(client.authorityFence, isNot(oldFence));
    expect(server.loginRequests, 0);
  });

  testWidgets('temporary session outage retries without a new login', (
    tester,
  ) async {
    final server = _Server();
    final client = server.client();
    await client.refresh();
    server.available = false;
    await client.refresh();
    expect(client.state.hasError, isTrue);
    server.available = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(client.user?.id, _adminId);
    expect(server.loginRequests, 0);
    client.dispose();
  });
}
