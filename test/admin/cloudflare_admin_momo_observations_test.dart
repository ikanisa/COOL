import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/cloudflare_admin_momo_page.dart';
import 'package:collect_app/admin/core/cloudflare_admin_observation_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

const _source = '11111111-1111-4111-8111-111111111111';
const _request = '22222222-2222-4222-8222-222222222222';
const _group = 'group-1';
const _time = '2026-11-11T09:30:00.000Z';
const _body = 'Synthetic source message';
final _hash = sha256.convert(utf8.encode(_body)).toString();
Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map);
http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

class _TestSession extends CloudflareAdminSession {
  _TestSession(super.client)
    : super(
        origin: Uri.parse('https://admin.example.test/'),
        environment: legacyBackendFixtureEnvironment,
      );
  bool suppressAutomaticRefresh = false;
  @override
  Future<void> refresh() async {
    if (!suppressAutomaticRefresh) await super.refresh();
  }

  void emailProof(DateTime? at) =>
      state = AsyncData(user!.withEmailVerification(at));
}

class _Fixture {
  _Fixture({
    this.retained = true,
    this.hintsEnabled = false,
    DateTime? expiresAt,
  }) {
    final fixture = _map(
      jsonDecode(
        File(
          'test/fixtures/admin-sms-capture-dto-examples.json',
        ).readAsStringSync(),
      ),
    );
    final saved = _map(fixture['session']);
    final expiry = (expiresAt ?? DateTime.now().add(const Duration(hours: 1)))
        .toUtc()
        .toIso8601String();
    session = _TestSession(
      MockClient((request) async {
        if (request.url.path == '/api/admin/auth/session') {
          return _json({
            ...saved,
            'user': {
              ..._map(saved['user']),
              'role': 'admin',
              'permissions': ['sms.read', 'sms.reveal'],
              'expiresAt': expiry,
            },
            'expiresAt': expiry,
          });
        }
        requests.add(request);
        if (request.url.path == '/api/admin/sms/receipts') {
          return _json({
            'rows': [],
            'total': 0,
            'limit': 25,
            'offset': 0,
            'next_offset': null,
          });
        }
        if (request.url.path == '/api/admin/momo/observations/collections') {
          return _json({
            'contractVersion': 1,
            'items': [
              {'collectionId': _group, 'label': 'Example group'},
            ],
            'asOf': _time,
          });
        }
        if (request.url.path == '/api/admin/momo/observations') {
          expect(request.url.queryParameters['collectionId'], _group);
          return _json({
            'contractVersion': 1,
            'collectionId': _group,
            'items': [
              {
                'requestId': _request,
                'sourceId': _source,
                'admittedAt': _time,
                'retentionState': retained ? 'retained' : 'unresolved',
                'bodySha256': retained ? _hash : null,
              },
            ],
            'nextCursor': null,
            'asOf': _time,
          });
        }
        if (request.url.path ==
            '/api/admin/momo/observations/$_source/content') {
          expect(
            request.headers['X-Collect-Review-Reason'],
            'Review the source',
          );
          expect(request.url.queryParameters, {
            'collectionId': _group,
            if (hintsEnabled) 'displayHintsVersion': '1',
          });
          return _json({
            'contractVersion': 1,
            'collectionId': _group,
            'sourceId': _source,
            'sourceKind': 'observation',
            'retentionState': 'retained',
            'rawSender': 'Synthetic',
            'rawBody': _body,
            'bodySha256': _hash,
            if (hintsEnabled)
              'displayHints': {
                'schemaVersion': 1,
                'kind': 'partial_inbox_display_only',
                'profileVersion': 'synthetic-profile',
                'profileSha256': List.filled(64, 'a').join(),
                'bodySha256': _hash,
                'hints': [
                  {
                    'kind': 'quoted_reference',
                    'text': 'Synthetic',
                    'start': 0,
                    'end': 9,
                  },
                ],
              },
          });
        }
        return http.Response('{}', 404);
      }),
    );
  }
  final bool retained, hintsEnabled;
  late final _TestSession session;
  final requests = <http.Request>[];
  int get observationReads =>
      requests.where((r) => r.url.path.contains('/momo/observations')).length;
  int get contentReads =>
      requests.where((r) => r.url.path.endsWith('/content')).length;
}

