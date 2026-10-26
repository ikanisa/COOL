import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/main_admin_cloudflare.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cloudflare_core_fixtures.dart';
import '../support/legacy_backend_fixture.dart';

http.Response response(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);
Map<String, dynamic> page(String cursor, [List<Object> events = const []]) => {
  'contract_version': 1,
  'cursor': cursor,
  'events': events,
};

class Probe {
  late CloudflareAdminSession session;
  late ProviderContainer container;
  final calls = <http.Request>[];
  List<String> permissions = ['users.read'];
  late Future<http.Response> Function(http.Request) reply;
  Future<void> start() async {
    reply = (_) async => response(page('7'));
    session = CloudflareAdminSession(
      MockClient((request) async {
        if (request.url.path.endsWith('/auth/session')) {
          return response(coreSession(permissions: permissions));
        }
        expectSync(request.url.path, '/api/admin/sync');
        expectSync(request.method, 'GET');
        expectSync(request.headers.containsKey('Authorization'), isFalse);
        expectSync(request.body, isEmpty);
        expectSync(request.url.queryParameters['areas'], 'members,profiles');
        expectSync(request.url.queryParameters['limit'], '100');
        calls.add(request);
        return reply(request);
      }),
      origin: Uri.parse('https://admin.example.test'),
      environment: legacyBackendFixtureEnvironment,
    );
    container = ProviderContainer(
      overrides: [
        ...cloudflareAdminOverrides(),
        cloudflareAdminSessionProvider.overrideWith((_) => session),
      ],
    );
    await session.refresh();
  }

  void listen() => container.listen(
    adminRealtimeSubscriptionProvider,
    (_, _) {},
    fireImmediately: true,
  );
  int get ticks => container.read(adminRealtimeTickProvider);
  AdminLiveUpdateStatus get status =>
      container.read(adminLiveUpdateStatusProvider);
}

void syncTest(String name, Future<void> Function(WidgetTester, Probe) body) {
  testWidgets(name, (tester) async {
    final p = Probe();
    await p.start();
    try {
      await body(tester, p);
    } finally {
      p.container.dispose();
      if (p.session.mounted) p.session.dispose();
      await tester.pump();
    }
  });
}

void main() {
  syncTest(
    'grant denial refreshes current authority and stops the departed area subscription',
    (tester, p) async {
      p.reply = (_) async {
        p.permissions = [];
        return response({
          'error': {'code': 'admin_access_changed'},
        }, 403);
      };
      p.listen();
      await tester.pump();
      await tester.pump();
      expect(p.session.user?.permissions, isEmpty);
      expect(p.status, AdminLiveUpdateStatus.unavailable);
      await tester.pump(const Duration(seconds: 40));
      expect(p.calls, hasLength(1));
      expect(p.ticks, 0);
    },
  );
  syncTest(
    'shipping cookie provider becomes live only after an accepted bounded response',
    (tester, p) async {
      final held = Completer<http.Response>();
      p.reply = (_) => held.future;
      p.listen();
      await tester.pump();
      expect(p.status, AdminLiveUpdateStatus.connecting);
      expect(p.ticks, 0);
      held.complete(response(page('7')));
      await tester.pump();
      expect(p.status, AdminLiveUpdateStatus.live);
      await tester.pump(const Duration(milliseconds: 350));
      expect(p.ticks, 1);
      expect(p.calls, hasLength(1));
    },
  );
  syncTest(
    'same-authority session reread preserves the poll and a current event invalidates once',
    (tester, p) async {
      p.listen();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final held = Completer<http.Response>();
      p.reply = (_) => held.future;
      await tester.pump(const Duration(seconds: 5));
      expect(p.calls, hasLength(2));
      await p.session.refresh();
      await tester.pump();
      expect(p.status, AdminLiveUpdateStatus.live);
      expect(p.calls, hasLength(2));
      held.complete(
        response(
          page('8', [
            {'id': '8:profiles', 'area': 'profiles'},
            {'id': '8:profiles', 'area': 'profiles'},
          ]),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(p.ticks, 2);
    },
  );
  syncTest(
    'outage rejects a backwards cursor, keeps the old cursor and reconciles once on recovery',
    (tester, p) async {
      p.listen();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      p.reply = (_) async => response(page('6'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(p.status, AdminLiveUpdateStatus.reconnecting);
      expect(p.ticks, 1);
      p.reply = (_) async => response(page('8'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(p.calls.last.url.queryParameters['cursor'], '7');
      expect(p.status, AdminLiveUpdateStatus.live);
      await tester.pump(const Duration(milliseconds: 350));
      expect(p.ticks, 2);
    },
  );
  syncTest(
    'late old response cannot revive a cleared and restored A-to-A authority',
    (tester, p) async {
      final held = Completer<http.Response>();
      p.reply = (_) => held.future;
      p.listen();
      await tester.pump();
      p.session.clear();
      await tester.pump();
      p.reply = (_) async => response(page('9'));
      await p.session.refresh();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final before = p.ticks;
      held.complete(
        response(
          page('99', [
            {'id': '99:profiles', 'area': 'profiles'},
          ]),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(p.ticks, before);
      expect(p.status, AdminLiveUpdateStatus.live);
    },
  );
  syncTest('a cookie401 clears authority and stops successors', (
    tester,
    p,
  ) async {
    p.reply = (_) async => response({
      'error': {'code': 'unauthenticated'},
    }, 401);
    p.listen();
    await tester.pump();
    expect(p.session.user, isNull);
    expect(p.status, AdminLiveUpdateStatus.unavailable);
    await tester.pump(const Duration(seconds: 40));
    expect(p.calls, hasLength(1));
    expect(p.ticks, 0);
  });
  syncTest(
    'unrequested or malformed invalidation metadata never becomes a live signal',
    (tester, p) async {
      p.reply = (_) async => response(
        page('7', [
          {'id': '7:payments', 'area': 'payments'},
        ]),
      );
      p.listen();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(p.status, AdminLiveUpdateStatus.reconnecting);
      expect(p.ticks, 0);
    },
  );
}
