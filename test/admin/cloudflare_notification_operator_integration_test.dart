import 'dart:convert';

import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/cloudflare_admin_app.dart';
import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_notification_operator_page.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/main_admin_cloudflare.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cloudflare_core_fixtures.dart' show coreOverview;
import '../support/legacy_backend_fixture.dart';

const _supabaseOperatorEnvironment = AppEnv(
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
  supabaseUrl: 'https://operator-fixture.supabase.co',
  supabaseApiUrl: 'https://admin.example.test',
  supabaseAdminApiUrl: 'https://admin.example.test',
  supabasePublishableKey: 'sb_publishable_synthetic_operator_test_only',
);

const _path = '/admin/notification-operator';
const _actor = '20000000-0000-4000-8000-000000000001';
const _principal = '20000000-0000-4000-8000-000000000002';
const _publicSession = '20000000-0000-4000-8000-000000000003';
const _canonicalSession = '20000000-0000-4000-8000-000000000004';
const _job = '20000000-0000-4000-8000-000000000005';
const _payment = '20000000-0000-4000-8000-000000000006';
const _claim = '20000000-0000-4000-8000-000000000007';
const _recipient = '+250781234567';
const _message =
    'Collect record: contribution recorded. Provider confirmation is not asserted.';
const _marker = {
  'contract_version': 1,
  'scope': 'assisted_sms_internal_record',
  'delivery_confirmed': false,
  'provider_confirmation': false,
  'settlement_status': 'not_asserted',
};

http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: const {'content-type': 'application/json'},
);
String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

class _Workspace {
  _Workspace({
    required this.permissions,
    this.signedIn = true,
    this.assuranceLevel = 2,
    this.teamBody,
    this.useSupabase = false,
    this.emailProofAge = Duration.zero,
  }) {
    session = CloudflareAdminSession(
      MockClient((request) async {
        final path =
            useSupabase &&
                request.url.path.startsWith(
                  '/functions/v1/admin-api/api/admin/',
                )
            ? request.url.path.replaceFirst(
                '/functions/v1/admin-api/api/admin/',
                '/api/admin/',
              )
            : request.url.path;
        if (path == '/api/admin/auth/session') {
          return _json(
            signedIn
                ? {
                    'user': {
                      'id': _actor,
                      'email': 'operator@example.test',
                      'role': 'owner',
                      'sessionId': _publicSession,
                      'principalId': _principal,
                      'permissions': permissions,
                      'assuranceLevel': assuranceLevel,
                      if (assuranceLevel == 2) 'mfaAt': now.toIso8601String(),
                      if (useSupabase && assuranceLevel == 1) 'mfaAt': null,
                    },
                    'expiresAt': now
                        .add(const Duration(hours: 1))
                        .toIso8601String(),
                    if (useSupabase) 'csrfToken': 'a' * 64,
                  }
                : {'user': null},
          );
        }
        if (useSupabase && path == '/api/admin/auth/email-verification') {
          expect(request.method, 'GET');
          return _json({
            'contractVersion': 1,
            'sessionId': _publicSession,
            'emailVerifiedAt': emailProofAge == null
                ? null
                : now.subtract(emailProofAge!).toUtc().toIso8601String(),
          });
        }
        if (path == '/api/admin/core/overview') {
          return _json(coreOverview());
        }
        if (path == '/api/admin/sync') {
          return _json({
            'contract_version': 1,
            'events': [],
            'cursor': request.url.queryParameters['cursor'],
          });
        }
        if (path == '/api/admin/team' && teamBody != null) {
          if (request.method != 'GET') {
            throw StateError(
              'Role definitions must remain a read-only request.',
            );
          }
          teamReads++;
          return _json(teamBody!);
        }
        if (path != '/api/admin/notification-operator') {
          throw StateError(
            'Unexpected integration transport ${request.url.path}',
          );
        }
        final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        commands.add(body);
        return _json({'ok': true, 'result': _result(body)});
      }),
      origin: Uri.parse('https://admin.example.test/'),
      environment: useSupabase
          ? _supabaseOperatorEnvironment
          : legacyBackendFixtureEnvironment,
    );
  }
  _Workspace.supabase({
    required List<String> permissions,
    Duration? proofAge = Duration.zero,
  }) : this(
         permissions: permissions,
         assuranceLevel: 1,
         useSupabase: true,
         emailProofAge: proofAge,
       );
  final List<String> permissions;
  final bool signedIn;
  final int assuranceLevel;
  final bool useSupabase;
  final Duration? emailProofAge;
  final Map<String, dynamic>? teamBody;
  int teamReads = 0;
  final now = DateTime.fromMillisecondsSinceEpoch(
    (DateTime.now().millisecondsSinceEpoch ~/ 1000) * 1000,
    isUtc: true,
  );
  final commands = <Map<String, dynamic>>[];
  late final CloudflareAdminSession session;
  String get expiry => now.add(const Duration(seconds: 110)).toIso8601String();
  Map<String, dynamic> _result(Map<String, dynamic> body) =>
      switch (body['action']) {
        'list_pending' => {
          ..._marker,
          'items': [
            {
              'id': _job,
              'payment_id': _payment,
              'state': 'queued',
              'created_at': '2026-10-01T00:00:00.000Z',
              'fence': 0,
              'attempt_id': null,
            },
          ],
          'next_cursor': null,
        },
        'claim' => {
          ..._marker,
          'job_id': _job,
          'claim_token': _claim,
          'fence_version': 1,
          'worker_id': body['worker_id'],
          'claim_expires_at': expiry,
          'originating_session_id': _canonicalSession,
          'public_session_id': _publicSession,
        },
        'get_claimed' => {
          ..._marker,
          'job_id': _job,
          'claim_token': _claim,
          'fence_version': 1,
          'destination_e164': _recipient,
          'destination_sha256': _digest(_recipient),
          'destination_revision': 1,
          'message_body': _message,
          'body_sha256': _digest(_message),
          'payment_id': _payment,
          'template_key': 'collect.recorded_contribution.v1',
          'claim_expires_at': expiry,
        },
        'confirm' => {
          ..._marker,
          'job_id': _job,
          'claim_token': _claim,
          'fence_version': 1,
          'confirmation_id': body['confirmation_id'],
          'body_sha256': _digest(_message),
          'destination_sha256': _digest(_recipient),
          'destination_revision': 1,
          'expires_at': expiry,
          'originating_session_id': _canonicalSession,
          'public_session_id': _publicSession,
        },
        'release_claim' => {
          ..._marker,
          'job_id': _job,
          'state': 'queued',
          'fence_version': 2,
        },
        _ => throw StateError(
          'The routed workspace must not dispatch ${body['action']}',
        ),
      };
}

