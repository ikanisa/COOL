import 'dart:async';
import 'dart:convert';

import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _a = '10000000-0000-4000-8000-000000000001';
const _b = '10000000-0000-4000-8000-000000000002';
const _s = '20000000-0000-4000-8000-000000000001';
const _g = '30000000-0000-4000-8000-000000000001';
const _code = '40000000-0000-4000-8000-000000000001';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final op in ['read', 'rotate']) {
    for (final change in ['account', 'session', 'A-B-A', 'logout']) {
      test('late $op rejects $change completion', () async {
        final entered = Completer<void>(), release = Completer<http.Response>();
        final h = await _Harness.create((request) {
          if (request.url.path.endsWith('/logout')) {
            return Future.value(http.Response('', 204, request: request));
          }
          if (!entered.isCompleted) entered.complete();
          return release.future;
        });
        final future = op == 'read'
            ? h.repo.getGroupShareCode(_g)
            : h.repo.rotateGroupShareCode(_g);
        final checked = expectLater(future, throwsStateError);
        await entered.future;
        final request = h.requests.single;
        expect(request.headers['authorization'], 'Bearer ${_jwt(_a, _s)}');
        if (change == 'logout') {
          await h.client.auth.signOut(scope: SignOutScope.local);
        } else {
          await h.client.auth.setInitialSession(
            _session(change == 'session' ? _a : _b, '${_s}2'),
          );
        }
        await Future<void>.delayed(Duration.zero);
        if (change == 'A-B-A') {
          await h.client.auth.setInitialSession(_session(_a, _s));
          await Future<void>.delayed(Duration.zero);
        }
        release.complete(_reply(op == 'read' ? _code : _ack(request)));
        await checked;
      });
    }
  }
  for (final value in [
    '',
    'bad-code',
    'https://attacker.invalid',
    '  $_code',
    '${_code}x',
  ]) {
    test('share read rejects malformed code $value', () async {
      final h = await _Harness.create((_) async => _reply(value));
      await expectLater(h.repo.getGroupShareCode(_g), throwsFormatException);
    });
  }
  for (final value in [null, 7, {}, []]) {
    test('share read rejects non-string ${value.runtimeType}', () async {
      final h = await _Harness.create((_) async => _reply(value));
      await expectLater(h.repo.getGroupShareCode(_g), throwsFormatException);
      expect(h.requests, hasLength(1));
    });
  }
  for (final error in ['lost', '503']) {
    test('rotation has one actual SDK mutation request after $error', () async {
      final h = await _Harness.create((_) async {
        if (error == 'lost') {
          throw http.ClientException('synthetic response loss');
        }
        return _reply({
          'message': 'synthetic unavailable',
          'code': '503',
        }, status: 503);
      });
      await expectLater(h.repo.rotateGroupShareCode(_g), throwsA(anything));
      expect(h.requests, hasLength(1));
      expect(
        h.requests.single.url.path,
        '/rest/v1/rpc/rotate_group_share_code_v2',
      );
      expect(_body(h.requests.single).keys.toSet(), {
        'p_collection_id',
        'p_request_id',
      });
    });
  }
  for (final defect in [
    'empty',
    'extra',
    'target',
    'request',
    'code',
    'boolean',
    'version',
    'fractional-version',
  ]) {
    test('rotation rejects exact receipt defect $defect', () async {
      final h = await _Harness.create((r) async {
        final ack = _ack(r);
        switch (defect) {
          case 'empty':
            ack.clear();
          case 'extra':
            ack['raw_sms'] = 'synthetic forbidden';
          case 'target':
            ack['collection_id'] = _b;
          case 'request':
            ack['request_id'] = _b;
          case 'code':
            ack['share_code'] = 'bad';
          case 'boolean':
            ack['ok'] = 'true';
          case 'version':
            ack['contract_version'] = 2;
          case 'fractional-version':
            ack['contract_version'] = 1.0;
        }
        return _reply(ack);
      });
      await expectLater(h.repo.rotateGroupShareCode(_g), throwsFormatException);
      expect(h.requests, hasLength(1));
    });
  }
  for (final restriction in ['loading', 'cache', 'nonmember', 'nonowner']) {
    test('invitation refuses $restriction authority before dispatch', () async {
      final h = await _Harness.create((r) async => _reply(_ack(r)));
      h.repo.restrict(restriction);
      final operation = restriction == 'nonowner'
          ? h.repo.rotateGroupShareCode(_g)
          : h.repo.getGroupShareCode(_g);
      await expectLater(operation, throwsStateError);
      expect(h.requests, isEmpty);
    });
  }
  test(
    'uncertain rotation deliberately reuses its exact request once',
    () async {
      var calls = 0;
      final h = await _Harness.create((r) async {
        if (++calls == 1) {
          throw http.ClientException('synthetic loss');
        }
        return _reply(_ack(r));
      });
      await expectLater(h.repo.rotateGroupShareCode(_g), throwsA(anything));
      expect(await h.repo.rotateGroupShareCode(_g), _code);
      expect(h.requests, hasLength(2));
      expect(_body(h.requests[0]), _body(h.requests[1]));
    },
  );
  test(
    'acknowledged refresh permits a deliberate new rotation request',
    () async {
      var calls = 0;
      final h = await _Harness.create((r) async {
        if (++calls == 1) {
          throw http.ClientException('synthetic loss');
        }
        return _reply(
          r.url.path.endsWith('/get_group_share_code') ? _code : _ack(r),
        );
      });
      await expectLater(h.repo.rotateGroupShareCode(_g), throwsA(anything));
      expect(await h.repo.getGroupShareCode(_g), _code);
      expect(await h.repo.rotateGroupShareCode(_g), _code);
      expect(
        _body(h.requests[0])['p_request_id'],
        isNot(_body(h.requests[2])['p_request_id']),
      );
    },
  );
  test('valid rotation binds exact request and captured Bearer', () async {
    final h = await _Harness.create((r) async => _reply(_ack(r)));
    expect(await h.repo.rotateGroupShareCode(_g), _code);
    final r = h.requests.single;
    expect(r.url.path, '/rest/v1/rpc/rotate_group_share_code_v2');
    expect(r.headers['authorization'], 'Bearer ${_jwt(_a, _s)}');
    expect(_body(r)['p_collection_id'], _g);
    expect(
      _body(r)['p_request_id'],
      matches(RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$')),
    );
  });
}

