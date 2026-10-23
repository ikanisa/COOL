import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/cloudflare_admin_app.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_privacy_review_host.dart';
import 'package:collect_app/main_admin_cloudflare.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/privacy_review_fixtures.dart';
import 'cloudflare_core_fixtures.dart';
import '../support/legacy_backend_fixture.dart';

// These are shipping route cases, not a visual specification or proof that a
// provider, authenticated task or all presentation states have been accepted.
// Keep the cases independent of the router's loops so a new declaration cannot
// silently acquire coverage merely by expanding the same implementation enum.
const _shippingPaths = <String>{
  '/',
  '/admin/session',
  '/admin/login',
  '/admin/forgot-password',
  '/admin/setup',
  '/admin',
  '/admin/momo-receipts',
  '/admin/reconciliations',
  '/admin/reconciliations/:id',
  '/admin/notification-operator',
  '/admin/notification-settings',
  '/admin/sms-receipts',
  '/admin/sms-receipts/:kind/:id',
  '/admin/email',
  '/admin/member-receipts',
  '/admin/member-receipts/:id',
  '/admin/gateway',
  '/admin/gateway/receiver-grants',
  '/admin/gateway/receiver-grants/:id',
  '/admin/gateway/new',
  '/admin/gateway/:id',
  '/admin/groups',
  '/admin/groups/new',
  '/admin/groups/:id/edit',
  '/admin/groups/:id',
  '/admin/users',
  '/admin/users/new',
  '/admin/users/:id/edit',
  '/admin/users/:id',
  '/admin/members',
  '/admin/members/new',
  '/admin/members/:id/edit',
  '/admin/members/:id',
  '/admin/payees',
  '/admin/payees/new',
  '/admin/payees/:id/edit',
  '/admin/payees/:id',
  '/admin/transactions',
  '/admin/transactions/new',
  '/admin/transactions/:id',
  '/admin/ledgers',
  '/admin/ledgers/new',
  '/admin/ledgers/:id/edit',
  '/admin/ledgers/:id',
  '/admin/ledger-accounts/:id',
  '/admin/ledger-accounts/:id/edit',
  '/admin/requests',
  '/admin/admin-users',
  '/admin/privacy-requests',
  '/admin/security',
  '/admin/security/authenticator',
  '/admin/security/verify-email',
  '/admin/licenses',
};

Map<String, GoRoute> _declaredRoutes(List<RouteBase> routes) {
  final found = <String, GoRoute>{};
  void visit(List<RouteBase> children, String parent) {
    for (final child in children) {
      var path = parent;
      if (child is GoRoute) {
        path = child.path.startsWith('/')
            ? child.path
            : '${parent == '/' ? '' : parent}/${child.path}';
        expect(found.containsKey(path), isFalse, reason: 'Duplicate $path');
        found[path] = child;
      }
      visit(child.routes, path);
    }
  }

  visit(routes, '');
  return found;
}

const _routeSessionId = '33333333-3333-4333-8333-333333333333';
const _routePrincipalId = '22222222-2222-4222-8222-222222222222';
const _routeFactorId = '44444444-4444-4444-8444-444444444444';
const _routeChallengeId = '55555555-5555-4555-8555-555555555555';

