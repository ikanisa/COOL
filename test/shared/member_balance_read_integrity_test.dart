import 'dart:convert';

import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/synthetic_jwt.dart';

// Fake session, transport and cache only: no phone, network, platform store,
// payment, SMS, roster or recovery operation.
const _actor = '10000000-0000-0000-0000-000000000001';
const _group = '30000000-0000-0000-0000-000000000001';

Map<String, dynamic> _groupRow() => {
  'id': _group,
  'slug': 'synthetic-group',
  'creator_user_id': _actor,
  'title': 'Synthetic group',
  'created_at': '2000-01-01T00:00:00+00',
  'is_member': true,
  'settlement_currency': 'RWF',
};

Map<String, dynamic> _history() => {
  'contract_version': 2,
  'contribution_basis': 'reconciled_evidence_entries',
  'items': [],
  'total_count': 0,
  'totals': {'RWF': 0},
  'own_totals': {'RWF': 0},
  'credit_totals': {'RWF': 0},
  'debit_totals': {'RWF': 0},
  'own_credit_totals': {'RWF': 0},
  'own_debit_totals': {'RWF': 0},
  'own_collection_ids': [],
  'revision': '0123456789abcdef0123456789abcdef',
  'next_cursor': null,
};

Map<String, dynamic> _balanceRow({bool empty = false}) => {
  'collection_id': _group,
  'currency': 'RWF',
  'supporter_count': 0,
  'balances': empty
      ? <Object>[]
      : [
          {
            'currency': 'RWF',
            'amount_raised_minor': 0,
            'current_user_balance_minor': 0,
          },
        ],
};

class _ImmediateSms extends SmsAccessChannel {
  const _ImmediateSms();

  @override
  Future<bool> suspendUnlessOwner(String? ownerUserId) async => true;
}

class _RecordingCache extends CollectOfflineCache {
  _RecordingCache(this.snapshot) : super(preferencesKey: 'synthetic.balance');

  final CollectOfflineSnapshot? snapshot;
  int readCalls = 0;
  int saveCalls = 0;
  int clearCalls = 0;
  String? requestedOwner;

  @override
  Future<CollectOfflineSnapshot?> read({String? ownerUserId}) async {
    readCalls++;
    requestedOwner = ownerUserId;
    return snapshot;
  }

  @override
  Future<void> save(CollectOfflineSnapshot snapshot) async {
    saveCalls++;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
  }
}

class _Repository extends CollectRepository {
  _Repository(CollectCloudflareClient client, _RecordingCache cache)
    : super(
        backend: client,
        smsAccessChannel: const _ImmediateSms(),
        offlineCache: cache,
      );

  // Suppress only auth-listener automatic reload; the test calls the real
  // load implementation exactly once through executeInitial.
  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {}

  Future<void> executeInitial() => super.loadInitial();
}

CollectOfflineSnapshot _savedSnapshot() => CollectOfflineSnapshot(
  savedAt: DateTime.utc(2026, 1, 1),
  currentProfile: const CollectProfile(
    id: _actor,
    publicId: '123456',
    whatsappPhone: '+250788123456',
    countryCode: 'RW',
    currencyCode: 'RWF',
    momoProvider: 'mtn_momo',
    momoNumber: '0788123456',
  ),
  collections: [CollectCollection.fromJson(_groupRow())],
  paymentIntents: const [],
  contributions: const [],
  collectionSummaries: const {
    _group: CollectionSummary(
      amountRaisedRwf: 75,
      currentUserBalanceRwf: 20,
      supporterCount: 1,
    ),
  },
);

class _Harness {
  _Harness(this.repo, this.client, this.cache, this.requests);

  final _Repository repo;
  final CollectCloudflareClient client;
  final _RecordingCache cache;
  final List<http.Request> requests;

