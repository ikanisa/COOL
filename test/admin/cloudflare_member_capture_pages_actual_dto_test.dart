import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/cloudflare_admin_receipt_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map);

// Exact real workerd/D1 response objects, copied after the focused Node cohort.
// This is a UI/DTO replay, not a hosted authentication or provider test.
Map<String, dynamic> _examples() => _map(
  jsonDecode(
    File(
      'test/fixtures/admin-member-capture-dto-examples.json',
    ).readAsStringSync(),
  ),
);

http.Response _response(Object? value) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Future<void> _open(
  WidgetTester tester,
  Map<String, dynamic> examples, {
  String? detailId,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final session = CloudflareAdminSession(
    MockClient((request) async {
      expect(request.method, 'GET');
      if (request.url.path == '/api/admin/auth/session') {
        final recorded = _map(jsonDecode(jsonEncode(examples['session'])));
        final expiry = DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String();
        recorded['expiresAt'] = expiry;
        (recorded['user'] as Map)['expiresAt'] = expiry;
        return _response(recorded);
      }
      if (request.url.path == '/api/admin/gateway/receipts') {
        expect(request.url.queryParameters, {'limit': '25', 'offset': '0'});
        return _response(examples['list']!);
      }
      final detail = (examples['details'] as List)
          .map(_map)
          .singleWhere(
            (value) =>
                request.url.path ==
                '/api/admin/gateway/receipts/${_map(value['resource'])['id']}',
          );
      expect(request.url.queryParameters, isEmpty);
      return _response(detail);
    }),
    origin: Uri.parse('https://admin.example.test/'),
    environment: legacyBackendFixtureEnvironment,
  );
  await tester.runAsync(session.refresh);
  final repository = CloudflareAdminRepository(session);
  final container = ProviderContainer(
    overrides: [
      adminRepositoryProvider.overrideWithValue(repository),
      cloudflareAdminSessionProvider.overrideWith((_) => session),
    ],
  );
  final router = GoRouter(
    initialLocation: detailId == null
        ? '/admin/member-receipts'
        : '/admin/member-receipts/$detailId',
    routes: [
      GoRoute(
        path: '/admin/member-receipts',
        builder: (_, _) => const CloudflareMemberReceiptListPage(),
      ),
      GoRoute(
        path: '/admin/member-receipts/:id',
        builder: (_, state) =>
            CloudflareMemberReceiptDetailPage(id: state.pathParameters['id']!),
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'actual capture Member list remains a keyboard-scrollable table at 320px and 2x',
    (tester) async {
      final examples = _examples();
      await _open(tester, examples);
      expect(tester.takeException(), isNull);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(AdminDataTable), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);
      final table = tester.widget<AdminDataTable>(find.byType(AdminDataTable));
      expect(table.columns!.map((column) => column.label), [
        'Member ID',
        'Member name',
        'Receipt status',
        'Device time (source)',
        'Evidence level',
        'Received',
        'Created',
        'Reviewed',
        'Attached transaction ID',
        'Version',
        'Submission ID',
        'User record ID',
        'Source SHA-256',
      ]);
      expect(
        table.rows.map((row) => row.extra).toList(),
        _map(examples['list'])['rows'],
      );
      final focus = tester.widget<Focus>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Focus &&
              widget.focusNode?.debugLabel ==
                  'Admin table horizontal scrolling',
        ),
      );
      final scroll = tester
          .widgetList<SingleChildScrollView>(
            find.descendant(
              of: find.byType(AdminDataTable),
              matching: find.byType(SingleChildScrollView),
            ),
          )
          .singleWhere((view) => view.scrollDirection == Axis.horizontal)
          .controller!
          .position;
      expect(scroll.maxScrollExtent, greaterThan(0));
      focus.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(scroll.pixels, greaterThan(0));
      expect(find.text('Reveal submitted content'), findsNothing);
      expect(find.text('Review classification'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actual capture Member detail stays read-only and table based at 320px and 2x',
    (tester) async {
      final examples = _examples();
      final detail = _map((examples['details'] as List).first);
      final resource = _map(detail['resource']);
      await _open(tester, examples, detailId: resource['id'] as String);
      expect(tester.takeException(), isNull);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(AdminDataTable), findsWidgets);
      expect(
        find.text('Source review is unavailable for this captured receipt'),
        findsOneWidget,
      );
      expect(find.text('Reveal submitted content'), findsNothing);
      expect(find.text('Review classification'), findsNothing);
      expect(find.text('Confirm classification'), findsNothing);
      final tables = tester.widgetList<AdminDataTable>(
        find.byType(AdminDataTable),
      );
      expect(
        tables.any(
          (table) => table.rows.any((row) => row.extra['id'] == resource['id']),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
