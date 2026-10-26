import 'dart:async';
import 'dart:convert';

import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/cloudflare/realtime_invalidation.dart';
import 'package:collect_app/core/supabase/collect_supabase_configuration.dart';
import 'package:collect_app/core/supabase/collect_supabase_member_realtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _app = '99110000-0000-4000-8000-000000000001';
const _subject = '99110000-0000-4000-8000-000000000002';
const _sid = '99110000-0000-4000-8000-000000000003';
const _sid2 = '99110000-0000-4000-8000-000000000004';
const _secret = 'SYNTHETIC_JWT_PRIVATE_MARKER';
const _project = 'https://rrlduytparvsjfmegalh.supabase.co';

String _token(String sid, int revision, {bool mapped = true}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'sub': mapped ? _subject : _app, 'session_id': sid, 'iss': '$_project/auth/v1', 'aud': 'authenticated', 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600, 'revision': revision})}.$_secret';
}

class _Socket implements WebSocketChannel {
  _Socket({this.autoJoin = true, this.autoHeartbeat = true}) {
    sink = _Sink(this);
  }
  final bool autoJoin, autoHeartbeat;
  final incoming = StreamController<Object>();
  final sent = <Map<String, dynamic>>[];
  // Fake sink lifetime belongs to this socket and SDK disconnect().
  @override
  // ignore: close_sinks
  late final _Sink sink;
  bool throwOnSend = false;
  int? _closeCode;
  String? _closeReason;
  @override
  Stream<Object> get stream => incoming.stream;
  @override
  Future<void> get ready => Future.value();
  @override
  String? get protocol => null;
  @override
  int? get closeCode => _closeCode;
  @override
  String? get closeReason => _closeReason;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void receive(Map<String, dynamic> message) {
    if (!incoming.isClosed) incoming.add(jsonEncode(message));
  }

  void ack(Map<String, dynamic> message) => receive({
    'topic': message['topic'],
    'event': 'phx_reply',
    'ref': message['ref'],
    'join_ref': message['join_ref'],
    'payload': {'status': 'ok', 'response': <String, dynamic>{}},
  });
  void hint(String id, {Map<String, dynamic>? data}) => receive({
    'topic': 'realtime:collect:member:$_subject:$_sid',
    'event': 'broadcast',
    'ref': null,
    'join_ref': null,
    'payload': {
      'type': 'broadcast',
      'event': 'invalidate',
      'payload': data ?? {'v': 1, 'id': id},
    },
  });
  Future<void> serverClose(String reason) async {
    _closeCode = 1006;
    _closeReason = reason;
    await incoming.close();
  }
}

class _Sink implements WebSocketSink {
  _Sink(this.owner);
  final _Socket owner;
  final _done = Completer<void>();
  @override
  Future<void> get done => _done.future;
  @override
  void add(Object? value) {
    if (owner.throwOnSend) throw StateError(_secret);
    final message = jsonDecode(value as String) as Map<String, dynamic>;
    owner.sent.add(message);
    if ((message['event'] == 'phx_join' && owner.autoJoin) ||
        (message['event'] == 'heartbeat' && owner.autoHeartbeat)) {
      owner.ack(message);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (!owner.incoming.isClosed) owner.incoming.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final value in stream) {
      add(value);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    owner._closeCode = closeCode;
    owner._closeReason = closeReason;
    if (!owner.incoming.isClosed) await owner.incoming.close();
    if (!_done.isCompleted) _done.complete();
  }
}

class _Harness {
  _Harness({
    this.autoJoin = true,
    this.autoHeartbeat = true,
    this.httpReply,
    this.surface = 'member',
    this.useSupabase = true,
  });
  final bool autoJoin, autoHeartbeat;
  final String surface;
  final bool useSupabase;
  final Future<http.Response> Function(http.Request)? httpReply;
  final sockets = <_Socket>[];
  final urls = <String>[];
  final headers = <Map<String, String>>[];
  final statuses = <bool>[];
  final requests = <http.Request>[];
  late final CollectCloudflareClient client;
  CollectSupabaseMemberRealtime? adapter;
  CollectSyncInvalidationSubscription? subscription;
  int reads = 0;

