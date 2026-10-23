import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/cloudflare_admin_app.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/core/admin_privacy_review_controller.dart';
import 'package:collect_app/admin/core/cloudflare_admin_privacy_review_host.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_retention_inspection.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/main_admin_cloudflare.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/privacy_review_fixtures.dart';
import 'cloudflare_core_fixtures.dart';
import '../support/legacy_backend_fixture.dart';

final _source = List.filled(64, '1').join();
final _schema = List.filled(64, '2').join();
final _snapshot = List.filled(64, '3').join();
const _subject = '99790000-0000-4000-8000-000000000099';

Map<String, dynamic> _context({DateTime? checked, DateTime? until}) => {
  'contract_version': 1,
  'scope': 'account_retention_inspection_context',
  'source_id': _source,
  'checked_at': (checked ?? privacyNow).toIso8601String(),
  'valid_until': (until ?? privacyNow.add(const Duration(minutes: 5)))
      .toIso8601String(),
  'approval_granted': false,
  'erasure_completed': false,
};

Map<String, dynamic> _inspection() => {
  'contract_version': 1,
  'request_id': privacyRequest,
  'subject_id': _subject,
  'source_id': _source,
  'schema_sha256': _schema,
  'snapshot_sha256': _snapshot,
  'table_counts': {'users': 1, 'deletion_requests': 1, 'sessions': 0},
  'object_count': 2,
  'active_hold_count': 1,
  'in_flight_unresolved': true,
  'approval_granted': false,
  'erasure_completed': false,
};

class _CookieFixture {
  _CookieFixture({
    this.environment = legacyBackendFixtureEnvironment,
    String origin = 'https://admin.example.test',
  }) : origin = Uri.parse(origin);

  final AppEnv environment;
  final Uri origin;
  final journal = PrivacyJournalFixture();
  final requests = <http.Request>[];
  final verificationRequests = <http.Request>[];
  late final CloudflareAdminSession session;
  DateTime now = privacyNow;
  List<String> permissions = [
    'overview.read',
    'account.manage',
    'privacy.review',
  ];
  int assurance = 2;
  String role = 'staff', state = 'not_started', operation = privacyOperation;
  bool loseClaimResponse = false, deny = false;
  Completer<http.Response>? delayedList;
  Completer<void>? listStarted;
  Map<String, dynamic> Function()? contextResponse;
  Map<String, dynamic> Function()? inspectionResponse;
  DateTime? emailVerifiedAt;
  String publicSession = privacySession;
  String? verificationSession;

  String get prefix => environment.usesSupabase
      ? '/functions/v1/admin-api/api/admin'
      : '/api/admin';

  DateTime clock() => now;
  List<http.Request> calls(String name) => requests
      .where((request) => request.url.path == '$prefix/privacy/$name')
      .toList();

  http.Response reply(Object? value, [int code = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(value)),
    code,
    headers: {'content-type': 'application/json'},
  );

