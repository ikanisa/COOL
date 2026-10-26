import 'support/recorded_auth_fixture.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/admin/core/admin_privacy_review_host.dart';
import 'support/privacy_review_fixtures.dart';

// Exercises the current Cloudflare client and repository with controlled HTTP replies.
class PrivacyMountHarness {
  final journal = PrivacyJournalFixture(), requests = <http.Request>[];
  final permissions = <String>{'users.read', 'audit.read'};
  late CollectCloudflareClient client;
  late ProviderContainer container;
  bool owner = true, loseResponse = false, deny = false;
  String session = privacySession,
      state = 'not_started',
      operation = privacyOperation;
  Completer<http.Response>? delayedList;
  Completer<http.Request>? delayedListStarted;
  List<http.Request> calls(String name) =>
      requests.where((r) => r.url.path == '/v1/rpc/$name').toList();
  http.Response reply(http.Request request, Object? value, [int code = 200]) =>
      http.Response(
        jsonEncode(value),
        code,
        headers: {'content-type': 'application/json'},
        request: request,
      );
  Future<void> start() async {
    client = recordedFixtureClient(
      'https://synthetic.invalid',
      httpClient: MockClient((r) async {
        if (r.url.path == '/v1/auth/verify') {
          return reply(r, {
            'access_token':
                'e30.${base64Url.encode(utf8.encode(jsonEncode({'role': 'authenticated', 'sub': privacyActor, 'session_id': session, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
            'refresh_token': 'synthetic-refresh',
            'token_type': 'bearer',
            'user': {
              'id': privacyActor,
              'aud': 'authenticated',
              'email': 'owner@example.invalid',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-10-03T00:00:00Z',
            },
          });
        }
        if (r.url.path == '/v1/auth/logout') return reply(r, {});
        requests.add(r);
        final name = r.url.path.split('/').last;
        if (name == 'admin_current_user') {
          return reply(r, {
            'user_id': privacyActor,
            'display_name': 'Synthetic owner',
            'phone_masked': null,
            'roles': owner ? ['platform_owner'] : ['operator'],
            'permissions': permissions.toList(),
          });
        }
        if (deny) {
          return reply(r, {
            'code': '42501',
            'message': 'PRIVATE_SERVER_CANARY',
          }, 403);
        }
        // The real no-argument identity RPC legitimately posts JSON null.
        // Privacy operations below still require their actual parameter map.
        final p = jsonDecode(r.body) as Map;
        if (name == 'admin_list_account_deletion_reviews_v1') {
          if (delayedList != null) {
            delayedListStarted?.complete(r);
            return delayedList!.future;
          }
          return reply(r, privacyPageRaw(items: [privacyItem(state: state)]));
        }
        if (name == 'admin_get_account_deletion_review_v1') {
          return reply(
            r,
            privacyDetailRaw(state: state, owned: state != 'not_started'),
          );
        }
        if (name == 'admin_claim_account_deletion_review_v1') {
          final saved = await journal.store.read(privacyActor, privacySession);
          expect(p, saved.pending!.parameters);
          operation = p['p_claim_request_id'] as String;
          state = 'claim_active';
          if (loseResponse) throw TimeoutException('Synthetic lost response');
          return reply(r, privacyClaimReceipt(operation: operation));
        }
        if (name == 'admin_record_account_deletion_review_v1') {
          final saved = await journal.store.read(privacyActor, privacySession);
          expect(p, saved.pending!.parameters);
          state = 'blocked';
          return reply(
            r,
            privacyOutcomeReceipt(
              operation: p['p_outcome_request_id'] as String,
            ),
          );
        }
        if (name == 'admin_get_account_deletion_review_operation_v1') {
          final saved = (await journal.store.read(
            privacyActor,
            privacySession,
          )).pending!;
          return reply(
            r,
            privacyOperationRaw(
              saved,
              observed: state == 'claim_active',
              receipt: state == 'claim_active'
                  ? privacyClaimReceipt(operation: operation)
                  : null,
              current: state == 'claim_active',
            ),
          );
        }
        return reply(r, {
          'code': '42501',
          'message': 'Unexpected synthetic RPC',
        }, 403);
      }),
    );
    await login();
    container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(client),
        adminClockProvider.overrideWithValue(() => privacyNow),
        adminPrivacyReviewStoreProvider.overrideWithValue(journal.store),
      ],
    );
    await container.read(adminIdentityProvider.future);
  }

  Future<void> login() => installRecordedAuthFixture(
    client,
    type: CollectOtpType.email,
    token: 'synthetic',
    email: 'owner@example.invalid',
  ).then((_) {});
  Future<AdminSessionScope> loginAndAdopt(String targetSession) async {
    final before = container.read(adminAuthSessionScopeProvider);
    expect(before, isNotNull);
    final adopted = Completer<AdminSessionScope>();
    // Subscribe before the real SDK call. Its response may precede delivery
    // through Auth's asynchronous stream to the session-owned providers.
    final subscription = container.listen(adminAuthSessionScopeProvider, (
      _,
      next,
    ) {
      if (next != null &&
          next.key == (userId: privacyActor, sessionId: targetSession) &&
          next.generation > before!.generation &&
          !adopted.isCompleted) {
        adopted.complete(next);
      }
    });
    try {
      session = targetSession;
      await login();
      final scope = await adopted.future.timeout(const Duration(seconds: 5));
      expect(adminSessionKey(client.auth.currentSession), scope.key);
      final identity = await container.read(adminIdentityProvider.future);
      expect(identity?.userId, privacyActor);
      expect(container.read(adminAuthSessionScopeProvider), scope);
      return scope;
    } finally {
      subscription.close();
    }
  }

  Widget app({double scale = 1}) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: CollectTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const Scaffold(body: AdminPrivacyReviewPageHost()),
    ),
  );
  Future<void> close() async {
    container.dispose();
    await client.dispose();
  }
}

