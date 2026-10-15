import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/cloudflare_admin_app.dart';
import 'package:collect_app/admin/core/cloudflare_admin_core_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_route_reporting.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:collect_app/main_admin_cloudflare.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cloudflare_core_fixtures.dart';
import 'cloudflare_core_pages_test.dart' show pumpCore;
import 'cloudflare_operating_repository_test.dart'
    show operatingResponse, operatingReceipt, otherId, requestKey;

// Models only the installed engine's navigation-message protocol. Native
// browser Back/history and cold bootstrap remain separate acceptance checks.
class _EngineHistory {
  final entries = <RouteInformation>[
    RouteInformation(uri: Uri.parse('/admin')),
  ];
  final calls = <MethodCall>[];
  Future<void> _queue = Future.value();
  Completer<void>? firstWrite;

  Future<void> handle(MethodCall call) {
    if (call.method != 'routeInformationUpdated') return Future.value();
    calls.add(call);
    final arguments = call.arguments as Map<Object?, Object?>;
    final gate = calls.length == 1 ? firstWrite : null;
    if (firstWrite == null) {
      _apply(arguments);
      return Future.value();
    }
    return _queue = _queue.then((_) async {
      if (gate != null) await gate.future;
      _apply(arguments);
    });
  }

  void _apply(Map<Object?, Object?> arguments) {
    final String location;
    if (arguments['uri'] is String) {
      final uri = Uri.parse(arguments['uri'] as String);
      // Flutter 3.44.4 EngineFlutterWindow.handleNavigationMessage.
      location = Uri.decodeComponent(
        Uri(
          path: uri.path.isEmpty ? '/' : uri.path,
          queryParameters: uri.queryParametersAll.isEmpty
              ? null
              : uri.queryParametersAll,
          fragment: uri.fragment.isEmpty ? null : uri.fragment,
        ).toString(),
      );
    } else {
      location = arguments['location'] as String;
    }
    final value = RouteInformation(
      uri: Uri.parse(location),
      state: arguments['state'],
    );
    if (arguments['replace'] == true) {
      entries[entries.length - 1] = value;
    } else {
      entries.add(value);
    }
  }

  Future<void> drain() => _queue;
}

String _list(String search) => Uri(
  path: '/admin/users',
  queryParameters: {
    'search': search,
    'status': 'active',
    'sort': 'created_at_asc',
    'page': '2',
  },
).toString();

