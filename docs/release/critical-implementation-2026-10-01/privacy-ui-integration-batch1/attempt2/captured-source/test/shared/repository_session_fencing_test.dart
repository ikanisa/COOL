import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _a = '10000000-0000-0000-0000-000000000001';
const _b = '10000000-0000-0000-0000-000000000002';
const _s1 = '20000000-0000-0000-0000-000000000001';
const _s2 = '20000000-0000-0000-0000-000000000002';
const _s3 = '20000000-0000-0000-0000-000000000003';
const _oldToken = 'fcm-synthetic-original-token';
const _newToken = 'fcm-synthetic-newer-token';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final nextUser in [_b, _a]) {
    test(
      'late registration cannot replace ${nextUser == _a ? 'same-user new-session' : 'B'} bookkeeping',
      () async {
        final pending = _HttpBarrier();
        final h = await _Harness.create((request) {
          if (_rpc(request, 'register_notification_device') &&
              _body(request)['p_token'] == _oldToken) {
            return pending.hold();
          }
          return _ok(request);
        });
        final original = h.register(_oldToken);
        await pending.entered.future;
        expect(_bearer(h.requests.last), _jwt(_a, _s1));
        await h.login(nextUser, _s2);
        await h.register(_newToken);
        pending.release.complete(
          _json('"30000000-0000-0000-0000-000000000001"'),
        );
        await original;
        await h.repo.signOut();
        final unregister = h.requests
            .where((r) => _rpc(r, 'unregister_notification_device'))
            .toList();
        expect(unregister.map((r) => _body(r)['p_token']), [
          _oldToken,
          _newToken,
        ]);
        expect(unregister.map(_bearer), [_jwt(_a, _s1), _jwt(nextUser, _s2)]);
        expect(h.logoutRequests.single.url.queryParameters['scope'], 'local');
      },
    );
  }

  for (final reply in ['null', '7', '{}', '[]', '"not-a-uuid"', '""']) {
    test(
      'malformed registration acknowledgement $reply cannot become connected',
      () async {
        final h = await _Harness.create(
          (r) =>
              _rpc(r, 'register_notification_device') ? _json(reply) : _ok(r),
        );
        await expectLater(h.register(_oldToken), throwsStateError);
        expect(
          h.repo.isNotificationDeviceRegistered(
            provider: 'fcm',
            token: _oldToken,
          ),
          isFalse,
        );
        await h.repo.signOut();
        expect(
          h.requests.where((r) => _rpc(r, 'unregister_notification_device')),
          isEmpty,
        );
      },
    );
  }

  test(
    'acknowledged tuple becomes unconnected before a pending sign-out finishes',
    () async {
      final pending = _HttpBarrier();
      final h = await _Harness.create(
        (r) =>
            _rpc(r, 'unregister_notification_device') ? pending.hold() : _ok(r),
      );
      await h.register(_oldToken);
      expect(
        h.repo.isNotificationDeviceRegistered(
          provider: 'fcm',
          token: _oldToken,
        ),
        isTrue,
      );
      final logout = h.repo.signOut();
      await pending.entered.future;
      expect(
        h.repo.isNotificationDeviceRegistered(
          provider: 'fcm',
          token: _oldToken,
        ),
        isFalse,
      );
      pending.release.complete(_json('null'));
      await logout;
    },
  );

  test(
    'same-session token refresh preserves current registration but pins request authorization',
    () async {
      final pending = _HttpBarrier();
      final h = await _Harness.create(
        (r) =>
            _rpc(r, 'register_notification_device') ? pending.hold() : _ok(r),
      );
      final registration = h.register(_newToken);
      await pending.entered.future;
      await h.client.auth.setInitialSession(_session(_a, _s1, revision: 2));
      pending.release.complete(_json('"30000000-0000-0000-0000-000000000001"'));
      await registration;
      expect(h.repo.state.currentProfile?.id, _a);
      await h.repo.signOut();
      expect(_bearer(h.requests.first), _jwt(_a, _s1));
      final unregister = h.requests
          .where((r) => _rpc(r, 'unregister_notification_device'))
          .single;
      expect(_body(unregister)['p_token'], _newToken);
      expect(_bearer(unregister), _jwt(_a, _s1, revision: 2));
    },
  );

  test(
    'late same-device registration cleanup uses original session only',
    () async {
      final pending = _HttpBarrier();
      String? deviceOwner;
      final h = await _Harness.create((r) {
        if (_rpc(r, 'register_notification_device')) {
          if (_bearer(r) == _jwt(_a, _s1)) return pending.hold();
          deviceOwner = _bearer(r);
        }
        if (_rpc(r, 'unregister_notification_device') &&
            deviceOwner == _bearer(r)) {
          deviceOwner = null;
        }
        return _ok(r);
      });
      final original = h.register(_oldToken);
      await pending.entered.future;
      await h.login(_b, _s2);
      await h.register(_oldToken);
      pending.release.complete(_json('"30000000-0000-0000-0000-000000000001"'));
      await original;
      await h.expectCurrent(_b, _s2);
      expect(deviceOwner, _jwt(_b, _s2));
      final cleanup = h.requests
          .where((r) => _rpc(r, 'unregister_notification_device'))
          .single;
      expect(_bearer(cleanup), _jwt(_a, _s1));
      expect(_body(cleanup)['p_token'], _oldToken);
      await h.repo.signOut();
      expect(deviceOwner, isNull);
    },
  );

  test(
    'current stale-session registration error requests a fresh login',
    () async {
      final h = await _Harness.create(
        (r) => _rpc(r, 'register_notification_device')
            ? _json(
                '{"message":"notification_registration_session_stale","code":"42501"}',
                status: 403,
              )
            : _ok(r),
      );
      await expectLater(
        h.register(_oldToken),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Sign in again to register notifications on this device.',
          ),
        ),
      );
      expect(
        h.repo.state.lastError,
        'Sign in again to register notifications on this device.',
      );
      expect(h.client.auth.currentSession?.accessToken, _jwt(_a, _s1));
      await h.repo.signOut();
      expect(
        h.requests.where((r) => _rpc(r, 'unregister_notification_device')),
        isEmpty,
      );
    },
  );

  test(
    'late stale-session rejection does not change newer account error state',
    () async {
      final pending = _HttpBarrier();
      final h = await _Harness.create(
        (r) =>
            _rpc(r, 'register_notification_device') &&
                _bearer(r) == _jwt(_a, _s1)
            ? pending.hold()
            : _ok(r),
      );
      final original = h.register(_oldToken);
      await pending.entered.future;
      await h.login(_b, _s2);
      await h.register(_newToken);
      pending.release.complete(
        _json(
          '{"message":"notification_registration_session_stale","code":"42501"}',
          status: 403,
        ),
      );
      await original;
      await h.expectCurrent(_b, _s2);
      expect(h.repo.state.lastError, isNull);
      await h.repo.signOut();
      expect(
        _body(
          h.requests
              .where((r) => _rpc(r, 'unregister_notification_device'))
              .single,
        )['p_token'],
        _newToken,
      );
    },
  );

  test(
    'failed stale registration cleanup cannot affect the newer login',
    () async {
      final pending = _HttpBarrier();
      final h = await _Harness.create((r) {
        if (_rpc(r, 'register_notification_device') &&
            _bearer(r) == _jwt(_a, _s1)) {
          return pending.hold();
        }
        if (_rpc(r, 'unregister_notification_device') &&
            _bearer(r) == _jwt(_a, _s1)) {
          return _json(
            '{"message":"synthetic unavailable","code":"503"}',
            status: 503,
          );
        }
        return _ok(r);
      });
      final original = h.register(_oldToken);
      await pending.entered.future;
      await h.login(_b, _s2);
      await h.register(_newToken);
      final clears = h.cache.clears;
      final nativeCalls = h.sms.calls.length;
      pending.release.complete(_json('"30000000-0000-0000-0000-000000000001"'));
      await original;
      await h.expectCurrent(_b, _s2);
      expect(h.cache.clears, clears);
      expect(h.sms.calls.length, nativeCalls);
      expect(h.repo.state.lastError, isNull);
    },
  );

  test(
    'out-of-order same-session registration cannot overwrite a newer token',
    () async {
      final pending = _HttpBarrier();
      final h = await _Harness.create(
        (r) =>
            _rpc(r, 'register_notification_device') &&
                _body(r)['p_token'] == _oldToken
            ? pending.hold()
            : _ok(r),
      );
      final old = h.register(_oldToken);
      await pending.entered.future;
      await h.register(_newToken);
      pending.release.complete(_json('"30000000-0000-0000-0000-000000000001"'));
      await old;
      await h.repo.signOut();
      expect(
        _body(
          h.requests
              .where((r) => _rpc(r, 'unregister_notification_device'))
              .single,
        )['p_token'],
        _newToken,
      );
    },
  );

  test(
    'registration completing after logout cannot repopulate bookkeeping',
    () async {
      final pending = _HttpBarrier();
      final h = await _Harness.create(
        (r) =>
            _rpc(r, 'register_notification_device') ? pending.hold() : _ok(r),
      );
      final registration = h.register(_oldToken);
      await pending.entered.future;
      await h.repo.signOut();
      expect(h.client.auth.currentSession, isNull);
      pending.release.complete(_json('"30000000-0000-0000-0000-000000000001"'));
      await registration;
      await h.login(_a, _s2);
      await h.repo.signOut();
      expect(
        h.requests
            .where((r) => _rpc(r, 'unregister_notification_device'))
            .map(_bearer),
        [_jwt(_a, _s1)],
      );
      expect(h.logoutRequests.map(_bearer), [_jwt(_a, _s1), _jwt(_a, _s2)]);
    },
  );

  test(
    'new registration is refused while that session is signing out',
    () async {
      final pending = _HttpBarrier();
      final h = await _Harness.create(
        (r) =>
            _rpc(r, 'unregister_notification_device') ? pending.hold() : _ok(r),
      );
      await h.register(_oldToken);
      final logout = h.repo.signOut();
      await pending.entered.future;
      await expectLater(h.register(_newToken), throwsStateError);
      pending.release.complete(_json('null'));
      await logout;
      expect(
        h.requests.where((r) => _rpc(r, 'register_notification_device')),
        hasLength(1),
      );
    },
  );

  for (final nextUser in [_b, _a]) {
    for (final path in [
      'unregister_notification_device',
      'record_sms_access_consent',
    ]) {
      test(
        'old sign-out waiting for $path cannot touch ${nextUser == _a ? 'new same-user session' : 'B'}',
        () async {
          final pending = _HttpBarrier();
          final h = await _Harness.create(
            (r) => _rpc(r, path) ? pending.hold() : _ok(r),
          );
          await h.register(_oldToken);
          final logout = h.repo.signOut();
          await pending.entered.future;
          expect(_bearer(h.requests.last), _jwt(_a, _s1));
          await h.login(nextUser, _s2);
          await h.register(_newToken);
          final clears = h.cache.clears;
          final nativeCalls = h.sms.calls.length;
          pending.release.complete(_json('null'));
          await logout;
          await h.expectCurrent(nextUser, _s2);
          expect(h.cache.clears, clears);
          expect(h.sms.calls.length, nativeCalls);
          expect(h.logoutRequests, hasLength(1));
          expect(_bearer(h.logoutRequests.single), _jwt(_a, _s1));
          expect(h.logoutRequests.single.url.queryParameters['scope'], 'local');
          if (path == 'unregister_notification_device') {
            expect(
              h.requests.where((r) => _rpc(r, 'record_sms_access_consent')),
              isEmpty,
            );
          }
        },
      );
    }
  }

  for (final nextUser in [_b, _a]) {
    test(
      'late GoTrue logout HTTP response cannot clear ${nextUser == _a ? 'same-user new session' : 'B'}',
      () async {
        final pending = _HttpBarrier();
        final h = await _Harness.create(
          (r) => r.url.path.endsWith('/logout') ? pending.hold() : _ok(r),
        );
        final logout = h.repo.signOut();
        await pending.entered.future;
        expect(h.client.auth.currentSession, isNull);
        await h.login(nextUser, _s2);
        final clears = h.cache.clears;
        pending.release.complete(http.Response('', 204));
        await logout;
        await h.expectCurrent(nextUser, _s2);
        expect(h.cache.clears, clears);
        expect(_bearer(h.logoutRequests.single), _jwt(_a, _s1));
        expect(h.logoutRequests.single.url.queryParameters['scope'], 'local');
      },
    );
  }

  test(
    'GoTrue PKCE storage await cannot make repository clear a newer login',
    () async {
      final storage = _PkceStorageBarrier();
      final h = await _Harness.create(_ok, storage: storage);
      final logout = h.repo.signOut();
      await storage.entered.future;
      expect(h.client.auth.currentSession, isNull);
      await h.login(_b, _s2);
      final clears = h.cache.clears;
      storage.release.complete();
      await logout;
      await h.expectCurrent(_b, _s2);
      expect(h.cache.clears, clears);
      expect(_bearer(h.logoutRequests.single), _jwt(_a, _s1));
    },
  );

  test(
    'failed old cleanup RPC cannot trigger native/cache fallback against B',
    () async {
      final pending = _HttpBarrier();
      final h = await _Harness.create(
        (r) => _rpc(r, 'record_sms_access_consent') ? pending.hold() : _ok(r),
      );
      final logout = h.repo.signOut();
      await pending.entered.future;
      await h.login(_b, _s2);
      final clears = h.cache.clears;
      final nativeCalls = h.sms.calls.length;
      pending.release.complete(
        _json('{"message":"synthetic unavailable","code":"503"}', status: 503),
      );
      await logout;
      await h.expectCurrent(_b, _s2);
      expect(h.cache.clears, clears);
      expect(h.sms.calls.length, nativeCalls);
    },
  );

  test(
    'best-effort unregister/consent failures still use local session revocation',
    () async {
      final h = await _Harness.create((r) {
        if (_rpc(r, 'unregister_notification_device') ||
            _rpc(r, 'record_sms_access_consent')) {
          return _json(
            '{"message":"synthetic unavailable","code":"503"}',
            status: 503,
          );
        }
        return _ok(r);
      });
      await h.register(_oldToken);
      await h.repo.signOut();
      expect(h.client.auth.currentSession, isNull);
      expect(h.repo.state.currentProfile, isNull);
      expect(h.sms.enabled, isFalse);
      expect(h.logoutRequests.single.url.queryParameters['scope'], 'local');
    },
  );

  test(
    'native disable failure fails closed without revoking or clearing current account',
    () async {
      final h = await _Harness.create(_ok);
      h.sms.failDisable = true;
      await expectLater(h.repo.signOut(), throwsStateError);
      expect(h.client.auth.currentUser?.id, _a);
      expect(h.repo.state.currentProfile?.id, _a);
      expect(h.cache.clears, 0);
      expect(h.requests, isEmpty);
      expect(h.sms.enabled, isTrue);
    },
  );

  test(
    'cache cleanup failure is reported and cannot restore stale data',
    () async {
      final h = await _Harness.create(_ok);
      h.cache.failClear = true;
      await expectLater(h.repo.signOut(), throwsStateError);
      expect(h.client.auth.currentUser?.id, _a);
      expect(h.sms.enabled, isFalse);
      expect(h.logoutRequests, isEmpty);
      expect(
        await h.repo.restoreOfflineSnapshot(reason: 'synthetic offline'),
        isFalse,
      );
      h.cache.failClear = false;
      await h.repo.signOut();
      expect(h.client.auth.currentSession, isNull);
    },
  );

  test(
    'late native disable completion does not re-disable a new session',
    () async {
      final h = await _Harness.create(_ok);
      h.sms.disableReply = Completer<bool>();
      final logout = h.repo.signOut();
      await h.sms.disableStarted.future;
      await h.login(_b, _s2);
      final nativeCalls = h.sms.calls.length;
      h.sms.disableReply!.complete(true);
      await logout;
      await h.expectCurrent(_b, _s2);
      expect(h.sms.calls.length, nativeCalls);
    },
  );

  test(
    'late auth-change cleanup cannot clear a later session cache or state',
    () async {
      final h = await _Harness.create(_ok);
      h.sms.delayedSuspendOwner = _b;
      h.sms.suspendReply = Completer<bool>();
      await h.client.auth.setInitialSession(_session(_b, _s2));
      await h.sms.suspendStarted.future;
      await h.login(_a, _s3);
      final clears = h.cache.clears;
      h.sms.suspendReply!.complete(false);
      await Future<void>.delayed(Duration.zero);
      await h.expectCurrent(_a, _s3);
      expect(h.cache.clears, clears);
      expect(h.repo.state.smsSyncNeedsAttention, isFalse);
    },
  );

  test('disposed repository ignores late registration completion', () async {
    final pending = _HttpBarrier();
    final h = await _Harness.create(
      (r) => _rpc(r, 'register_notification_device') ? pending.hold() : _ok(r),
    );
    final registration = h.register(_oldToken);
    await pending.entered.future;
    h.repo.dispose();
    h.disposed = true;
    pending.release.complete(_json('"30000000-0000-0000-0000-000000000001"'));
    await registration;
    expect(h.requests, hasLength(1));
  });
}

