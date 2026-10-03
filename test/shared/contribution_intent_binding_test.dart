import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/data/exact_json_values.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _actor = '10000000-0000-0000-0000-000000000001';
const _other = '10000000-0000-0000-0000-000000000002';
const _groupId = '30000000-0000-0000-0000-000000000001';
const _intentId = '40000000-0000-0000-0000-000000000001';
const _session1 = '20000000-0000-0000-0000-000000000001';
const _session2 = '20000000-0000-0000-0000-000000000002';
const _draft = PaymentIntentDraft(collectionId: _groupId, amountRwf: 5000);
Map<String, dynamic> _intent({
  int amount = 5000,
  String group = _groupId,
  String id = _intentId,
}) => {
  'id': id,
  'collection_id': group,
  'amount_minor': amount,
  'rail': 'rwanda_momo',
  'currency': 'RWF',
  'status': 'pending',
  'created_at': '2026-09-30T10:00:00+00',
  'expires_at': '2030-09-30T10:00:00Z',
  'receiver_momo_number': '0788123456',
  'momo_network': 'mtn_momo',
};
http.Response _json(Object? value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final amount in [0, -1, maxExactJsonInteger + 1]) {
    test(
      'unsafe input $amount makes no create RPC and publishes no intent',
      () async {
        final h = await _Harness.create((_) => _json(_intent()));
        await expectLater(
          h.repo.createPaymentIntent(
            PaymentIntentDraft(collectionId: _groupId, amountRwf: amount),
          ),
          throwsFormatException,
        );
        expect(h.creates, isEmpty);
        expect(h.repo.state.paymentIntents, isEmpty);
      },
    );
  }
  for (final shape in ['map', 'singleton list']) {
    test(
      'valid $shape ACK is bound to submitted group and exact amount',
      () async {
        final h = await _Harness.create(
          (_) => _json(shape == 'map' ? _intent() : [_intent()]),
        );
        final result = await h.repo.createPaymentIntent(_draft);
        expect(result.id, _intentId);
        expect(result.collectionId, _groupId);
        expect(result.expectedAmountMinor, 5000);
        expect(h.repo.state.paymentIntents.single.id, _intentId);
        expect(h.creates, hasLength(1));
        final request = h.creates.single;
        expect(jsonDecode(request.body)['collection'], _groupId);
        expect(jsonDecode(request.body)['p_expected_amount_rwf'], 5000);
        expect(
          request.headers['Authorization'],
          'Bearer ${_jwt(_actor, _session1)}',
        );
      },
    );
  }
  final malformed = <String, Object?>{
    'wrong group': _intent(group: 'foreign-group'),
    'wrong amount': _intent(amount: 5001),
    'multiple rows': [_intent(), _intent(id: 'different-intent')],
    'empty rows': [],
    'null': null,
    'scalar': 17,
    'inexact amount': _intent()..['amount_minor'] = maxExactJsonInteger + 1,
  };
  for (final entry in malformed.entries) {
    test(
      '${entry.key} ACK cannot enter client state or mark membership',
      () async {
        final h = await _Harness.create((_) => _json(entry.value));
        await expectLater(
          h.repo.createPaymentIntent(_draft),
          throwsFormatException,
        );
        expect(h.creates, hasLength(1));
        expect(h.repo.state.paymentIntents, isEmpty);
        expect(h.repo.state.collections.single.isCurrentUserMember, isFalse);
      },
    );
  }
  for (final transition in [
    'same-user new session',
    'A to B to A original session',
  ]) {
    test(
      'late create ACK denied after $transition with pinned old request authority',
      () async {
        final entered = Completer<void>(), reply = Completer<http.Response>();
        final h = await _Harness.create((_) {
          entered.complete();
          return reply.future;
        });
        final pending = h.repo.createPaymentIntent(_draft);
        final failure = expectLater(pending, throwsStateError);
        await entered.future;
        if (transition.startsWith('A')) {
          await h.login(_other, _session2);
          await h.login(_actor, _session1);
        } else {
          await h.login(_actor, _session2);
        }
        reply.complete(_json(_intent()));
        await failure;
        expect(h.repo.state.currentProfile!.id, _actor);
        expect(h.repo.state.paymentIntents, isEmpty);
        expect(h.creates, hasLength(1));
        expect(
          h.creates.single.headers['Authorization'],
          'Bearer ${_jwt(_actor, _session1)}',
        );
      },
    );
  }
  test('same-session token refresh retains valid intent authority', () async {
    final entered = Completer<void>(), reply = Completer<http.Response>();
    final h = await _Harness.create((_) {
      entered.complete();
      return reply.future;
    });
    final pending = h.repo.createPaymentIntent(_draft);
    await entered.future;
    await h.client.auth.setInitialSession(
      _session(_actor, _session1, revision: 2),
    );
    reply.complete(_json(_intent()));
    expect((await pending).id, _intentId);
    expect(
      h.creates.single.headers['Authorization'],
      'Bearer ${_jwt(_actor, _session1)}',
    );
  });
  for (final mode in ['503', 'transport loss']) {
    test('$mode makes one mutation POST per explicit caller', () async {
      final h = await _Harness.create((_) {
        if (mode == 'transport loss') {
          throw http.ClientException('Synthetic response loss');
        }
        return http.Response(
          '{"message":"Synthetic unavailable"}',
          503,
          headers: {'content-type': 'application/json'},
        );
      });
      await expectLater(
        h.repo.createPaymentIntent(_draft),
        throwsA(isA<Exception>()),
      );
      expect(h.creates, hasLength(1));
      expect(h.repo.state.paymentIntents, isEmpty);
      await expectLater(
        h.repo.createPaymentIntent(_draft),
        throwsA(isA<Exception>()),
      );
      expect(h.creates, hasLength(2));
    });
  }
  for (final mode in [
    'foreign ID',
    'extra row',
    'inexact count',
    'changed group',
    'changed amount',
  ]) {
    test(
      'refresh $mode is denied without replacing the immutable request',
      () async {
        final h = await _Harness.create((_) => _json(_intent()));
        await h.repo.createPaymentIntent(_draft);
        await Future<void>.delayed(Duration.zero);
        h.recent = (_) => _json({
          'pending_count': mode == 'inexact count'
              ? maxExactJsonInteger + 1
              : 1,
          'items': mode == 'foreign ID'
              ? [_intent(id: 'foreign-id')]
              : mode == 'extra row'
              ? [_intent(), _intent(id: 'extra-id')]
              : [
                  _intent(
                    group: mode == 'changed group' ? 'foreign-group' : _groupId,
                    amount: mode == 'changed amount' ? 5001 : 5000,
                  ),
                ],
        });
        await expectLater(
          h.repo.refreshPaymentIntent(_intentId),
          throwsFormatException,
        );
        expect(h.repo.state.paymentIntents.single.collectionId, _groupId);
        expect(h.repo.state.paymentIntents.single.expectedAmountMinor, 5000);
      },
    );
  }
  test(
    'old-session refresh response cannot publish into fresh same-user state',
    () async {
      final h = await _Harness.create((_) => _json(_intent()));
      final entered = Completer<void>(), reply = Completer<http.Response>();
      h.recent = (_) {
        entered.complete();
        return reply.future;
      };
      final pending = h.repo.refreshPaymentIntent(_intentId);
      final failure = expectLater(pending, throwsStateError);
      await entered.future;
      await h.login(_actor, _session2);
      reply.complete(
        _json({
          'pending_count': 1,
          'items': [_intent()],
        }),
      );
      await failure;
      expect(h.repo.state.paymentIntents, isEmpty);
      final request = h.requests.singleWhere(
        (r) => r.url.path.endsWith('/list_current_member_recent_intents'),
      );
      expect(
        request.headers['Authorization'],
        'Bearer ${_jwt(_actor, _session1)}',
      );
    },
  );
}

