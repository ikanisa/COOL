import 'dart:convert';

import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _balanceRow = {
  'collection_id': 'group',
  'supporter_count': 2,
  'balances': [
    {
      'currency': 'EUR',
      'amount_raised_minor': 12845,
      'current_user_balance_minor': 12345,
    },
    {
      'currency': 'RWF',
      'amount_raised_minor': 3000,
      'current_user_balance_minor': 3000,
    },
  ],
};
const _date = '2026-09-02T00:00:00Z';
const _history = [
  {
    'payment_id': 'momo:same-id',
    'collection_id': 'group',
    'amount_minor': 3000,
    'currency': 'RWF',
    'rail': 'rwanda_momo',
    'posted_at': _date,
    'is_current_user_contribution': true,
  },
  {
    'payment_id': 'bank:same-id',
    'collection_id': 'group',
    'amount_minor': 12345,
    'currency': 'EUR',
    'rail': 'diaspora_bank',
    'posted_at': _date,
    'is_current_user_contribution': true,
  },
];
const _intents = [
  {
    'id': 'momo-intent',
    'collection_id': 'group',
    'amount_minor': 1000,
    'currency': 'RWF',
    'rail': 'rwanda_momo',
    'created_at': _date,
    'expires_at': '2099-01-01T00:00:00Z',
    'status': 'pending',
  },
  {
    'id': 'bank-intent',
    'collection_id': 'group',
    'amount_minor': 100,
    'currency': 'EUR',
    'rail': 'diaspora_bank',
    'created_at': _date,
    'expires_at': '2099-01-01T00:00:00Z',
    'status': 'awaiting_transfer',
  },
];

Future<SupabaseClient> _client(Object? Function(String) response) async {
  final client = SupabaseClient(
    'http://127.0.0.1:1',
    'local-test-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(
      (request) async => http.Response(
        jsonEncode(response(request.url.path.split('/').last)),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      ),
    ),
  );
  await client.auth.setInitialSession(
    jsonEncode({
      'access_token': 'local-test-access',
      'refresh_token': 'local-test-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': '10000000-0000-0000-0000-000000000001',
        'aud': 'authenticated',
        'app_metadata': <String, Object>{},
        'user_metadata': <String, Object>{},
        'created_at': _date,
      },
    }),
  );
  return client;
}

Object? _response(String rpc, {String country = 'RW'}) => switch (rpc) {
  'get_current_member_profile' => {
    'id': '10000000-0000-0000-0000-000000000001',
    'public_id': '123456',
    'whatsapp_phone': '250788123456',
    'country_code': country,
    'currency_code': country == 'RW' ? 'RWF' : 'EUR',
  },
  'list_current_user_collections' => [
    {
      'id': 'group',
      'slug': 'synthetic-group',
      'title': 'Synthetic group',
      'created_at': _date,
    },
  ],
  'list_current_member_recent_intents' => {
    'items': _intents,
    'pending_count': 2,
  },
  'list_current_member_history_page' => _historyPage(_history),
  'list_current_member_collection_balances' => [_balanceRow],
  'notification_preferences' || 'notification_events' => [],
  _ => throw StateError('Unexpected endpoint $rpc'),
};