class _RouteStateHarness {
  _RouteStateHarness() {
    session = CloudflareAdminSession(
      MockClient((request) async {
        expect(request.url.origin, 'https://router-state.invalid');
        requests.add(request);
        final custom = await respond?.call(request);
        if (custom != null) return custom;
        switch (request.url.path) {
          case '/api/admin/auth/session':
            return reply(signedIn ? sessionBody() : {'user': null});
          case '/api/admin/auth/login':
            signedIn = true;
            return reply({'ok': true});
          case '/api/admin/auth/otp':
            expect(jsonDecode(request.body), {
              'email': 'operator@example.test',
            });
            return reply({
              'accepted': true,
              'challenge_id': _routeChallengeId,
              'expires_in': 300,
              'retry_after': 60,
              'emailStatus': 'accepted',
            }, 202);
          case '/api/admin/auth/verify':
            expect(jsonDecode(request.body), {
              'email': 'operator@example.test',
              'challenge_id': _routeChallengeId,
              'code': '123456',
            });
            signedIn = true;
            return reply(sessionBody());
          case '/api/admin/sync':
            return reply({
              'contract_version': 1,
              'events': [],
              'cursor': request.url.queryParameters['cursor'],
            });
          case '/api/admin/core/overview':
            return reply(coreOverview());
          case '/api/admin/core/users':
          case '/api/admin/core/groups':
            return reply({'rows': [], 'total': 0});
          case '/api/admin/auth/user':
            return reply({
              'id': _routePrincipalId,
              'factors': [
                {
                  'id': _routeFactorId,
                  'factor_type': 'totp',
                  'status': 'verified',
                  'friendly_name': 'Controlled authenticator',
                },
              ],
            });
          case '/api/admin/auth/mfa/challenge':
            expect(jsonDecode(request.body), {'factor_id': _routeFactorId});
            return reply({
              'id': _routeChallengeId,
              'challenge_id': _routeChallengeId,
              'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 300,
            });
          case '/api/admin/auth/mfa/verify':
            expect(jsonDecode(request.body), {
              'factor_id': _routeFactorId,
              'challenge_id': _routeChallengeId,
              'code': '123456',
            });
            assurance = 2;
            return reply({'ok': true});
          case '/api/admin/privacy/admin_get_account_retention_context_v1':
            return reply({
              'contract_version': 1,
              'scope': 'account_retention_inspection_context',
              'source_id': List.filled(64, '1').join(),
              'checked_at': now.toIso8601String(),
              'valid_until': now
                  .add(const Duration(minutes: 5))
                  .toIso8601String(),
              'approval_granted': false,
              'erasure_completed': false,
            });
          case '/api/admin/privacy/admin_list_account_deletion_reviews_v1':
            return reply(privacyPageRaw(checked: now));
          default:
            throw StateError(
              'Unexpected controlled route request: ${request.url.path}',
            );
        }
      }),
      origin: Uri.parse('https://router-state.invalid/'),
      environment: legacyBackendFixtureEnvironment,
    );
    container = ProviderContainer(
      overrides: [
        ...cloudflareAdminOverrides(),
        cloudflareAdminSessionProvider.overrideWith((_) => session),
        cloudflareAdminPrivacyStoreProvider.overrideWithValue(null),
        cloudflareAdminPrivacyClockProvider.overrideWithValue(() => now),
      ],
    );
  }

  late final CloudflareAdminSession session;
  late final ProviderContainer container;
  final requests = <http.Request>[];
  Future<http.Response?> Function(http.Request)? respond;
  bool signedIn = true;
  String role = 'staff';
  int assurance = 1;
  DateTime now = DateTime.fromMillisecondsSinceEpoch(
    DateTime.now().millisecondsSinceEpoch,
    isUtc: true,
  );
  List<String> permissions = ['overview.read'];

  GoRouter get router => container.read(cloudflareAdminRouterProvider);
  String diagnostic(WidgetTester tester) => jsonEncode({
    'router': router.routeInformationProvider.value.uri.toString(),
    'session_error': container
        .read(cloudflareAdminSessionProvider)
        .error
        ?.toString(),
    'session': session.user == null
        ? 'absent'
        : {
            'role': session.user!.role.name,
            'permissions': session.user!.permissions,
            'aal': session.user!.assuranceLevel,
          },
    'requests': requests.map((r) => r.url.path).toList(),
    'visible_text': tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .toList(),
  });
  List<http.Request> calls(String path) =>
      requests.where((request) => request.url.path == path).toList();
  Map<String, dynamic> sessionBody() {
    final body = coreSession(
      permissions: permissions,
      sessionId: _routeSessionId,
    );
    body['user'] = <String, dynamic>{
      ...Map<String, dynamic>.from(body['user'] as Map),
      'role': role,
      'principalId': _routePrincipalId,
      'assuranceLevel': assurance,
      'mfaAt': assurance == 2 ? now.toIso8601String() : null,
    };
    return body;
  }

  http.Response reply(Object value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: const {'content-type': 'application/json'},
  );

  Future<void> mount(WidgetTester tester, String location) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    router.go(location);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CloudflareAdminApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    session.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    container.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late GoRouter router;
  var transportCalls = 0;

  setUp(() {
    transportCalls = 0;
    final session = CloudflareAdminSession(
      MockClient((_) async {
        transportCalls++;
        throw StateError('Declaration inventory must not call a service');
      }),
      origin: Uri.parse('https://inventory.invalid/'),
      environment: legacyBackendFixtureEnvironment,
    );
    container = ProviderContainer(
      overrides: [cloudflareAdminSessionProvider.overrideWith((_) => session)],
    );
    router = container.read(cloudflareAdminRouterProvider);
  });

  tearDown(() {
    container.dispose();
    expect(transportCalls, 0);
  });

  test('shipping inventory covers every expanded Cloudflare route', () {
    final actual = _declaredRoutes(router.configuration.routes);
    expect(actual.keys.toSet(), _shippingPaths);
    expect(actual.length, 53);
    final paths = actual.keys.toList()..sort();
    if (Platform.environment['COLLECT_EXPORT_CLOUDFLARE_ROUTES'] == '1') {
      // The controller retains this generated result beside the exact source
      // hashes. It is declaration evidence only; missing state reviews stay open.
      // ignore: avoid_print
      print(
        'COLLECT_CLOUDFLARE_ROUTES=${jsonEncode({'schema_version': 1, 'router': 'cloudflareAdminRouterProvider', 'paths': paths, 'route_count': paths.length, 'service_calls': transportCalls, 'scope': 'Expanded shipping declarations, not visual or hosted acceptance', 'all_supported_states_reviewed': false})}',
      );
    }
  });

