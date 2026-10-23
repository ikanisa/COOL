import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'admin_action_session_test.dart' as sdk;
import 'support/admin_read_fixture.dart';

class _GroupSourceRepository extends AdminEvidenceRepository {
  const _GroupSourceRepository();
  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async => {
    ...adminDetailFixture('admin_get_collection', id),
    'active_members': 42,
  };
}

void main() {
  group('actual SDK support read gap probes', () {
    late CollectCloudflareClient client;
    late AdminRepository repository;
    late Object? body;
    late int code;
    setUp(() async {
      body = {};
      code = 200;
      client = CollectCloudflareClient(
        'http://127.0.0.1:1',
        httpClient: MockClient((r) async {
          if (r.url.path.endsWith('/verify')) {
            final values = (jsonDecode(r.body)['token'] as String).split('|');
            return sdk.response(sdk.authReceipt(values[0], values[1]));
          }
          return http.Response.bytes(
            sdk.response(body, code).bodyBytes,
            code,
            headers: {'content-type': 'application/json'},
            request: r,
          );
        }),
      );
      await sdk.session(client, 'source-gap-session');
      repository = AdminRepository(client);
    });
    tearDown(() => client.dispose());
    test('GAP-A07 SLA rejects a response for another queue', () async {
      body = {
        'queue_key': 'admin_list_collect_payees',
        'target': 'Review within one day',
        'owner': 'Collect operations',
        'escalation': 'Escalate an unresolved route',
        'updated_at': adminReadDate,
      };
      await expectLater(
        repository.queueSla('admin_list_notifications'),
        throwsFormatException,
      );
    });
    test('GAP-A08 approval read rejects incomplete access state', () async {
      body = {
        'user_id': sdk.target,
        'approved': true,
        'role_granted': false,
        'admin_access': false,
        'status': 'approved',
      };
      await expectLater(
        repository.action('admin_get_whatsapp_approval', {
          'p_user_id': sdk.target,
        }),
        throwsFormatException,
      );
    });
    test('GAP-A09 successful null runtime response rejects fallback', () async {
      body = null;
      await expectLater(repository.runtimeConfig(), throwsFormatException);
    });
    test(
      'GAP-A10 RPC names in permission failures never select compatibility',
      () async {
        body = {
          'code': '42501',
          'message': 'admin_runtime_config permission denied',
        };
        code = 403;
        await expectLater(
          repository.runtimeConfig(),
          throwsA(isA<CollectApiException>()),
        );
        body = {
          'code': '42501',
          'message': 'admin_get_queue_sla permission denied',
        };
        await expectLater(
          repository.queueSla('admin_list_notifications'),
          throwsA(isA<CollectApiException>()),
        );
      },
    );
  });

  Future<ProviderContainer> shell(
    WidgetTester tester, {
    required Future<AdminRuntimeConfig?> Function() config,
    AdminIdentity? identity,
    String location = '/admin/groups',
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(null),
        adminIdentityProvider.overrideWith(
          (_) async =>
              identity ??
              const AdminIdentity(
                userId: adminReadActor,
                displayName: 'Synthetic operator',
                roles: ['admin'],
                permissions: ['collections.read', 'overview.read'],
              ),
        ),
        adminRuntimeConfigProvider.overrideWith((_) => config()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: AdminShell(
            location: location,
            child: const Text('Protected route body'),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets(
    'GAP-A11 unresolved runtime configuration does not mount a route',
    (tester) async {
      final pending = Completer<AdminRuntimeConfig?>();
      await shell(tester, config: () => pending.future);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Loading admin configuration'), findsOneWidget);
      expect(find.text('Protected route body'), findsNothing);
      pending.complete(AdminRuntimeConfig.fromJson(adminRuntimeFixture()));
      await tester.pumpAndSettle();
      expect(find.text('Protected route body'), findsOneWidget);
    },
  );
  testWidgets(
    'GAP-A12 runtime failure is visible, redacted and explicitly retried',
    (tester) async {
      var calls = 0;
      await shell(
        tester,
        config: () async {
          if (calls++ == 0) {
            throw StateError('Network timeout private synthetic payload');
          }
          return AdminRuntimeConfig.fromJson(adminRuntimeFixture());
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('Protected route body'), findsNothing);
      expect(
        find.text('The admin service could not be reached.'),
        findsOneWidget,
      );
      expect(find.textContaining('private synthetic payload'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Protected route body'), findsOneWidget);
    },
  );
  testWidgets(
    'GAP-A13 configured weaker permission cannot grant baseline route access',
    (tester) async {
      final raw = adminRuntimeFixture();
      (raw['navigation_items'] as List).single['required_permission'] =
          'overview.read';
      await shell(
        tester,
        config: () async => AdminRuntimeConfig.fromJson(raw),
        identity: const AdminIdentity(
          userId: adminReadActor,
          displayName: 'Synthetic operator',
          roles: ['admin'],
          permissions: ['overview.read'],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Protected route body'), findsNothing);
      expect(find.text('Admin access required'), findsOneWidget);
    },
  );
  testWidgets('GAP-A14 valid empty navigation stays empty', (tester) async {
    await shell(
      tester,
      config: () async =>
          const AdminRuntimeConfig(navigationItems: [], queueSpecs: []),
    );
    await tester.pumpAndSettle();
    expect(find.text('Protected route body'), findsOneWidget);
    expect(find.byTooltip('Groups'), findsNothing);
    expect(find.text('Overview'), findsNothing);
  });
  testWidgets(
    'explicit supported legacy config retains authorized static routes',
    (tester) async {
      await shell(tester, config: () async => null);
      await tester.pumpAndSettle();
      expect(find.text('Protected route body'), findsOneWidget);
      expect(find.text('Overview'), findsWidgets);
    },
  );
  testWidgets(
    'GAP-A15 actual group source field displays its active member count',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          collectBackendClientProvider.overrideWithValue(null),
          adminRepositoryProvider.overrideWithValue(
            const _GroupSourceRepository(),
          ),
          adminIdentityProvider.overrideWith(
            (_) async => const AdminIdentity(
              userId: adminReadActor,
              displayName: 'Synthetic operator',
              roles: ['admin'],
              permissions: ['collections.read'],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: AdminDetailPage(
                title: 'Group',
                rpcName: 'admin_get_collection',
                id: adminReadTarget,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Members'), findsOneWidget);
      expect(find.text('42 members'), findsOneWidget);
      final memberField = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .singleWhere((widget) => widget.properties.label == 'Members');
      expect(memberField.properties.value, '42 members');
      expect(tester.takeException(), isNull);
    },
  );
}