Future<void> _withWorkspace(
  WidgetTester tester,
  _Workspace workspace,
  Future<void> Function(ProviderContainer) exercise,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 1000);
  tester.binding.platformDispatcher.defaultRouteNameTestValue = '/admin';
  final container = ProviderContainer(
    overrides: [
      ...cloudflareAdminOverrides(),
      cloudflareAdminSessionProvider.overrideWith((_) => workspace.session),
      adminPendingAttemptStorageProvider.overrideWithValue(
        MemoryAdminPendingAttemptStorage(),
      ),
    ],
  );
  try {
    await tester.runAsync(workspace.session.refresh);
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
    workspace.session.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    container.dispose();
    tester.binding.platformDispatcher.clearDefaultRouteNameTestValue();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _button(Type type, String label) => find.widgetWithText(type, label);
String _location(ProviderContainer container) => container
    .read(cloudflareAdminRouterProvider)
    .routeInformationProvider
    .value
    .uri
    .path;

void main() {
  testWidgets(
    'Supabase AAL1 email proof opens the routed operator without a sender',
    (tester) async {
      final workspace = _Workspace.supabase(
        permissions: const [
          'overview.read',
          'assisted_sms.read',
          'assisted_sms.manage',
        ],
      );
      await _withWorkspace(tester, workspace, (container) async {
        await _tap(tester, find.byTooltip('Assisted SMS'));
        expect(_location(container), _path);
        expect(workspace.session.user!.assuranceLevel, 1);
        expect(workspace.session.user!.mfaAt, isNull);
        expect(workspace.session.user!.sessionId, _publicSession);
        expect(workspace.commands.map((r) => r['action']), ['list_pending']);
        final page = tester.widget<CloudflareAdminNotificationOperatorPage>(
          find.byType(CloudflareAdminNotificationOperatorPage),
        );
        expect(page.assistedSmsAdapter, isNull);
        await _tap(tester, _button(TextButton, 'Claim for review'));
        expect(find.text(_recipient), findsOneWidget);
        expect(find.text(_message), findsOneWidget);
        await _tap(tester, find.byType(CheckboxListTile));
        await _tap(tester, _button(FilledButton, 'Confirm exact content'));
        expect(
          tester
              .widget<FilledButton>(
                _button(FilledButton, 'Record start and send once'),
              )
              .onPressed,
          isNull,
        );
        expect(
          workspace.commands.where((r) => r['action'] == 'record_send_start'),
          isEmpty,
        );
        await _tap(tester, _button(OutlinedButton, 'Release claim'));
        expect(workspace.commands.map((r) => r['action']), [
          'list_pending',
          'claim',
          'get_claimed',
          'confirm',
          'release_claim',
          'list_pending',
        ]);
      });
    },
  );

  testWidgets(
    'Supabase missing proof keeps the routed page behind Verify email',
    (tester) async {
      final workspace = _Workspace.supabase(
        permissions: const ['overview.read', 'assisted_sms.read'],
        proofAge: null,
      );
      await _withWorkspace(tester, workspace, (container) async {
        await _tap(tester, find.byTooltip('Assisted SMS'));
        expect(_location(container), _path);
        expect(
          find.textContaining('recent email verification'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Verify email'),
          findsOneWidget,
        );
        expect(workspace.commands, isEmpty);
      });
    },
  );

  testWidgets('Supabase email proof does not grant Assisted SMS navigation', (
    tester,
  ) async {
    final workspace = _Workspace.supabase(
      permissions: const [
        'overview.read',
        'notifications.read',
        'notifications.manage',
      ],
    );
    await _withWorkspace(tester, workspace, (container) async {
      expect(find.byTooltip('Assisted SMS'), findsNothing);
      container.read(cloudflareAdminRouterProvider).go(_path);
      await tester.pumpAndSettle();
      expect(_location(container), '/admin');
      expect(
        find.byType(CloudflareAdminNotificationOperatorPage),
        findsNothing,
      );
      expect(workspace.commands, isEmpty);
    });
  });

  test(
    'configured navigation binds Assisted SMS to its exact read grant and preserves incoming receipts',
    () async {
      final workspace = _Workspace(permissions: const []);
      try {
        final config = await CloudflareAdminRepository(
          workspace.session,
        ).runtimeConfig();
        expect(config.useConfiguredNavigationPermissions, isTrue);
        final entry = config.navigationItems.singleWhere(
          (item) => item.path == _path,
        );
        expect(entry.label, 'Assisted SMS');
        expect(entry.requiredPermission, 'assisted_sms.read');
        final incoming = config.navigationItems.singleWhere(
          (item) => item.path == '/admin/sms-receipts',
        );
        expect(incoming.label, 'SMS receipts');
        expect(incoming.requiredPermission, 'sms.read');
        for (final grants in [
          <String>[],
          ['assisted_sms.manage'],
          ['notifications.read', 'notifications.manage'],
        ]) {
          final identity = AdminIdentity(
            userId: _actor,
            displayName: 'Owner',
            roles: const ['platform_owner'],
            permissions: grants,
          );
          expect(
            adminCanOpenPath(identity, _path, runtimeConfig: config),
            isFalse,
          );
        }
        const reader = AdminIdentity(
          userId: _actor,
          displayName: 'Reader',
          roles: ['staff'],
          permissions: ['assisted_sms.read'],
        );
        expect(adminCanOpenPath(reader, _path, runtimeConfig: config), isTrue);
      } finally {
        workspace.session.dispose();
      }
    },
  );

  for (final extra in [
    <String>[],
    ['assisted_sms.manage'],
    ['notifications.read', 'notifications.manage'],
  ]) {
    testWidgets(
      'router and configured nav reject missing read grant with $extra',
      (tester) async {
        final workspace = _Workspace(permissions: ['overview.read', ...extra]);
        await _withWorkspace(tester, workspace, (container) async {
          expect(find.byTooltip('Assisted SMS'), findsNothing);
          container.read(cloudflareAdminRouterProvider).go(_path);
          await tester.pumpAndSettle();
          expect(_location(container), '/admin');
          expect(
            find.byType(CloudflareAdminNotificationOperatorPage),
            findsNothing,
          );
          expect(workspace.commands, isEmpty);
        });
      },
    );
  }

  testWidgets(
    'signed-out direct entry redirects to login with a protected return destination',
    (tester) async {
      final workspace = _Workspace(
        permissions: const ['assisted_sms.read'],
        signedIn: false,
      );
      await _withWorkspace(tester, workspace, (container) async {
        final router = container.read(cloudflareAdminRouterProvider);
        router.go(_path);
        await tester.pumpAndSettle();
        expect(_location(container), '/admin/login');
        expect(
          router.routeInformationProvider.value.uri.queryParameters['returnTo'],
          _path,
        );
        expect(
          find.byType(CloudflareAdminNotificationOperatorPage),
          findsNothing,
        );
        expect(find.byTooltip('Assisted SMS'), findsNothing);
        expect(workspace.commands, isEmpty);
      });
    },
  );

  testWidgets(
    'granted read permission opens the actual page through configured navigation',
    (tester) async {
      final workspace = _Workspace(
        permissions: const ['overview.read', 'assisted_sms.read'],
      );
      await _withWorkspace(tester, workspace, (container) async {
        await _tap(tester, find.byTooltip('Assisted SMS'));
        expect(_location(container), _path);
        expect(
          find.byType(CloudflareAdminNotificationOperatorPage),
          findsOneWidget,
        );
        expect(find.textContaining('Read-only access.'), findsOneWidget);
        expect(workspace.commands.map((command) => command['action']), [
          'list_pending',
        ]);
        expect(
          tester
              .widget<TextButton>(_button(TextButton, 'Claim for review'))
              .onPressed,
          isNull,
        );
      });
    },
  );

  testWidgets(
    'a read grant and AAL1 expose verification guidance without operator transport',
    (tester) async {
      final workspace = _Workspace(
        permissions: const ['overview.read', 'assisted_sms.read'],
        assuranceLevel: 1,
      );
      await _withWorkspace(tester, workspace, (container) async {
        await _tap(tester, find.byTooltip('Assisted SMS'));
        expect(_location(container), _path);
        expect(
          find.byType(CloudflareAdminNotificationOperatorPage),
          findsOneWidget,
        );
        expect(
          find.textContaining('fresh authenticator verification'),
          findsOneWidget,
        );
        expect(workspace.commands, isEmpty);
      });
    },
  );

  testWidgets(
    'role capability definitions do not grant Assisted SMS navigation or route access',
    (tester) async {
      final workspace = _Workspace(
        permissions: const ['overview.read', 'admin_users.read'],
        teamBody: const {
          'currentEmail': 'operator@example.test',
          'canManage': false,
          'members': [],
          'permissionsByRole': {
            'owner': ['assisted_sms.read', 'assisted_sms.manage'],
            'admin': [],
            'staff': [],
          },
        },
      );
      await _withWorkspace(tester, workspace, (container) async {
        expect(find.byTooltip('Assisted SMS'), findsNothing);
        await _tap(tester, find.byTooltip('Admins and staff'));
        expect(_location(container), '/admin/admin-users');
        expect(workspace.teamReads, 1);
        expect(find.text('Role capability definitions'), findsOneWidget);
        expect(find.text('View assisted SMS jobs'), findsOneWidget);
        expect(
          find.text('Review and record assisted SMS operations'),
          findsOneWidget,
        );
        expect(find.text('Included in role'), findsNWidgets(2));
        expect(
          find.text(
            'These definitions set the role maximum. Actual account grants and current verification determine available actions.',
          ),
          findsOneWidget,
        );
        expect(workspace.session.user!.permissions, [
          'overview.read',
          'admin_users.read',
        ]);
        expect(find.byTooltip('Assisted SMS'), findsNothing);
        container.read(cloudflareAdminRouterProvider).go(_path);
        await tester.pumpAndSettle();
        expect(_location(container), '/admin');
        expect(
          find.byType(CloudflareAdminNotificationOperatorPage),
          findsNothing,
        );
        expect(find.byTooltip('Assisted SMS'), findsNothing);
        expect(workspace.commands, isEmpty);
      });
    },
  );

  testWidgets(
    'the routed managed page has no sender and cannot record a send start',
    (tester) async {
      final workspace = _Workspace(
        permissions: const [
          'overview.read',
          'assisted_sms.read',
          'assisted_sms.manage',
        ],
      );
      await _withWorkspace(tester, workspace, (container) async {
        await _tap(tester, find.byTooltip('Assisted SMS'));
        expect(_location(container), _path);
        expect(
          tester
              .widget<CloudflareAdminNotificationOperatorPage>(
                find.byType(CloudflareAdminNotificationOperatorPage),
              )
              .assistedSmsAdapter,
          isNull,
        );
        await _tap(tester, _button(TextButton, 'Claim for review'));
        expect(find.text(_recipient), findsOneWidget);
        expect(find.text(_message), findsOneWidget);
        await _tap(tester, find.byType(CheckboxListTile));
        await _tap(tester, _button(FilledButton, 'Confirm exact content'));
        expect(
          tester
              .widget<FilledButton>(
                _button(FilledButton, 'Record start and send once'),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.textContaining('Native SMS adapter is unavailable'),
          findsOneWidget,
        );
        expect(
          workspace.commands.where(
            (command) => command['action'] == 'record_send_start',
          ),
          isEmpty,
        );
        await _tap(tester, _button(OutlinedButton, 'Release claim'));
        expect(
          workspace.commands.where(
            (command) => command['action'] == 'release_claim',
          ),
          hasLength(1),
        );
      });
    },
  );
}
