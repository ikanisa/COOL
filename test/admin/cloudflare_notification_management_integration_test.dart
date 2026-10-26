import 'dart:convert';

import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/cloudflare_admin_app.dart';
import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_notification_management_page.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/main_admin_cloudflare.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cloudflare_core_fixtures.dart' show coreOverview;
import '../support/legacy_backend_fixture.dart';

const _path = '/admin/notification-settings';
const _actor = '30000000-0000-4000-8000-000000000001';
const _principal = '30000000-0000-4000-8000-000000000002';
const _sessionId = '30000000-0000-4000-8000-000000000003';
const _historyRequest = '30000000-0000-4000-8000-000000000004';

class _Workspace {
  _Workspace({
    required this.permissions,
    this.role = 'owner',
    this.signedIn = true,
    this.assuranceLevel = 2,
  }) {
    session = CloudflareAdminSession(
      MockClient((request) async {
        http.Response json(Object value) => http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json'},
        );
        if (request.url.path == '/api/admin/auth/session') {
          return json(
            signedIn
                ? {
                    'user': {
                      'id': _actor,
                      'email': 'info@ikanisa.com',
                      'role': role,
                      'sessionId': _sessionId,
                      'principalId': _principal,
                      'permissions': permissions,
                      'assuranceLevel': assuranceLevel,
                      if (assuranceLevel == 2) 'mfaAt': now.toIso8601String(),
                    },
                    'expiresAt': now
                        .add(const Duration(hours: 1))
                        .toIso8601String(),
                  }
                : {'user': null},
          );
        }
        if (request.url.path == '/api/admin/core/overview') {
          return json(coreOverview());
        }
        if (request.url.path == '/api/admin/sync') {
          return json({
            'contract_version': 1,
            'events': [],
            'cursor': request.url.queryParameters['cursor'],
          });
        }
        if (request.url.path.startsWith('/api/admin/notification-operator')) {
          managementMethods.add(request.method);
        }
        if (request.url.path == '/api/admin/notification-operator/operations') {
          historyReads++;
          return json({
            'ok': true,
            'result': {
              'contract_version': 1,
              'scope': 'own_receipt_sms_request_history',
              'items': [
                {
                  'request_id': _historyRequest,
                  'kind': 'access',
                  'recorded_at': now.toIso8601String(),
                  'recorded_outcome': 'decision_recorded',
                  'status_path':
                      '/api/admin/notification-operator/access/operations/$_historyRequest',
                  'recorded_state_only': true,
                  'may_send': false,
                },
              ],
              'next_cursor': null,
              'original_session_only': true,
              'recorded_state_only': true,
              'may_send': false,
              'replay_authorized': false,
              'legal_release_approved': false,
              'provider_approved': false,
              'delivery_confirmed': false,
            },
          });
        }
        if (request.url.path ==
            '/api/admin/notification-operator/access/operations/$_historyRequest') {
          accessOperationReads++;
          return json({
            'ok': true,
            'result': {
              'contract_version': 1,
              'scope': 'owner_receipt_sms_access_operation',
              'request_id': _historyRequest,
              'observed': false,
              'status': 'not_recorded',
              'may_be_in_flight': true,
              'recorded_decision': null,
              'current_access': {
                'contract_version': 1,
                'scope': 'owner_receipt_sms_access',
                'current_admin_id': _actor,
                'current_principal_id': _principal,
                'read_granted': false,
                'manage_granted': false,
                'decision_revision': 0,
                'can_operate': false,
                'permissions': ['assisted_sms.read', 'assisted_sms.manage'],
                'legal_release_approved': false,
                'provider_approved': false,
                'delivery_confirmed': false,
              },
              'recorded_state_only': true,
              'may_send': false,
              'replay_authorized': false,
              'legal_release_approved': false,
              'provider_approved': false,
              'delivery_confirmed': false,
            },
          });
        }
        if (request.url.path == '/api/admin/notification-operator/access' &&
            request.method == 'GET') {
          accessReads++;
          return json({
            'ok': true,
            'result': {
              'contract_version': 1,
              'scope': 'owner_receipt_sms_access',
              'current_admin_id': _actor,
              'current_principal_id': _principal,
              'read_granted': false,
              'manage_granted': false,
              'decision_revision': 0,
              'can_operate': false,
              'permissions': ['assisted_sms.read', 'assisted_sms.manage'],
              'legal_release_approved': false,
              'provider_approved': false,
              'delivery_confirmed': false,
            },
          });
        }
        throw StateError(
          'Unexpected transport ${request.method} ${request.url.path}',
        );
      }),
      origin: Uri.parse('https://admin.example.test'),
      environment: legacyBackendFixtureEnvironment,
    );
  }
  final List<String> permissions;
  final String role;
  final bool signedIn;
  final int assuranceLevel;
  final now = DateTime.fromMillisecondsSinceEpoch(
    DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000,
    isUtc: true,
  );
  late final CloudflareAdminSession session;
  int accessReads = 0, historyReads = 0, accessOperationReads = 0;
  final managementMethods = <String>[];
}