  static Future<_Harness> create(
    String scenario, {
    CollectOfflineSnapshot? cached,
  }) async {
    final requests = <http.Request>[];
    final client = CollectCloudflareClient(
      'http://127.0.0.1:1',
      sessionStorage: CollectMemorySessionStorage(),
      httpClient: MockClient((request) async {
        requests.add(request);
        final name = request.url.path.split('/').last;
        final Object body = switch (name) {
          'get_current_member_profile' => {
            'id': _actor,
            'public_id': '123456',
            'whatsapp_phone': '+250788123456',
            'country_code': 'RW',
            'currency_code': 'RWF',
            'momo_provider': 'mtn_momo',
            'momo_number': '0788123456',
          },
          'list_current_user_collections' =>
            scenario == 'no groups' ? [] : [_groupRow()],
          'list_current_member_recent_intents' => {
            'items': [],
            'pending_count': 0,
          },
          'list_current_member_history_page' => _history(),
          'list_current_member_collection_balances' =>
            scenario == 'no groups'
                ? []
                : [_balanceRow(empty: scenario == 'empty group balance')],
          'get_notification_preferences_v2' => {
            'contract_version': 2,
            'ok': true,
            'user_id': _actor,
            'revision': 0,
            'exists': false,
            'preferences': NotificationPreferences.defaults.toJson(),
          },
          'notification-events' || 'public-collections' => [],
          'sync' => {'events': [], 'cursor': '0'},
          _ => throw StateError('Unexpected synthetic request'),
        };
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': syntheticMemberAccessToken(_actor),
        'refresh_token': 'synthetic-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': _actor,
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    final cache = _RecordingCache(cached);
    final repo = _Repository(client, cache);
    addTearDown(() async {
      repo.dispose();
      await client.dispose();
    });
    return _Harness(repo, client, cache, requests);
  }

  Iterable<http.Request> get balanceRequests => requests.where(
    (request) =>
        request.url.path == '/v1/rpc/list_current_member_collection_balances',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no memberships accept an empty top-level balance array', () async {
    final h = await _Harness.create('no groups');
    await h.repo.executeInitial();

    expect(h.balanceRequests, hasLength(1));
    expect(h.repo.state.lastError, isNull);
    expect(h.repo.state.lastSuccessfulSyncAt, isNotNull);
    expect(h.repo.state.collections, isEmpty);
    expect(h.repo.state.collectionSummaries, isEmpty);
    expect(h.repo.state.historyPage, isNotNull);
    expect(h.repo.state.usingStaleCache, isFalse);
    expect(h.cache.readCalls, 0);
    expect(h.cache.clearCalls, 0);
  });

  test('an explicit RWF zero row remains an available zero', () async {
    final h = await _Harness.create('explicit zero');
    await h.repo.executeInitial();

    expect(h.balanceRequests, hasLength(1));
    expect(h.repo.state.lastError, isNull);
    expect(h.repo.state.collections.single.id, _group);
    expect(h.repo.state.collectionSummaries[_group]!.amountRaisedRwf, 0);
    expect(h.repo.state.collectionSummaries[_group]!.currentUserBalanceRwf, 0);
    expect(h.repo.state.collectionSummaries[_group]!.supporterCount, 0);
    expect(h.repo.state.usingStaleCache, isFalse);
    expect(h.cache.readCalls, 0);
    expect(h.cache.clearCalls, 0);
  });

  test(
    'empty per-group balances reject a live refresh and retain saved data',
    () async {
      final saved = _savedSnapshot();
      final h = await _Harness.create('empty group balance', cached: saved);
      await h.repo.executeInitial();

      expect(h.balanceRequests, hasLength(1));
      expect(
        h.requests.last.url.path,
        '/v1/rpc/list_current_member_collection_balances',
      );
      expect(h.repo.state.usingStaleCache, isTrue);
      expect(h.repo.state.lastError, isNotNull);
      expect(h.repo.state.collectionSummaries[_group]!.amountRaisedRwf, 75);
      expect(
        h.repo.state.collectionSummaries[_group]!.currentUserBalanceRwf,
        20,
      );
      expect(h.cache.readCalls, 1);
      expect(h.cache.requestedOwner, _actor);
      expect(h.cache.saveCalls, 0);
      expect(h.cache.clearCalls, 0);
      expect(identical(h.cache.snapshot, saved), isTrue);
    },
  );

  test(
    'empty per-group balances fail before publishing when cache is absent',
    () async {
      final h = await _Harness.create('empty group balance');
      await h.repo.executeInitial();

      expect(h.balanceRequests, hasLength(1));
      expect(
        h.requests.last.url.path,
        '/v1/rpc/list_current_member_collection_balances',
      );
      expect(h.repo.state.lastError, isNotNull);
      expect(h.repo.state.hasInitialLoadFailure, isTrue);
      expect(h.repo.state.collectionSummaries, isEmpty);
      expect(h.repo.state.historyPage, isNull);
      expect(h.cache.readCalls, 1);
      expect(h.cache.saveCalls, 0);
      expect(h.cache.clearCalls, 0);
    },
  );
}
