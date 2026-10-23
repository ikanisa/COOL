import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/core/cloudflare/realtime_invalidation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'admin_action_session_test.dart' as auth;

// The actual Cloudflare HTTP poller and Admin provider execute unchanged.
// Only response timing and synthetic session claims are controlled. No Phoenix
// socket, hosted admission or provider-delivery evidence is implied.
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
    expect(
      next.url.queryParameters['areas']!.split(','),
      containsAll(collectAdminRealtimeAreas),
    );
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

class _Probe {
  late CollectCloudflareClient client;
  late ProviderContainer container;
  final joins = <_SyncScope>[];
  final requests = <http.Request>[];
  final identityActors = <String>[];
  int epoch = 0, identityReads = 0;
  bool disposed = false;
  Future<void> start() async {
    client = CollectCloudflareClient(
      'https://api.collect.test',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/logout')) return auth.response({});
        expect(request.url.path, '/v1/sync');
        var scope = joins.where((s) => s.epoch == epoch).firstOrNull;
        if (scope == null) {
          scope = _SyncScope(epoch, request);
          joins.add(scope);
        }
        return scope.accept(request);
      }),
    );
    await login('admin-http-a');
    container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(client),
        adminIdentityProvider.overrideWith((ref) async {
          final actor = ref.watch(adminAuthUserIdProvider);
          if (actor == null) return null;
          identityReads++;
          identityActors.add(actor);
          return AdminIdentity(
            userId: actor,
            displayName: 'Synthetic HTTP operator',
            roles: ['admin'],
            permissions: ['users.read'],
          );
        }),
      ],
    );
    container.listen(adminIdentityProvider, (_, _) {});
    await container.read(adminIdentityProvider.future);
    container.listen(adminRealtimeSubscriptionProvider, (_, _) {});
    await until(() => joins.isNotEmpty && ticks == 1 && identityReads == 2);
  }

  Future<void> login(String id, {bool otherAccount = false}) async {
    epoch++;
    final receipt = auth.authReceipt(id, '$epoch');
    if (otherAccount) {
      final parts = (receipt['access_token'] as String).split('.');
      final claims = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
            as Map,
      );
      claims['sub'] = auth.target;
      receipt['access_token'] =
          '${parts[0]}.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.${parts[2]}';
      (receipt['user'] as Map)['id'] = auth.target;
    }
    await client.auth.recoverSession(jsonEncode(receipt));
  }

  int get ticks => container.read(adminRealtimeTickProvider);
  Future<void> until(bool Function() condition, {int seconds = 7}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!condition() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      condition(),
      isTrue,
      reason:
          'poll scopes=${joins.length}, ticks=$ticks, identity reads=$identityReads',
    );
  }

  Future<void> quiet() =>
      Future<void>.delayed(const Duration(milliseconds: 450));
  Future<void> dispose() async {
    if (!disposed) {
      disposed = true;
      container.dispose();
    }
    for (final scope in joins) {
      scope.finish();
    }
    await client.dispose();
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
    'Admin HTTP sync sends the current bearer, bounds areas and deduplicates invalidations',
    () async {
      final scope = probe.joins.single;
      expect(scope.request.method, 'GET');
      expect(
        scope.request.headers['Authorization'],
        'Bearer ${probe.client.auth.currentSession!.accessToken}',
      );
      expect(scope.request.url.queryParameters['cursor'], '0');
      await probe.until(() => scope.pending != null);
      scope.queued.addAll([
        {'id': 'role-event', 'area': 'admin_roles'},
        {'id': 'role-event', 'area': 'admin_roles'},
        {'id': 'irrelevant', 'area': 'not-an-admin-area'},
      ]);
      scope.flush();
      await probe.until(() => probe.ticks == 2 && probe.identityReads == 3);
      await probe.quiet();
      expect(probe.ticks, 2);
      expect(probe.requests.every((r) => r.url.path == '/v1/sync'), isTrue);
    },
  );
  test(
    'Admin HTTP outage retains its cursor and performs one scoped recovery refresh',
    () async {
      final scope = probe.joins.single;
      await probe.until(() => scope.pending != null);
      final before = scope.cursor;
      scope.bindingFailure();
      await probe.until(
        () =>
            probe.container.read(adminLiveUpdateStatusProvider) ==
            AdminLiveUpdateStatus.reconnecting,
      );
      expect(scope.cursor, before);
      expect(probe.ticks, 1);
      await probe.until(
        () =>
            probe.ticks == 2 &&
            probe.container.read(adminLiveUpdateStatusProvider) ==
                AdminLiveUpdateStatus.live,
      );
      expect(probe.joins, hasLength(1));
      await probe.quiet();
      expect(probe.ticks, 2);
    },
  );
  for (final switchBack in [false, true]) {
    test(
      'held old Admin HTTP response is discarded after session change A-B-A=$switchBack',
      () async {
        final old = probe.joins.single;
        await probe.until(() => old.pending != null);
        final before = probe.ticks;
        await probe.login('admin-http-b');
        if (switchBack) {
          await probe.login('admin-http-a');
        }
        await probe.until(
          () => probe.joins.length >= 2 && probe.ticks == before + 1,
        );
        old.event('departed-private-event', area: 'admin_roles');
        await probe.quiet();
        expect(probe.ticks, before + 1);
        expect(
          probe.joins.last.request.headers['Authorization'],
          'Bearer ${probe.client.auth.currentSession!.accessToken}',
        );
        probe.joins.last.event('current-event');
        await probe.until(() => probe.ticks == before + 2);
      },
    );
  }
  test(
    'Admin logout ignores a held response and never schedules a successor poll',
    () async {
      final old = probe.joins.single;
      await probe.until(() => old.pending != null);
      await probe.client.auth.signOut(scope: CollectSignOutScope.local);
      expect(probe.container.read(adminAuthSessionScopeProvider), isNull);
      old.event('departed-after-logout', area: 'admin_roles');
      await probe.quiet();
      expect(probe.ticks, 1);
      final calls = probe.requests.length;
      await Future<void>.delayed(const Duration(milliseconds: 5200));
      expect(probe.requests.length, calls);
      expect(probe.joins, hasLength(1));
    },
  );
  test(
    'Admin account switch suppresses departed data and reads only the new actor',
    () async {
      final old = probe.joins.single;
      await probe.until(() => old.pending != null);
      await probe.login('admin-http-other-account', otherAccount: true);
      await probe.until(() => probe.joins.length == 2 && probe.ticks == 2);
      expect(
        probe.container.read(adminAuthSessionScopeProvider)!.key.userId,
        auth.target,
      );
      expect(probe.identityActors.last, auth.target);
      old.event('departed-account', area: 'admin_roles');
      await probe.quiet();
      expect(probe.ticks, 2);
      probe.joins.last.event('current-account', area: 'admin_roles');
      await probe.until(() => probe.ticks == 3);
      expect(probe.identityActors.last, auth.target);
    },
  );
  test(
    'Admin provider disposal suppresses its pending invalidation and stops polling',
    () async {
      final old = probe.joins.single;
      await probe.until(() => old.pending != null);
      final reads = probe.identityReads;
      probe.container.dispose();
      probe.disposed = true;
      old.event('departed-after-dispose', area: 'admin_roles');
      await probe.quiet();
      expect(probe.identityReads, reads);
      final calls = probe.requests.length;
      await Future<void>.delayed(const Duration(milliseconds: 5200));
      expect(probe.requests.length, calls);
    },
  );
}