  test('every inventory case resolves to its intended declared route', () {
    final actual = _declaredRoutes(router.configuration.routes);
    for (final entry in actual.entries) {
      final sample = entry.key
          .replaceAll(':kind', 'gateway')
          .replaceAll(':id', '00000000-0000-0000-0000-000000000001');
      final matches = router.configuration.findMatch(Uri.parse(sample));
      expect(matches.error, isNull, reason: sample);
      expect(matches.last.route, same(entry.value), reason: sample);
    }
  });

  test('static create and receiver routes precede dynamic detail matches', () {
    final actual = _declaredRoutes(router.configuration.routes);
    for (final path in [
      '/admin/groups/new',
      '/admin/users/new',
      '/admin/members/new',
      '/admin/payees/new',
      '/admin/transactions/new',
      '/admin/ledgers/new',
      '/admin/gateway/new',
      '/admin/gateway/receiver-grants',
    ]) {
      final matches = router.configuration.findMatch(Uri.parse(path));
      expect(matches.error, isNull, reason: path);
      expect(matches.last.route, same(actual[path]), reason: path);
      expect(matches.pathParameters, isEmpty, reason: path);
    }
    expect(
      router.configuration
          .findMatch(Uri.parse('/admin/__inventory_unregistered_route'))
          .error,
      isNotNull,
    );
  });