Map<String, dynamic> _historyPage(List<Map<String, Object>> rows) => {
  'items': rows,
  'total_count': rows.length,
  'totals': {'RWF': 3000, 'EUR': 12345},
  'own_totals': {'RWF': 3000, 'EUR': 12345},
  'own_collection_ids': ['group'],
  'revision': '11111111111111111111111111111111',
  'next_cursor': null,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'country switch preserves both rails, original precision, and distinct count',
    () async {
      var country = 'RW';
      final client = await _client((rpc) => _response(rpc, country: country));
      final repo = CollectRepository(supabase: client);
      addTearDown(client.dispose);
      addTearDown(repo.dispose);
      for (final nextCountry in ['RW', 'MT', 'RW']) {
        country = nextCountry;
        await repo.loadInitial();
        expect(repo.state.lastError, isNull);
        expect(repo.state.currentProfile!.countryCode, country);
        expect(repo.state.contributions.map((item) => item.id).toSet(), {
          'momo:same-id',
          'bank:same-id',
        });
        expect(repo.state.paymentIntents.map((item) => item.currency).toSet(), {
          'RWF',
          'EUR',
        });
        final summary = repo.summaryFor('group');
        expect(summary.supporterCount, 2);
        expect(summary.totalsByCurrency, {'RWF': 3000, 'EUR': 12845});
        expect(summary.ownBalancesByCurrency, {'RWF': 3000, 'EUR': 12345});
        expect(() => summary.amountRaisedMinor, throwsStateError);
      }
      expect(
        (await repo.refreshPaymentIntent('momo-intent')).isRwandaMomo,
        isTrue,
      );
      expect((await repo.refreshPaymentIntent('bank-intent')).currency, 'EUR');
    },
  );

  for (final rpc in [
    'list_current_member_recent_intents',
    'list_current_member_history_page',
    'list_current_member_collection_balances',
  ]) {
    for (final invalid in [
      null,
      {'unexpected': true},
      [null],
    ]) {
      test(
        '$rpc rejects malformed response $invalid without false zero',
        () async {
          final client = await _client(
            (name) => name == rpc ? invalid : _response(name),
          );
          final repo = CollectRepository(supabase: client);
          addTearDown(client.dispose);
          addTearDown(repo.dispose);
          await repo.loadInitial();
          expect(repo.state.hasInitialLoadFailure, isTrue);
          expect(repo.state.lastSuccessfulSyncAt, isNull);
        },
      );
    }
  }

  test(
    'payment row rejects mismatched rail/currency instead of relabelling',
    () async {
      final client = await _client(
        (name) => name == 'list_current_member_history_page'
            ? _historyPage([
                {..._history.first, 'currency': 'EUR'},
              ])
            : _response(name),
      );
      final repo = CollectRepository(supabase: client);
      addTearDown(client.dispose);
      addTearDown(repo.dispose);
      await repo.loadInitial();
      expect(repo.state.hasInitialLoadFailure, isTrue);
      expect(repo.state.lastError, contains('Invalid payment history'));
    },
  );

  test('cache round trip retains both currency balances and unknown count', () {
    final row = Map<String, dynamic>.of(_balanceRow)
      ..['supporter_count'] = null;
    final summary = CollectionSummary.fromJson(row);
    final snapshot = CollectOfflineSnapshot(
      savedAt: DateTime.utc(2026, 9, 2),
      currentProfile: null,
      collections: const [],
      paymentIntents: const [],
      contributions: const [],
      collectionSummaries: {'group': summary},
    );
    final restored = CollectOfflineSnapshot.fromJson(
      snapshot.toJson(),
    ).collectionSummaries['group']!;
    expect(restored.totalsByCurrency, summary.totalsByCurrency);
    expect(restored.ownBalancesByCurrency, summary.ownBalancesByCurrency);
    expect(restored.supporterCount, isNull);
    expect(restored.supporterCountSemantics, 'Contributor count unavailable');
  });

  test('duplicate and unsupported currency balances fail closed', () {
    expect(
      () => CollectionSummary.fromJson({
        ..._balanceRow,
        'balances': [
          ...(_balanceRow['balances'] as List),
          (_balanceRow['balances'] as List).first,
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => CollectionSummary.fromJson(const {
        'supporter_count': 2,
        'balances': [
          {
            'currency': 'GBP',
            'amount_raised_minor': 10,
            'current_user_balance_minor': 10,
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('fixture fallback counts repeated own contributions once', () {
    final repo = CollectRepository.fixture();
    addTearDown(repo.dispose);
    expect(repo.summaryFor('col-church').supporterCount, 1);
    expect(repo.summaryFor('col-church').totalsByCurrency, {'RWF': 35000});
  });

  test('zero own balance retains the group settlement currency', () {
    final summary = CollectionSummary.multiCurrency(
      totals: const {'EUR': 12345},
      ownBalances: const {},
      supporterCount: 1,
    );
    expect(summary.currency, 'EUR');
    expect(summary.ownBalancesByCurrency, {'EUR': 0});
    expect(summary.supporterCountSemantics, '1 contributor');
  });
}