typedef _Responder = FutureOr<http.Response> Function(http.Request);

class _Harness {
  _Harness(this.client, this.repo, this.sms, this.cache, this.requests);
  final SupabaseClient client;
  final _Repository repo;
  final _Sms sms;
  final _Cache cache;
  final List<http.Request> requests;
  bool disposed = false;
  Iterable<http.Request> get logoutRequests =>
      requests.where((r) => r.url.path.endsWith('/logout'));

  static Future<_Harness> create(
    _Responder respond, {
    GotrueAsyncStorage? storage,
  }) async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'http://127.0.0.1:1',
      'synthetic-anon-key',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: storage,
      ),
      httpClient: MockClient((r) async {
        requests.add(r);
        final response = await respond(r);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: r,
        );
      }),
    );
    await client.auth.setInitialSession(_session(_a, _s1));
    final sms = _Sms(), cache = _Cache();
    final repo = _Repository(client, sms, cache);
    final h = _Harness(client, repo, sms, cache, requests);
    await repo.saveSnapshot();
    addTearDown(() async {
      if (!h.disposed) repo.dispose();
      await client.dispose();
    });
    return h;
  }

  Future<void> register(String token) => repo.registerNotificationDevice(
    platform: 'android',
    provider: 'fcm',
    token: token,
    environment: 'production',
  );
  Future<void> login(String user, String session) async {
    final loaded = Completer<void>();
    repo.nextLoad = loaded;
    await client.auth.setInitialSession(_session(user, session));
    await loaded.future.timeout(const Duration(seconds: 3));
    sms.owner = user;
    sms.enabled = true;
  }

  Future<void> expectCurrent(String user, String session) async {
    expect(client.auth.currentUser?.id, user);
    expect(client.auth.currentSession?.accessToken, _jwt(user, session));
    expect(repo.state.currentProfile?.id, user);
    expect((await cache.read(ownerUserId: user))?.currentProfile?.id, user);
    expect(sms.owner, user);
    expect(sms.enabled, isTrue);
  }
}