  Future<void> login({String sid = _sid, int revision = 0}) => client.auth
      .recoverSession(
        jsonEncode({
          'access_token': _token(sid, revision, mapped: useSupabase),
          'refresh_token': 'SYNTHETIC_REFRESH',
          'token_type': 'bearer',
          'user': {'id': _app, if (useSupabase) 'auth_user_id': _subject},
        }),
        event: revision == 0
            ? CollectAuthEvent.signedIn
            : CollectAuthEvent.tokenRefreshed,
      )
      .then((_) {});

  Future<void> initialize() async {
    final config = CollectSupabaseConfiguration.fromEnvironment(
      const AppEnv(
        apiUrl: '',
        publicUrl: 'https://collect.ikanisa.com',
        adminAppUrl: '',
        enableSmsReader: false,
        enableAndroidSmsAccess: false,
        enableAdminPanel: false,
        enableAdminDevTools: false,
        authCaptchaEnabled: false,
        authCaptchaProvider: '',
        authCaptchaSiteKey: '',
        backend: 'supabase',
        supabaseUrl: _project,
        supabaseApiUrl: 'https://platform-admin.collect.ikanisa.com',
        supabasePublishableKey: 'sb_publishable_syntheticPublicKey1234',
      ),
    );
    client = CollectCloudflareClient(
      config.api.origin,
      supabaseConfiguration: useSupabase ? config : null,
      surface: surface,
      httpClient: MockClient((request) async {
        requests.add(request);
        if (httpReply != null) return httpReply!(request);
        return http.Response(
          '{"events":[],"cursor":"0"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await login();
  }

  WebSocketChannel transport(String url, Map<String, String> inputHeaders) {
    urls.add(url);
    headers.add(Map.of(inputHeaders));
    final socket = _Socket(autoJoin: autoJoin, autoHeartbeat: autoHeartbeat);
    sockets.add(socket);
    return socket;
  }

  void start({
    Duration heartbeat = const Duration(seconds: 25),
    Duration deadline = const Duration(seconds: 10),
  }) {
    adapter = CollectSupabaseMemberRealtime(
      client: client,
      transport: transport,
      observeLifecycle: false,
      joinTimeout: deadline,
      heartbeatInterval: heartbeat,
      retryAfterMs: (_) => 1000,
      onReconcile: () => reads++,
      onConnectionChanged: statuses.add,
    )..start();
  }

  Future<void> close() async {
    await subscription?.dispose();
    await adapter?.dispose();
    await client.dispose();
  }
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    // Stream cancellation continuations can use the real queue, while the
    // controller's done event and SDK timers use WidgetTester's fake queue.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump();
  }
}

Future<void> _settleOwned(Future<void> closing, WidgetTester tester) async {
  var done = false;
  Object? failure;
  StackTrace? trace;
  unawaited(
    closing.then(
      (_) {
        done = true;
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
        trace = stack;
        done = true;
      },
    ),
  );
  for (var tick = 0; tick < 100 && !done; tick++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    done,
    true,
    reason: 'Owned fixture cleanup exceeded bounded queue settling',
  );
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
}

Future<void> _closeHarness(_Harness harness, WidgetTester tester) async {
  await _settleOwned(harness.close(), tester);
  expect(harness.sockets.every((socket) => socket.incoming.isClosed), true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'actual SDK sends exact private subject/SID join, not before ack',
    (tester) async {
      final h = _Harness(autoJoin: false);
      await h.initialize();
      h.start();
      await _flush(tester);
      expect(h.sockets, hasLength(1));
      expect(h.statuses, isEmpty);
      expect(h.reads, 0);
      final join = h.sockets.single.sent.singleWhere(
        (m) => m['event'] == 'phx_join',
      );
      expect(join['topic'], 'realtime:collect:member:$_subject:$_sid');
      final payload = join['payload'] as Map<String, dynamic>;
      expect(
        payload['access_token'],
        h.client.auth.currentSession!.accessToken,
      );
      final config = payload['config'] as Map<String, dynamic>;
      expect(config['private'], true);
      expect(config['postgres_changes'], isEmpty);
      expect((config['presence'] as Map)['enabled'], false);
      expect((config['broadcast'] as Map)['replay'], isNull);
      expect(h.urls.single, isNot(contains(_secret)));
      expect(h.headers.single.values.join(), isNot(contains(_secret)));
      expect(Uri.parse(h.urls.single).queryParameters['vsn'], '1.0.0');
      h.sockets.single.ack(join);
      await _flush(tester);
      expect(h.statuses, [true]);
      expect(h.reads, 1);
      await _closeHarness(h, tester);
      await _flush(tester);
    },
  );

  testWidgets(
    'opaque duplicate IDs dedupe and financial/extra payload fails closed',
    (tester) async {
      final h = _Harness();
      await h.initialize();
      h.start();
      await _flush(tester);
      final socket = h.sockets.single;
      socket.hint('99110000-0000-4000-8000-000000000010');
      socket.hint('99110000-0000-4000-8000-000000000010');
      await _flush(tester);
      expect(h.reads, 2);
      socket.hint(
        '',
        data: {'v': 1, 'id': _sid, 'amount': 100, 'group_id': _app},
      );
      await _flush(tester);
      expect(h.adapter!.isConnected, false);
      final attempts = h.sockets.length;
      await _closeHarness(h, tester);
      await tester.pump(const Duration(seconds: 40));
      expect(h.sockets.length, attempts);
    },
  );

  testWidgets(
    'same SID refreshed JWT replaces socket and ignores departed callbacks',
    (tester) async {
      final h = _Harness();
      await h.initialize();
      h.start();
      await _flush(tester);
      final old = h.sockets.single;
      final before = h.reads;
      await h.login(revision: 1);
      await _flush(tester);
      expect(h.sockets, hasLength(2));
      expect(old.incoming.isClosed, true);
      final join = h.sockets.last.sent.singleWhere(
        (m) => m['event'] == 'phx_join',
      );
      expect(
        (join['payload'] as Map)['access_token'],
        h.client.auth.currentSession!.accessToken,
      );
      old.hint('99110000-0000-4000-8000-000000000011');
      await _flush(tester);
      expect(h.reads, before + 1);
      await _closeHarness(h, tester);
      await _flush(tester);
    },
  );

  testWidgets('changed SID fences old subscription, including A-B-A recovery', (
    tester,
  ) async {
    final h = _Harness();
    await h.initialize();
    h.start();
    await _flush(tester);
    final before = h.reads;
    await h.login(sid: _sid2);
    await _flush(tester);
    expect(h.adapter!.isConnected, false);
    await h.login(sid: _sid);
    await _flush(tester);
    // Old object must not regain authority merely because its strings match.
    expect(h.sockets.length, 1);
    expect(h.reads, before);
    await _closeHarness(h, tester);
    await _flush(tester);
  });

  testWidgets(
    'join timeout and heartbeat timeout use bounded owned reconnect',
    (tester) async {
      final h = _Harness(autoJoin: false);
      await h.initialize();
      h.start(deadline: const Duration(seconds: 1));
      await _flush(tester);
      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      expect(h.adapter!.isConnected, false);
      expect(h.sockets, hasLength(1));
      await tester.pump(const Duration(milliseconds: 999));
      expect(h.sockets, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      await _flush(tester);
      expect(h.sockets, hasLength(2));
      await _closeHarness(h, tester);
      await _flush(tester);
      final hb = _Harness(autoHeartbeat: false);
      await hb.initialize();
      hb.start();
      await _flush(tester);
      await tester.pump(const Duration(seconds: 25));
      await _flush(tester);
      expect(
        hb.adapter!.isConnected,
        true,
      ); // sent is not an ack or a failure yet.
      await tester.pump(const Duration(seconds: 25));
      await _flush(tester);
      expect(hb.adapter!.isConnected, false);
      await _closeHarness(hb, tester);
      await _flush(tester);
    },
  );

  testWidgets('background suspends socket and resume reconciles/rejoins', (
    tester,
  ) async {
    final h = _Harness();
    await h.initialize();
    h.start();
    await _flush(tester);
    final before = h.reads;
    h.adapter!.handleLifecycle(AppLifecycleState.paused);
    await _flush(tester);
    expect(h.adapter!.isConnected, false);
    await tester.pump(const Duration(minutes: 2));
    expect(h.sockets, hasLength(1));
    h.adapter!.handleLifecycle(AppLifecycleState.resumed);
    await _flush(tester);
    expect(h.sockets, hasLength(2));
    expect(h.reads, greaterThan(before));
    await _closeHarness(h, tester);
    await _flush(tester);
  });

  testWidgets(
    '257 distinct hints overflow to reconciliation/fallback with no retained replay',
    (tester) async {
      final h = _Harness();
      await h.initialize();
      h.start();
      await _flush(tester);
      final socket = h.sockets.single;
      for (var i = 1; i <= 257; i++) {
        socket.hint(
          '99110000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}',
        );
      }
      await _flush(tester);
      expect(h.adapter!.isConnected, false);
      await _closeHarness(h, tester);
      await _flush(tester);
    },
  );

  testWidgets(
    'empty200 poll still reconciles at60s and denial reaches authoritative callback',
    (tester) async {
      var now = DateTime.utc(2026, 10, 21);
      var denied = false;
      var denials = 0, deniedRequests = 0;
      String? deniedBearer;
      final h = _Harness(
        autoJoin: false,
        httpReply: (_) async {
          if (denied) deniedRequests++;
          return http.Response(
            denied ? '{"code":"access_revoked"}' : '{"events":[],"cursor":"0"}',
            denied ? 403 : 200,
            headers: {'content-type': 'application/json'},
          );
        },
      );
      await h.initialize();
      h.subscription = CollectSyncInvalidationSubscription(
        client: h.client,
        topic: 'local-test-label',
        areas: collectMobileRealtimeAreas,
        realtimeTransport: h.transport,
        observeRealtimeLifecycle: false,
        currentTime: () => now,
        debounce: const Duration(milliseconds: 1),
        onInvalidate: () => h.reads++,
        onAuthorityDenied: (bearer) {
          deniedBearer = bearer;
          denials++;
          h.reads++;
        },
        onStatus: (status, _) =>
            h.statuses.add(status == CollectSyncStatus.connected),
      )..start();
      await _flush(tester);
      await tester.pump(const Duration(milliseconds: 2));
      expect(h.reads, 1);
      expect(h.statuses, isEmpty); // HTTP200 cannot acknowledge a private join.
      now = now.add(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 5));
      await _flush(tester);
      await tester.pump(const Duration(milliseconds: 2));
      expect(h.reads, 2);
      denied = true;
      // The10s join timeout and5s polling timers share this boundary. Settle
      // both queues until the actual HTTP403 callback, with a finite10s cap.
      for (var tick = 0; tick < 40 && denials == 0; tick++) {
        await tester.pump(const Duration(milliseconds: 250));
        await _flush(tester);
      }
      expect(deniedRequests, greaterThanOrEqualTo(1));
      expect(denials, 1);
      expect(deniedBearer, h.client.auth.currentSession!.accessToken);
      expect(h.reads, 3);
      await _closeHarness(h, tester);
      await _flush(tester);
    },
  );

  testWidgets(
    'coordinator serializes opaque refreshes and dispose cancels trailing window',
    (tester) async {
      var active = 0, peak = 0, reads = 0;
      final held = Completer<void>();
      final coordinator = CollectSyncInvalidationCoordinator(
        areas: collectMobileRealtimeAreas,
        debounce: const Duration(milliseconds: 1),
        onInvalidate: () async {
          reads++;
          active++;
          if (active > peak) peak = active;
          if (reads == 1) await held.future;
          active--;
        },
      );
      coordinator.reconcileAll();
      await tester.pump(const Duration(milliseconds: 2));
      for (var i = 0; i < 100; i++) {
        coordinator.reconcileAll();
      }
      await tester.pump(const Duration(milliseconds: 2));
      held.complete();
      await _flush(tester);
      expect(peak, 1);
      expect(reads, 2);
      coordinator.reconcileAll();
      coordinator.dispose();
      await tester.pump(const Duration(milliseconds: 2));
      expect(reads, 2);
    },
  );

  testWidgets(
    'late old-token403 cannot deny refreshed scope or force a stale read',
    (tester) async {
      final old = Completer<http.Response>();
      var count = 0;
      final h = _Harness(
        autoJoin: false,
        httpReply: (_) async {
          if (++count == 1) return old.future;
          return http.Response(
            '{"events":[],"cursor":"0"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        },
      );
      await h.initialize();
      h.subscription = CollectSyncInvalidationSubscription(
        client: h.client,
        topic: 'local-label',
        areas: collectMobileRealtimeAreas,
        realtimeTransport: h.transport,
        observeRealtimeLifecycle: false,
        debounce: const Duration(milliseconds: 1),
        onInvalidate: () => h.reads++,
      )..start();
      await _flush(tester);
      expect(count, 1);
      await h.login(revision: 1);
      await _flush(tester);
      old.complete(
        http.Response(
          '{"code":"access_revoked"}',
          403,
          headers: {'content-type': 'application/json'},
        ),
      );
      await _flush(tester);
      await tester.pump(const Duration(milliseconds: 2));
      expect(h.reads, 0);
      await tester.pump(const Duration(seconds: 5));
      await _flush(tester);
      await tester.pump(const Duration(milliseconds: 2));
      expect(h.reads, 1);
      expect(
        h.requests.last.headers['Authorization'],
        'Bearer ${h.client.auth.currentSession!.accessToken}',
      );
      await _closeHarness(h, tester);
      await _flush(tester);
    },
  );

  testWidgets(
    'dispose before join ack prevents late callback and all future attempts',
    (tester) async {
      final h = _Harness(autoJoin: false);
      await h.initialize();
      h.start();
      await _flush(tester);
      final socket = h.sockets.single;
      final join = socket.sent.singleWhere((row) => row['event'] == 'phx_join');
      await _settleOwned(h.adapter!.dispose(), tester);
      socket.ack(join);
      await tester.pump(const Duration(minutes: 2));
      await _flush(tester);
      expect(h.reads, 0);
      expect(h.sockets, hasLength(1));
      await _closeHarness(h, tester);
      await _flush(tester);
    },
  );

  testWidgets('Admin-surface client never opens a member websocket', (
    tester,
  ) async {
    final h = _Harness(surface: 'admin');
    await h.initialize();
    h.start();
    await _flush(tester);
    expect(h.sockets, isEmpty);
    expect(h.statuses, isEmpty);
    await _closeHarness(h, tester);
    await _flush(tester);
  });

  testWidgets(
    'departed Supabase polling cannot revive after A-B-A strings match again',
    (tester) async {
      final old = Completer<http.Response>();
      final h = _Harness(autoJoin: false, httpReply: (_) => old.future);
      await h.initialize();
      h.subscription = CollectSyncInvalidationSubscription(
        client: h.client,
        topic: 'poll-scope',
        areas: collectMobileRealtimeAreas,
        realtimeTransport: h.transport,
        observeRealtimeLifecycle: false,
        onInvalidate: () => h.reads++,
      )..start();
      await _flush(tester);
      expect(h.requests, hasLength(1));
      await h.login(sid: _sid2);
      await _flush(tester);
      await h.login(sid: _sid);
      await _flush(tester);
      old.complete(
        http.Response(
          '{"events":[],"cursor":"0"}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await _flush(tester);
      await tester.pump(const Duration(minutes: 2));
      await _flush(tester);
      expect(h.requests, hasLength(1));
      expect(h.reads, 0);
      await _closeHarness(h, tester);
    },
  );

  for (final surface in ['member', 'admin']) {
    testWidgets(
      'existing legacy $surface HTTP200 still publishes fallback connected status',
      (tester) async {
        final h = _Harness(surface: surface, useSupabase: false);
        await h.initialize();
        h.subscription = CollectSyncInvalidationSubscription(
          client: h.client,
          topic: 'legacy-poll-status',
          areas: collectMobileRealtimeAreas,
          observeRealtimeLifecycle: false,
          onInvalidate: () => h.reads++,
          onStatus: (status, _) =>
              h.statuses.add(status == CollectSyncStatus.connected),
        )..start();
        await _flush(tester);
        expect(h.statuses, [true]);
        expect(h.sockets, isEmpty);
        await _closeHarness(h, tester);
      },
    );
  }

  for (final hierarchy in [false, true]) {
    test(
      'actual SDK token/error/heartbeat paths stay out of Logger and Zone hierarchy=$hierarchy',
      () async {
        final oldHierarchy = hierarchicalLoggingEnabled,
            oldLevel = Logger.root.level;
        hierarchicalLoggingEnabled = hierarchy;
        Logger.root.level = Level.ALL;
        final records = <LogRecord>[];
        final errors = <Object>[];
        final logs = Logger.root.onRecord.listen(records.add);
        _Harness? h;
        final joinedControls = <bool>[];
        final finished = Completer<void>();
        try {
          runZonedGuarded(
            () {
              unawaited(() async {
                try {
                  h = _Harness();
                  await h!.initialize();
                  h!.start(heartbeat: const Duration(milliseconds: 15));
                  await Future<void>.delayed(const Duration(milliseconds: 25));
                  joinedControls.add(h!.adapter!.isConnected);
                  await h!.login(revision: 1);
                  await Future<void>.delayed(const Duration(milliseconds: 20));
                  h!.sockets.last.throwOnSend =
                      true; // Actual SDK heartbeat sink failure.
                  await Future<void>.delayed(const Duration(milliseconds: 35));
                  await h!.close();
                  final socketError = _Harness();
                  await socketError.initialize();
                  socketError.start();
                  await Future<void>.delayed(const Duration(milliseconds: 10));
                  socketError.sockets.last.incoming.addError(
                    StateError(_secret),
                  );
                  await Future<void>.delayed(const Duration(milliseconds: 5));
                  await socketError.close();
                  final malformed = _Harness();
                  await malformed.initialize();
                  malformed.start();
                  await Future<void>.delayed(const Duration(milliseconds: 10));
                  malformed.sockets.last.incoming.add(
                    '{"topic":false,"event":"broadcast","payload":{"secret":"$_secret"}}',
                  );
                  await Future<void>.delayed(const Duration(milliseconds: 5));
                  await malformed.close();
                  final closeReason = _Harness();
                  await closeReason.initialize();
                  closeReason.start();
                  await Future<void>.delayed(const Duration(milliseconds: 10));
                  await closeReason.sockets.last.serverClose(_secret);
                  await Future<void>.delayed(const Duration(milliseconds: 5));
                  await closeReason.close();
                } catch (error) {
                  errors.add(error);
                } finally {
                  if (!finished.isCompleted) finished.complete();
                }
              }());
            },
            (error, _) {
              errors.add(error);
            },
          );
          await finished.future.timeout(const Duration(seconds: 5));
          expect(errors, isEmpty);
          expect(joinedControls, [true]);
          final allFields = records
              .map((r) => '${r.message}|${r.error}|${r.object}|${r.stackTrace}')
              .join('\n');
          expect(allFields, isNot(contains(_secret)));
          expect(
            records.any((r) => r.message.contains('Initialize')),
            true,
            reason:
                'RootALL must actually observe the SDK public-only constructor control',
          );
        } finally {
          await h?.close();
          await logs.cancel();
          Logger.root.level = oldLevel;
          hierarchicalLoggingEnabled = oldHierarchy;
        }
      },
    );
  }
}