Future<void> _withWorkspace(
  WidgetTester tester,
  _Workspace fixture,
  Future<void> Function(ProviderContainer) exercise,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 1000);
  tester.binding.platformDispatcher.defaultRouteNameTestValue = '/admin';
  final container = ProviderContainer(
    overrides: [
      ...cloudflareAdminOverrides(),
      cloudflareAdminSessionProvider.overrideWith((_) => fixture.session),
      adminPendingAttemptStorageProvider.overrideWithValue(
        MemoryAdminPendingAttemptStorage(),
      ),
    ],
  );
  try {
    await tester.runAsync(fixture.session.refresh);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CloudflareAdminApp(),
      ),
    );
    await tester.pumpAndSettle();
    await exercise(container);
    expect(tester.takeException(), isNull);
  } finally {
    fixture.session.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    container.dispose();
    tester.binding.platformDispatcher.clearDefaultRouteNameTestValue();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

String _location(ProviderContainer container) => container
    .read(cloudflareAdminRouterProvider)
    .routeInformationProvider
    .value
    .uri
    .path;

void main() {
  test(
    'Owner controls use existing account management independently of SMS grants',
    () async {
      final fixture = _Workspace(
        permissions: ['overview.read', 'admin_users.manage'],
      );
      await fixture.session.refresh();
      final config = await CloudflareAdminRepository(
        fixture.session,
      ).runtimeConfig();
      final destination = config.navigationItems.singleWhere(
        (item) => item.path == _path,
      );
      expect(destination.requiredPermission, 'admin_users.manage');
      expect(destination.label, 'SMS controls');
      final identity = AdminIdentity(
        userId: _actor,
        displayName: 'Owner',
        roles: ['platform_owner'],
        permissions: fixture.permissions,
      );
      expect(adminCanOpenPath(identity, _path, runtimeConfig: config), isTrue);
      expect(
        adminCanOpenPath(
          identity,
          '/admin/notification-operator',
          runtimeConfig: config,
        ),
        isFalse,
      );
      expect(
        fixture.session.user!.permissions,
        isNot(contains('assisted_sms.read')),
      );
      expect(
        fixture.session.user!.permissions,
        isNot(contains('assisted_sms.manage')),
      );
      fixture.session.dispose();
    },
  );

  for (final candidate in [
    ('owner', ['overview.read']),
    ('admin', ['overview.read', 'admin_users.manage']),
    ('staff', ['overview.read', 'admin_users.manage']),
  ]) {
    testWidgets('controls deny ${candidate.$1} with ${candidate.$2}', (
      tester,
    ) async {
      final fixture = _Workspace(role: candidate.$1, permissions: candidate.$2);
      await _withWorkspace(tester, fixture, (container) async {
        expect(find.text('SMS controls'), findsNothing);
        container.read(cloudflareAdminRouterProvider).go(_path);
        await tester.pumpAndSettle();
        expect(_location(container), '/admin');
        expect(
          find.byType(CloudflareAdminNotificationManagementPage),
          findsNothing,
        );
        expect(fixture.accessReads, 0);
        expect(fixture.historyReads, 0);
        expect(fixture.accessOperationReads, 0);
      });
    });
  }

  testWidgets(
    'signed-out controls preserve their protected login return location',
    (tester) async {
      final fixture = _Workspace(permissions: [], signedIn: false);
      await _withWorkspace(tester, fixture, (container) async {
        container.read(cloudflareAdminRouterProvider).go(_path);
        await tester.pumpAndSettle();
        final uri = container
            .read(cloudflareAdminRouterProvider)
            .routeInformationProvider
            .value
            .uri;
        expect(uri.path, '/admin/login');
        expect(uri.queryParameters['returnTo'], _path);
        expect(fixture.accessReads, 0);
        expect(fixture.historyReads, 0);
        expect(fixture.accessOperationReads, 0);
      });
    },
  );

  testWidgets(
    'AAL1 Owner reaches verification guidance without management transport',
    (tester) async {
      final fixture = _Workspace(
        permissions: ['overview.read', 'admin_users.manage'],
        assuranceLevel: 1,
      );
      await _withWorkspace(tester, fixture, (container) async {
        container.read(cloudflareAdminRouterProvider).go(_path);
        await tester.pumpAndSettle();
        expect(_location(container), _path);
        expect(
          find.byType(CloudflareAdminNotificationManagementPage),
          findsOneWidget,
        );
        expect(fixture.accessReads, 0);
        expect(fixture.historyReads, 0);
        expect(fixture.accessOperationReads, 0);
      });
    },
  );

  testWidgets(
    'fresh Owner enters actual controls without inherited notification grants',
    (tester) async {
      final fixture = _Workspace(
        permissions: ['overview.read', 'admin_users.manage'],
      );
      await _withWorkspace(tester, fixture, (container) async {
        final navigation = find.text('SMS controls');
        await tester.ensureVisible(navigation);
        await tester.pumpAndSettle();
        expect(navigation.hitTestable(), findsOneWidget);
        await tester.tap(navigation);
        await tester.pumpAndSettle();
        expect(_location(container), _path);
        expect(
          find.byType(CloudflareAdminNotificationManagementPage),
          findsOneWidget,
        );
        expect(fixture.accessReads, greaterThan(0));
        expect(
          fixture.session.user!.permissions,
          isNot(contains('assisted_sms.read')),
        );
        expect(
          fixture.session.user!.permissions,
          isNot(contains('assisted_sms.manage')),
        );
      });
    },
  );
  testWidgets(
    'actual Owner route reads own history and unknown access status without assisted grants',
    (tester) async {
      final fixture = _Workspace(
        permissions: ['overview.read', 'admin_users.manage'],
      );
      await _withWorkspace(tester, fixture, (container) async {
        container.read(cloudflareAdminRouterProvider).go(_path);
        await tester.pumpAndSettle();
        final load = find.byKey(
          const Key('notification-management-history-load'),
        );
        await tester.ensureVisible(load);
        await tester.tap(load);
        await tester.pumpAndSettle();
        expect(fixture.historyReads, 1);
        expect(find.text(_historyRequest), findsWidgets);
        final read = find.byKey(
          const ValueKey('management-history-status:$_historyRequest'),
        );
        await tester.ensureVisible(read);
        await tester.tap(read);
        await tester.pumpAndSettle();
        expect(fixture.accessOperationReads, 1);
        expect(
          find.text(
            'No recorded result was observed. The request may still be in flight; this does not clear any local original UUID.',
          ),
          findsOneWidget,
        );
        expect(fixture.managementMethods, everyElement('GET'));
        expect(
          fixture.session.user!.permissions,
          isNot(contains('assisted_sms.manage')),
        );
        expect(
          fixture.session.user!.permissions,
          isNot(contains('assisted_sms.read')),
        );
        expect(find.text('Current access decision revision'), findsWidgets);
      });
    },
  );
}
