import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/data/exact_json_values.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'member_data_authority_test.dart' as authority;

const actor = '10000000-0000-0000-0000-000000000001';
const group = '30000000-0000-0000-0000-000000000001';
Map<String, dynamic> groupRow() => {
  'id': group,
  'slug': 'synthetic-group',
  'creator_user_id': actor,
  'title': 'Synthetic group',
  'created_at': '2000-01-01T00:00:00+00',
  'settlement_currency': 'RWF',
};
Map<String, dynamic> event() => {
  'id': '50000000-0000-0000-0000-000000000001',
  'user_id': actor,
  'type': 'group_update',
  'created_at': '2000-01-01T00:00:00+00',
};
Map<String, dynamic> zeroHistory() => {
  'items': [],
  'total_count': 0,
  'totals': {},
  'own_totals': {},
  'own_collection_ids': [],
  'revision': '0123456789abcdef0123456789abcdef',
};
Object? response(http.Request r, String scenario) {
  final name = r.url.path.split('/').last;
  return switch (name) {
    'get_current_member_profile' => {
      'id': scenario == 'foreign profile' ? 'foreign-user' : actor,
      'public_id': '123456',
      'whatsapp_phone': '+250788123456',
      'country_code': 'RW',
      'currency_code': 'RWF',
      'momo_provider': 'mtn_momo',
      'momo_number': '0788123456',
    },
    'list_current_user_collections' =>
      scenario == 'duplicate group' ? [groupRow(), groupRow()] : [groupRow()],
    'list_current_member_recent_intents' => {
      'items': [],
      'pending_count': scenario == 'inexact pending count'
          ? maxExactJsonInteger + 1
          : 0,
    },
    'list_current_member_history_page' => zeroHistory(),
    'list_current_member_collection_balances' => [
      {
        'collection_id': group,
        'supporter_count': 0,
        'balances': [
          {
            'currency': 'RWF',
            'amount_raised_minor': scenario == 'inexact modern total'
                ? maxExactJsonInteger + 1
                : 0,
            'current_user_balance_minor': 0,
          },
        ],
      },
    ],
    'get_notification_preferences_v2' => {
      'contract_version': 2,
      'ok': true,
      'user_id': actor,
      'revision': 0,
      'exists': false,
      'preferences': NotificationPreferences.defaults.toJson(),
    },
    'notification_events' =>
      scenario == 'duplicate event'
          ? [event(), event()]
          : [
              event()
                ..['user_id'] = scenario == 'foreign event'
                    ? 'foreign-user'
                    : actor,
            ],
    _ => throw StateError('Unexpected synthetic request'),
  };
}

class _ImmediateSms extends SmsAccessChannel {
  const _ImmediateSms();
  @override
  Future<bool> suspendUnlessOwner(String? ownerUserId) async => true;
}