class _Repository extends CollectRepository {
  _Repository(this.client, _Sms sms, this.cache)
    : super.fixture(
        initialState: CollectState(
          currentProfile: _profile(_a),
          collections: const [],
          paymentIntents: const [],
          contributions: const [],
        ),
        supabase: client,
        smsAccessChannel: sms,
        offlineCache: cache,
      );
  final SupabaseClient client;
  final _Cache cache;
  Completer<void>? nextLoad;
  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    state = state.copyWith(
      currentProfile: _profile(client.auth.currentUser!.id),
    );
    await saveSnapshot();
    final ready = nextLoad;
    nextLoad = null;
    ready?.complete();
  }

  Future<void> saveSnapshot() => cache.save(
    CollectOfflineSnapshot(
      savedAt: DateTime.utc(2026, 9, 30),
      currentProfile: state.currentProfile,
      collections: const [],
      paymentIntents: const [],
      contributions: const [],
    ),
  );
}

class _Cache extends CollectOfflineCache {
  int clears = 0;
  bool failClear = false;
  @override
  Future<void> clear() {
    clears++;
    if (failClear) return Future.error(StateError('synthetic cache failure'));
    return super.clear();
  }
}

class _Sms extends SmsAccessChannel {
  String owner = _a;
  bool enabled = true, failDisable = false;
  final List<String> calls = [];
  Completer<bool>? disableReply, suspendReply;
  final disableStarted = Completer<void>(), suspendStarted = Completer<void>();
  String? delayedSuspendOwner;
  @override
  Future<bool> setEnabled(bool value, {String? ownerUserId}) {
    calls.add('set:$ownerUserId:$value');
    if (!disableStarted.isCompleted) disableStarted.complete();
    if (failDisable || ownerUserId != owner) return Future.value(false);
    enabled = value;
    return disableReply?.future ?? Future.value(true);
  }

