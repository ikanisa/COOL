import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/data/exact_json_values.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const other = '10000000-0000-0000-0000-000000000002';
const firstSession = '20000000-0000-0000-0000-000000000001';
const nextSession = '20000000-0000-0000-0000-000000000002';
const group = '30000000-0000-0000-0000-000000000001';
Map<String, dynamic> health({String id = group, int pending = 1}) => {
  'collection_id': id,
  'sms_access_enabled': true,
  'receiver_configured': true,
  'pending_payment_intents': pending,
  'needs_review_events': 0,
  'last_synced_at': '2026-09-30T12:00:00+02:00',
};
Map<String, dynamic> roster() => {
  'public_id': '123456',
  'role': 'owner',
  'status': 'active',
  'joined_at': '2026-09-30T12:00:00+02:00',
  'amount_scope': 'own',
  'contributions': [
    {'currency': 'RWF', 'amount_minor': 10},
  ],
};
Map<String, dynamic> history() => {
  'total_count': 1,
  'totals': {'RWF': 10},
  'own_totals': {'RWF': 0},
  'own_collection_ids': [],
  'revision': '0123456789abcdef0123456789abcdef',
  'items': [
    {
      'payment_id': 'momo:40000000-0000-0000-0000-000000000001',
      'collection_id': group,
      'rail': 'rwanda_momo',
      'currency': 'RWF',
      'amount_minor': 10,
      'posted_at': '2000-01-01T00:00:00+00',
      'is_current_user_contribution': false,
    },
  ],
};
http.Response jsonResponse(Object? value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('owner health ACK is exactly bound to requested group', () async {
    final h = await Harness.create(
      (_) => jsonResponse(health(id: 'foreign-group')),
    );
    await expectLater(h.repo.ownerHealthFor(group), throwsFormatException);
    expect(h.requests, hasLength(1));
    expect(jsonDecode(h.requests.single.body), {'collection': group});
  });
  for (final value in [null, -1, 1.5, maxExactJsonInteger + 1]) {
    test('owner health cannot truncate/default invalid count $value', () async {
      final h = await Harness.create(
        (_) => jsonResponse(health()..['pending_payment_intents'] = value),
      );
      await expectLater(h.repo.ownerHealthFor(group), throwsFormatException);
    });
  }
  test(
    'roster IDs and exact amount cannot be duplicated or forged as own',
    () async {
      for (final rows in [
        [roster(), roster()],
        [roster()..['public_id'] = '654321'],
        [roster()..['joined_at'] = '2026-02-30T10:00:00Z'],
        [
          roster()
            ..['contributions'] = [
              {'currency': 'RWF', 'amount_minor': maxExactJsonInteger + 1},
            ],
        ],
      ]) {
        final h = await Harness.create((_) => jsonResponse(rows));
        await expectLater(
          h.repo.membersForCollection(group),
          throwsFormatException,
        );
      }
    },
  );
  for (final method in ['health', 'roster', 'history']) {
    for (final transition in [
      'same-user new-session',
      'A to B to A original-session',
    ]) {
      test(
        '$method old reply is fenced after $transition and pins request authority',
        () async {
          final entered = Completer<void>(), reply = Completer<http.Response>();
          final h = await Harness.create((_) {
            entered.complete();
            return reply.future;
          });
          final Future<Object?> pending = switch (method) {
            'health' => h.repo.ownerHealthFor(group),
            'roster' => h.repo.membersForCollection(group),
            _ => h.repo.fetchHistoryPage(const MemberHistoryQuery()),
          };
          final failure = expectLater(pending, throwsStateError);
          await entered.future;
          if (transition.startsWith('A')) {
            await h.login(other, nextSession);
            await h.login(actor, firstSession);
          } else {
            await h.login(actor, nextSession);
          }
          reply.complete(
            jsonResponse(switch (method) {
              'health' => health(),
              'roster' => [roster()],
              _ => history(),
            }),
          );
          await failure;
          expect(
            h.requests.single.headers['Authorization'],
            'Bearer ${jwt(actor, firstSession)}',
          );
          expect(h.repo.state.contributions, isEmpty);
          expect(h.repo.state.paymentIntents, isEmpty);
        },
      );
    }
  }
  test(
    'retained history controller cannot publish after same-user replacement session',
    () async {
      final entered = Completer<void>(), reply = Completer<http.Response>();
      final h = await Harness.create((_) {
        entered.complete();
        return reply.future;
      });
      final controller = MemberHistoryController(
        h.repo,
        const MemberHistoryQuery(),
      );
      addTearDown(controller.dispose);
      await entered.future;
      await h.login(actor, nextSession);
      reply.complete(jsonResponse(history()));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.page, isNull);
      expect(controller.state.error, 'Account changed. Reload history.');
    },
  );
  test(
    'resolved health provider reloads for same-user replacement session',
    () async {
      var reads = 0;
      final h = await Harness.create(
        (_) => jsonResponse(health(pending: ++reads)),
      );
      final container = ProviderContainer(
        overrides: [collectRepositoryProvider.overrideWith((_) => h.repo)],
      );
      // Repository ownership belongs to the container from this point.
      h.containerOwnsRepo = true;
      addTearDown(container.dispose);
      final provider = ownerGroupHealthProvider(group);
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      expect((await container.read(provider.future)).pendingPaymentIntents, 1);
      await h.login(actor, nextSession);
      expect((await container.read(provider.future)).pendingPaymentIntents, 2);
      expect(
        h.requests.last.headers['Authorization'],
        'Bearer ${jwt(actor, nextSession)}',
      );
    },
  );
  test(
    'late health provider result cannot replace current-session result',
    () async {
      final entered = Completer<void>(), reply = Completer<http.Response>();
      var calls = 0;
      final h = await Harness.create((_) {
        if (++calls == 1) {
          entered.complete();
          return reply.future;
        }
        return jsonResponse(health(pending: 2));
      });
      final container = ProviderContainer(
        overrides: [collectRepositoryProvider.overrideWith((_) => h.repo)],
      );
      h.containerOwnsRepo = true;
      addTearDown(container.dispose);
      final provider = ownerGroupHealthProvider(group);
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      await entered.future;
      await h.login(actor, nextSession);
      expect((await container.read(provider.future)).pendingPaymentIntents, 2);
      reply.complete(jsonResponse(health(pending: 99)));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(provider).requireValue.pendingPaymentIntents, 2);
    },
  );
  test(
    'production offline history without aggregate metadata stays unavailable',
    () async {
      final repo = CollectRepository();
      addTearDown(repo.dispose);
      final controller = MemberHistoryController(
        repo,
        const MemberHistoryQuery(),
      );
      addTearDown(controller.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.page, isNull);
      expect(controller.state.error, 'Connect to load the complete history.');
    },
  );
}

