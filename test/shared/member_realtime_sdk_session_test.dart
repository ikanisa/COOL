import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';

const _a = '99790000-0000-4000-8000-000000000001';
const _b = '99790000-0000-4000-8000-000000000002';
const _groupA = '99790000-0000-4000-8000-000000000011';
const _groupB = '99790000-0000-4000-8000-000000000012';

String _token(String user, String sid, [int revision = 0]) {
  String part(Object body) =>
      base64Url.encode(utf8.encode(jsonEncode(body))).replaceAll('=', '');
  final issued = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  return '${part({'alg': 'none'})}.${part({'sub': user, 'session_id': sid, 'role': 'authenticated', 'surface': 'member', 'iat': issued, 'exp': issued + 3600, 'revision': revision})}.synthetic';
}

Map<String, dynamic> _claims(String token) => Map<String, dynamic>.from(
  jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
      )
      as Map,
);

class _Sms extends SmsAccessChannel {
  const _Sms();
  @override
  Future<bool> suspendUnlessOwner(String? ownerUserId) async => true;
}

class _SyncScope {
  _SyncScope(this.epoch, this.request);
  final int epoch;
  final http.Request request;
  final requests = <http.Request>[];
  final queued = <Map<String, dynamic>>[];
  Completer<http.Response>? pending;
  http.Request? pendingRequest;
  bool failNext = false;
  bool recovering = false;
  int cursor = 0;
  String get topic => 'http-sync-$epoch';
  Map<String, dynamic> get payload => {
    'access_token': request.headers['Authorization']!.substring(7),
  };
  http.Response reply(http.Request request, {bool failed = false}) {
    final events = List<Map<String, dynamic>>.of(queued);
    if (!failed) {
      queued.clear();
      cursor += events.length;
    }
    return http.Response(
      jsonEncode(
        failed
            ? {'code': 'synthetic_outage'}
            : {'events': events, 'cursor': '$cursor'},
      ),
      failed ? 503 : 200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }

  Future<http.Response> accept(http.Request next) async {
    requests.add(next);
    expect(next.method, 'GET');
    expect(next.url.queryParameters['limit'], '100');
    expect(next.url.queryParameters['areas']!.split(','), contains('members'));
    if (requests.length == 1 || recovering) {
      recovering = false;
      return reply(next);
    }
    if (failNext) {
      failNext = false;
      recovering = true;
      return reply(next, failed: true);
    }
    if (queued.isNotEmpty) return reply(next);
    expect(
      pending,
      isNull,
      reason: 'The current HTTP adapter must not overlap polls',
    );
    pending = Completer<http.Response>();
    pendingRequest = next;
    return pending!.future;
  }

  void flush() {
    if (pending == null) return;
    final response = reply(pendingRequest!, failed: failNext);
    if (failNext) {
      failNext = false;
      recovering = true;
    }
    final completion = pending!;
    pending = null;
    pendingRequest = null;
    completion.complete(response);
  }

  void event(String id, {String area = 'members'}) {
    queued.add({'id': id, 'area': area});
    flush();
  }

  void bindingFailure() {
    failNext = true;
    flush();
  }

  void finish() {
    flush();
  }
}

class _Pending {
  final entered = Completer<void>();
  final release = Completer<void>();
}

// The production Cloudflare HTTP client, repository, cache and polling adapter
// execute unchanged. Held HTTP responses model account changes and transport
// interruptions. All claims and records are synthetic; this grants no hosted,
// provider, signed-token or installed-device acceptance.
class _Probe {
  late CollectCloudflareClient client;
  late CollectRepository repo;
  final cache = const CollectOfflineCache(
    preferencesKey: 'synthetic.member.http.scope',
  );
  final joins = <_SyncScope>[];
  int epoch = 0;
  String? sessionOwner;
  final requests = <http.Request>[];
  final retainedReads = <_Pending>[];
  bool disposed = false;
  bool revoked = false;
  bool offline = false;
  bool member = true;
  _Pending? pendingProfile;
  int get reads => requests
      .where((r) => r.url.path.endsWith('get_current_member_profile'))
      .length;