  @override
  Future<bool> suspendUnlessOwner(String? user) {
    calls.add('suspend:$user');
    if (user != owner) enabled = false;
    if (user == delayedSuspendOwner && suspendReply != null) {
      if (!suspendStarted.isCompleted) suspendStarted.complete();
      return suspendReply!.future;
    }
    return Future.value(true);
  }

  @override
  Future<SmsAccessStatus> status() async => SmsAccessStatus(
    supported: true,
    declared: true,
    enabled: enabled,
    consentEnabled: enabled,
    granted: true,
    requestedBefore: true,
    shouldShowRationale: false,
    permanentlyDenied: false,
    queueOverflowed: false,
  );
}

class _PkceStorageBarrier extends GotrueAsyncStorage {
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<String?> getItem({required String key}) async => null;
  @override
  Future<void> setItem({required String key, required String value}) async {}
  @override
  Future<void> removeItem({required String key}) {
    if (!entered.isCompleted) entered.complete();
    return release.future;
  }
}

class _HttpBarrier {
  final entered = Completer<void>();
  final release = Completer<http.Response>();
  Future<http.Response> hold() {
    if (!entered.isCompleted) entered.complete();
    return release.future;
  }
}

bool _rpc(http.Request r, String name) => r.url.path == '/rest/v1/rpc/$name';
Map<String, dynamic> _body(http.Request r) =>
    jsonDecode(r.body) as Map<String, dynamic>;
