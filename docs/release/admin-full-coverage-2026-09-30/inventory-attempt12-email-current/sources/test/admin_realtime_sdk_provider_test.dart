import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;

// Real locked SDK and production provider, with an isolated loopback Phoenix
// 2.0 WebSocket. No hosted service, database or provider is contacted.
class _Join {
  _Join(this.socket, this.joinRef, this.topic, this.payload);
  final WebSocket socket;
  final Object? joinRef;
  final String topic;
  final Map<String, dynamic> payload;
  int events = 0;

  void event(String id, {String area = 'members'}) {
    events++;
    socket.add(
      jsonEncode([
        joinRef,
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

  void replicationFailure() => socket.add(
    jsonEncode([
      joinRef,
      null,
      topic,
      'system',
      {'status': 'error', 'message': 'Synthetic binding unavailable'},
    ]),
  );
}

class _Probe {
  late HttpServer server;
  late SupabaseClient client;
  late ProviderContainer container;
  final joins = <_Join>[];
  final sockets = <WebSocket>[];
  final frames = <List<dynamic>>[];
  int identityReads = 0;
  final identityActors = <String>[];
  bool disposed = false;
  bool closing = false;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.notFound;
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
            (event == 'phx_join' ||
                event == 'phx_leave' ||
                event == 'heartbeat')) {
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
        if (request.url.path.endsWith('/verify')) {
          final values = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          final receipt = auth.authReceipt(values[0], values[1]);
          if (values[0] == 'realtime-other-account') {
            final parts = (receipt['access_token'] as String).split('.');
            final claims =
                jsonDecode(
                      utf8.decode(
                        base64Url.decode(base64Url.normalize(parts[1])),
                      ),
                    )
                    as Map<String, dynamic>;
            claims['sub'] = auth.target;
            receipt['access_token'] =
                '${parts[0]}.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.${parts[2]}';
            (receipt['user'] as Map)['id'] = auth.target;
          }
          return auth.response(receipt);
        }
        if (request.url.path.endsWith('/logout')) return auth.response({});
        throw StateError('Unexpected HTTP: ${request.url.path}');
      }),
    );
    await auth.session(client, 'realtime-owner-a');
    container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        adminIdentityProvider.overrideWith((ref) async {
          final actor = ref.watch(adminAuthUserIdProvider);
          if (actor == null) return null;
          identityReads++;
          identityActors.add(actor);
          return AdminIdentity(
            userId: actor,
            displayName: 'Synthetic realtime operator',
            roles: ['admin'],
            permissions: ['users.read'],
          );
        }),
      ],
    );
    container.listen(adminIdentityProvider, (_, _) {});
    await container.read(adminIdentityProvider.future);
    container.listen(adminRealtimeSubscriptionProvider, (_, _) {});
    await until(() => joins.isNotEmpty && ticks == 1 && identityReads >= 2);
  }

  int get ticks => container.read(adminRealtimeTickProvider);

  Future<void> until(bool Function() predicate) async {
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    while (!predicate() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      predicate(),
      isTrue,
      reason:
          'joins=${joins.length}, frames=${frames.map((f) => f[3]).toList()}',
    );
  }

  Future<void> quiet() =>
      Future<void>.delayed(const Duration(milliseconds: 450));

  Future<void> dispose() async {
    if (!disposed) {
      disposed = true;
      container.dispose();
    }
    // Let the production leave handshake finish before closing this fixture's
    // socket. A queued leave must not receive an ACK after client.disconnect.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    closing = true;
    await client.dispose();
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  }
}

