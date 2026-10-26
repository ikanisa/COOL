import 'support/recorded_auth_fixture.dart';
import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';

const _actor = '99720000-0000-4000-8000-000000000021';
const _key = 'qa_runtime_fixture';
const _request = {
  'p_key': _key,
  'p_enabled': true,
  'p_expected_revision': 4,
  'p_reason': 'Reviewed local setting',
};
Map<String, dynamic> _ack({bool changed = true}) => {
  'contract_version': 2,
  'ok': true,
  'previous_revision': 4,
  'revision': changed ? 5 : 4,
  'changed': changed,
  'updated_at': '2026-09-30T10:00:00+00:00',
  'key': _key,
  'enabled': true,
};
http.Response _json(Object? value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late CollectCloudflareClient client;
  late AdminRepository repository;
  late List<http.Request> requests;
  late FutureOr<http.Response> Function(http.Request) respond;
  Future<void> login(String session, {int nonce = 0}) async {
    await installRecordedAuthFixture(
      client,
      phone: '+250788972021',
      token: '$session|$nonce',
      type: CollectOtpType.sms,
    );
  }

  setUp(() async {
    requests = [];
    respond = (_) => _json(_ack());
    client = recordedFixtureClient(
      'http://127.0.0.1:1',
      httpClient: MockClient((r) async {
        http.Response result;
        if (r.url.path.endsWith('/verify')) {
          final parts = (jsonDecode(r.body)['token'] as String).split('|');
          result = _json({
            'access_token':
                'e30.${base64Url.encode(utf8.encode(jsonEncode({'role': 'authenticated', 'sub': _actor, 'session_id': parts[0], 'nonce': parts[1], 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
            'refresh_token': 'synthetic-refresh',
            'token_type': 'bearer',
            'user': {
              'id': _actor,
              'aud': 'authenticated',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-09-30T00:00:00Z',
            },
          });
        } else {
          requests.add(r);
          result = await respond(r);
        }
        return http.Response.bytes(
          result.bodyBytes,
          result.statusCode,
          headers: result.headers,
          request: r,
        );
      }),
    );
    await login('session-a');
    repository = AdminRepository(client);
  });
  tearDown(() => client.dispose());

  for (final changed in [true, false]) {
    test(
      'feature v2 exact HTTP request and ${changed ? 'changed' : 'unchanged'} ACK',
      () async {
        respond = (_) => _json(_ack(changed: changed));
        final result = await repository.action(
          'admin_set_feature_flag_v2',
          _request,
        );
        expect(result['revision'], changed ? 5 : 4);
        expect(requests.single.url.path, '/v1/rpc/admin_set_feature_flag_v2');
        expect(jsonDecode(requests.single.body), _request);
      },
    );
  }
  final malformed = <String, Object?>{
    'null': null,
    'array': [],
    'missing': {},
    'extra': {..._ack(), 'value': true},
    'wrong key': {..._ack(), 'key': 'other'},
    'wrong state': {..._ack(), 'enabled': false},
    'nullable state': {..._ack(), 'enabled': null},
    'string state': {..._ack(), 'enabled': 'true'},
    'version string': {..._ack(), 'contract_version': '2'},
    'version double': {..._ack(), 'contract_version': 2.0},
    'previous mismatch': {..._ack(), 'previous_revision': 3},
    'revision string': {..._ack(), 'revision': '5'},
    'revision double': {..._ack(), 'revision': 5.0},
    'nullable changed': {..._ack(), 'changed': null},
    'string changed': {..._ack(), 'changed': 'true'},
    'nonincrement': {..._ack(), 'revision': 4},
    'noop increment': {..._ack(), 'changed': false},
    'invalid date': {..._ack(), 'updated_at': '2026-02-30T10:00:00Z'},
    'nullable date': {..._ack(), 'updated_at': null},
    'year0000 date': {..._ack(), 'updated_at': '0000-01-01T10:00:00Z'},
    'UTC year underflow': {
      ..._ack(),
      'updated_at': '0001-01-01T00:00:00+23:00',
    },
    'UTC year overflow': {..._ack(), 'updated_at': '9999-12-31T23:00:00-23:00'},
    'naive date': {..._ack(), 'updated_at': '2026-09-30T10:00:00'},
    'offset overflow': {..._ack(), 'updated_at': '2026-09-30T10:00:00+02:60'},
  };
  for (final entry in malformed.entries) {
    test(
      'feature actual HTTP rejects ${entry.key} ACK without resend',
      () async {
        respond = (_) => _json(entry.value);
        await expectLater(
          repository.action('admin_set_feature_flag_v2', _request),
          entry.key == 'array' ? throwsStateError : throwsFormatException,
        );
        expect(requests, hasLength(1));
      },
    );
  }
  test('feature 40001 conflict surfaces with one exact dispatch', () async {
    respond = (_) =>
        _json({'code': '40001', 'message': 'runtime_control_conflict'}, 409);
    await expectLater(
      repository.action('admin_set_feature_flag_v2', _request),
      throwsA(
        isA<CollectApiException>().having((e) => e.code, 'code', '40001'),
      ),
    );
    expect(requests, hasLength(1));
  });
  for (final switchBack in [false, true]) {
    test('feature late session reply fails; A-B-A=$switchBack', () async {
      final entered = Completer<void>(), release = Completer<void>();
      respond = (_) async {
        entered.complete();
        await release.future;
        return _json(_ack());
      };
      final original = client.auth.currentSession!.accessToken;
      final pending = expectLater(
        repository.action('admin_set_feature_flag_v2', _request),
        throwsA(isA<AdminSessionChanged>()),
      );
      await entered.future;
      await login('session-b');
      if (switchBack) await login('session-a', nonce: 2);
      release.complete();
      await pending;
      expect(requests.single.headers['Authorization'], 'Bearer $original');
      expect(requests, hasLength(1));
    });
  }
  test('feature same-session token refresh retains captured bearer', () async {
    final entered = Completer<void>(), release = Completer<void>();
    respond = (_) async {
      entered.complete();
      await release.future;
      return _json(_ack());
    };
    final original = client.auth.currentSession!.accessToken;
    final pending = repository.action('admin_set_feature_flag_v2', _request);
    await entered.future;
    await login('session-a', nonce: 2);
    release.complete();
    expect((await pending)['revision'], 5);
    expect(requests.single.headers['Authorization'], 'Bearer $original');
  });
}