Future<GoRouter> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  required bool enabled,
  DateTime Function()? clock,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.runAsync(fixture.session.refresh);
  fixture.session.emailProof(DateTime.now().toUtc());
  final container = ProviderContainer(
    overrides: [
      cloudflareAdminSessionProvider.overrideWith((_) => fixture.session),
      burimunsiObservationEnabledProvider.overrideWith((_) => enabled),
      burimunsiObservationHintsEnabledProvider.overrideWith(
        (_) => fixture.hintsEnabled,
      ),
      if (clock != null)
        burimunsiObservationClockProvider.overrideWith((_) => clock),
    ],
  );
  final router = GoRouter(
    initialLocation: '/admin/momo-receipts',
    routes: [
      GoRoute(
        path: '/admin/momo-receipts',
        builder: (_, _) => const CloudflareAdminMomoPage(),
      ),
      GoRoute(path: '/elsewhere', builder: (_, _) => const Text('Elsewhere')),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: CollectTheme.dark(),
        routerConfig: router,
        builder: (_, child) => Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('disabled feature makes no observation request', (tester) async {
    final fixture = _Fixture(hintsEnabled: true);
    await _mount(tester, fixture, enabled: false);
    expect(find.text('Unassigned SMS'), findsNothing);
    expect(fixture.observationReads, 0);
  });

  testWidgets(
    'optional literal hints remain in the audited source and clear with it',
    (tester) async {
      final fixture = _Fixture(hintsEnabled: true);
      await _mount(tester, fixture, enabled: true);
      await tester.ensureVisible(find.byTooltip('Open $_source'));
      await tester.tap(find.byTooltip('Open $_source'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Source review reason'),
        'Review the source',
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open audited source'));
      await tester.tap(find.text('Open audited source'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Visible text from an incomplete message; not payment confirmation.',
        ),
        findsOneWidget,
      );
      expect(find.text('Visible reference text'), findsOneWidget);
      expect(find.text('Synthetic'), findsNWidgets(2));
      expect(fixture.contentReads, 1);
      fixture.session.emailProof(null);
      await tester.pumpAndSettle();
      expect(find.text('Visible reference text'), findsNothing);
      expect(find.text(_body), findsNothing);
    },
  );

  testWidgets('the visible idle group refreshes without changing screens', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, enabled: true);
    final before = fixture.observationReads;
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(fixture.observationReads, greaterThan(before));
    expect(find.text('Retained for review'), findsOneWidget);
  });

  testWidgets(
    'existing incoming screen shows scoped retained metadata and audited reveal',
    (tester) async {
      final fixture = _Fixture();
      final router = await _mount(tester, fixture, enabled: true);
      expect(find.text('Example group'), findsOneWidget);
      expect(find.text('Retained for review'), findsOneWidget);
      expect(find.text(_body), findsNothing);
      await tester.ensureVisible(find.byTooltip('Open $_source'));
      await tester.tap(find.byTooltip('Open $_source'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Source review reason'),
        'Review the source',
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open audited source'));
      await tester.tap(find.text('Open audited source'));
      await tester.pumpAndSettle();
      expect(find.text(_body), findsOneWidget);
      expect(fixture.contentReads, 1);
      fixture.session.emailProof(null);
      await tester.pumpAndSettle();
      expect(find.text(_body), findsNothing);
      router.go('/elsewhere');
      await tester.pumpAndSettle();
      router.go('/admin/momo-receipts');
      await tester.pumpAndSettle();
      expect(find.text(_body), findsNothing);
    },
  );

  testWidgets('unresolved admission cannot open source or report success', (
    tester,
  ) async {
    final fixture = _Fixture(retained: false);
    await _mount(tester, fixture, enabled: true);
    expect(find.text('Admission outcome unresolved'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Open $_source'));
    await tester.tap(find.byTooltip('Open $_source'));
    await tester.pumpAndSettle();
    expect(find.textContaining('original phone may retry'), findsOneWidget);
    expect(find.text('Open audited source'), findsNothing);
    expect(fixture.contentReads, 0);
  });

  testWidgets('the periodic check hides revealed SMS after proof ages out', (
    tester,
  ) async {
    final fixture = _Fixture();
    var now = DateTime.now().toUtc();
    await _mount(tester, fixture, enabled: true, clock: () => now);
    now = DateTime.now().toUtc().add(const Duration(seconds: 1));
    await tester.pump();
    await tester.ensureVisible(find.byTooltip('Open $_source'));
    await tester.tap(find.byTooltip('Open $_source'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Source review reason'),
      'Review the source',
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open audited source'));
    await tester.tap(find.text('Open audited source'));
    await tester.pumpAndSettle();
    expect(find.text(_body), findsOneWidget);
    now = now.add(const Duration(minutes: 6));
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.text(_body), findsNothing);
  });

  for (final deadlineKind in ['verification', 'session']) {
    testWidgets('revealed SMS clears at the $deadlineKind deadline', (
      tester,
    ) async {
      final startedAt = DateTime.now().toUtc();
      final fixture = _Fixture(
        expiresAt: deadlineKind == 'session'
            ? startedAt.add(const Duration(minutes: 3))
            : null,
      );
      var baseTime = startedAt.add(const Duration(seconds: 1));
      final testStart = tester.binding.clock.now();
      DateTime now() =>
          baseTime.add(tester.binding.clock.now().difference(testStart));
      await _mount(tester, fixture, enabled: true, clock: now);
      // Keep this boundary test focused on its explicit proof and deadline.
      fixture.session.suppressAutomaticRefresh = true;
      baseTime = DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 1))
          .subtract(tester.binding.clock.now().difference(testStart));
      await tester.pump();
      await tester.ensureVisible(find.byTooltip('Open $_source'));
      await tester.tap(find.byTooltip('Open $_source'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Source review reason'),
        'Review the source',
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open audited source'));
      await tester.tap(find.text('Open audited source'));
      await tester.pumpAndSettle();
      expect(find.text(_body), findsOneWidget);
      final user = fixture.session.user!;
      final proofDeadline = user.sensitiveVerificationAt!.add(
        const Duration(minutes: 5),
      );
      final deadline = user.expiresAt.isBefore(proofDeadline)
          ? user.expiresAt
          : proofDeadline;
      final remaining = deadline.difference(now());
      expect(remaining > const Duration(milliseconds: 1), isTrue);
      await tester.pump(remaining - const Duration(milliseconds: 1));
      expect(find.text(_body), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text(_body), findsNothing);
    });
  }
}