class _InitialReadRepository extends CollectRepository {
  _InitialReadRepository(SupabaseClient client)
    : super(
        supabase: client,
        smsAccessChannel: const _ImmediateSms(),
        offlineCache: const CollectOfflineCache(
          preferencesKey: 'synthetic.initial-read-scope',
        ),
      );
  Completer<void>? nextReload;
  // Keep automatic Auth reload dispatch separate from the explicitly retained
  // old production pipeline. executeInitial invokes its actual implementation.
  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    nextReload?.complete();
    nextReload = null;
  }

  Future<void> executeInitial() => super.loadInitial();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final scenario in [
    'foreign profile',
    'duplicate group',
    'inexact pending count',
    'inexact modern total',
    'foreign event',
    'duplicate event',
  ]) {
    test(
      'production SDK read rejects $scenario before publishing finance/notifications',
      () async {
        final requests = <http.Request>[];
        final client = SupabaseClient(
          'http://127.0.0.1:1',
          'synthetic-anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((r) async {
            requests.add(r);
            return http.Response(
              jsonEncode(response(r, scenario)),
              200,
              headers: {'content-type': 'application/json'},
              request: r,
            );
          }),
        );
        addTearDown(client.dispose);
        await client.auth.setInitialSession(
          jsonEncode({
            'access_token': 'synthetic-access',
            'refresh_token': 'synthetic-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': actor,
              'aud': 'authenticated',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-01-01T00:00:00Z',
            },
          }),
        );
        final repo = CollectRepository(
          supabase: client,
          offlineCache: const CollectOfflineCache(
            preferencesKey: 'synthetic.read-integrity',
          ),
        );
        addTearDown(repo.dispose);
        await repo.loadInitial();
        expect(repo.state.lastError, isNotNull);
        expect(repo.state.historyPage, isNull);
        expect(repo.state.notificationEvents, isEmpty);
        expect(repo.state.collectionSummaries, isEmpty);
        expect(repo.state.pendingIntentCount, isNull);
        if (scenario.endsWith('event')) {
          expect(requests.last.url.path, '/rest/v1/notification_events');
          expect(requests.last.url.queryParameters['user_id'], 'eq.$actor');
          expect(
            requests.last.headers['Authorization'],
            'Bearer synthetic-access',
          );
        }
      },
    );
  }
  for (final blocked in [
    'get_current_member_profile',
    'list_current_user_collections',
    'list_current_member_recent_intents',
    'list_current_member_history_page',
    'list_current_member_collection_balances',
  ]) {
    for (final transition in ['same-user new-session', 'A to B to A']) {
      test('initial read stops after $blocked across $transition', () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final requests = <http.Request>[];
        final client = SupabaseClient(
          'http://127.0.0.1:1',
          'synthetic-anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.url.path.split('/').last == blocked) {
              entered.complete();
              await release.future;
            }
            return http.Response(
              jsonEncode(response(request, 'valid')),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        await client.auth.setInitialSession(
          authority.session(actor, authority.firstSession),
        );
        final repo = _InitialReadRepository(client);
        addTearDown(repo.dispose);
        final loading = repo.executeInitial();
        await entered.future;
        Future<void> replace(String user, String sid) async {
          final reloaded = Completer<void>();
          repo.nextReload = reloaded;
          await client.auth.setInitialSession(authority.session(user, sid));
          await reloaded.future.timeout(const Duration(seconds: 3));
        }

        if (transition.startsWith('A')) {
          await replace(authority.other, authority.nextSession);
          await replace(actor, authority.firstSession);
        } else {
          await replace(actor, authority.nextSession);
        }
        release.complete();
        await loading;
        expect(requests.last.url.path.split('/').last, blocked);
        expect(requests.map((r) => r.headers['Authorization']).toSet(), {
          'Bearer ${authority.jwt(actor, authority.firstSession)}',
        });
        expect(repo.state.historyPage, isNull);
        expect(repo.state.paymentIntents, isEmpty);
        expect(repo.state.collectionSummaries, isEmpty);
        expect(repo.state.notificationEvents, isEmpty);
      });
    }
  }
  test(
    'initial read retains captured Bearer across same-session refresh',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'http://127.0.0.1:1',
        'synthetic-anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('get_current_member_profile')) {
            entered.complete();
            await release.future;
          }
          return http.Response(
            jsonEncode(response(request, 'valid')),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.setInitialSession(
        authority.session(actor, authority.firstSession),
      );
      final repo = _InitialReadRepository(client);
      addTearDown(repo.dispose);
      final loading = repo.executeInitial();
      await entered.future;
      final refreshed =
          jsonDecode(authority.session(actor, authority.firstSession))
              as Map<String, dynamic>;
      refreshed['access_token'] =
          '${authority.jwt(actor, authority.firstSession)}-refreshed';
      await client.auth.setInitialSession(jsonEncode(refreshed));
      release.complete();
      await loading;
      expect(requests, hasLength(7));
      expect(requests.map((r) => r.headers['Authorization']).toSet(), {
        'Bearer ${authority.jwt(actor, authority.firstSession)}',
      });
      expect(repo.state.currentProfile?.id, actor);
      expect(repo.state.historyPage?.totalCount, 0);
      expect(repo.state.pendingIntentCount, 0);
      expect(repo.state.lastError, isNull);
    },
  );
}