typedef Respond = FutureOr<http.Response> Function(http.Request);

class Harness {
  Harness(this.client, this.repo, this.requests);
  final SupabaseClient client;
  final Repository repo;
  final List<http.Request> requests;
  bool containerOwnsRepo = false;
  static Future<Harness> create(Respond respond) async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'http://127.0.0.1:1',
      'synthetic-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
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
    await client.auth.setInitialSession(session(actor, firstSession));
    final repo = Repository(client);
    final h = Harness(client, repo, requests);
    addTearDown(() async {
      if (!h.containerOwnsRepo) repo.dispose();
      await client.dispose();
    });
    return h;
  }

  Future<void> login(String user, String sid) async {
    final loaded = Completer<void>();
    repo.nextLoad = loaded;
    await client.auth.setInitialSession(session(user, sid));
    await loaded.future.timeout(const Duration(seconds: 3));
  }
}

class Repository extends CollectRepository {
  Repository(this.client)
    : super.fixture(initialState: stateFor(actor), supabase: client);
  final SupabaseClient client;
  Completer<void>? nextLoad;
  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    state = stateFor(client.auth.currentUser!.id);
    nextLoad?.complete();
    nextLoad = null;
  }
}

CollectState stateFor(String user) => CollectState(
  currentProfile: CollectProfile(
    id: user,
    publicId: '123456',
    whatsappPhone: '+250788123456',
    countryCode: 'RW',
    currencyCode: 'RWF',
    momoProvider: 'mtn_momo',
    momoNumber: '0788123456',
  ),
  collections: [
    CollectCollection(
      id: group,
      slug: 'synthetic-group',
      creatorUserId: user,
      title: 'Synthetic group',
      description: '',
      createdAt: DateTime.utc(2026),
    ),
  ],
  paymentIntents: const [],
  contributions: const [],
);
String jwt(String user, String sid) {
  String p(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${p({'alg': 'HS256'})}.${p({'sub': user, 'session_id': sid, 'exp': 4102444800})}.synthetic';
}

String session(String user, String sid) => jsonEncode({
  'access_token': jwt(user, sid),
  'refresh_token': 'synthetic-$sid',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': user,
    'aud': 'authenticated',
    'app_metadata': {},
    'user_metadata': {},
    'created_at': '2026-01-01T00:00:00Z',
  },
});