typedef _Respond = FutureOr<http.Response> Function(http.Request);

class _Harness {
  _Harness(this.client, this.repo, this.requests);
  final SupabaseClient client;
  final _Repository repo;
  final List<http.Request> requests;
  late _Respond recent;
  List<http.Request> get creates => requests
      .where((r) => r.url.path.endsWith('/create_contribution_intent'))
      .toList();
  static Future<_Harness> create(_Respond respond) async {
    final requests = <http.Request>[];
    late _Harness h;
    final client = SupabaseClient(
      'http://127.0.0.1:1',
      'synthetic-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        requests.add(r);
        final http.Response response;
        if (r.url.path.endsWith('/create_contribution_intent')) {
          response = await respond(r);
        } else if (r.url.path.endsWith('/list_current_member_recent_intents')) {
          response = await h.recent(r);
        } else {
          throw StateError('Unexpected synthetic request');
        }
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: r,
        );
      }),
    );
    await client.auth.setInitialSession(_session(_actor, _session1));
    final repo = _Repository(client);
    h = _Harness(client, repo, requests)
      ..recent = (_) => _json({
        'pending_count': 1,
        'items': [_intent()],
      });
    addTearDown(() async {
      repo.dispose();
      await client.dispose();
    });
    return h;
  }

  Future<void> login(String user, String session) async {
    final loaded = Completer<void>();
    repo.nextLoad = loaded;
    await client.auth.setInitialSession(_session(user, session));
    await loaded.future.timeout(const Duration(seconds: 3));
  }
}

class _Repository extends CollectRepository {
  _Repository(this.client)
    : super.fixture(initialState: _state(_actor), supabase: client);
  final SupabaseClient client;
  Completer<void>? nextLoad;
  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    state = _state(client.auth.currentUser!.id);
    nextLoad?.complete();
    nextLoad = null;
  }
}

CollectState _state(String actor) => CollectState(
  currentProfile: CollectProfile(
    id: actor,
    publicId: '123456',
    whatsappPhone: '+250788123456',
    countryCode: 'RW',
    currencyCode: 'RWF',
    momoProvider: 'mtn_momo',
    momoNumber: '0788123456',
  ),
  collections: [
    CollectCollection(
      id: _groupId,
      slug: 'synthetic-group',
      creatorUserId: actor,
      title: 'Synthetic group',
      description: '',
      createdAt: DateTime.utc(2026),
      receiverMomoNumber: '0788123456',
      receiverNetwork: 'mtn_momo',
      isPublic: true,
    ),
  ],
  paymentIntents: const [],
  contributions: const [],
);
String _jwt(String user, String session, {int revision = 1}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'sub': user, 'session_id': session, 'role': 'authenticated', 'revision': revision, 'exp': 4102444800})}.synthetic';
}

String _session(String user, String session, {int revision = 1}) => jsonEncode({
  'access_token': _jwt(user, session, revision: revision),
  'refresh_token': 'synthetic-$session-$revision',
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