String _detail(String list) => Uri(
  path: '/admin/users/$coreId',
  queryParameters: {'returnTo': list},
).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _EngineHistory engine;

  setUp(() {
    engine = _EngineHistory();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, engine.handle);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, null);
  });

  CloudflareAdminRouteReporting provider({bool web = true}) {
    final delegate = GoRouteInformationProvider(
      initialLocation: '/admin',
      initialExtra: null,
    );
    addTearDown(delegate.dispose);
    return CloudflareAdminRouteReporting(
      delegate: delegate,
      preserveWebEncoding: web,
    );
  }

  test('unadapted web reporting reproduces the nested search loss', () async {
    final list = _list('+250 788 600 002');
    provider(web: false).routerReportsNewRouteInformation(
      RouteInformation(uri: Uri.parse(_detail(list)), state: {'route': 1}),
      type: RouteInformationReportingType.navigate,
    );
    await engine.drain();
    final returnTo = engine.entries.last.uri.queryParameters['returnTo'];
    expect(returnTo, isNot(list));
    expect(
      cloudflareCoreReturnLocation(CloudflareCoreArea.users, returnTo),
      '/admin/users',
    );
    expect(engine.calls, hasLength(1));
  });

  for (final search in [
    '+250 788 600 002',
    'ALICE & BOB=QA',
    'literal+plus 50% ? #',
    'Éliane Kigali',
  ]) {
    test('encoded list and nested return preserve $search', () async {
      final list = _list(search);
      final location = _detail(list);
      final reporting = provider();
      final state = {'route': location, 'nonce': search};
      reporting.routerReportsNewRouteInformation(
        RouteInformation(uri: Uri.parse(list), state: state),
        type: RouteInformationReportingType.navigate,
      );
      reporting.routerReportsNewRouteInformation(
        RouteInformation(uri: Uri.parse(location), state: state),
        type: RouteInformationReportingType.navigate,
      );
      await engine.drain();
      expect(engine.entries, hasLength(3));
      expect(engine.entries[1].uri.queryParameters['search'], search);
      final published = engine.entries.last;
      expect(published.uri.toString(), location);
      expect(published.state, state);
      final returnTo = published.uri.queryParameters['returnTo'];
      expect(returnTo, list);
      expect(
        cloudflareCoreReturnLocation(CloudflareCoreArea.users, returnTo),
        list,
      );
      final filters = Uri.parse(returnTo!).queryParameters;
      expect(filters['search'], search);
      expect(filters['status'], 'active');
      expect(filters['sort'], 'created_at_asc');
      expect(filters['page'], '2');
      expect(engine.calls, hasLength(4));
      expect(engine.calls[1].arguments, {
        'location': list,
        'state': state,
        'replace': true,
      });
    });
  }

  test(
    'no-op report does not republish; navigate and neglect keep history',
    () async {
      final reporting = provider();
      final detail = RouteInformation(
        uri: Uri.parse(_detail(_list('+250'))),
        state: {'route': 1},
      );
      reporting.routerReportsNewRouteInformation(
        detail,
        type: RouteInformationReportingType.navigate,
      );
      await engine.drain();
      reporting.routerReportsNewRouteInformation(detail);
      await engine.drain();
      expect(engine.calls, hasLength(2));
      reporting.routerReportsNewRouteInformation(
        detail,
        type: RouteInformationReportingType.navigate,
      );
      await engine.drain();
      expect(engine.entries, hasLength(3));
      final replacement = RouteInformation(
        uri: Uri.parse(_list('ALICE & BOB')),
        state: {'route': 2},
      );
      reporting.routerReportsNewRouteInformation(
        replacement,
        type: RouteInformationReportingType.neglect,
      );
      await engine.drain();
      expect(engine.entries, hasLength(3));
      expect(engine.entries.last.uri, replacement.uri);
      expect(reporting.value, same(replacement));
    },
  );

  test(
    'rapid reports preserve protocol arrival order and final state',
    () async {
      engine.firstWrite = Completer<void>();
      final reporting = provider();
      final locations = [_list('+250'), _detail(_list('A&B')), _list('C=50%')];
      for (var i = 0; i < locations.length; i++) {
        reporting.routerReportsNewRouteInformation(
          RouteInformation(uri: Uri.parse(locations[i]), state: {'route': i}),
          type: RouteInformationReportingType.navigate,
        );
      }
      expect(engine.calls, hasLength(6));
      engine.firstWrite!.complete();
      await engine.drain();
      expect(engine.entries.skip(1).map((e) => e.uri.toString()), locations);
      expect(engine.entries.last.state, {'route': 2});
    },
  );

  test(
    'delegate remains the authority for changes and restored state',
    () async {
      final delegate = GoRouteInformationProvider(
        initialLocation: '/admin',
        initialExtra: null,
      );
      addTearDown(delegate.dispose);
      final reporting = CloudflareAdminRouteReporting(
        delegate: delegate,
        preserveWebEncoding: true,
      );
      var changes = 0;
      void listener() => changes++;
      reporting.addListener(listener);
      addTearDown(() => reporting.removeListener(listener));
      delegate.go(_list('+250 788 600 002'));
      expect(changes, 1);
      expect(reporting.value.uri.queryParameters['search'], '+250 788 600 002');
      final restored = RouteInformation(
        uri: Uri.parse(_detail(_list('A&B'))),
        state: {'restored': true},
      );
      await delegate.didPushRouteInformation(restored);
      expect(reporting.value, same(restored));
      expect(changes, 2);
      expect(engine.calls, isEmpty);
    },
  );

  test('same-area and post-auth guards remain strict', () {
    for (final unsafe in [
      'https://outside.example/admin/users',
      '//outside.example/admin/users',
      '/admin/users?page=2&page=3',
      '/admin/users?token=secret',
      '/admin/users?search=secret#outside',
      '/admin/groups?page=2',
    ]) {
      expect(
        cloudflareCoreReturnLocation(CloudflareCoreArea.users, unsafe),
        '/admin/users',
      );
    }
    for (final unsafe in [
      'https://outside.example/admin',
      '//outside.example/admin',
      '/admin/setup?token=secret',
      '/admin/login',
      '/outside',
    ]) {
      expect(cloudflareAdminReturnLocation(unsafe), isNull);
    }
  });

  testWidgets(
    'real request route query changes reset receipt identity and fence a pending previous lookup',
    (tester) async {
      const secondKey = 'another-request-reference';
      const secondRequestId = '44444444-4444-4444-8444-444444444444';
      final pending = Completer<http.Response>();
      final lookups = <String>[];
      final container = await pumpCore(tester, (request) async {
        if (request.url.path == '/api/admin/operations/requests') {
          return operatingResponse({'rows': [], 'total': 0});
        }
        if (request.url.path.startsWith('/api/admin/operations/requests/')) {
          lookups.add(request.url.path);
          if (request.url.path.endsWith('/$requestKey')) return pending.future;
          return operatingResponse({
            'status': 'succeeded',
            'request_id': secondRequestId,
            'receipt': {
              ...operatingReceipt(version: 8),
              'request_id': secondRequestId,
            },
          });
        }
        return operatingResponse({'rows': [], 'total': 0});
      });
      final router = container.read(cloudflareAdminRouterProvider);
      final reference = find.widgetWithText(TextField, 'Request reference');
      String selectedKey() =>
          tester.widget<TextField>(reference).controller!.text;
      Finder receiptTable() => find.byWidgetPredicate(
        (widget) =>
            widget is AdminDataTable &&
            widget.tableLabel == 'Saved change receipt',
      );
      router.go('/admin/requests?key=$requestKey');
      await tester.pumpAndSettle();
      expect(selectedKey(), requestKey);
      await tester.tap(find.text('Check request'));
      await tester.pump();
      expect(find.text('Checking…'), findsOneWidget);

      router.go('/admin/requests?key=$secondKey');
      await tester.pumpAndSettle();
      expect(selectedKey(), secondKey);
      expect(tester.widget<TextField>(reference).enabled, isTrue);
      expect(find.text('Checking…'), findsNothing);
      expect(receiptTable(), findsNothing);
      await tester.tap(find.text('Check request'));
      await tester.pumpAndSettle();
      expect(lookups, [
        '/api/admin/operations/requests/$requestKey',
        '/api/admin/operations/requests/$secondKey',
      ]);
      expect(
        tester
            .widget<AdminDataTable>(receiptTable())
            .rows
            .single
            .extra['request_id'],
        secondRequestId,
      );

      pending.complete(
        operatingResponse({
          'status': 'succeeded',
          'request_id': otherId,
          'receipt': operatingReceipt(id: otherId, version: 7),
        }),
      );
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.queryParameters['key'],
        secondKey,
      );
      expect(selectedKey(), secondKey);
      final current = tester
          .widget<AdminDataTable>(receiptTable())
          .rows
          .single
          .extra;
      expect(current['request_id'], secondRequestId);
      expect(current['resource_id'], coreId);
      expect(current['version'], 8);

      router.go('/admin/requests?key=$requestKey');
      await tester.pumpAndSettle();
      expect(selectedKey(), requestKey);
      expect(receiptTable(), findsNothing);
      expect(find.text('Check request'), findsOneWidget);
      expect(tester.takeException(), isNull);
      container.read(cloudflareAdminSessionProvider.notifier).clear();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('real app cold restore retains nested list state through Back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final list = _list('+250 788 600 002 & ALICE=50%');
    final detail = _detail(list);
    tester.binding.platformDispatcher.defaultRouteNameTestValue = detail;
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final pendingSession = Completer<http.Response>();
    final searches = <String>[];
    final offsets = <String>[];
    http.Response response(Object value) => http.Response(
      jsonEncode(value),
      200,
      headers: const {'content-type': 'application/json'},
    );
    final session = CloudflareAdminSession(
      MockClient((request) async {
        if (request.url.path.endsWith('/auth/session')) {
          return pendingSession.future;
        }
        if (request.url.path == '/api/admin/operations/users/$coreId') {
          return response({
            'resource_type': 'users',
            'resource': {...coreRow(CloudflareCoreArea.users), 'version': 1},
            'current_actor_id': coreId,
            'can_manage': false,
            'related': {},
            'related_truncated': false,
          });
        }
        if (request.url.path.endsWith('/core/users')) {
          searches.add(request.url.queryParameters['search']!);
          offsets.add(request.url.queryParameters['offset']!);
          return response({
            'rows': [coreRow(CloudflareCoreArea.users)],
            'total': 26,
          });
        }
        return response(coreOverview());
      }),
      origin: Uri.parse('https://admin.example.test'),
    );
    final container = ProviderContainer(
      overrides: [
        ...cloudflareAdminOverrides(),
        cloudflareAdminSessionProvider.overrideWith((_) => session),
        cloudflareAdminRouterConfigProvider.overrideWith((ref) {
          final router = ref.watch(cloudflareAdminRouterProvider);
          return RouterConfig(
            routeInformationProvider: CloudflareAdminRouteReporting(
              delegate: router.routeInformationProvider,
              preserveWebEncoding: true,
            ),
            routeInformationParser: router.routeInformationParser,
            routerDelegate: router.routerDelegate,
            backButtonDispatcher: router.backButtonDispatcher,
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    final refreshing = session.refresh();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CloudflareAdminApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    final checking = container
        .read(cloudflareAdminRouterProvider)
        .routeInformationProvider
        .value
        .uri;
    expect(checking.path, '/admin/session');
    expect(checking.queryParameters['returnTo'], detail);
    pendingSession.complete(response(coreSession()));
    await refreshing;
    await tester.pumpAndSettle();
    expect(engine.entries.last.uri.toString(), detail);
    expect(find.byTooltip('Back to records'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to records'));
    await tester.pumpAndSettle();
    expect(engine.entries.last.uri.toString(), list);
    expect(searches.last, '+250 788 600 002 & ALICE=50%');
    expect(offsets.last, '25');
    session.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'request query navigation replaces stale input and pending lookup',
    (tester) async {
      const secondKey = 'another-request-reference';
      final pendingFirst = Completer<http.Response>();
      final lookups = <String>[];
      final session = CloudflareAdminSession(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/session')) {
            return operatingResponse(coreSession());
          }
          if (request.url.path == '/api/admin/operations/requests') {
            return operatingResponse({'rows': [], 'total': 0});
          }
          if (request.url.path.startsWith('/api/admin/operations/requests/')) {
            final key = request.url.pathSegments.last;
            lookups.add(key);
            if (key == requestKey) return pendingFirst.future;
            return operatingResponse({
              'status': 'succeeded',
              'request_id': otherId,
              'receipt': operatingReceipt(id: otherId, version: 9),
            });
          }
          return operatingResponse(coreOverview());
        }),
        origin: Uri.parse('https://admin.example.test'),
      );
      await session.refresh();
      final container = ProviderContainer(
        overrides: [
          ...cloudflareAdminOverrides(),
          cloudflareAdminSessionProvider.overrideWith((_) => session),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CloudflareAdminApp(),
        ),
      );
      final router = container.read(cloudflareAdminRouterProvider);
      router.go('/admin/requests?key=$requestKey');
      await tester.pumpAndSettle();
      final reference = find.widgetWithText(TextField, 'Request reference');
      expect(tester.widget<TextField>(reference).controller!.text, requestKey);
      await tester.tap(find.text('Check request'));
      await tester.pump();
      await tester.pump();
      expect(lookups, [requestKey]);
      expect(find.text('Checking…'), findsOneWidget);

      router.go('/admin/requests?key=$secondKey');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(reference).controller!.text, secondKey);
      expect(find.text('Checking…'), findsNothing);
      expect(find.text('Change saved'), findsNothing);
      pendingFirst.complete(
        operatingResponse({
          'status': 'succeeded',
          'request_id': otherId,
          'receipt': operatingReceipt(version: 7),
        }),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(reference).controller!.text, secondKey);
      expect(find.text('Change saved'), findsNothing);

      await tester.tap(find.text('Check request'));
      await tester.pumpAndSettle();
      expect(lookups, [requestKey, secondKey]);
      final receipt = tester.widget<AdminDataTable>(
        find.byWidgetPredicate(
          (widget) =>
              widget is AdminDataTable &&
              widget.tableLabel == 'Saved change receipt',
        ),
      );
      expect(receipt.rows.single.extra['resource_id'], otherId);
      expect(receipt.rows.single.extra['version'], 9);
      session.clear();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