  Future<void> start() async {
    session = CloudflareAdminSession(
      MockClient((request) async {
        if (request.url.path == '$prefix/auth/session') {
          return reply({
            'user': {
              // Account roster ID and canonical principal are deliberately distinct.
              'id': coreId,
              'principalId': privacyActor,
              'sessionId': publicSession,
              'email': 'reviewer@example.test',
              'role': role,
              'permissions': permissions,
              'assuranceLevel': assurance,
              'mfaAt': assurance == 2 ? privacyNow.toIso8601String() : null,
            },
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
            if (environment.usesSupabase) 'csrfToken': 'a' * 64,
          });
        }
        if (request.url.path == '$prefix/auth/email-verification') {
          verificationRequests.add(request);
          return reply({
            'contractVersion': 1,
            'sessionId': verificationSession ?? publicSession,
            'emailVerifiedAt': emailVerifiedAt?.toUtc().toIso8601String(),
          });
        }
        if (request.url.path == '$prefix/core/overview') {
          return reply(coreOverview());
        }
        if (request.url.path == '$prefix/sync') {
          return reply({
            'contract_version': 1,
            'events': [],
            'cursor': request.url.queryParameters['cursor'],
          });
        }
        requests.add(request);
        if (deny) {
          return reply({
            'error': 'fresh_auth_required',
            'message': 'PRIVATE_CANARY',
          }, 403);
        }
        final name = request.url.path.split('/').last;
        final parameters = jsonDecode(request.body) as Map;
        switch (name) {
          case 'admin_get_account_retention_context_v1':
            return reply(contextResponse?.call() ?? _context());
          case 'admin_list_account_deletion_reviews_v1':
            if (delayedList != null) {
              listStarted?.complete();
              return delayedList!.future;
            }
            return reply(privacyPageRaw(items: [privacyItem(state: state)]));
          case 'admin_get_account_deletion_review_v1':
            return reply(
              privacyDetailRaw(state: state, owned: state != 'not_started'),
            );
          case 'admin_claim_account_deletion_review_v1':
            final checkpoint = await journal.store.read(
              privacyActor,
              privacySession,
            );
            expect(parameters, checkpoint.pending!.parameters);
            operation = parameters['p_claim_request_id'] as String;
            state = 'claim_active';
            if (loseClaimResponse) {
              throw http.ClientException('Synthetic lost response');
            }
            return reply(privacyClaimReceipt(operation: operation));
          case 'admin_get_account_deletion_review_operation_v1':
            final intent = (await journal.store.read(
              privacyActor,
              privacySession,
            )).pending!;
            return reply(
              privacyOperationRaw(
                intent,
                observed: state == 'claim_active',
                receipt: state == 'claim_active'
                    ? privacyClaimReceipt(operation: operation)
                    : null,
                current: state == 'claim_active',
              ),
            );
          case 'admin_record_account_deletion_review_v1':
            final checkpoint = await journal.store.read(
              privacyActor,
              privacySession,
            );
            expect(parameters, checkpoint.pending!.parameters);
            state = 'blocked';
            return reply(
              privacyOutcomeReceipt(
                operation: parameters['p_outcome_request_id'] as String,
              ),
            );
          case 'admin_inspect_account_retention_scope_v1':
            return reply(inspectionResponse?.call() ?? _inspection());
          default:
            throw StateError(
              'Unexpected private fixture request: ${request.url.path}',
            );
        }
      }),
      origin: origin,
      environment: environment,
    );
    await session.refresh();
  }

  CloudflareAdminPrivacyAccess access({VoidCallback? onDenied}) =>
      CloudflareAdminPrivacyAccess(
        session: session,
        user: session.user!,
        now: clock,
        onDenied: onDenied,
      );

  void dispose() => session.dispose();
}

