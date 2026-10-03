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
import 'package:supabase_flutter/supabase_flutter.dart';

const _a = '99790000-0000-4000-8000-000000000001';
const _b = '99790000-0000-4000-8000-000000000002';
const _groupA = '99790000-0000-4000-8000-000000000011';
const _groupB = '99790000-0000-4000-8000-000000000012';

String _token(String user, String sid, [int revision = 0]) {
  String part(Object body) =>
      base64Url.encode(utf8.encode(jsonEncode(body))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'sub': user, 'session_id': sid, 'role': 'authenticated', 'revision': revision})}.synthetic';
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

class _Join {
  _Join(this.socket, this.ref, this.topic, this.payload);
  final WebSocket socket;
  final Object? ref;
  final String topic;
  final Map<String, dynamic> payload;

  void event(String id, {String area = 'members'}) {
    socket.add(
      jsonEncode([
        ref,
        null,
        topic,
        'postgres_changes',
        {
          'ids': [1],
          'data': {
            'schema': 'public',
            'table': 'app_realtime_events',
            'type': 'INSERT',
            'commit_timestamp': '2026-09-30T10:00:00Z',
            'columns': [
              {'name': 'id', 'type': 'text'},
              {'name': 'area', 'type': 'text'},
            ],
            'record': {'id': id, 'area': area},
            'old_record': <String, dynamic>{},
          },
        },
      ]),
    );
  }

  void bindingFailure() => socket.add(
    jsonEncode([
      ref,
      null,
      topic,
      'system',
      {'status': 'error', 'message': 'Synthetic binding interruption'},
    ]),
  );
}

class _Pending {
  final entered = Completer<void>();
  final release = Completer<void>();
}

// HTTP reads use the actual locked PostgREST/Auth SDK with explicit response
// request metadata; Phoenix frames traverse a genuine loopback WebSocket.
// Claims and financial records are synthetic mechanics, not signed JWT/RLS or
// provider evidence. Production repository, cache and subscription are real.
class _Probe {
  late HttpServer server;
  late SupabaseClient client;
  late CollectRepository repo;
  final cache = const CollectOfflineCache(
    preferencesKey: 'synthetic.member.ws.scope',
  );
  final joins = <_Join>[];
  final sockets = <WebSocket>[];
  final frames = <List<dynamic>>[];
  final requests = <http.Request>[];
  final retainedReads = <_Pending>[];
  bool closing = false;
  bool disposed = false;
  bool revoked = false;
  bool offline = false;
  bool member = true;
  _Pending? pendingProfile;
  int get reads => requests
      .where((r) => r.url.path.endsWith('get_current_member_profile'))
      .length;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((raw) {
        final frame = jsonDecode(raw as String) as List<dynamic>;
        frames.add(frame);
        final event = frame[3];
        final payload = Map<String, dynamic>.from(frame[4] as Map);
        Map<String, dynamic> response = {};
        if (event == 'phx_join') {
          joins.add(_Join(socket, frame[0], frame[2] as String, payload));
          final filters =
              (payload['config'] as Map)['postgres_changes'] as List;
          response = {
            'postgres_changes': [
              for (final filter in filters)
                {...Map<String, dynamic>.from(filter as Map), 'id': 1},
            ],
          };
        }
        if (!closing &&
            socket.readyState == WebSocket.open &&
            ['phx_join', 'phx_leave', 'heartbeat'].contains(event)) {
          socket.add(
            jsonEncode([
              frame[0],
              frame[1],
              frame[2],
              'phx_reply',
              {'status': 'ok', 'response': response},
            ]),
          );
        }
      });
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'synthetic-publishable',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/logout')) {
          return _json(request, {});
        }
        if (offline) {
          throw const SocketException('Synthetic offline transport');
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
            'items': [],
            'total_count': 0,
            'totals': {},
            'own_totals': {},
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
          'notification_events' => [],
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
      supabase: client,
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

  Future<void> login(String user, String sid, {int revision = 0}) =>
      client.auth.setInitialSession(
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

  Future<void> until(bool Function() predicate) async {
    final deadline = DateTime.now().add(const Duration(seconds: 8));
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
    closing = true;
    await client.dispose();
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
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
    'actual member SDK current join and duplicate/irrelevant frames yield one refresh',
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
      probe.joins.single.event('duplicate');
      await probe.quiet();
      expect(probe.reads, 3);
      expect(probe.repo.state.collections.single.id, _groupA);
    },
  );

  test(
    'actual member SDK failed binding rejoins and reconciles missed membership reduction',
    () async {
      final old = probe.joins.single;
      probe.member = false;
      old.bindingFailure();
      old.event('missed-offline');
      await probe.until(
        () =>
            probe.joins.length == 2 &&
            probe.reads >= 3 &&
            !probe.repo.state.isLoading,
      );
      await probe.quiet();
      expect(probe.reads, 3);
      expect(probe.repo.state.collections, isEmpty);
      expect((await probe.cache.read())?.collections, isEmpty);
      expect(
        probe.frames.where((frame) => frame[3] == 'phx_leave'),
        hasLength(1),
      );
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
      'actual member SDK $mode cancels pending and late departed frames',
      () async {
        final old = probe.joins.single;
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
              'A departed socket frame cannot refresh a replacement authority scope',
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

  test(
    'actual member SDK same-session token refresh preserves live channel and current writes',
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
    'actual member SDK old in-flight refresh cannot republish old account/cache',
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
      // The replacement channel's legitimate join reconciliation is distinct
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
    'actual member SDK retained rows stay stale when failed refresh has no readable cache',
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
    'actual member SDK revoked read clears private cache and departed frames cannot restore it offline',
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
    'actual member SDK logout cancels pending work and leaves no private cache',
    () async {
      final old = probe.joins.single;
      old.event('logout-pending');
      await probe.client.auth.signOut(scope: SignOutScope.local);
      await probe.until(
        () => probe.frames.any((frame) => frame[3] == 'phx_leave'),
      );
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
    'actual member SDK repository disposal cancels pending channel callbacks',
    () async {
      probe.joins.single.event('dispose-pending');
      probe.repo.dispose();
      probe.disposed = true;
      await probe.until(
        () => probe.frames.any((frame) => frame[3] == 'phx_leave'),
      );
      await probe.quiet();
      expect(probe.reads, 2);
    },
  );
}
