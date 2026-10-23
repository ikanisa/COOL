import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/core/cloudflare_admin_sms_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_sms_pages.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

// Captured API objects from the isolated real workerd/D1 metadata route tests.
// This replay tests DTO compatibility, not hosted authentication or transport.
Map<String, dynamic> _examples() {
  final bytes = File(
    'test/fixtures/admin-sms-capture-dto-examples.json',
  ).readAsBytesSync();
  expect(
    sha256.convert(bytes).toString(),
    '093f45e5692b5fe19d779c825c4d7d0db4b1897dbeecf6b757d71e1f0f1b519c',
  );
  return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
}

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map);

typedef _Response = ({
  String path,
  Map<String, String> query,
  Map<String, dynamic> body,
});

class _Replay {
  _Replay(this.recordedSession, this.responses, {this.denyRead = false});
  final Map<String, dynamic> recordedSession;
  final List<_Response> responses;
  final bool denyRead;
  late final CloudflareAdminSession session;
  var requests = 0;

  Future<CloudflareAdminSmsApi> open({bool registerDispose = true}) async {
    session = CloudflareAdminSession(
      MockClient((request) async {
        expect(request.method, 'GET');
        if (request.url.path == '/api/admin/auth/session') {
          // Keep recorded public identity/grants. Rebase only fixture expiry so
          // this DTO replay remains usable after the original test session ends.
          final user = _map(recordedSession['user']);
          if (denyRead) {
            user['permissions'] = (user['permissions'] as List)
                .where((permission) => permission != 'sms.read')
                .toList();
          }
          return _response({
            ...recordedSession,
            'user': user,
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          });
        }
        expect(requests, lessThan(responses.length));
        final response = responses[requests++];
        expect(request.url.path, response.path);
        expect(request.url.queryParameters, response.query);
        return _response(response.body);
      }),
      origin: Uri.parse('https://admin.example.test/'),
      environment: legacyBackendFixtureEnvironment,
    );
    if (registerDispose) addTearDown(session.dispose);
    await session.refresh();
    return CloudflareAdminSmsApi(session);
  }

  static http.Response _response(Map<String, dynamic> body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  test(
    'actual API capture pages pass repository DTO and pagination checks',
    () async {
      final examples = _examples();
      final pages = [
        for (final key in ['list', 'list_next', 'list_all'])
          _map(examples[key]),
      ];
      final replay = _Replay(_map(examples['session']), [
        for (final page in pages)
          (
            path: '/api/admin/sms/receipts',
            query: {'limit': '${page['limit']}', 'offset': '${page['offset']}'},
            body: page,
          ),
      ]);
      final api = await replay.open();
      expect(api.canExtract, isFalse);
      expect(api.canReveal, isFalse);
      for (final body in pages) {
        final page = await api.receipts(
          limit: body['limit'] as int,
          offset: body['offset'] as int,
        );
        expect(page.total, 4);
        expect(page.nextOffset, body['next_offset']);
        expect(page.rows.map((source) => source.values).toList(), body['rows']);
        expect(page.rows.every((source) => source.kind == 'capture'), isTrue);
      }
      expect(replay.requests, 3);
    },
  );

  test('actual API capture details preserve all four states and unknowns', () async {
    final examples = _examples();
    final details = (examples['details'] as List).map(_map).toList();
    final replay = _Replay(_map(examples['session']), [
      for (final detail in details)
        (
          path:
              '/api/admin/sms/receipts/capture/${_map(detail['resource'])['id']}',
          query: {
            'limit':
                '${_map(_map(detail['related'])['duplicate_references'])['limit']}',
            'offset':
                '${_map(_map(detail['related'])['duplicate_references'])['offset']}',
          },
          body: detail,
        ),
    ]);
    final api = await replay.open();
    final states = <String>{};
    for (final body in details) {
      final resource = _map(body['resource']);
      final related = _map(_map(body['related'])['duplicate_references']);
      final detail = await api.detail(
        'capture',
        resource['id'] as String,
        limit: related['limit'] as int,
        offset: related['offset'] as int,
      );
      expect(detail.source.values, resource);
      expect(detail.canExtract, isFalse);
      expect(detail.duplicates.total, 0);
      expect(detail.source.values['amount_rwf'], isNull);
      expect(detail.source.values['provider_confirmation'], isFalse);
      states.add(detail.source.values['status'] as String);
    }
    expect(states, {'received', 'under_review', 'rejected', 'linked'});
    expect(replay.requests, 4);
  });

  test(
    'missing SMS read grant stops capture lookup before the transport',
    () async {
      final examples = _examples();
      final replay = _Replay(_map(examples['session']), [], denyRead: true);
      final api = await replay.open();
      await expectLater(api.receipts(), throwsA(isA<AdminAccountException>()));
      expect(replay.requests, 0);
    },
  );

  testWidgets(
    'capture metadata stays in a keyboard-scrollable table at 320px and 2x',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final examples = _examples();
      final replay = _Replay(_map(examples['session']), [
        (
          path: '/api/admin/sms/receipts',
          query: {'limit': '100', 'offset': '0', 'source_kind': 'capture'},
          body: _map(examples['list_all']),
        ),
      ]);
      await tester.runAsync(() => replay.open(registerDispose: false));
      final container = ProviderContainer(
        overrides: [
          cloudflareAdminSessionProvider.overrideWith((_) => replay.session),
        ],
      );
      final router = GoRouter(
        initialLocation: '/admin/sms-receipts?source=capture&limit=100',
        routes: [
          GoRoute(
            path: '/admin/sms-receipts',
            builder: (_, _) => const CloudflareAdminSmsReceiptsPage(),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: Scaffold(body: child),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AdminDataTable), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      expect(find.text('Device time (source)'), findsOneWidget);
      expect(find.text('2026-10-15T12:00:00'), findsOneWidget);
      expect(find.text('Confirm extraction'), findsNothing);
      expect(find.text('Open audited source'), findsNothing);
      final focus = tester
          .widgetList<Focus>(find.byType(Focus))
          .firstWhere(
            (widget) =>
                widget.focusNode?.debugLabel ==
                'Admin table horizontal scrolling',
          );
      focus.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      final horizontal = tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .firstWhere((widget) => widget.scrollDirection == Axis.horizontal);
      expect(horizontal.controller!.offset, greaterThan(0));
      expect(replay.requests, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