Future<void> privacySettle(WidgetTester t) async {
  for (var n = 0; n < 12; n++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 25));
  }
}

Future<void> privacyTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  // A zero-duration scroll changes the offset before render geometry updates.
  // Verify the actual settled target before sending any material action.
  await tester.pump();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
}

void main() {
  final priorHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(
    () => WidgetController.hitTestWarningShouldBeFatal = priorHitTestPolicy,
  );
  test(
    'privacy route inventory and direct navigation require actual owner plus BOTH permissions',
    () {
      expect(adminRoutePaths, contains('/admin/privacy-requests'));
      for (final roles in [
        <String>['platform_owner'],
        <String>['operator'],
      ]) {
        for (final permissions in [
          <String>[],
          <String>['users.read'],
          <String>['audit.read'],
          <String>['users.read', 'audit.read'],
        ]) {
          final identity = AdminIdentity(
            userId: privacyActor,
            displayName: 'Synthetic',
            roles: roles,
            permissions: permissions,
          );
          final allowed =
              roles.contains('platform_owner') && permissions.length == 2;
          expect(
            adminCanOpenPath(identity, '/admin/privacy-requests'),
            allowed,
          );
          expect(adminPrivacyReviewIdentityAllows(identity), allowed);
        }
      }
    },
  );
  testWidgets(
    'concrete mounted host sends pinned Authorization and only supported review/blocker actions',
    (t) async {
      final h = PrivacyMountHarness();
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app());
      await privacySettle(t);
      expect(find.text('Privacy requests'), findsOneWidget);
      expect(h.calls('admin_list_account_deletion_reviews_v1'), hasLength(1));
      expect(
        h
            .calls('admin_list_account_deletion_reviews_v1')
            .single
            .headers['authorization'],
        'Bearer ${h.client.auth.currentSession!.accessToken}',
      );
      await privacyTap(t, find.text('Open request'));
      await privacySettle(t);
      await privacyTap(t, find.text('Start review'));
      await privacySettle(t);
      expect(h.calls('admin_claim_account_deletion_review_v1'), hasLength(1));
      await privacyTap(t, find.text('Record policy blocker'));
      await privacySettle(t);
      expect(h.calls('admin_record_account_deletion_review_v1'), hasLength(1));
      expect(find.textContaining('no data was erased'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'lost response is not automatically retried and remount recovers originating operation',
    (t) async {
      final h = PrivacyMountHarness()..loseResponse = true;
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app());
      await privacySettle(t);
      await privacyTap(t, find.text('Open request'));
      await privacySettle(t);
      await privacyTap(t, find.text('Start review'));
      await privacySettle(t);
      expect(h.calls('admin_claim_account_deletion_review_v1'), hasLength(1));
      final original = (await h.journal.store.read(
        privacyActor,
        privacySession,
      )).pending!.operationId;
      await t.pumpWidget(const SizedBox.shrink());
      await privacySettle(t);
      await t.pumpWidget(h.app());
      await privacySettle(t);
      await privacyTap(t, find.text('Check original operation'));
      await privacySettle(t);
      expect(
        h.calls('admin_get_account_deletion_review_operation_v1'),
        hasLength(1),
      );
      expect(
        (jsonDecode(
              h
                  .calls('admin_get_account_deletion_review_operation_v1')
                  .single
                  .body,
            )
            as Map)['p_operation_id'],
        original,
      );
      expect(h.calls('admin_claim_account_deletion_review_v1'), hasLength(1));
      expect(
        (await h.journal.store.read(privacyActor, privacySession)).pending,
        isNull,
      );
    },
  );
  testWidgets(
    'permission loss and role loss redact the mounted route before RPC',
    (t) async {
      final h = PrivacyMountHarness();
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app());
      await privacySettle(t);
      h.permissions.remove('audit.read');
      h.container.invalidate(adminIdentityProvider);
      await t.runAsync(() => h.container.read(adminIdentityProvider.future));
      await privacySettle(t);
      expect(find.text('Privacy review access required'), findsOneWidget);
      expect(find.text('Open request'), findsNothing);
      h.permissions.add('audit.read');
      h.owner = false;
      h.container.invalidate(adminIdentityProvider);
      await t.runAsync(() => h.container.read(adminIdentityProvider.future));
      await privacySettle(t);
      expect(find.text('Privacy review access required'), findsOneWidget);
      expect(h.calls('admin_claim_account_deletion_review_v1'), isEmpty);
    },
  );
  testWidgets(
    'A to B to A session transition cannot adopt original late read or resurrect old access',
    (t) async {
      final h = PrivacyMountHarness();
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      // This case exercises real asynchronous HTTP/Auth, with no widget work.
      // Keep the held request and its completion in one real async zone.
      await t.runAsync(() async {
        final subscription = h.container.listen(
          adminPrivacyReviewAccessProvider,
          (_, _) {},
          fireImmediately: true,
        );
        try {
          final access = h.container.read(adminPrivacyReviewAccessProvider)!;
          h.delayedList = Completer<http.Response>();
          h.delayedListStarted = Completer<http.Request>();
          final request = access.api.list();
          final denied = expectLater(
            request,
            throwsA(isA<AdminSessionChanged>()),
          );
          final originalHttp = await h.delayedListStarted!.future.timeout(
            const Duration(seconds: 5),
          );
          expect(
            originalHttp.headers['authorization'],
            'Bearer ${h.client.auth.currentSession!.accessToken}',
          );
          final before = h.container.read(adminAuthSessionScopeProvider)!;
          final away = await h.loginAndAdopt(privacyClaim);
          final returned = await h.loginAndAdopt(privacySession);
          expect(away.generation, greaterThan(before.generation));
          expect(returned.generation, greaterThan(away.generation));
          h.delayedList!.complete(h.reply(originalHttp, privacyPageRaw()));
          await denied;
          expect(access.isCurrent(), isFalse);
          expect(
            h.calls('admin_list_account_deletion_reviews_v1'),
            hasLength(1),
          );
        } finally {
          subscription.close();
        }
      });
    },
  );
  testWidgets(
    'denial is unavailable and does not fabricate empty queue or expose server messages',
    (t) async {
      final h = PrivacyMountHarness()..deny = true;
      await t.runAsync(h.start);
      addTearDown(() => t.runAsync(h.close));
      await t.pumpWidget(h.app());
      await privacySettle(t);
      expect(find.textContaining('PRIVATE_SERVER_CANARY'), findsNothing);
      expect(find.textContaining('No privacy requests'), findsNothing);
      expect(
        find.textContaining('Current platform-owner access'),
        findsOneWidget,
      );
    },
  );
  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'privacy queue and detail retain labels and keyboard targets at $width with 2x text',
      (t) async {
        await t.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final h = PrivacyMountHarness();
        await t.runAsync(h.start);
        addTearDown(() => t.runAsync(h.close));
        final semantics = t.ensureSemantics();
        await t.pumpWidget(h.app(scale: 2));
        await privacySettle(t);
        await privacyTap(t, find.text('Open request'));
        await privacySettle(t);
        await t.ensureVisible(find.text('Start review'));
        await t.pump();
        expect(find.text('Start review').hitTestable(), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        expect(find.text('Record policy blocker'), findsOneWidget);
        expect(FocusManager.instance.primaryFocus?.context, isNotNull);
        expect(t.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}