class _Harness {
  _Harness(this.client, this.repo, this.requests);
  final SupabaseClient client;
  final _Repository repo;
  final List<http.Request> requests;
  static Future<_Harness> create(
    Future<http.Response> Function(http.Request) response,
  ) async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'http://127.0.0.1:1',
      'synthetic-local-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) {
        requests.add(r);
        return response(r).then(
          (reply) => http.Response.bytes(
            reply.bodyBytes,
            reply.statusCode,
            headers: reply.headers,
            request: r,
          ),
        );
      }),
    );
    await client.auth.setInitialSession(_session(_a, _s));
    final repo = _Repository(client);
    addTearDown(() async {
      repo.dispose();
      await client.dispose();
    });
    return _Harness(client, repo, requests);
  }
}

class _Repository extends CollectRepository {
  _Repository(this.client)
    : super.fixture(
        supabase: client,
        initialState: CollectState(
          currentProfile: const CollectProfile(
            id: _a,
            publicId: '123456',
            whatsappPhone: '+250788123456',
          ),
          collections: [
            CollectCollection(
              id: _g,
              slug: 'local-group',
              creatorUserId: _a,
              title: 'Synthetic group',
              description: '',
              collectionType: CollectionType.church,
              categorySubtype: 'building_fund',
              receiverMomoNumber: '0788123456',
              receiverDisplayLabel: 'Synthetic',
              receiverNetwork: 'mtn_momo',
              isPublic: false,
              isCurrentUserMember: true,
              createdAt: DateTime.utc(2026),
            ),
          ],
          paymentIntents: const [],
          contributions: const [],
        ),
      );
  final SupabaseClient client;
  void restrict(String restriction) {
    state = state.copyWith(
      isLoading: restriction == 'loading',
      usingStaleCache: restriction == 'cache',
      collections: [
        for (final group in state.collections)
          group.copyWith(
            creatorUserId:
                restriction == 'nonmember' || restriction == 'nonowner'
                ? _b
                : group.creatorUserId,
            isCurrentUserMember: restriction != 'nonmember',
          ),
      ],
    );
  }

  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {}
}

Map<String, dynamic> _body(http.Request r) =>
    jsonDecode(r.body) as Map<String, dynamic>;
Map<String, dynamic> _ack(http.Request r) => {
  'contract_version': 1,
  'ok': true,
  'collection_id': _body(r)['p_collection_id'],
  'request_id': _body(r)['p_request_id'],
  'share_code': _code,
};
http.Response _reply(Object? value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);
String _jwt(String user, String session) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'HS256'})}.${encode({'sub': user, 'session_id': session, 'exp': 4102444800})}.synthetic';
}

String _session(String user, String session) => jsonEncode({
  'access_token': _jwt(user, session),
  'refresh_token': 'synthetic-refresh-$session',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': user,
    'aud': 'authenticated',
    'app_metadata': {},
    'user_metadata': {},
    'created_at': '2026-09-01T00:00:00Z',
  },
});
