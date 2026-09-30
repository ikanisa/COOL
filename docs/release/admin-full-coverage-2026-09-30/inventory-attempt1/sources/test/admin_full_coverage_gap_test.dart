import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _a = '99740000-0000-4000-8000-000000000001';
const _b = '99740000-0000-4000-8000-000000000002';
Map<String, dynamic> _identity(String id) => {
  'user_id': id,
  'display_name': 'Synthetic operator',
  'roles': ['admin'],
  'permissions': ['overview.read', 'users.read'],
};
http.Response _json(Object? value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

class _PkceBarrier extends GotrueAsyncStorage {
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

void main() {
  late SupabaseClient client;
  late AdminRepository repository;
  late FutureOr<http.Response> Function(http.Request) respond;
  late List<http.Request> requests;
  SupabaseClient makeClient({GotrueAsyncStorage? storage}) => SupabaseClient(
    'http://127.0.0.1:1',
    'synthetic-anon-key',
    authOptions: AuthClientOptions(
      autoRefreshToken: false,
      pkceAsyncStorage: storage,
    ),
    httpClient: MockClient((r) async {
      if (r.url.path.endsWith('/verify')) {
        final parts = (jsonDecode(r.body)['token'] as String).split('|');
        return _json({
          'access_token':
              'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': parts[0], 'session_id': parts[1], 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
          'refresh_token': 'synthetic-refresh',
          'token_type': 'bearer',
          'user': {
            'id': parts[0],
            'aud': 'authenticated',
            'app_metadata': {},
            'user_metadata': {},
            'created_at': '2026-09-30T00:00:00Z',
          },
        });
      }
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
  Future<void> login(SupabaseClient c, String user, String session) => c.auth
      .verifyOTP(
        phone: '+250788974001',
        token: '$user|$session',
        type: OtpType.sms,
      )
      .then((_) {});
  setUp(() async {
    requests = [];
    respond = (r) => r.url.path.endsWith('/logout')
        ? http.Response('', 204)
        : r.url.path.endsWith('admin_current_user')
        ? _json(_identity(_a))
        : _json({});
    client = makeClient();
    await login(client, _a, 'session-a');
    repository = AdminRepository(client);
  });
  tearDown(() => client.dispose());

  test('bound identity and real not-found detail remain supported', () async {
    expect((await repository.currentIdentity())?.userId, _a);
    expect(await repository.detail('admin_get_user', _b), isEmpty);
  });
  test(
    'GAP-A01 current identity rejects another actor at the repository boundary',
    () async {
      respond = (_) => _json(_identity(_b));
      await expectLater(repository.currentIdentity(), throwsFormatException);
      expect(requests, hasLength(1));
    },
  );
  test('GAP-A02 generic detail rejects a wrong returned record', () async {
    respond = (_) =>
        _json({'id': _b, 'phone_masked': '***0002', 'country_code': 'RW'});
    await expectLater(
      repository.detail('admin_get_user', _a),
      throwsFormatException,
    );
    expect(jsonDecode(requests.single.body)['p_id'], _a);
  });
  test(
    'GAP-A03 malformed overview is not certified as an empty operation set',
    () async {
      respond = (_) => _json({'metrics': null});
      await expectLater(repository.overviewMetrics(), throwsFormatException);
    },
  );
  test(
    'GAP-A04 malformed runtime configuration cannot silently become defaults',
    () async {
      respond = (_) =>
          _json({'navigation_items': 'malformed', 'queue_specs': 7});
      await expectLater(repository.runtimeConfig(), throwsFormatException);
    },
  );
  test('valid empty overview remains a valid empty state', () async {
    respond = (_) => _json({'metrics': []});
    expect(await repository.overviewMetrics(), isEmpty);
  });
  test(
    'GAP-A05 delayed old SDK logout cannot invalidate a newer Admin session',
    () async {
      final storage = _PkceBarrier();
      final c = makeClient(storage: storage);
      addTearDown(c.dispose);
      await login(c, _a, 'session-a');
      final controller = AdminSessionController(c);
      addTearDown(controller.dispose);
      final logout = AdminRepository(c).signOut();
      await storage.entered.future;
      await login(c, _b, 'session-b');
      await Future<void>.delayed(Duration.zero);
      final newer = controller.state;
      expect(newer?.key.userId, _b);
      storage.release.complete();
      await logout;
      await Future<void>.delayed(Duration.zero);
      expect(c.auth.currentUser?.id, _b);
      expect(controller.state, newer);
      final sent = requests.singleWhere((r) => r.url.path.endsWith('/logout'));
      expect(sent.url.queryParameters['scope'], 'local');
    },
  );
}