class _SupabaseCookieFixture extends _CookieFixture {
  _SupabaseCookieFixture()
    : super(
        origin: 'https://backend.collect.ikanisa.com',
        environment: const AppEnv(
          apiUrl: '',
          publicUrl: '',
          adminAppUrl: '',
          enableSmsReader: false,
          enableAndroidSmsAccess: true,
          enableAdminPanel: false,
          enableAdminDevTools: false,
          authCaptchaEnabled: false,
          authCaptchaProvider: '',
          authCaptchaSiteKey: '',
          backend: 'supabase',
          supabaseUrl: 'https://rrlduytparvsjfmegalh.supabase.co',
          supabaseAdminApiUrl: 'https://backend.collect.ikanisa.com',
          supabasePublishableKey: 'sb_publishable_synthetic_test_key_only',
        ),
      ) {
    assurance = 1;
    emailVerifiedAt = privacyNow;
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _CookieFixture fixture, {
  double width = 1440,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final container = ProviderContainer(
    overrides: [
      ...cloudflareAdminOverrides(),
      cloudflareAdminSessionProvider.overrideWith((_) => fixture.session),
      cloudflareAdminPrivacyClockProvider.overrideWithValue(fixture.clock),
      cloudflareAdminPrivacyStoreProvider.overrideWithValue(
        fixture.journal.store,
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(cloudflareAdminRouterProvider).go('/admin/privacy-requests');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const CloudflareAdminApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('context uses exact source and canonical bounded server expiry', () {
    final context = CloudflareAdminRetentionContext.parse(
      _context(),
      privacyNow,
    );
    expect(context.sourceId, _source);
    expect(context.fresh(privacyNow.add(const Duration(minutes: 5))), isFalse);
    expect(
      context.fresh(privacyNow.subtract(const Duration(microseconds: 1))),
      isFalse,
    );
    for (final change in <Map<String, dynamic>>[
      {'contract_version': 1.0},
      {'approval_granted': true},
      {'erasure_completed': true},
      {'extra': false},
      {'source_id': 'A' * 64},
      {'checked_at': '2026-10-03T12:00:00Z'},
      {'checked_at': '2026-10-03T12:00:00.000+00:00'},
      {'checked_at': '2026-10-03T12:00:01.000Z'},
      {'checked_at': '2026-02-30T12:00:00.000Z'},
      {'valid_until': privacyNow.toIso8601String()},
      {
        'valid_until': privacyNow
            .add(const Duration(minutes: 5, milliseconds: 1))
            .toIso8601String(),
      },
    ]) {
      expect(
        () => CloudflareAdminRetentionContext.parse({
          ..._context(),
          ...change,
        }, privacyNow),
        throwsFormatException,
        reason: '$change',
      );
    }
  });

  test(
    'inspection rejects mismatched scope, rows, malformed counts and false approvals',
    () {
      CloudflareAdminRetentionInspection parse(Map<String, dynamic> row) =>
          CloudflareAdminRetentionInspection.parse(
            row,
            requestId: privacyRequest,
            sourceId: _source,
          );
      final value = parse(_inspection());
      expect(value.tableCounts.keys, [
        'deletion_requests',
        'sessions',
        'users',
      ]);
      expect(value.activeHoldCount, 1);
      expect(() => value.tableCounts['users'] = 0, throwsUnsupportedError);
      for (final change in <Map<String, dynamic>>[
        {'request_id': privacyOperation},
        {'source_id': _schema},
        {'subject_id': 'not-an-identifier'},
        {'schema_sha256': 'short'},
        {'snapshot_sha256': '${_snapshot.toUpperCase()}a'},
        {'table_counts': <String, int>{}},
        {
          'table_counts': {'users': -1},
        },
        {
          'table_counts': {'users': 1.0},
        },
        {
          'table_counts': {'users': 9007199254740992},
        },
        {
          'table_counts': {'users; SELECT': 1},
        },
        {
          'table_counts': {'users': []},
        },
        {'object_count': -1},
        {'active_hold_count': false},
        {'in_flight_unresolved': 'false'},
        {'approval_granted': true},
        {'erasure_completed': true},
        {
          'rows': [
            {'private': 'canary'},
          ],
        },
      ]) {
        expect(
          () => parse({..._inspection(), ...change}),
          throwsFormatException,
          reason: '$change',
        );
      }
    },
  );

  test(
    'cookie bridge sends exact POST bodies and never sends local journal identities',
    () async {
      final h = _CookieFixture();
      await h.start();
      addTearDown(h.dispose);
      final access = h.access();
      await access.initialize();
      final page = await access.review.list();
      expect(page.items.single.requestId, privacyRequest);
      final detail = await access.review.detail(privacyRequest);
      final observed = await access.inspection.inspect(detail);
      expect(observed.objectCount, 2);
      final config = h.calls('admin_get_account_retention_context_v1').single;
      expect(jsonDecode(config.body), isEmpty);
      final inspect = h
          .calls('admin_inspect_account_retention_scope_v1')
          .single;
      expect(jsonDecode(inspect.body), {
        'p_request_id': privacyRequest,
        'p_expected_review_revision': 0,
        'p_expected_source_id': _source,
      });
      for (final request in h.requests) {
        expect(request.method, 'POST');
        expect(request.headers['X-Collect-Admin'], '1');
        expect(
          request.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('authorization')),
        );
        expect(request.body, isNot(contains(privacyActor)));
        expect(request.body, isNot(contains(privacySession)));
        expect(request.body, isNot(contains(coreId)));
      }
      final count = h.requests.length;
      await expectLater(
        access.rpc('admin_execute_account_retention_task_v1', {}),
        throwsArgumentError,
      );
      expect(h.requests, hasLength(count));
    },
  );

  test(
    'unknown review write resolves its durable original UUID without resending',
    () async {
      final h = _CookieFixture();
      await h.start();
      addTearDown(h.dispose);
      final access = h.access();
      await access.initialize();
      final controller = AdminPrivacyReviewController(
        api: access.review,
        actorId: privacyActor,
        sessionId: privacySession,
        store: h.journal.store,
        now: h.clock,
        isCurrent: access.isCurrent,
        newOperationId: () => privacyOperation,
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.open(privacyRequest);
      h.loseClaimResponse = true;
      await controller.startReview();
      final pending = (await h.journal.store.read(
        privacyActor,
        privacySession,
      )).pending!;
      expect(pending.operationId, privacyOperation);
      expect(h.calls('admin_claim_account_deletion_review_v1'), hasLength(1));
      expect(controller.pending?.operationId, privacyOperation);
      await controller.resolve();
      expect(h.calls('admin_claim_account_deletion_review_v1'), hasLength(1));
      expect(
        h.calls('admin_get_account_deletion_review_operation_v1'),
        hasLength(1),
      );
      expect(
        (await h.journal.store.read(privacyActor, privacySession)).pending,
        isNull,
      );
      expect(controller.detail?.claimAuthorityCurrent, isTrue);
    },
  );

  test(
    'cookie A-to-B-to-A generation and context expiry reject old queue replies',
    () async {
      for (final expire in [false, true]) {
        final h = _CookieFixture();
        await h.start();
        try {
          final access = h.access();
          await access.initialize();
          h.delayedList = Completer<http.Response>();
          h.listStarted = Completer<void>();
          final waiting = access.review.list();
          final rejection = expectLater(
            waiting,
            throwsA(isA<AdminSessionChanged>()),
          );
          await h.listStarted!.future;
          if (expire) {
            h.now = privacyNow.add(const Duration(minutes: 5));
          } else {
            h.session.clear();
            await h.session.refresh();
            expect(h.session.user!.sessionId, privacySession);
          }
          h.delayedList!.complete(h.reply(privacyPageRaw()));
          await rejection;
          expect(access.isCurrent(), isFalse);
        } finally {
          h.dispose();
        }
      }
    },
  );

  test(
    'server denial invalidates access and inspection cannot accept self or changed source',
    () async {
      final h = _CookieFixture();
      await h.start();
      addTearDown(h.dispose);
      var denied = 0;
      final access = h.access(onDenied: () => denied++);
      await access.initialize();
      h.inspectionResponse = () => {
        ..._inspection(),
        'subject_id': privacyActor,
      };
      await expectLater(
        access.inspection.inspect(privacyDetail()),
        throwsFormatException,
      );
      h.inspectionResponse = () => {..._inspection(), 'source_id': _schema};
      await expectLater(
        access.inspection.inspect(privacyDetail()),
        throwsFormatException,
      );
      h.deny = true;
      await expectLater(
        access.review.list(),
        throwsA(isA<AdminSessionChanged>()),
      );
      expect(denied, 1);
      expect(access.isCurrent(), isFalse);
      final count = h.requests.length;
      await expectLater(
        access.review.list(),
        throwsA(isA<AdminSessionChanged>()),
      );
      expect(h.requests, hasLength(count));
    },
  );

  test(
    'configured cookie privacy permission and legacy owner fallback stay distinct',
    () async {
      final h = _CookieFixture();
      await h.start();
      addTearDown(h.dispose);
      final repository = CloudflareAdminRepository(h.session);
      final config = await repository.runtimeConfig();
      final identity = (await repository.currentIdentity())!;
      expect(identity.roles, ['staff']);
      expect(identity.permissions, isNot(contains('users.read')));
      expect(
        adminCanOpenPath(
          identity,
          '/admin/privacy-requests',
          runtimeConfig: config,
        ),
        isTrue,
      );
      expect(adminCanOpenPath(identity, '/admin/privacy-requests'), isFalse);
      const noPrivacy = AdminIdentity(
        userId: coreId,
        displayName: 'Owner',
        roles: ['platform_owner'],
        permissions: ['users.read', 'audit.read'],
      );
      expect(adminCanOpenPath(noPrivacy, '/admin/privacy-requests'), isTrue);
      expect(
        adminCanOpenPath(
          noPrivacy,
          '/admin/privacy-requests',
          runtimeConfig: config,
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'shipping cookie route shows review and read-only scope without legacy permissions',
    (tester) async {
      final h = _CookieFixture();
      await h.start();
      await _mount(tester, h);
      expect(find.byKey(const Key('privacy-requests-table')), findsOneWidget);
      await _tap(
        tester,
        find.byKey(const ValueKey('privacy-open-$privacyRequest')),
      );
      await _tap(tester, find.text('Inspect retained scope'));
      expect(find.text('Stored objects'), findsOneWidget);
      expect(find.text('Active legal holds'), findsOneWidget);
      expect(
        find.text('Unresolved work is present in this scope.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Policy approval and deletion remain unavailable.'),
        findsOneWidget,
      );
      expect(h.calls('admin_inspect_account_retention_scope_v1'), hasLength(1));
      expect(
        h.requests.where(
          (r) =>
              r.url.path.contains('admin_plan_') ||
              r.url.path.contains('admin_execute_'),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      h.session.clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'denied direct route sends no privacy request; AAL1 requires actual verification',
    (tester) async {
      final h = _CookieFixture()
        ..permissions = ['overview.read', 'account.manage'];
      await h.start();
      final container = await _mount(tester, h);
      expect(
        container
            .read(cloudflareAdminRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/admin',
      );
      expect(h.requests, isEmpty);
      h.permissions = ['overview.read', 'account.manage', 'privacy.review'];
      h.assurance = 1;
      await h.session.refresh();
      container
          .read(cloudflareAdminRouterProvider)
          .go('/admin/privacy-requests');
      await tester.pumpAndSettle();
      expect(find.text('Verify authenticator'), findsOneWidget);
      expect(find.text('Fresh privacy review access required'), findsOneWidget);
      expect(h.requests, isEmpty);
      h.session.clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'compact enlarged-text inspection reflows; expiry removes queue and selected scope',
    (tester) async {
      final h = _CookieFixture();
      await h.start();
      await _mount(tester, h, width: 390, scale: 2);
      await _tap(
        tester,
        find.byKey(const ValueKey('privacy-open-$privacyRequest')),
      );
      await _tap(tester, find.text('Inspect retained scope'));
      expect(tester.takeException(), isNull);
      h.now = privacyNow.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('privacy-requests-table')), findsNothing);
      expect(
        find.byKey(const Key('privacy-retention-inspection')),
        findsNothing,
      );
      expect(find.text('Fresh privacy review access required'), findsOneWidget);
      expect(find.text('Sign in again'), findsOneWidget);
      expect(find.text('PRIVATE_CANARY'), findsNothing);
      h.session.clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'Supabase privacy uses the current SID-bound email proof at real AAL1',
    () async {
      final h = _SupabaseCookieFixture();
      await h.start();
      addTearDown(h.dispose);
      final user = h.session.user!;
      expect(user.assuranceLevel, 1);
      expect(user.mfaAt, isNull);
      expect(user.usesEmailVerification, isTrue);
      expect(user.emailVerifiedAt, privacyNow);
      expect(cloudflareAdminPrivacyIdentityAllows(user, now: h.now), isTrue);
      final proofRequest = h.verificationRequests.single;
      expect(proofRequest.method, 'GET');
      expect(proofRequest.body, isEmpty);
      expect(
        proofRequest.url.path,
        '/functions/v1/admin-api/api/admin/auth/email-verification',
      );
      final access = h.access();
      await access.initialize();
      expect(
        (await access.review.list()).items.single.requestId,
        privacyRequest,
      );
      expect(h.session.user!.assuranceLevel, 1);
      expect(h.session.user!.mfaAt, isNull);
      for (final request in h.requests) {
        expect(
          request.url.path,
          startsWith('/functions/v1/admin-api/api/admin/privacy/'),
        );
        expect(request.headers['X-Collect-CSRF'], 'a' * 64);
        expect(
          request.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('authorization')),
        );
        expect(request.body, isNot(contains(privacyActor)));
        expect(request.body, isNot(contains(privacySession)));
      }
    },
  );

  for (final scenario in ['absent', 'stale', 'future', 'wrong session']) {
    testWidgets('Supabase $scenario email proof cannot open privacy review', (
      tester,
    ) async {
      final h = _SupabaseCookieFixture();
      if (scenario == 'absent') h.emailVerifiedAt = null;
      if (scenario == 'stale') {
        h.emailVerifiedAt = privacyNow.subtract(
          const Duration(minutes: 5, microseconds: 1),
        );
      }
      if (scenario == 'future') {
        h.emailVerifiedAt = privacyNow.add(const Duration(seconds: 1));
      }
      if (scenario == 'wrong session') {
        h.verificationSession = '99790000-0000-4000-8000-000000000088';
      }
      await h.start();
      expect(
        cloudflareAdminPrivacyIdentityAllows(h.session.user, now: h.now),
        isFalse,
      );
      await _mount(tester, h);
      expect(h.requests, isEmpty);
      expect(find.byKey(const Key('privacy-requests-table')), findsNothing);
      expect(find.text('Verify authenticator'), findsNothing);
      if (scenario != 'wrong session') {
        expect(find.text('Verify email'), findsOneWidget);
      }
      h.session.clear();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final outcome in ['proof expiry', 'replacement session']) {
    test('Supabase $outcome refuses an old in-flight privacy reply', () async {
      final h = _SupabaseCookieFixture()
        ..emailVerifiedAt = privacyNow.subtract(const Duration(minutes: 4));
      await h.start();
      addTearDown(h.dispose);
      final access = h.access();
      await access.initialize();
      expect(access.validUntil, privacyNow.add(const Duration(minutes: 1)));
      h.delayedList = Completer<http.Response>();
      h.listStarted = Completer<void>();
      final waiting = access.review.list();
      final rejected = expectLater(
        waiting,
        throwsA(isA<AdminSessionChanged>()),
      );
      await h.listStarted!.future;
      if (outcome == 'proof expiry') {
        h.now = privacyNow.add(const Duration(minutes: 1, microseconds: 1));
      } else {
        h.publicSession = '99790000-0000-4000-8000-000000000088';
        h.verificationSession = privacySession;
        await h.session.refresh();
      }
      h.delayedList!.complete(h.reply(privacyPageRaw()));
      await rejected;
      expect(access.isCurrent(), isFalse);
      expect(h.calls('admin_list_account_deletion_reviews_v1'), hasLength(1));
      expect(h.calls('admin_claim_account_deletion_review_v1'), isEmpty);
    });
  }

  test(
    'same-session email renewal preserves the original unknown operation and context cap',
    () async {
      final h = _SupabaseCookieFixture()
        ..emailVerifiedAt = privacyNow.subtract(const Duration(minutes: 4));
      await h.start();
      addTearDown(h.dispose);
      final fence = h.session.authorityFence;
      final access = h.access();
      await access.initialize();
      final contextUntil = access.context!.validUntil;
      final controller = AdminPrivacyReviewController(
        api: access.review,
        actorId: privacyActor,
        sessionId: privacySession,
        store: h.journal.store,
        now: h.clock,
        isCurrent: access.isCurrent,
        newOperationId: () => privacyOperation,
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.open(privacyRequest);
      h.loseClaimResponse = true;
      await controller.startReview();
      expect(controller.pending?.operationId, privacyOperation);
      h.now = privacyNow.add(const Duration(seconds: 30));
      h.emailVerifiedAt = h.now;
      await h.session.refresh();
      expect(h.session.authorityFence, fence);
      expect(access.isCurrent(), isTrue);
      expect(access.validUntil, contextUntil);
      expect(controller.pending?.operationId, privacyOperation);
      await controller.resolve();
      expect(h.calls('admin_claim_account_deletion_review_v1'), hasLength(1));
      expect(
        h.calls('admin_get_account_deletion_review_operation_v1'),
        hasLength(1),
      );
      expect(
        (await h.journal.store.read(privacyActor, privacySession)).pending,
        isNull,
      );
      expect(h.session.user!.assuranceLevel, 1);
      expect(h.session.user!.mfaAt, isNull);
    },
  );

  testWidgets(
    'email renewal reschedules the proof timer without extending server context',
    (tester) async {
      final h = _SupabaseCookieFixture()
        ..emailVerifiedAt = privacyNow.subtract(const Duration(minutes: 4));
      await h.start();
      await _mount(tester, h);
      expect(find.byKey(const Key('privacy-requests-table')), findsOneWidget);
      final contextCalls = h
          .calls('admin_get_account_retention_context_v1')
          .length;
      final listCalls = h
          .calls('admin_list_account_deletion_reviews_v1')
          .length;
      h.now = privacyNow.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      h.emailVerifiedAt = h.now;
      await h.session.refresh();
      await tester.pumpAndSettle();
      h.now = privacyNow.add(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 31));
      expect(find.byKey(const Key('privacy-requests-table')), findsOneWidget);
      expect(
        h.calls('admin_get_account_retention_context_v1'),
        hasLength(contextCalls),
      );
      expect(
        h.calls('admin_list_account_deletion_reviews_v1'),
        hasLength(listCalls),
      );
      h.now = privacyNow.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 3, seconds: 59));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('privacy-requests-table')), findsNothing);
      expect(find.text('Verify email'), findsOneWidget);
      expect(find.text('Verify authenticator'), findsNothing);
      h.session.clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
