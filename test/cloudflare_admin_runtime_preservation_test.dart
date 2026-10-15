import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/cloudflare_admin_app.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/main_admin_cloudflare.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'admin/cloudflare_core_fixtures.dart';

http.Response _json(Object value) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  200,
  headers: const {'content-type': 'application/json'},
);

class _Workspace {
  _Workspace({this.signedIn = true, this.pendingRestore}) {
    session = CloudflareAdminSession(
      MockClient((request) async {
        if (request.url.path.endsWith('/auth/session')) {
          sessionReads++;
          if (pendingRestore != null) return pendingRestore!.future;
          return _json(sessionBody());
        }
        if (request.url.path.endsWith('/auth/login')) {
          signedIn = true;
          return _json({'ok': true});
        }
        if (request.url.path.endsWith('/core/overview')) {
          return _json(coreOverview());
        }
        if (request.url.path.endsWith('/core/users')) {
          final offset = int.parse(request.url.queryParameters['offset']!);
          final limit = int.parse(request.url.queryParameters['limit']!);
          searches.add(request.url.queryParameters['search']!);
          offsets.add(offset);
          return _json({
            'rows': [
              for (var i = offset; i < 30 && i < offset + limit; i++)
                {
                  ...coreRow(CloudflareCoreArea.users),
                  'id':
                      '11111111-1111-4111-8111-${(i + 1).toString().padLeft(12, '0')}',
                  'title': '${940001 + i}',
                  'person_id':
                      '11111111-1111-4111-8111-${(i + 1).toString().padLeft(12, '0')}',
                  'collect_user_id':
                      '11111111-1111-4111-8111-${(i + 1).toString().padLeft(12, '0')}',
                  'public_id': '${940001 + i}',
                },
            ],
            'total': 30,
          });
        }
        if (request.url.path == '/api/admin/operations/groups' &&
            request.method == 'POST') {
          writes++;
          writeKey = request.headers['Idempotency-Key'];
          throw http.ClientException('Lost mutation response');
        }
        if (request.url.path.startsWith('/api/admin/operations/requests/')) {
          checkedKey = request.url.pathSegments.last;
          return _json({'status': 'pending'});
        }
        return _json({'ok': true});
      }),
      origin: Uri.parse('https://admin.example.test/'),
    );
  }

  bool signedIn;
  Duration expiry = const Duration(hours: 1);
  Completer<http.Response>? pendingRestore;
  late final CloudflareAdminSession session;
  String actor = coreId;
  String sessionId = 'owned-session';
  List<String> permissions = [
    'overview.read',
    'account.manage',
    ...CloudflareCoreArea.values.map((area) => area.permission).toSet(),
    'collections.manage',
    'collections.create',
  ];
  int sessionReads = 0, writes = 0;
  String? writeKey, checkedKey;
  final offsets = <int>[];
  final searches = <String>[];

  Map<String, dynamic> sessionBody() => signedIn
      ? {
          ...coreSession(permissions: permissions, sessionId: sessionId),
          'expiresAt': DateTime.now().add(expiry).toIso8601String(),
          'user': {
            ...(coreSession()['user'] as Map<String, dynamic>),
            'id': actor,
            'sessionId': sessionId,
            'permissions': permissions,
          },
        }
      : {'user': null, 'expiresAt': null};

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    String initialLocation = '/admin',
    bool restoreBeforeMount = true,
  }) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        initialLocation;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final container = ProviderContainer(
      overrides: [
        ...cloudflareAdminOverrides(),
        cloudflareAdminSessionProvider.overrideWith((_) => session),
      ],
    );
    addTearDown(container.dispose);
    if (restoreBeforeMount) await session.refresh();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CloudflareAdminApp(),
      ),
    );
    if (restoreBeforeMount) await tester.pumpAndSettle();
    return container;
  }

  Future<void> close(WidgetTester tester) async {
    session.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }
}

String _location(ProviderContainer container) => container
    .read(cloudflareAdminRouterProvider)
    .routeInformationProvider
    .value
    .uri
    .toString();