  Future<void> start() async {
    client = CollectCloudflareClient(
      'https://api.collect.test',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/logout')) {
          return _json(request, {});
        }
        if (offline) {
          throw const SocketException('Synthetic offline transport');
        }
        if (request.url.path == '/v1/sync') {
          var current = joins.reversed
              .where((scope) => scope.epoch == epoch)
              .firstOrNull;
          // A fresh subscription restarts its HTTP cursor after revocation.
          // Never replay a departed response queue into that new subscription.
          if (current != null &&
              current.cursor > 0 &&
              request.url.queryParameters['cursor'] == '0') {
            current = null;
          }
          final scope = current ?? _SyncScope(epoch, request);
          if (current == null) joins.add(scope);
          return scope.accept(request);
        }
        final claims = _claims(request.headers['Authorization']!.substring(7));
        final user = claims['sub'] as String;
        final group = user == _a ? _groupA : _groupB;
        if (revoked) {
          return _json(request, {
            'code': '42501',
            'message': 'Synthetic revoked member',
          }, status: 403);
        }
        final body = switch (request.url.path.split('/').last) {
          'get_current_member_profile' => {
            'id': user,
            'public_id': user == _a ? '123456' : '234567',
            'whatsapp_phone': '250788123456',
            'country_code': 'RW',
            'currency_code': 'RWF',
          },
          'list_current_user_collections' =>
            member
                ? [
                    {
                      'id': group,
                      'slug': 'synthetic-member-${user == _a ? 'a' : 'b'}',
                      'creator_user_id': user,
                      'title': 'Synthetic private ${user == _a ? 'A' : 'B'}',
                      'description': '',
                      'payment_rail': 'rwanda_momo',
                      'settlement_currency': 'RWF',
                      'receiver_network': 'mtn_momo',
                      'is_member': true,
                      'created_at': '2026-09-01T00:00:00Z',
                    },
                  ]
                : [],
          'list_current_member_recent_intents' => {
            'items': [],
            'pending_count': 0,
          },
          'list_current_member_history_page' => {
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
          },
          'list_current_member_collection_balances' => [],
          'get_notification_preferences_v2' => {
            'contract_version': 2,
            'ok': true,
            'user_id': user,
            'revision': 0,
            'exists': false,
            'preferences': NotificationPreferences.defaults.toJson(),
          },
          'notification-events' => [],
          _ => throw StateError(
            'Unexpected fixture dispatch: ${request.url.path}',
          ),
        };
        final pending = pendingProfile;
        if (request.url.path.endsWith('get_current_member_profile') &&
            pending != null) {
          pendingProfile = null;
          retainedReads.add(pending);
          pending.entered.complete();
          await pending.release.future;
        }
        return _json(request, body);
      }),
    );
    await login(_a, 'session-a');
    repo = CollectRepository(
      backend: client,
      smsAccessChannel: const _Sms(),
      offlineCache: cache,
    );
    await repo.loadInitial();
    await until(() => joins.length == 1 && reads == 2 && !repo.state.isLoading);
    expect(repo.state.lastError, isNull);
    expect((await cache.read())?.collections.single.id, _groupA);
  }

  http.Response _json(http.Request request, Object? body, {int status = 200}) =>
      http.Response(
        jsonEncode(body),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );

  Future<void> login(String user, String sid, {int revision = 0}) async {
    final owner = '$user:$sid';
    if (sessionOwner != owner) {
      epoch++;
      sessionOwner = owner;
    }
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': _token(user, sid, revision),
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
      }),
    );
  }

  Future<void> until(bool Function() predicate) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!predicate() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      predicate(),
      isTrue,
      reason:
          'joins=${joins.length}, profile reads=$reads, lastError=${disposed ? 'disposed' : repo.state.lastError}',
    );
  }

  Future<void> quiet() =>
      Future<void>.delayed(const Duration(milliseconds: 450));

  Future<void> close() async {
    for (final pending in retainedReads) {
      if (!pending.release.isCompleted) pending.release.complete();
    }
    if (!disposed) {
      disposed = true;
      repo.dispose();
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
    for (final scope in joins) {
      scope.finish();
    }
    await client.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Probe probe;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    probe = _Probe();
    await probe.start();
  });
  tearDown(() async => probe.close());

  test(
    'Cloudflare member HTTP sync successful poll and duplicate/irrelevant events yield one refresh',
    () async {
      expect(
        probe.joins.single.payload['access_token'],
        probe.client.auth.currentSession!.accessToken,
      );
      await probe.quiet();
      expect(probe.reads, 2);
      probe.joins.single.event('duplicate');
      probe.joins.single.event('duplicate');
      probe.joins.single.event('irrelevant', area: 'not-a-member-area');
      await probe.until(() => probe.reads == 3 && !probe.repo.state.isLoading);
      await probe.quiet();
      expect(probe.reads, 3);
      final polls = probe.joins.single.requests.length;
      probe.joins.single.event('duplicate');
      await probe.until(() => probe.joins.single.requests.length > polls);
      await probe.quiet();
      expect(probe.reads, 3);
      expect(probe.repo.state.collections.single.id, _groupA);
    },
  );

  test(
    'Cloudflare member HTTP sync failed poll retries and reconciles missed membership reduction',
    () async {
      final old = probe.joins.single;
      probe.member = false;
      old.bindingFailure();
      old.event('missed-offline');
      await probe.until(
        () =>
            probe.joins.single.requests.length >= 3 &&
            probe.reads >= 3 &&
            !probe.repo.state.isLoading,
      );
      await probe.quiet();
      expect(probe.reads, 3);
      expect(probe.repo.state.collections, isEmpty);
      expect((await probe.cache.read())?.collections, isEmpty);
      expect(probe.joins, hasLength(1));
      expect(probe.joins.single.requests, hasLength(3));
      probe.member = true;
      probe.joins.last.event('current-after-rejoin');
      await probe.until(() => probe.reads == 4 && !probe.repo.state.isLoading);
      expect(probe.repo.state.collections.single.id, _groupA);
    },
  );

  for (final mode in [
    'replacement session',
    'same-user A-B-A',
    'account switch',
  ]) {
    test(
      'Cloudflare member HTTP sync $mode cancels queued and late departed HTTP responses',
      () async {
        final old = probe.joins.single;
        await probe.until(() => old.pending != null);
        old.event('departed-pending');
        final user = mode == 'account switch' ? _b : _a;
        await probe.login(user, 'session-b');
        if (mode == 'same-user A-B-A') {
          await probe.login(_a, 'session-a');
        }
        await probe.until(
          () =>
              probe.joins.length >= 2 &&
              !probe.repo.state.isLoading &&
              probe.repo.state.currentProfile?.id == user,
        );
        await probe.quiet();
        final reads = probe.reads;
        old.event('departed-late');
        await probe.quiet();
        expect(
          probe.reads,
          reads,
          reason:
              'A departed HTTP response cannot refresh a replacement authority scope',
        );
        expect(
          probe.joins.map((join) => join.topic).toSet(),
          hasLength(probe.joins.length),
        );
        expect(
          probe.joins.last.payload['access_token'],
          probe.client.auth.currentSession!.accessToken,
        );
        expect((await probe.cache.read())?.currentProfile?.id, user);
        expect(
          (await probe.cache.read())?.collections.single.id,
          user == _a ? _groupA : _groupB,
        );
        probe.joins.last.event('current-session-control');
        await probe.until(
          () => probe.reads == reads + 1 && !probe.repo.state.isLoading,
        );
        expect(probe.repo.state.currentProfile?.id, user);
      },
    );
  }

  for (final mode in [
    'replacement session',
    'same-user A-B-A',
    'account switch',
  ]) {
    test(
      'Cloudflare member HTTP sync held response after $mode cannot restore old rows',
      () async {
        final old = probe.joins.single;
        await probe.until(() => old.pending != null);
        final user = mode == 'account switch' ? _b : _a;
        await probe.login(user, 'session-b');
        if (mode == 'same-user A-B-A') await probe.login(_a, 'session-a');
        await probe.until(
          () =>
              probe.joins.length >= 2 &&
              !probe.repo.state.isLoading &&
              probe.repo.state.currentProfile?.id == user,
        );
        await probe.quiet();
        final reads = probe.reads;
        expect(
          old.pending,
          isNotNull,
          reason: 'The old HTTP response is still retained',
        );
        old.event('retained-departed-response');
        await probe.quiet();
        expect(probe.reads, reads);
        expect(probe.repo.state.currentProfile?.id, user);
        expect((await probe.cache.read())?.currentProfile?.id, user);
        expect(
          (await probe.cache.read())?.collections.single.id,
          user == _a ? _groupA : _groupB,
        );
        probe.joins.last.event('current-http-positive-control');
        await probe.until(
          () => probe.reads == reads + 1 && !probe.repo.state.isLoading,
        );
      },
    );
  }

  test(
    'Cloudflare member HTTP sync same-session token refresh preserves polling scope and current writes',
    () async {
      final old = probe.joins.single;
      await probe.login(_a, 'session-a', revision: 1);
      await probe.quiet();
      expect(probe.joins, hasLength(1));
      expect(probe.reads, 2);
      old.event('current-refreshed-token');
      await probe.until(() => probe.reads == 3 && !probe.repo.state.isLoading);
      expect(
        probe.requests.last.headers['Authorization'],
        'Bearer ${probe.client.auth.currentSession!.accessToken}',
      );
      expect((await probe.cache.read())?.collections.single.id, _groupA);
    },
  );

  test(
    'Cloudflare member HTTP sync old in-flight refresh cannot republish old account/cache',
    () async {
      final old = probe.joins.single;
      final pending = _Pending();
      probe.pendingProfile = pending;
      old.event('retain-old-read');
      await pending.entered.future;
      final oldRequest = probe.requests.last;
      await probe.login(_b, 'session-b');
      await probe.until(
        () =>
            probe.joins.length == 2 &&
            !probe.repo.state.isLoading &&
            probe.repo.state.currentProfile?.id == _b,
      );
      // The replacement polling scope's legitimate connection reconciliation is distinct
      // from the retained old request. Settle that current read before its
      // final dispatch count becomes the old-request negative control.
      await probe.quiet();
      final before = probe.requests.length;
      pending.release.complete();
      await probe.quiet();
      expect(
        _claims(oldRequest.headers['Authorization']!.substring(7))['sub'],
        _a,
      );
      expect(
        probe.requests.length,
        before,
        reason: 'The old pipeline must stop before its next scoped read',
      );
      expect(probe.repo.state.collections.single.id, _groupB);
      expect((await probe.cache.read())?.currentProfile?.id, _b);
      expect((await probe.cache.read())?.collections.single.id, _groupB);
      old.event('old-after-barrier');
      await probe.quiet();
      expect(probe.requests.length, before);
    },
  );

  test(
    'Cloudflare member HTTP sync retained rows stay stale when failed refresh has no readable cache',
    () async {
      final lastSync = probe.repo.state.lastSuccessfulSyncAt;
      final priorRows = probe.repo.state.collections;
      expect(lastSync, isNotNull);
      await probe.cache.clear();
      expect(await probe.cache.read(), isNull);
      probe.offline = true;
      await probe.repo.loadInitial();

      expect(probe.repo.state.lastError, isNotNull);
      expect(probe.repo.state.collections, priorRows);
      expect(probe.repo.state.lastSuccessfulSyncAt, lastSync);
      expect(probe.repo.state.usingStaleCache, isTrue);
      final reads = probe.requests.length;
      await expectLater(
        probe.repo.fetchHistoryPage(const MemberHistoryQuery()),
        throwsStateError,
      );
      expect(probe.requests.length, reads);

      probe.offline = false;
      await probe.repo.loadInitial();
      expect(probe.repo.state.lastError, isNull);
      expect(probe.repo.state.usingStaleCache, isFalse);
      expect(probe.repo.state.collections.single.id, _groupA);
      expect(
        probe.repo.state.lastSuccessfulSyncAt!.isBefore(lastSync!),
        isFalse,
      );
    },
  );

  test(
    'Cloudflare member HTTP sync revoked read clears private cache and departed responses cannot restore it offline',
    () async {
      final old = probe.joins.single;
      probe.revoked = true;
      old.event('revocation');
      await probe.until(
        () =>
            probe.repo.state.currentProfile == null &&
            probe.repo.state.lastError != null,
      );
      expect(probe.repo.state.collections, isEmpty);
      expect(probe.repo.state.historyPage, isNull);
      expect(await probe.cache.read(), isNull);
      await probe.quiet();
      final reads = probe.reads;
      probe.revoked = false;
      probe.offline = true;
      old.event('departed-revoked-cache');
      await probe.quiet();
      expect(probe.reads, reads);
      expect(
        await probe.repo.restoreOfflineSnapshot(reason: 'synthetic offline'),
        isFalse,
      );
      expect(probe.repo.state.usingStaleCache, isFalse);
      expect(await probe.cache.read(), isNull);
      probe.offline = false;
      await probe.repo.loadInitial();
      await probe.until(
        () => probe.joins.length == 2 && !probe.repo.state.isLoading,
      );
      expect(probe.repo.state.collections.single.id, _groupA);
      expect((await probe.cache.read())?.collections.single.id, _groupA);
    },
  );

  test(
    'Cloudflare member HTTP sync logout cancels pending work and leaves no private cache',
    () async {
      final old = probe.joins.single;
      await probe.until(() => old.pending != null);
      old.event('logout-pending');
      await probe.client.auth.signOut(scope: CollectSignOutScope.local);
      await probe.until(() => probe.repo.state.currentProfile == null);
      await probe.quiet();
      final requests = probe.requests.length;
      old.event('logout-late');
      await probe.quiet();
      expect(probe.requests.length, requests);
      expect(probe.repo.state.currentProfile, isNull);
      expect(probe.repo.state.collections, isEmpty);
      expect(await probe.cache.read(), isNull);
      expect(probe.joins, hasLength(1));
    },
  );

  test(
    'Cloudflare member HTTP sync repository disposal cancels pending poll callbacks',
    () async {
      await probe.until(() => probe.joins.single.pending != null);
      probe.joins.single.event('dispose-pending');
      probe.repo.dispose();
      probe.disposed = true;
      final requests = probe.requests.length;
      await Future<void>.delayed(const Duration(milliseconds: 5500));
      expect(probe.requests.length, requests);
      expect(probe.reads, 2);
    },
  );
}