  testWidgets(
    'loading deep link fails closed and retry restores its exact route',
    (tester) async {
      final h = _RouteStateHarness()
        ..permissions = ['overview.read', 'collections.read'];
      h.respond = (request) async =>
          request.url.path.endsWith('/auth/session') &&
              h.calls('/api/admin/auth/session').length == 1
          ? h.reply({'error': 'controlled_unavailable'}, 503)
          : request.url.path == '/api/admin/core/groups'
          ? h.reply({
              'rows': [coreRow(CloudflareCoreArea.groups)],
              'total': 26,
            })
          : null;
      const destination =
          '/admin/groups?search=held%20group&page=2&sort=created_at_asc';
      try {
        await h.mount(tester, destination);
        expect(
          h.router.routeInformationProvider.value.uri.path,
          '/admin/session',
        );
        expect(
          h
              .router
              .routeInformationProvider
              .value
              .uri
              .queryParameters['returnTo'],
          destination,
        );
        expect(
          find.bySemanticsLabel('Checking account access'),
          findsOneWidget,
          reason: h.diagnostic(tester),
        );
        expect(h.calls('/api/admin/core/groups'), isEmpty);
        await h.session.refresh();
        await tester.pumpAndSettle();
        expect(
          find.text('Account access could not be checked.'),
          findsOneWidget,
        );
        expect(h.calls('/api/admin/core/groups'), isEmpty);
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(
          h.router.routeInformationProvider.value.uri.toString(),
          destination,
        );
        expect(find.text('Example record'), findsOneWidget);
        expect(h.calls('/api/admin/auth/session'), hasLength(2));
        final groupRequests = h.calls('/api/admin/core/groups');
        expect(groupRequests, isNotEmpty);
        for (final request in groupRequests) {
          expect(request.method, 'GET');
          final query = request.url.queryParameters;
          expect(query['search'], 'held group');
          expect(query['offset'], '25');
          expect(query['sort'], 'created_at_asc');
        }
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'signed-out protected link signs in through actual form then denies missing capability',
    (tester) async {
      final h = _RouteStateHarness()..signedIn = false;
      const destination = '/admin/privacy-requests';
      try {
        await h.session.refresh();
        await h.mount(tester, destination);
        await tester.pumpAndSettle();
        expect(
          h.router.routeInformationProvider.value.uri.path,
          '/admin/login',
        );
        expect(
          h
              .router
              .routeInformationProvider
              .value
              .uri
              .queryParameters['returnTo'],
          destination,
        );
        expect(
          h.requests.where((r) => r.url.path.startsWith('/api/admin/privacy/')),
          isEmpty,
        );
        await tester.enterText(
          find.byKey(const Key('admin-account-email')),
          'operator@example.test',
        );
        await tester.tap(find.text('Send sign-in code'));
        await tester.pumpAndSettle();
        expect(h.signedIn, isFalse);
        await tester.enterText(
          find.byKey(const Key('admin-account-email-code')),
          '123456',
        );
        await tester.tap(find.text('Verify and sign in'));
        await tester.pumpAndSettle();
        expect(h.calls('/api/admin/auth/otp'), hasLength(1));
        expect(h.calls('/api/admin/auth/verify'), hasLength(1));
        expect(h.calls('/api/admin/auth/login'), isEmpty);
        expect(
          h.router.routeInformationProvider.value.uri.path,
          '/admin',
          reason: h.diagnostic(tester),
        );
        expect(
          find.text('Your workspace'),
          findsOneWidget,
          reason: h.diagnostic(tester),
        );
        expect(
          h.requests.where((r) => r.url.path.startsWith('/api/admin/privacy/')),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'current capability revocation evicts an open route and role label grants no access',
    (tester) async {
      final h = _RouteStateHarness()
        ..role = 'owner'
        ..permissions = ['overview.read', 'users.read'];
      try {
        await h.session.refresh();
        await h.mount(tester, '/admin/users');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('cloudflare-core-empty-users')),
          findsOneWidget,
          reason: h.diagnostic(tester),
        );
        expect(h.calls('/api/admin/core/users'), hasLength(1));
        h.permissions = ['overview.read'];
        await h.session.refresh();
        await tester.pumpAndSettle();
        expect(h.session.user!.sessionId, _routeSessionId);
        expect(h.router.routeInformationProvider.value.uri.path, '/admin');
        expect(
          find.byKey(const ValueKey('cloudflare-core-empty-users')),
          findsNothing,
        );
        h.router.go('/admin/users');
        await tester.pumpAndSettle();
        expect(h.router.routeInformationProvider.value.uri.path, '/admin');
        expect(h.calls('/api/admin/core/users'), hasLength(1));
        h.role = 'staff';
        h.permissions = ['overview.read', 'users.read'];
        await h.session.refresh();
        h.router.go('/admin/users');
        await tester.pumpAndSettle();
        expect(
          h.router.routeInformationProvider.value.uri.path,
          '/admin/users',
        );
        expect(
          find.byKey(const ValueKey('cloudflare-core-empty-users')),
          findsOneWidget,
          reason: h.diagnostic(tester),
        );
        expect(h.calls('/api/admin/core/users'), hasLength(2));
        h.router.go('/admin/users/new');
        await tester.pumpAndSettle();
        expect(
          h.router.routeInformationProvider.value.uri.path,
          '/admin/users',
        );
        expect(find.text('Review change'), findsNothing);
        expect(
          h.requests.where(
            (r) => r.url.path.startsWith('/api/admin/operations/users'),
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
  );

  testWidgets(
    'privacy route requires server-readback AAL2 and removes queue on assurance loss',
    (tester) async {
      final h = _RouteStateHarness()
        ..permissions = ['overview.read', 'account.manage', 'privacy.review'];
      try {
        await h.session.refresh();
        await h.mount(tester, '/admin/privacy-requests');
        await tester.pumpAndSettle();
        expect(
          find.text('Fresh privacy review access required'),
          findsOneWidget,
          reason: h.diagnostic(tester),
        );
        expect(
          h.requests.where((r) => r.url.path.startsWith('/api/admin/privacy/')),
          isEmpty,
        );
        await tester.tap(find.text('Verify authenticator'));
        await tester.pumpAndSettle();
        expect(
          h.router.routeInformationProvider.value.uri.path,
          '/admin/security/authenticator',
        );
        await tester.enterText(
          find.byKey(const ValueKey('cloudflare_admin_mfa_code')),
          '123456',
        );
        await tester.tap(
          find.byKey(const ValueKey('cloudflare_admin_mfa_verify')),
        );
        await tester.pumpAndSettle();
        expect(h.calls('/api/admin/auth/mfa/verify'), hasLength(1));
        expect(h.calls('/api/admin/auth/session'), hasLength(2));
        expect(h.session.user!.assuranceLevel, 2);
        expect(
          find.text('Two-step verification is complete for this session.'),
          findsOneWidget,
        );
        h.router.go('/admin/privacy-requests');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('privacy-requests-table')),
          findsOneWidget,
          reason: h.diagnostic(tester),
        );
        expect(
          h.calls('/api/admin/privacy/admin_list_account_deletion_reviews_v1'),
          hasLength(1),
        );
        h.assurance = 1;
        await h.session.refresh();
        await tester.pumpAndSettle();
        expect(
          h.router.routeInformationProvider.value.uri.path,
          '/admin/privacy-requests',
        );
        expect(
          find.text('Fresh privacy review access required'),
          findsOneWidget,
          reason: h.diagnostic(tester),
        );
        expect(find.byKey(const Key('privacy-requests-table')), findsNothing);
        expect(
          h.calls('/api/admin/privacy/admin_list_account_deletion_reviews_v1'),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await h.close(tester);
      }
    },
  );
}