void main() {
  test('post-auth destination accepts local protected URIs only', () {
    const good = '/admin/users/11111111-1111-4111-8111-111111111111?tab=groups';
    expect(cloudflareAdminReturnLocation(good), good);
    for (final unsafe in [
      'https://outside.example/admin',
      '//outside.example/admin',
      '/outside',
      '/administrator',
      '/admin/login',
      '/admin/session?returnTo=/admin/users',
      '/admin/setup?token=secret',
      '/admin/forgot-password',
      '/admin/users#secret',
      '/admin/users\n',
      r'/admin\outside',
    ]) {
      expect(cloudflareAdminReturnLocation(unsafe), isNull, reason: unsafe);
    }
  });

  testWidgets('real shell poll preserves draft and repository ownership', (
    tester,
  ) async {
    final workspace = _Workspace();
    final container = await workspace.pump(
      tester,
      initialLocation: '/admin/groups/new',
    );
    expect(find.byType(AdminShell), findsOneWidget);
    final repository = container.read(adminRepositoryProvider);
    final scope = container.read(adminAuthSessionScopeProvider);
    final field = find.widgetWithText(TextFormField, 'Group name');
    await tester.enterText(field, 'Unsaved group survives the poll');
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(workspace.sessionReads, 2);
    expect(
      identical(container.read(adminRepositoryProvider), repository),
      isTrue,
    );
    expect(container.read(adminAuthSessionScopeProvider), scope);
    expect(
      tester.widget<TextFormField>(field).controller!.text,
      'Unsaved group survives the poll',
    );
    expect(_location(container), '/admin/groups/new');
    await workspace.close(tester);
  });

  testWidgets('real shell poll preserves applied search and second page', (
    tester,
  ) async {
    final workspace = _Workspace();
    final container = await workspace.pump(
      tester,
      initialLocation: '/admin/users',
    );
    final search = find.byKey(const Key('admin-queue-search-input'));
    await tester.enterText(search, '9400');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Next'),
      500,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('admin-page-scroll-view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('26–30 of 30'), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(workspace.sessionReads, 2);
    expect(tester.widget<TextField>(search).controller!.text, '9400');
    expect(find.text('26–30 of 30'), findsOneWidget);
    expect(workspace.offsets.last, 25);
    expect(workspace.searches.last, '9400');
    expect(Uri.parse(_location(container)).path, '/admin/users');
    expect(Uri.parse(_location(container)).queryParameters, {
      'search': '9400',
      'page': '2',
    });
    await workspace.close(tester);
  });

  testWidgets(
    'uncertain-write lock and original request key survive real shell poll',
    (tester) async {
      final workspace = _Workspace();
      await workspace.pump(tester, initialLocation: '/admin/groups/new');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Group name'),
        'Recoverable group',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Group slug'),
        'recoverable-group',
      );
      final reason = find.widgetWithText(
        TextFormField,
        'Reason for this change',
      );
      await tester.ensureVisible(reason);
      await tester.enterText(reason, 'Reviewed the supporting evidence');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Review change'),
        500,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('admin-page-scroll-view')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm change'));
      await tester.pumpAndSettle();
      expect(workspace.writes, 1);
      expect(workspace.writeKey, isNotNull);
      final reference = find.textContaining('Request reference:');
      expect(reference, findsOneWidget);
      final originalReference = tester
          .widget<EditableText>(reference)
          .controller
          .text;
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(reference).controller.text,
        originalReference,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Group name'),
            )
            .enabled,
        isFalse,
      );
      expect(find.text('Review change'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Check request status'),
        400,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('admin-page-scroll-view')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check request status'));
      await tester.pumpAndSettle();
      expect(workspace.checkedKey, workspace.writeKey);
      expect(workspace.writes, 1);
      await workspace.close(tester);
    },
  );

  testWidgets(
    'same session capability loss drops draft and blocks the departed action',
    (tester) async {
      final workspace = _Workspace();
      final container = await workspace.pump(
        tester,
        initialLocation: '/admin/groups/new',
      );
      final generation = container
          .read(adminAuthSessionScopeProvider)!
          .generation;
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Group name'),
        'Private departed draft',
      );
      workspace.permissions.remove('collections.create');
      await workspace.session.refresh();
      await tester.pumpAndSettle();
      expect(
        container.read(adminAuthSessionScopeProvider)!.generation,
        greaterThan(generation),
      );
      expect(_location(container), '/admin/groups');
      expect(find.widgetWithText(TextFormField, 'Group name'), findsNothing);
      expect(find.text('Private departed draft'), findsNothing);
      expect(workspace.writes, 0);
      await workspace.close(tester);
    },
  );

  testWidgets('expired authority removes the real shell and protected draft', (
    tester,
  ) async {
    final workspace = _Workspace();
    final container = await workspace.pump(
      tester,
      initialLocation: '/admin/groups/new',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Group name'),
      'Expired private draft',
    );
    workspace.expiry = const Duration(seconds: 1);
    await workspace.session.refresh();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(workspace.session.user, isNull);
    expect(find.byType(AdminShell), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Group name'), findsNothing);
    expect(Uri.parse(_location(container)).path, '/admin/login');
    await workspace.close(tester);
  });

  testWidgets(
    'revoked cookie poll removes the real shell and protected draft',
    (tester) async {
      final workspace = _Workspace();
      final container = await workspace.pump(
        tester,
        initialLocation: '/admin/groups/new',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Group name'),
        'Revoked private draft',
      );
      workspace.signedIn = false;
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(workspace.sessionReads, 2);
      expect(workspace.session.user, isNull);
      expect(find.byType(AdminShell), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Group name'), findsNothing);
      expect(Uri.parse(_location(container)).path, '/admin/login');
      await workspace.close(tester);
    },
  );

  testWidgets('cold protected URI survives asynchronous cookie restoration', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final workspace = _Workspace(pendingRestore: pending);
    final restoring = workspace.session.refresh();
    final container = await workspace.pump(
      tester,
      initialLocation: '/admin/groups/new?draft=from-reload',
      restoreBeforeMount: false,
    );
    await tester.pump();
    final checking = Uri.parse(_location(container));
    expect(checking.path, '/admin/session');
    expect(
      checking.queryParameters['returnTo'],
      '/admin/groups/new?draft=from-reload',
    );
    pending.complete(_json(workspace.sessionBody()));
    await restoring;
    await tester.pumpAndSettle();
    expect(_location(container), '/admin/groups/new?draft=from-reload');
    expect(find.widgetWithText(TextFormField, 'Group name'), findsOneWidget);
    await workspace.close(tester);
  });

  testWidgets(
    'anonymous protected URI survives login and still enforces permissions',
    (tester) async {
      final workspace = _Workspace(signedIn: false);
      final container = await workspace.pump(
        tester,
        initialLocation: '/admin/groups/new?draft=after-login',
      );
      final login = Uri.parse(_location(container));
      expect(login.path, '/admin/login');
      expect(
        login.queryParameters['returnTo'],
        '/admin/groups/new?draft=after-login',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'operator@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'local-test-password',
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(_location(container), '/admin/groups/new?draft=after-login');
      workspace.permissions.remove('collections.create');
      workspace.session.clear();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email address'),
        'operator@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'local-test-password',
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(_location(container), '/admin/groups');
      expect(find.widgetWithText(TextFormField, 'Group name'), findsNothing);
      await workspace.close(tester);
    },
  );
}