void main() {
  late _Probe probe;
  setUp(() async {
    probe = _Probe();
    await probe.start();
  });
  tearDown(() => probe.dispose());

  test(
    'actual SDK Admin channel joins with current token and reconciles once',
    () async {
      expect(
        probe.joins.single.topic,
        startsWith('realtime:collect:admin:invalidation:'),
      );
      expect(
        probe.joins.single.payload['access_token'],
        probe.client.auth.currentSession!.accessToken,
      );
      expect(
        (probe.joins.single.payload['config'] as Map)['postgres_changes'],
        [
          {
            'event': 'INSERT',
            'schema': 'public',
            'table': 'app_realtime_events',
          },
        ],
      );
      expect(probe.identityReads, 2);
      await probe.quiet();
      expect(probe.ticks, 1);
      probe.joins.single.event('same-event');
      probe.joins.single.event('same-event');
      probe.joins.single.event('irrelevant-event', area: 'not-an-admin-area');
      await probe.until(() => probe.ticks == 2);
      await probe.quiet();
      expect(probe.ticks, 2);
      expect(probe.identityReads, 3);
    },
  );

  test(
    'actual SDK Admin binding error rejoins and reconciles missed events',
    () async {
      final previous = probe.joins.single;
      previous.replicationFailure();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      previous.event('missed-before-rejoin');
      await probe.until(() => probe.joins.length == 2 && probe.ticks == 2);
      expect(
        probe.frames.where((frame) => frame[3] == 'phx_leave'),
        hasLength(1),
      );
      await probe.quiet();
      expect(
        probe.ticks,
        2,
        reason: 'rejoin replaces missed-event delivery with one scoped refresh',
      );
      previous.event('stale-channel-event');
      await probe.until(() => probe.ticks == 3);
      // A binding rejoin stays inside the same live Auth/provider scope.
      // Its invalidation asks for a fresh scoped read and contains no records.
      previous.event('stale-channel-event');
      await probe.quiet();
      expect(probe.ticks, 3);
      probe.joins.last.event('current-channel-event');
      await probe.until(() => probe.ticks == 4);
    },
  );

  for (final switchBack in [false, true]) {
    test(
      'actual SDK Admin pending old channel is suppressed after session change A-B-A=$switchBack',
      () async {
        final old = probe.joins.single;
        old.event('old-scope-event');
        await auth.session(probe.client, 'realtime-owner-b');
        if (switchBack) await auth.session(probe.client, 'realtime-owner-a');
        await probe.until(() => probe.joins.length >= 2 && probe.ticks == 2);
        await probe.quiet();
        expect(
          probe.ticks,
          2,
          reason:
              'only the new channel join may reconcile; the old debounce is cancelled',
        );
        old.event('late-old-scope-event');
        await probe.quiet();
        expect(probe.ticks, 2);
        expect(
          probe.joins.last.payload['access_token'],
          probe.client.auth.currentSession!.accessToken,
        );
        expect(
          probe.joins.map((join) => join.topic).toSet(),
          hasLength(probe.joins.length),
        );
        probe.joins.last.event('new-scope-event');
        await probe.until(() => probe.ticks == 3);
      },
    );
  }

  test(
    'actual SDK Admin logout leaves its channel and cancels pending work',
    () async {
      final old = probe.joins.single;
      old.event('pending-before-logout');
      await probe.client.auth.signOut(scope: SignOutScope.local);
      await probe.until(
        () => probe.frames.any((frame) => frame[3] == 'phx_leave'),
      );
      expect(probe.container.read(adminAuthSessionScopeProvider), isNull);
      old.event('late-after-logout');
      await probe.quiet();
      expect(probe.ticks, 1);
      expect(probe.joins, hasLength(1));
    },
  );

  test(
    'actual SDK Admin account switch separates departed frames and refreshes the current actor',
    () async {
      final old = probe.joins.single;
      old.event('old-account-pending');
      await auth.session(probe.client, 'realtime-other-account');
      await probe.until(() => probe.joins.length == 2 && probe.ticks == 2);
      expect(
        probe.container.read(adminAuthSessionScopeProvider)!.key.userId,
        auth.target,
      );
      expect(probe.identityActors.last, auth.target);
      old.event('old-account-late');
      await probe.quiet();
      expect(probe.ticks, 2);
      probe.joins.last.event('current-account-event');
      await probe.until(() => probe.ticks == 3);
      expect(probe.identityActors.last, auth.target);
    },
  );

  test(
    'actual SDK Admin provider disposal leaves and cancels its debounce',
    () async {
      probe.joins.single.event('pending-before-dispose');
      probe.container.dispose();
      probe.disposed = true;
      await probe.until(
        () => probe.frames.any((frame) => frame[3] == 'phx_leave'),
      );
      await probe.quiet();
      expect(probe.identityReads, 2);
      expect(probe.joins, hasLength(1));
    },
  );
}
