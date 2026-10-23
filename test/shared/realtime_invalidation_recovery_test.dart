import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/cloudflare/realtime_invalidation.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import '../support/synthetic_jwt.dart';

const _userId = '10000000-0000-0000-0000-000000000001';
const _secondUserId = '10000000-0000-0000-0000-000000000002';
const _groupId = '20000000-0000-0000-0000-000000000001';
const _profile = CollectProfile(
  id: _userId,
  publicId: '123456',
  whatsappPhone: '250788123456',
  countryCode: 'RW',
  currencyCode: 'RWF',
);
final _group = CollectCollection(
  id: _groupId,
  slug: 'private-group',
  creatorUserId: _userId,
  title: 'Private group',
  description: '',
  isCurrentUserMember: true,
  createdAt: DateTime.utc(2026, 9, 1),
);
const _profileRow = <String, Object>{
  'id': _userId,
  'public_id': '123456',
  'whatsapp_phone': '250788123456',
  'country_code': 'RW',
  'currency_code': 'RWF',
};
const _groupRow = <String, Object>{
  'id': _groupId,
  'slug': 'private-group',
  'creator_user_id': _userId,
  'title': 'Private group',
  'description': '',
  'is_member': true,
  'created_at': '2026-09-01T00:00:00Z',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('join and rejoin reconcile missed events once per connection', () async {
    var reads = 0;
    final coordinator = CollectSyncInvalidationCoordinator(
      areas: const {'members'},
      debounce: const Duration(milliseconds: 1),
      onInvalidate: () => reads++,
    );
    addTearDown(coordinator.dispose);
    coordinator.connectionStatus(CollectSyncStatus.connected);
    coordinator.connectionStatus(CollectSyncStatus.connected);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(reads, 1);

    coordinator.connectionStatus(CollectSyncStatus.disconnected);
    coordinator.event({'area': 'members', 'id': 'missed-while-offline'});
    coordinator.connectionStatus(CollectSyncStatus.connected);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(reads, 2);
  });

  test(
    'duplicate IDs and irrelevant areas cannot multiply refreshes',
    () async {
      var reads = 0;
      final coordinator = CollectSyncInvalidationCoordinator(
        areas: const {'members'},
        debounce: const Duration(milliseconds: 1),
        onInvalidate: () => reads++,
      );
      addTearDown(coordinator.dispose);
      coordinator.connectionStatus(CollectSyncStatus.connected);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      coordinator.event({'area': 'members', 'id': 'event-1'});
      coordinator.event({'area': 'members', 'id': 'event-1'});
      coordinator.event({'area': 'payments', 'id': 'event-2'});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(reads, 2);
      coordinator.event({'area': 'members', 'id': 'event-1'});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(reads, 2);
    },
  );

  test('event bursts keep one read in flight and one trailing read', () async {
    final firstRead = Completer<void>();
    var reads = 0;
    var concurrent = 0;
    var peakConcurrent = 0;
    final coordinator = CollectSyncInvalidationCoordinator(
      areas: const {'members'},
      debounce: const Duration(milliseconds: 1),
      onInvalidate: () async {
        reads++;
        concurrent++;
        if (concurrent > peakConcurrent) peakConcurrent = concurrent;
        if (reads == 1) await firstRead.future;
        concurrent--;
      },
    );
    addTearDown(coordinator.dispose);
    coordinator.connectionStatus(CollectSyncStatus.connected);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(reads, 1);
    for (var i = 0; i < 50; i++) {
      coordinator.event({'area': 'members', 'id': 'event-$i'});
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    firstRead.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(reads, 2);
    expect(peakConcurrent, 1);
  });

  test('sustained events pause after two reads before a new window', () async {
    final firstRead = Completer<void>();
    final secondRead = Completer<void>();
    var reads = 0;
    final coordinator = CollectSyncInvalidationCoordinator(
      areas: const {'members'},
      debounce: const Duration(milliseconds: 80),
      onInvalidate: () async {
        reads++;
        if (reads == 1) await firstRead.future;
        if (reads == 2) await secondRead.future;
      },
    );
    addTearDown(coordinator.dispose);

    coordinator.connectionStatus(CollectSyncStatus.connected);
    await Future<void>.delayed(const Duration(milliseconds: 110));
    expect(reads, 1);
    coordinator.event({'area': 'members', 'id': 'during-first'});
    await Future<void>.delayed(const Duration(milliseconds: 110));
    firstRead.complete();
    await Future<void>.delayed(Duration.zero);
    expect(reads, 2);

    coordinator.event({'area': 'members', 'id': 'during-second'});
    await Future<void>.delayed(const Duration(milliseconds: 110));
    expect(reads, 2);
    secondRead.complete();
    await Future<void>.delayed(Duration.zero);
    expect(reads, 2, reason: 'a third read requires another debounce window');
    await Future<void>.delayed(const Duration(milliseconds: 110));
    expect(reads, 3);
  });

  test('permission revocation clears live and cached private data', () async {
    const cache = CollectOfflineCache();
    await cache.save(
      CollectOfflineSnapshot(
        savedAt: DateTime.utc(2026, 9, 1),
        currentProfile: _profile,
        collections: [_group],
        paymentIntents: const [],
        contributions: const [],
      ),
    );
    final client = _client((request) {
      if (request.url.path.endsWith('get_current_member_profile')) {
        return _json(_profileRow);
      }
      return _json({
        'code': '42501',
        'message': 'permission denied',
      }, status: 403);
    });
    addTearDown(client.dispose);
    await _signIn(client);
    final repository = CollectRepository.fixture(
      initialState: CollectState(
        currentProfile: _profile,
        collections: [_group],
        paymentIntents: const [],
        contributions: const [],
      ),
      backend: client,
      offlineCache: cache,
    );
    addTearDown(repository.dispose);
    await repository.loadInitial();
    expect(repository.state.collections, isEmpty);
    expect(repository.state.currentProfile, isNull);
    expect(repository.state.usingStaleCache, isFalse);
    expect(await cache.read(), isNull);
    expect(await repository.restoreOfflineSnapshot(reason: 'offline'), isFalse);
  });

  test('profile for another account cannot restore the old cache', () async {
    const cache = CollectOfflineCache();
    await cache.save(
      CollectOfflineSnapshot(
        savedAt: DateTime.utc(2026, 9, 1),
        currentProfile: _profile,
        collections: [_group],
        paymentIntents: const [],
        contributions: const [],
      ),
    );
    final client = _client((request) {
      expect(request.url.path, endsWith('get_current_member_profile'));
      return _json({..._profileRow, 'id': _secondUserId});
    });
    addTearDown(client.dispose);
    await _signIn(client);
    final repository = CollectRepository.fixture(
      initialState: CollectState(
        currentProfile: _profile,
        collections: [_group],
        paymentIntents: const [],
        contributions: const [],
      ),
      backend: client,
      offlineCache: cache,
    );
    addTearDown(repository.dispose);
    await repository.loadInitial();
    expect(repository.state.currentProfile, isNull);
    expect(repository.state.collections, isEmpty);
    expect(repository.state.usingStaleCache, isFalse);
    expect(await cache.read(), isNull);
  });

  test('member catalogue removal replaces private state and cache', () async {
    const cache = CollectOfflineCache();
    var membershipActive = true;
    final client = _client((request) {
      final path = request.url.path;
      if (path.endsWith('get_current_member_profile')) {
        return _json(_profileRow);
      }
      if (path.endsWith('list_current_user_collections')) {
        return _json(membershipActive ? [_groupRow] : []);
      }
      if (path.endsWith('list_current_member_recent_intents')) {
        return _json({'items': [], 'pending_count': 0});
      }
      if (path.endsWith('list_current_member_history_page')) {
        return _json({
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
          'revision': '00000000000000000000000000000000',
          'next_cursor': null,
        });
      }
      if (path.endsWith('list_current_member_collection_balances')) {
        return _json([]);
      }
      if (path.endsWith('get_notification_preferences_v2')) {
        return _json({
          'contract_version': 2,
          'ok': true,
          'user_id': _userId,
          'revision': 0,
          'exists': false,
          'preferences': NotificationPreferences.defaults.toJson(),
        });
      }
      if (path.endsWith('notification-events')) {
        return _json([]);
      }
      fail('Unexpected request: $path');
    });
    addTearDown(client.dispose);
    await _signIn(client);
    final repository = CollectRepository(backend: client, offlineCache: cache);
    addTearDown(repository.dispose);
    await repository.loadInitial();
    expect(
      repository.state.collections,
      hasLength(1),
      reason: repository.state.lastError,
    );
    membershipActive = false;
    await repository.loadInitial();
    expect(
      repository.state.collections,
      isEmpty,
      reason: repository.state.lastError,
    );
    expect((await cache.read())?.collections, isEmpty);
  });

  test('account switch drops the first owner before reloading', () async {
    const cache = CollectOfflineCache();
    late final CollectCloudflareClient client;
    client = _client((request) {
      final path = request.url.path;
      final userId = client.auth.currentUser!.id;
      if (path.endsWith('get_current_member_profile')) {
        return _json({..._profileRow, 'id': userId});
      }
      if (path.endsWith('list_current_user_collections')) {
        return _json(userId == _userId ? [_groupRow] : []);
      }
      if (path.endsWith('list_current_member_recent_intents')) {
        return _json({'items': [], 'pending_count': 0});
      }
      if (path.endsWith('list_current_member_history_page')) {
        return _json({
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
          'revision': '00000000000000000000000000000000',
          'next_cursor': null,
        });
      }
      if (path.endsWith('get_notification_preferences_v2')) {
        return _json({
          'contract_version': 2,
          'ok': true,
          'user_id': userId,
          'revision': 0,
          'exists': false,
          'preferences': NotificationPreferences.defaults.toJson(),
        });
      }
      if (path.endsWith('list_current_member_collection_balances') ||
          path.endsWith('notification-events')) {
        return _json([]);
      }
      fail('Unexpected request: $path');
    });
    addTearDown(client.dispose);
    await _signIn(client);
    final repository = CollectRepository(backend: client, offlineCache: cache);
    addTearDown(repository.dispose);
    await repository.loadInitial();
    expect(repository.state.collections.single.id, _groupId);

    await _signIn(client, userId: _secondUserId);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(repository.state.collections, isEmpty);
    if (repository.state.currentProfile?.id != _secondUserId) {
      await repository.loadInitial();
    }
    expect(repository.state.currentProfile?.id, _secondUserId);
    expect(repository.state.collections, isEmpty);
    expect((await cache.read())?.currentProfile?.id, _secondUserId);
  });
}

CollectCloudflareClient _client(http.Response Function(http.Request) handler) =>
    CollectCloudflareClient(
      'http://127.0.0.1:1',
      httpClient: MockClient((request) async {
        final response = handler(request);
        return http.Response(
          response.body,
          response.statusCode,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

http.Response _json(Object? value, {int status = 200}) =>
    http.Response(jsonEncode(value), status);

Future<void> _signIn(
  CollectCloudflareClient client, {
  String userId = _userId,
}) => client.auth.recoverSession(
  jsonEncode({
    'access_token': syntheticMemberAccessToken(userId),
    'refresh_token': 'synthetic-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'app_metadata': {},
      'user_metadata': {},
      'created_at': '2026-09-01T00:00:00Z',
    },
  }),
);
