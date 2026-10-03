import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_roster_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/admin_read_fixture.dart';

const _sidA = '99740000-0000-4000-8000-000000000011';
const _sidB = '99740000-0000-4000-8000-000000000012';
Map<String, dynamic> _auth({
  String actor = adminReadActor,
  String sid = _sidA,
  Object? exp,
  String nonce = '0',
}) => {
  'access_token':
      'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': actor, 'session_id': sid, 'exp': exp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.$nonce',
  'refresh_token': 'synthetic-refresh',
  'token_type': 'bearer',
  'user': {
    'id': actor,
    'aud': 'authenticated',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': adminReadDate,
  },
};

class _Auth extends Fake implements GoTrueClient {
  _Auth(this.currentSession, this.onAuthStateChange);
  @override
  Session? currentSession;
  @override
  final Stream<AuthState> onAuthStateChange;
}

class _Client extends Fake implements SupabaseClient {
  _Client(this.auth);
  @override
  final _Auth auth;
}

http.Response _json(Object? value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  for (final exp in <Object?>['future', true, -1, 9007199254740991]) {
    test('gateway rejects malformed or unbounded expiry $exp', () {
      final events = StreamController<AuthState>.broadcast(sync: true);
      final client = _Client(
        _Auth(Session.fromJson(_auth(exp: exp)), events.stream),
      );
      addTearDown(events.close);
      expect(() => SupabaseAdminRosterGateway(client), throwsStateError);
    });
  }
  test('gateway rejects SDK expiry even when JWT expiry is later', () {
    final events = StreamController<AuthState>.broadcast(sync: true);
    final session = Session.fromJson(_auth())!
      ..expiresAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1;
    final client = _Client(_Auth(session, events.stream));
    addTearDown(events.close);
    expect(() => SupabaseAdminRosterGateway(client), throwsStateError);
  });
  test(
    'real expiry timer invalidates draft lease without an Auth event and never revives',
    () async {
      final events = StreamController<AuthState>.broadcast(sync: true);
      final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2;
      final auth = _Auth(Session.fromJson(_auth(exp: expiry)), events.stream);
      final gateway = SupabaseAdminRosterGateway(_Client(auth));
      addTearDown(() {
        gateway.dispose();
        return events.close();
      });
      final invalidated = Completer<void>();
      final sub = gateway.invalidations.listen((_) {
        if (!invalidated.isCompleted) invalidated.complete();
      });
      addTearDown(sub.cancel);
      await invalidated.future.timeout(const Duration(seconds: 4));
      expect(gateway.ownerStillCurrent, isFalse);
      auth.currentSession = Session.fromJson(_auth(nonce: 'newer'));
      events.add(
        AuthState(AuthChangeEvent.tokenRefreshed, auth.currentSession),
      );
      expect(gateway.isCurrent, isFalse);
      await expectLater(gateway.read(adminReadTarget), throwsStateError);
    },
  );
  for (final signal in ['genuine', 'broadcast', 'error', 'done', 'expired']) {
    test(
      '$signal Auth invalidation denies gateway and request scope permanently',
      () async {
        final events = StreamController<AuthState>.broadcast(sync: true);
        final auth = _Auth(Session.fromJson(_auth()), events.stream);
        final sdk = _Client(auth);
        final gateway = SupabaseAdminRosterGateway(sdk),
            fence = AdminRequestSession(sdk);
        final controller = AdminSessionController(sdk);
        addTearDown(() async {
          gateway.dispose();
          controller.dispose();
          await fence.dispose();
          if (!events.isClosed) await events.close();
        });
        switch (signal) {
          case 'genuine':
            auth.currentSession = null;
            events.add(const AuthState(AuthChangeEvent.signedOut, null));
          case 'broadcast':
            events.add(
              AuthState(
                AuthChangeEvent.signedOut,
                auth.currentSession,
                fromBroadcast: true,
                signOutReason: SignOutReason.userInitiated,
              ),
            );
          case 'error':
            events.addError(StateError('synthetic private Auth error'));
          case 'done':
            await events.close();
          default:
            auth.currentSession = Session.fromJson(
              _auth(exp: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1),
            );
            events.add(
              AuthState(AuthChangeEvent.tokenRefreshed, auth.currentSession),
            );
        }
        expect(controller.state, isNull);
        expect(gateway.isCurrent, isFalse);
        expect(fence.checkCurrent, throwsA(isA<AdminSessionChanged>()));
        if (!events.isClosed) {
          auth.currentSession = Session.fromJson(_auth());
          // A late local signedOut cannot recover a null controller scope.
          events.add(
            AuthState(
              AuthChangeEvent.signedOut,
              auth.currentSession,
              signOutReason: SignOutReason.userInitiated,
            ),
          );
          expect(controller.state, isNull);
          expect(fence.checkCurrent, throwsA(isA<AdminSessionChanged>()));
          expect(gateway.isCurrent, isFalse);
        }
      },
    );
  }
  test(
    'mismatched userInitiated signedOut cannot preserve a current request',
    () async {
      final events = StreamController<AuthState>.broadcast(sync: true);
      final auth = _Auth(Session.fromJson(_auth()), events.stream);
      final client = _Client(auth);
      final fence = AdminRequestSession(client),
          controller = AdminSessionController(client);
      addTearDown(() async {
        controller.dispose();
        await fence.dispose();
        await events.close();
      });
      events.add(
        AuthState(
          AuthChangeEvent.signedOut,
          Session.fromJson(_auth(nonce: 'other')),
          signOutReason: SignOutReason.userInitiated,
        ),
      );
      expect(controller.state, isNull);
      expect(fence.checkCurrent, throwsA(isA<AdminSessionChanged>()));
    },
  );
  test(
    'controller changes generation after A-B-A and fresh SID, preserving sticky old fences',
    () async {
      final events = StreamController<AuthState>.broadcast(sync: true);
      final auth = _Auth(Session.fromJson(_auth()), events.stream);
      final client = _Client(auth);
      final controller = AdminSessionController(client),
          fence = AdminRequestSession(client);
      addTearDown(() async {
        controller.dispose();
        await fence.dispose();
        await events.close();
      });
      final before = controller.state!.generation;
      for (final receipt in [
        _auth(actor: adminReadTarget, sid: _sidB),
        _auth(nonce: 'back'),
        _auth(sid: _sidB),
      ]) {
        auth.currentSession = Session.fromJson(receipt);
        events.add(AuthState(AuthChangeEvent.signedIn, auth.currentSession));
      }
      expect(controller.state!.generation, before + 3);
      expect(fence.checkCurrent, throwsA(isA<AdminSessionChanged>()));
    },
  );

  group('actual SDK dispatch and awaited expiry', () {
    late SupabaseClient client;
    late List<http.Request> requests;
    late FutureOr<http.Response> Function(http.Request) respond;
    late Map<String, dynamic> nextAuth;
    Future<void> login(Map<String, dynamic> receipt) async {
      nextAuth = receipt;
      await client.auth.verifyOTP(
        phone: '+250788974001',
        token: 'synthetic',
        type: OtpType.sms,
      );
    }

    setUp(() async {
      requests = [];
      respond = (_) => _json({});
      client = SupabaseClient(
        'http://127.0.0.1:1',
        'synthetic-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((r) async {
          if (r.url.path.endsWith('/verify')) return _json(nextAuth);
          requests.add(r);
          final result = await respond(r);
          return http.Response.bytes(
            result.bodyBytes,
            result.statusCode,
            headers: result.headers,
            request: r,
          );
        }),
      );
      await login(_auth());
    });
    tearDown(() => client.dispose());
    for (final operation in [
      'prepare',
      'review',
      'commit',
      'read',
      'recovery',
    ]) {
      test(
        '$operation pins token and suppresses same-owner A-B-A late acknowledgement',
        () async {
          final gateway = SupabaseAdminRosterGateway(client);
          addTearDown(gateway.dispose);
          final started = Completer<void>(), release = Completer<void>();
          respond = (_) async {
            started.complete();
            await release.future;
            return _json({});
          };
          final token = client.auth.currentSession!.accessToken;
          final pending = switch (operation) {
            'prepare' => gateway.prepare({}),
            'review' => gateway.review({}),
            'commit' => gateway.commit({}),
            'read' => gateway.read(adminReadTarget),
            _ => gateway.recoveryRpc('admin_recover_roster_import', {}),
          };
          final assertion = expectLater(pending, throwsStateError);
          await started.future;
          await login(_auth(sid: _sidB));
          await login(_auth(nonce: 'back'));
          release.complete();
          await assertion;
          expect(requests.single.headers['Authorization'], 'Bearer $token');
          expect(gateway.isCurrent, isFalse);
        },
      );
    }
    test(
      'same-SID refresh while live preserves pinned request and updates later dispatch',
      () async {
        final gateway = SupabaseAdminRosterGateway(client);
        addTearDown(gateway.dispose);
        final started = Completer<void>(), release = Completer<void>();
        respond = (_) async {
          if (!started.isCompleted) {
            started.complete();
            await release.future;
          }
          return _json({});
        };
        final token = client.auth.currentSession!.accessToken;
        final pending = gateway.read(adminReadTarget);
        await started.future;
        await login(_auth(nonce: 'refresh'));
        release.complete();
        await pending;
        expect(requests.first.headers['Authorization'], 'Bearer $token');
        await gateway.read(adminReadTarget);
        expect(
          requests.last.headers['Authorization'],
          'Bearer ${client.auth.currentSession!.accessToken}',
        );
      },
    );
    for (final error in [false, true]) {
      test(
        'actual awaited response error=$error after expiry is suppressed',
        () async {
          final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2;
          await login(_auth(exp: expiry));
          final gateway = SupabaseAdminRosterGateway(client);
          addTearDown(gateway.dispose);
          final started = Completer<void>(), release = Completer<void>();
          respond = (_) async {
            started.complete();
            await release.future;
            return error
                ? _json({
                    'code': '42501',
                    'message': 'synthetic private expired response',
                  }, 403)
                : _json({});
          };
          final assertion = expectLater(
            gateway.read(adminReadTarget),
            throwsStateError,
          );
          await started.future;
          await Future<void>.delayed(
            DateTime.fromMillisecondsSinceEpoch(
                  expiry * 1000,
                ).difference(DateTime.now()) +
                const Duration(milliseconds: 50),
          );
          release.complete();
          await assertion;
          expect(gateway.isCurrent, isFalse);
          expect(requests, hasLength(1));
        },
      );
    }
    test('dispose is idempotent and denies further dispatch', () async {
      final gateway = SupabaseAdminRosterGateway(client);
      gateway.dispose();
      gateway.dispose();
      await expectLater(gateway.read(adminReadTarget), throwsStateError);
      expect(requests, isEmpty);
    });
  });
}