String _bearer(http.Request r) => r.headers['authorization']!.substring(7);
http.Response _json(String body, {int status = 200}) =>
    http.Response(body, status, headers: {'content-type': 'application/json'});
http.Response _ok(http.Request r) => r.url.path.endsWith('/logout')
    ? http.Response('', 204)
    : _json(
        _rpc(r, 'register_notification_device')
            ? '"30000000-0000-0000-0000-000000000001"'
            : 'null',
      );
CollectProfile _profile(String user) => CollectProfile(
  id: user,
  publicId: user == _a ? '123456' : '234567',
  whatsappPhone: '+250788123456',
  countryCode: 'RW',
  currencyCode: 'RWF',
  momoProvider: 'mtn_momo',
  momoNumber: '0788123456',
);
String _jwt(String user, String session, {int revision = 1}) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': user, 'session_id': session, 'role': 'authenticated', 'revision': revision, 'exp': 4102444800})}.synthetic';
}

String _session(String user, String session, {int revision = 1}) => jsonEncode({
  'access_token': _jwt(user, session, revision: revision),
  'refresh_token': 'refresh-$session-$revision',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': user,
    'aud': 'authenticated',
    'app_metadata': <String, Object?>{},
    'user_metadata': <String, Object?>{},
    'created_at': '2026-09-01T00:00:00Z',
  },
});
