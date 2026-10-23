import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/core/cloudflare_admin_momo_page.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/core/cloudflare_admin_sms_pages.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map);

class _Fixture {
  _Fixture() {
    final recorded = _map(
      jsonDecode(
        File(
          'test/fixtures/admin-sms-capture-dto-examples.json',
        ).readAsStringSync(),
      ),
    );
    recordedSession = _map(recorded['session']);
    capture = _map((_map(recorded['list_all'])['rows'] as List).first);
    rows = [capture];
    session = CloudflareAdminSession(
      MockClient((request) async {
        if (request.url.path == '/api/admin/auth/session') {
          return response({
            ...recordedSession,
            'user': {
              ..._map(recordedSession['user']),
              'sessionId': sessionId,
              'permissions': permissions,
            },
            'expiresAt': DateTime.now()
                .add(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
          });
        }
        requests.add(request);
        if (request.url.path == '/api/admin/sms/receipts') {
          expect(request.method, 'GET');
          expect(request.url.queryParameters['source_kind'], 'capture');
          if (onRead case final handler?) return handler(request);
          return response(page());
        }
        return http.Response('{}', 404);
      }),
      origin: Uri.parse('https://admin.example.test/'),
      environment: legacyBackendFixtureEnvironment,
    );
  }
  late final Map<String, dynamic> recordedSession, capture;
  late final CloudflareAdminSession session;
  late List<Map<String, dynamic>> rows;
  List<String> permissions = ['sms.read', 'payments.read'];
  String sessionId = 'incoming-sms-session-one';
  Future<http.Response> Function(http.Request)? onRead;
  final requests = <http.Request>[];
  int get reads => requests
      .where((request) => request.url.path == '/api/admin/sms/receipts')
      .length;
  Map<String, dynamic> page() => {
    'rows': rows,
    'total': rows.length,
    'offset': 0,
    'limit': 25,
    'next_offset': null,
  };
  static http.Response response(Object data) => http.Response(
    jsonEncode(data),
    200,
    headers: {'content-type': 'application/json'},
  );
}

Future<({GoRouter router, ValueNotifier<bool> visible, GlobalKey capture})>
_mount(
  WidgetTester tester,
  _Fixture fixture, {
  double width = 1400,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.runAsync(fixture.session.refresh);
  final container = ProviderContainer(
    overrides: [
      cloudflareAdminSessionProvider.overrideWith((_) => fixture.session),
    ],
  );
  final visible = ValueNotifier(true);
  final capture = GlobalKey();
  final router = GoRouter(
    initialLocation: '/admin/momo-receipts',
    routes: [
      GoRoute(
        path: '/admin/momo-receipts',
        builder: (_, _) => ValueListenableBuilder(
          valueListenable: visible,
          builder: (_, enabled, _) => TickerMode(
            enabled: enabled,
            child: const CloudflareAdminMomoPage(),
          ),
        ),
      ),
      GoRoute(
        path: '/admin/sms-receipts/:kind/:id',
        builder: (_, state) => Text(
          '${state.pathParameters['kind']}/${state.pathParameters['id']} '
          'returnTo=${state.uri.queryParameters['returnTo']}',
        ),
      ),
      GoRoute(path: '/elsewhere', builder: (_, _) => const Text('Other view')),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
    visible.dispose();
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: capture,
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: CollectTheme.dark(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(body: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (router: router, visible: visible, capture: capture);
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['COLLECT_MOMO_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'compact incoming SMS table preserves fields and source navigation',
    (tester) async {
      final fixture = _Fixture();
      final mounted = await _mount(tester, fixture, width: 320, textScale: 2);
      final table = find.byType(DataTable);
      expect(table, findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      expect(find.byType(Card), findsNothing);
      for (final label in [
        'App user',
        'Member ID',
        'SMS time · Kigali',
        'Uploaded · Kigali',
        'Status',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Recorded Capture Owner'), findsOneWidget);
      expect(find.text('Uploaded'), findsOneWidget);
      final horizontal = find.ancestor(
        of: table,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.right,
        ),
      );
      expect(horizontal, findsOneWidget);
      final position = tester.state<ScrollableState>(horizontal).position;
      expect(position.maxScrollExtent, greaterThan(0));
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final open = find.byTooltip('Open Recorded Capture Owner');
      await tester.ensureVisible(open);
      await tester.pumpAndSettle();
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(
        mounted.router.routeInformationProvider.value.uri.path,
        '/admin/sms-receipts/capture/${fixture.capture['id']}',
      );
      expect(
        mounted.router.routeInformationProvider.value.uri.queryParameters,
        {'returnTo': '/admin/momo-receipts'},
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('default shows uploaded member captures without gateway reads', (
    tester,
  ) async {
    final fixture = _Fixture();
    final mounted = await _mount(tester, fixture);
    expect(find.text('Incoming SMS'), findsOneWidget);
    expect(find.text('Recorded Capture Owner'), findsOneWidget);
    expect(find.text('Uploaded'), findsOneWidget);
    expect(find.text('Gateway setup'), findsNothing);
    expect(find.text('Receiving account'), findsNothing);
    expect(fixture.requests, hasLength(1));
    expect(fixture.requests.single.url.path, '/api/admin/sms/receipts');
    await _capture(tester, mounted.capture, 'incoming-sms-desktop');
    await tester.tap(find.text('Recorded Capture Owner'));
    await tester.pumpAndSettle();
    expect(
      mounted.router.routeInformationProvider.value.uri.path,
      '/admin/sms-receipts/capture/${fixture.capture['id']}',
    );
    expect(mounted.router.routeInformationProvider.value.uri.queryParameters, {
      'returnTo': '/admin/momo-receipts',
    });
    expect(smsReturnLocation('/admin/momo-receipts'), '/admin/momo-receipts');
    expect(
      smsReturnLocation('/admin/momo-receipts?unexpected=1'),
      '/admin/sms-receipts',
    );
  });

  testWidgets(
    '15-second refresh displays new uploads and never overlaps reads',
    (tester) async {
      final fixture = _Fixture();
      await _mount(tester, fixture);
      final pending = Completer<http.Response>();
      fixture.onRead = (_) => pending.future;
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(fixture.reads, 2);
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(fixture.reads, 2);
      expect(find.text('Recorded Capture Owner'), findsOneWidget);
      fixture.rows = [
        {
          ...fixture.capture,
          'id': '11111111-1111-4111-8111-111111111111',
          'display_name': 'Newly uploaded owner',
        },
      ];
      pending.complete(_Fixture.response(fixture.page()));
      await tester.pumpAndSettle();
      expect(find.text('Newly uploaded owner'), findsOneWidget);
      expect(find.text('Recorded Capture Owner'), findsNothing);
    },
  );

  testWidgets('failed poll keeps last confirmed uploads and offers refresh', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    fixture.onRead = (_) async => http.Response('{}', 503);
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(find.text('Recorded Capture Owner'), findsOneWidget);
    expect(
      find.textContaining('Showing the last confirmed uploads.'),
      findsOneWidget,
    );
    fixture.onRead = null;
    await tester.tap(find.byTooltip('Refresh incoming SMS'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Showing the last confirmed uploads.'),
      findsNothing,
    );
    expect(fixture.reads, 3);
  });

  testWidgets('poll pauses in background, disabled branch, and another route', (
    tester,
  ) async {
    final fixture = _Fixture();
    final mounted = await _mount(tester, fixture);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(fixture.reads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fixture.reads, 2);
    mounted.visible.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(fixture.reads, 2);
    mounted.visible.value = true;
    await tester.pump();
    final context = tester.element(find.byType(CloudflareAdminMomoPage));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Another task')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(fixture.reads, 2);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    mounted.router.go('/elsewhere');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(fixture.reads, 2);
  });

  testWidgets('authority replacement removes old rows and fences a late poll', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    final old = Completer<http.Response>();
    fixture.onRead = (_) => old.future;
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(fixture.reads, 2);
    fixture.sessionId = 'incoming-sms-session-two';
    fixture.rows = [];
    fixture.onRead = null;
    await tester.runAsync(fixture.session.refresh);
    await tester.pumpAndSettle();
    expect(find.text('Recorded Capture Owner'), findsNothing);
    expect(find.textContaining('No SMS uploaded yet.'), findsOneWidget);
    old.complete(
      _Fixture.response({
        ...fixture.page(),
        'rows': [fixture.capture],
        'total': 1,
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recorded Capture Owner'), findsNothing);
    expect(find.textContaining('No SMS uploaded yet.'), findsOneWidget);
  });

  testWidgets(
    'SMS-only reader sees uploads without payment or setup controls',
    (tester) async {
      final fixture = _Fixture()..permissions = ['sms.read'];
      final mounted = await _mount(tester, fixture, width: 390, textScale: 2);
      expect(find.text('Transactions'), findsNothing);
      expect(find.text('Recorded Capture Owner'), findsOneWidget);
      expect(find.byTooltip('More MoMo tools'), findsNothing);
      expect(tester.takeException(), isNull);
      await _capture(tester, mounted.capture, 'incoming-sms-390-2x');
    },
  );
}
