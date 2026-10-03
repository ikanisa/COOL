import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_gateway_contracts.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_runtime_assets.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_gateway_contracts_test.dart' as owner;
import 'admin_gateway_models_test.dart' as source;

const _identity = AdminIdentity(
  userId: '99790000-0000-4000-8000-000000000099',
  displayName: 'Synthetic gateway reviewer',
  roles: ['admin'],
  permissions: [
    'notifications.read',
    'notifications.manage',
    'system_health.read',
  ],
);
final _now = DateTime.parse(
  source.gatewayListFixture()['checked_at'] as String,
);

class _Sessions extends AdminSessionController {
  _Sessions() : super(null) {
    change(1);
  }
  void change(int generation) => state = (
    key: (userId: _identity.userId, sessionId: 'synthetic-$generation'),
    generation: generation,
  );
}

class _GatewayRepository extends AdminEvidenceRepository {
  _GatewayRepository({Map<String, dynamic>? response})
    : response = response ?? source.gatewayListFixture();
  Map<String, dynamic> response;
  Object? readError, writeError, lookupError;
  final firstReadStarted = Completer<void>();
  AdminRuntimeConfig? configuration;
  AdminIdentity? actor = _identity;
  Completer<Map<String, dynamic>>? readGate;
  Completer<AdminGatewayActionReceipt>? writeGate;
  final queries = <AdminGatewayQuery>[];
  final intents = <AdminGatewayOwnerIntent>[];
  final lookupIds = <String>[];
  bool unknown = false;
  @override
  Future<AdminIdentity?> currentIdentity() async => actor;
  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async => configuration;
  @override
  Future<Map<String, dynamic>> gatewayDevices({
    int limit = 20,
    DateTime? beforeEnrolledAt,
    String? beforeDeviceId,
  }) async {
    queries.add(
      AdminGatewayQuery(
        limit: limit,
        beforeEnrolledAt: beforeEnrolledAt,
        beforeDeviceId: beforeDeviceId,
      ),
    );
    if (!firstReadStarted.isCompleted) firstReadStarted.complete();
    if (readError != null) throw readError!;
    if (readGate != null) return readGate!.future;
    final candidates = (response['rows'] as List).where((raw) {
      if (beforeEnrolledAt == null) return true;
      final row = raw as Map;
      final time = DateTime.parse(
        row['enrolled_at'] as String,
      ).compareTo(beforeEnrolledAt);
      return time < 0 ||
          time == 0 &&
              (row['device_id'] as String).compareTo(beforeDeviceId!) < 0;
    }).toList();
    final page = candidates.take(limit).toList();
    return source.gatewayCopy(response)
      ..['limit'] = limit
      ..['rows'] = page
      ..['next_cursor'] = candidates.length <= limit
          ? null
          : {
              'enrolled_at': (page.last as Map)['enrolled_at'],
              'device_id': (page.last as Map)['device_id'],
            };
  }

  @override
  Future<AdminGatewayActionReceipt> gatewayOwnerAction(
    AdminGatewayOwnerIntent intent,
  ) async {
    intents.add(intent);
    if (writeGate != null) return writeGate!.future;
    if (writeError != null) throw writeError!;
    return AdminGatewayActionReceipt.parse(
      {
        'request_id': intent.requestId,
        'device_id': intent.deviceId ?? owner.gatewayDevice,
        'state_at_action': intent.action.resultState.name,
        'recorded_at': _now.toIso8601String(),
        'replay': false,
      },
      requestId: intent.requestId,
      action: intent.action,
      deviceId: intent.deviceId,
    );
  }

  @override
  Future<Map<String, dynamic>> gatewayOwnerRequest(String requestId) async {
    lookupIds.add(requestId);
    if (lookupError != null) {
      throw lookupError!;
    }
    final intent = intents.isEmpty ? null : intents.last;
    final result = source.gatewayRequestFixture()..['request_id'] = requestId;
    if (unknown) {
      return result
        ..['outcome'] = 'unknown'
        ..['action'] = null
        ..['receipt'] = null
        ..['identity'] = null;
    }
    if (intent != null) {
      final deviceId = intent.deviceId ?? owner.gatewayDevice;
      result['action'] = intent.action.name;
      result['receipt'] = {
        'device_id': deviceId,
        'request_id': requestId,
        'state_at_action': intent.action.resultState.name,
        'recorded_at': _now.toIso8601String(),
        'replay': false,
      };
      result['identity'] = {
        'device_id': deviceId,
        'installation_id':
            intent.publicIdentity?.installationId ?? owner.gatewayInstallation,
        'key_sha256': intent.keySha256,
        'signing_certificate_sha256': intent.signingCertificateSha256,
      };
    }
    return result;
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _GatewayRepository repository, {
  AdminIdentity identity = _identity,
  _Sessions? sessions,
  DateTime Function()? clock,
  double width = 1440,
  double scale = 1,
  bool dark = true,
  bool shell = false,
  GlobalKey? capture,
  int pageSize = 20,
}) async {
  tester.view.physicalSize = Size(width, shell ? 2200 : 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(null),
      adminIdentityProvider.overrideWith((ref) async => identity),
      adminRepositoryProvider.overrideWithValue(repository),
      adminClockProvider.overrideWithValue(clock ?? () => _now),
      if (sessions != null)
        adminAuthSessionScopeProvider.overrideWith((ref) => sessions),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: dark ? CollectTheme.dark() : CollectTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: capture,
            child: shell
                ? AdminShell(
                    location: '/admin/sms-gateway',
                    child: AdminGatewayPage(pageSize: pageSize),
                  )
                : AdminGatewayPage(pageSize: pageSize),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 30));
  if (capture != null) {
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(CollectRuntimeAssets.officialLogo),
        capture.currentContext!,
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _enroll(WidgetTester tester, {bool submit = true}) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Enroll device'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('gateway-public-identity')),
    jsonEncode(owner.gatewayPublicIdentity()),
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Review identity'));
  await tester.pumpAndSettle();
  expect(find.text('Request ID'), findsOneWidget);
  if (submit) {
    await tester.tap(
      find.widgetWithText(FilledButton, 'Enroll pending device'),
    );
    await tester.pumpAndSettle();
  }
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
  test('gateway route requires both canonical read capabilities', () {
    expect(adminRoutePaths, contains('/admin/sms-gateway'));
    expect(
      adminRequiredPermissionForPath('/admin/sms-gateway'),
      'notifications.read',
    );
    expect(adminCanOpenPath(_identity, '/admin/sms-gateway'), isTrue);
    for (final permissions in [
      <String>[],
      ['notifications.read'],
      ['system_health.read'],
    ]) {
      expect(
        adminCanOpenPath(
          AdminIdentity(
            userId: _identity.userId,
            displayName: 'Synthetic denied',
            roles: [],
            permissions: permissions,
          ),
          '/admin/sms-gateway',
        ),
        isFalse,
      );
    }
  });
  testWidgets(
    'active identity keeps permission network SIM pause and dispatch separate',
    (tester) async {
      final repository = _GatewayRepository();
      await _mount(tester, repository);
      for (final text in [
        'Identity active',
        'Reported denied',
        'unvalidated',
        'unknown',
        'Not selected',
        'Paused on handset',
        'Dispatch authority pending',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.text('Send SMS'), findsNothing);
      expect(find.text('Dispatch available'), findsNothing);
      expect(repository.intents, isEmpty);
      await _finish(tester);
    },
  );
  testWidgets('read-only permissions expose evidence and no device mutations', (
    tester,
  ) async {
    final repository = _GatewayRepository();
    await _mount(
      tester,
      repository,
      identity: AdminIdentity(
        userId: _identity.userId,
        displayName: 'Read only',
        roles: ['admin'],
        permissions: ['notifications.read', 'system_health.read'],
      ),
    );
    expect(find.text('Enroll device'), findsNothing);
    expect(find.text('Revoke identity'), findsNothing);
    expect(repository.queries, hasLength(1));
    await _finish(tester);
  });
  for (final missing in ['notifications.read', 'system_health.read']) {
    testWidgets('missing $missing avoids all device requests', (tester) async {
      final repository = _GatewayRepository();
      await _mount(
        tester,
        repository,
        identity: AdminIdentity(
          userId: _identity.userId,
          displayName: 'Denied',
          roles: [],
          permissions: _identity.permissions
              .where((p) => p != missing)
              .toList(),
        ),
      );
      expect(repository.queries, isEmpty);
      expect(repository.intents, isEmpty);
      await _finish(tester);
    });
  }
  for (final error in [
    const PostgrestException(message: 'PRIVATE_CANARY', code: '42501'),
    UnsupportedError('PRIVATE_CANARY'),
    const FormatException('PRIVATE_CANARY'),
  ]) {
    testWidgets('distinct read state ${error.runtimeType} stays redacted', (
      tester,
    ) async {
      final repository = _GatewayRepository()..readError = error;
      await _mount(tester, repository);
      final title = error is PostgrestException
          ? 'Gateway read denied'
          : error is UnsupportedError
          ? 'Gateway service unavailable'
          : 'Gateway read failed';
      expect(find.text(title), findsOneWidget);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enroll device'),
            )
            .onPressed,
        isNull,
      );
      await _finish(tester);
    });
  }
  testWidgets(
    'list expiry hides identity health and action controls without refetch',
    (tester) async {
      var now = _now;
      final repository = _GatewayRepository();
      await _mount(tester, repository, clock: () => now);
      now = now.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Device sample expired'), findsOneWidget);
      expect(find.text('Reported denied'), findsNothing);
      expect(find.text('Identity active'), findsNothing);
      expect(find.text('Revoke identity'), findsNothing);
      expect(repository.queries, hasLength(1));
      await _finish(tester);
    },
  );
  testWidgets(
    'fresh list with expired heartbeat hides measurements and disables activation only',
    (tester) async {
      final raw = source.gatewayListFixture();
      final later = _now.add(const Duration(seconds: 130));
      raw['checked_at'] = later.toIso8601String();
      raw['sample_valid_until'] = later
          .add(const Duration(seconds: 60))
          .toIso8601String();
      final row = source.gatewayRow(raw)
        ..['state'] = 'pending'
        ..['activated_at'] = null
        ..['last_owner_action'] = null;
      (row['health'] as Map)['freshness'] = 'stale';
      await _mount(
        tester,
        _GatewayRepository(response: raw),
        clock: () => later,
      );
      expect(find.text('Report expired'), findsOneWidget);
      expect(find.text('Reported denied'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Activate identity'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Revoke identity'),
            )
            .onPressed,
        isNotNull,
      );
      await _finish(tester);
    },
  );
  testWidgets(
    'enrollment validates and reviews one UUID then acknowledges only pending identity',
    (tester) async {
      final repository = _GatewayRepository();
      await _mount(tester, repository);
      await _enroll(tester);
      expect(repository.intents, hasLength(1));
      final intent = repository.intents.single;
      expect(intent.action, AdminGatewayOwnerAction.enroll);
      expect(intent.publicIdentity!.installationId, owner.gatewayInstallation);
      expect(find.text('State at action: pending'), findsOneWidget);
      expect(find.text('Handset enrollment document'), findsOneWidget);
      expect(repository.queries, hasLength(2));
      await _finish(tester);
    },
  );
  testWidgets(
    'revoke reviews exact identity fingerprints and prevents duplicate submission',
    (tester) async {
      final repository = _GatewayRepository()
        ..writeGate = Completer<AdminGatewayActionReceipt>();
      await _mount(tester, repository);
      await _show(tester, find.text('Revoke identity'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Revoke identity'));
      await tester.pumpAndSettle();
      expect(find.text('Request ID'), findsOneWidget);
      expect(
        find.text(
          source.gatewayRow(repository.response)['key_sha256'] as String,
        ),
        findsOneWidget,
      );
      final confirm = find.widgetWithText(FilledButton, 'Revoke identity');
      await tester.tap(confirm);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(repository.intents, hasLength(1));
      final intent = repository.intents.single;
      expect(
        intent.deviceId,
        source.gatewayRow(repository.response)['device_id'],
      );
      repository.writeGate!.complete(
        AdminGatewayActionReceipt.parse(
          {
            'device_id': intent.deviceId,
            'request_id': intent.requestId,
            'state_at_action': 'revoked',
            'recorded_at': _now.toIso8601String(),
            'replay': false,
          },
          requestId: intent.requestId,
          action: intent.action,
          deviceId: intent.deviceId,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('State at action: revoked'), findsOneWidget);
      expect(repository.intents, hasLength(1));
      await _finish(tester);
    },
  );
  testWidgets(
    'uncertain enrollment checks same request read-only until exact result is resolved',
    (tester) async {
      final repository = _GatewayRepository()
        ..writeError = TimeoutException('PRIVATE_CANARY')
        ..unknown = true;
      await _mount(tester, repository);
      await _enroll(tester);
      final requestId = repository.intents.single.requestId;
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('gateway-request-lookup')))
            .controller!
            .text,
        requestId,
      );
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      await _show(tester, find.text('Check original request'));
      await tester.tap(find.text('Check original request'));
      await tester.pumpAndSettle();
      expect(find.text('Request outcome unknown'), findsOneWidget);
      expect(repository.intents, hasLength(1));
      repository.unknown = false;
      await _show(tester, find.text('Check original request'));
      await tester.tap(find.text('Check original request'));
      await tester.pumpAndSettle();
      expect(repository.lookupIds, [requestId, requestId]);
      expect(find.text('Handset enrollment document'), findsOneWidget);
      await _show(tester, find.text('Use recorded result and refresh'));
      await tester.tap(find.text('Use recorded result and refresh'));
      await tester.pumpAndSettle();
      expect(repository.intents, hasLength(1));
      expect(repository.queries, hasLength(2));
      await _finish(tester);
    },
  );
  testWidgets(
    'fresh actor permission loss before submission prevents mutation',
    (tester) async {
      final repository = _GatewayRepository()
        ..actor = AdminIdentity(
          userId: _identity.userId,
          displayName: 'Lost manage',
          roles: ['admin'],
          permissions: ['notifications.read', 'system_health.read'],
        );
      await _mount(tester, repository);
      await _enroll(tester);
      expect(repository.intents, isEmpty);
      expect(
        find.textContaining('current authority unavailable'),
        findsOneWidget,
      );
      await _finish(tester);
    },
  );
  testWidgets(
    'session replacement dismisses a reviewed enrollment before any write',
    (tester) async {
      final repository = _GatewayRepository(), sessions = _Sessions();
      await _mount(tester, repository, sessions: sessions);
      await _enroll(tester, submit: false);
      sessions.change(2);
      await tester.pumpAndSettle();
      expect(find.text('Enroll SMS Gateway'), findsNothing);
      expect(repository.intents, isEmpty);
      await _finish(tester);
    },
  );
  test('disposed provider rejects late unvalidated device evidence', () async {
    final pending = Completer<Map<String, dynamic>>();
    final repository = _GatewayRepository()..readGate = pending;
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(null),
        adminIdentityProvider.overrideWith((ref) async => _identity),
        adminRepositoryProvider.overrideWithValue(repository),
      ],
    );
    final provider = adminGatewayDevicesProvider(const AdminGatewayQuery());
    final listener = container.listen(provider, (_, _) {});
    final future = container.read(provider.future);
    await repository.firstReadStarted.future;
    await container.pump();
    expect(repository.queries, hasLength(1));
    listener.close();
    await container.pump();
    final result = expectLater(future, throwsA(isA<AdminSessionChanged>()));
    pending.complete({'PRIVATE_CANARY': 'departed response'});
    await result;
    container.dispose();
  });

  test(
    'same owner session replacement hides pending old evidence before parsing',
    () async {
      final pending = Completer<Map<String, dynamic>>(), sessions = _Sessions();
      final repository = _GatewayRepository()..readGate = pending;
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          adminAuthSessionScopeProvider.overrideWith((ref) => sessions),
          adminIdentityProvider.overrideWith((ref) async => _identity),
          adminRepositoryProvider.overrideWithValue(repository),
        ],
      );
      final provider = adminGatewayDevicesProvider(const AdminGatewayQuery());
      final listener = container.listen(provider, (_, _) {});
      await repository.firstReadStarted.future;
      await container.pump();
      expect(repository.queries, hasLength(1));
      repository.readGate = null;
      sessions.change(2);
      await container.pump();
      pending.complete({'PRIVATE_CANARY': 'old session evidence'});
      await container.pump();
      final result = await container.read(provider.future);
      expect(result.rows, hasLength(1));
      expect(container.read(provider).hasError, isFalse);
      expect(repository.queries, hasLength(2));
      listener.close();
      container.dispose();
    },
  );

  testWidgets(
    'keyset pagination keeps order and refresh returns to newest window',
    (tester) async {
      final raw = source.gatewayListFixture();
      final template = source.gatewayRow(raw);
      raw['total'] = 3;
      raw['rows'] = [
        for (final index in [3, 2, 1])
          (() {
            final row = source.gatewayCopy(template);
            final suffix = index.toString().padLeft(12, '0');
            final id = '99790000-0000-4000-8000-$suffix';
            row['device_id'] = id;
            row['installation_id'] = '99790000-0000-4000-8001-$suffix';
            row['key_sha256'] = index.toString().padLeft(64, '0');
            ((row['last_owner_action'] as Map)['receipt'] as Map)['device_id'] =
                id;
            return row;
          })(),
      ];
      final repository = _GatewayRepository(response: raw);
      await _mount(tester, repository, pageSize: 1);
      await _show(tester, find.text('Next devices'));
      await tester.tap(find.text('Next devices'));
      await tester.pumpAndSettle();
      expect(repository.queries.last.beforeDeviceId, endsWith('000003'));
      await _show(tester, find.text('Refresh devices'));
      await tester.tap(find.text('Refresh devices'));
      await tester.pumpAndSettle();
      expect(repository.queries.last.beforeDeviceId, isNull);
      expect(repository.intents, isEmpty);
      await _finish(tester);
    },
  );

  testWidgets(
    'additional: exact configured gateway icon and empty server menu are preserved',
    (tester) async {
      final repository = _GatewayRepository()
        ..configuration = const AdminRuntimeConfig(
          navigationItems: [
            AdminNavigationItemConfig(
              label: 'SMS Gateway',
              iconKey: 'router',
              path: '/admin/sms-gateway',
              requiredPermission: 'notifications.read',
            ),
          ],
          queueSpecs: [],
        );
      await _mount(tester, repository, shell: true);
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'SMS Gateway'),
      );
      expect((tile.leading! as Icon).icon, Icons.phonelink_ring_outlined);
      expect(tile.selected, isTrue);
      await _finish(tester);
      repository.configuration = const AdminRuntimeConfig(
        navigationItems: [],
        queueSpecs: [],
      );
      await _mount(tester, repository, shell: true);
      expect(find.widgetWithText(ListTile, 'SMS Gateway'), findsNothing);
      await _finish(tester);
    },
  );

  testWidgets(
    'additional: empty current device read shows enrollment and no invented health',
    (tester) async {
      final raw = source.gatewayListFixture()
        ..['rows'] = []
        ..['total'] = 0;
      final repository = _GatewayRepository(response: raw);
      await _mount(tester, repository);
      expect(find.text('No enrolled devices'), findsOneWidget);
      expect(find.text('Recent report'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enroll device'),
            )
            .onPressed,
        isNotNull,
      );
      expect(repository.intents, isEmpty);
      await _finish(tester);
    },
  );

  testWidgets(
    'additional: request lookup failure keeps independent device observations',
    (tester) async {
      final repository = _GatewayRepository()
        ..lookupError = UnsupportedError('PRIVATE_CANARY');
      await _mount(tester, repository);
      await _show(tester, find.byKey(const Key('gateway-request-lookup')));
      await tester.enterText(
        find.byKey(const Key('gateway-request-lookup')),
        source.gatewayRequestFixture()['request_id'] as String,
      );
      await _show(tester, find.text('Check original request'));
      await tester.tap(find.text('Check original request'));
      await tester.pumpAndSettle();
      expect(find.text('Gateway service unavailable'), findsOneWidget);
      expect(find.text('Identity active'), findsOneWidget);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(repository.intents, isEmpty);
      expect(repository.queries, hasLength(1));
      await _finish(tester);
    },
  );

  testWidgets(
    'additional: heartbeat expiry inside fresh read hides individual measurements',
    (tester) async {
      final raw = source.gatewayListFixture();
      final row = source.gatewayRow(raw);
      row['enrolled_at'] = '2026-09-30T23:58:00Z';
      final health = row['health'] as Map;
      health['reported_at'] = health['ingested_at'] = '2026-09-30T23:58:30Z';
      health['observation_valid_until'] = '2026-10-01T00:00:30Z';
      var now = _now;
      final repository = _GatewayRepository(response: raw);
      await _mount(tester, repository, clock: () => now);
      expect(find.text('Reported denied'), findsOneWidget);
      now = now.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Report expired'), findsOneWidget);
      expect(find.text('Reported denied'), findsNothing);
      expect(find.text('Identity active'), findsOneWidget);
      expect(repository.queries, hasLength(1));
      await _finish(tester);
    },
  );

  testWidgets(
    'additional: identity activation is independent of permission denial and never optimistic dispatch',
    (tester) async {
      final raw = source.gatewayListFixture();
      source.gatewayRow(raw)
        ..['state'] = 'pending'
        ..['activated_at'] = null
        ..['last_owner_action'] = null;
      final repository = _GatewayRepository(response: raw);
      await _mount(tester, repository);
      await _show(tester, find.text('Activate identity'));
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Activate identity'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Activate identity'));
      await tester.pumpAndSettle();
      expect(
        repository.intents.single.action,
        AdminGatewayOwnerAction.activate,
      );
      expect(find.text('State at action: active'), findsOneWidget);
      expect(find.text('Identity pending'), findsOneWidget);
      expect(find.text('Dispatch authority pending'), findsOneWidget);
      expect(find.text('Dispatch available'), findsNothing);
      await _finish(tester);
    },
  );

  testWidgets('gateway shell denial identifies both required reads', (
    tester,
  ) async {
    final repository = _GatewayRepository();
    await _mount(
      tester,
      repository,
      shell: true,
      identity: AdminIdentity(
        userId: _identity.userId,
        displayName: 'Missing health read',
        roles: ['admin'],
        permissions: ['notifications.read'],
      ),
    );
    expect(
      find.text(
        'Permission required: notifications.read and system_health.read',
      ),
      findsOneWidget,
    );
    expect(repository.queries, isEmpty);
    await _finish(tester);
  });

  for (final dark in [true, false]) {
    testWidgets(
      '320px 2x ${dark ? 'dark' : 'light'} exposes responsive labels and enrollment form',
      (tester) async {
        final repository = _GatewayRepository();
        await _mount(tester, repository, width: 320, scale: 2, dark: dark);
        await tester.ensureVisible(find.text('Revoke identity'));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Enroll device'));
        await _enroll(tester, submit: false);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await _finish(tester);
      },
    );
    testWidgets('desktop ${dark ? 'dark' : 'light'} synthetic gateway capture', (
      tester,
    ) async {
      final capture = GlobalKey();
      await _mount(
        tester,
        _GatewayRepository(),
        dark: dark,
        shell: true,
        capture: capture,
      );
      await tester.ensureVisible(find.text('Identity and recorded action'));
      await tester.tap(find.text('Identity and recorded action'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.environment['COLLECT_CAPTURE_GATEWAY_ADMIN'] == 'true') {
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final rendered = await boundary.toImage(pixelRatio: 1);
          final data = await rendered.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(
            'docs/release/collect-codex-goal-2026-09-30/admin-gateway/gateway-${dark ? 'dark' : 'light'}-synthetic.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          rendered.dispose();
        });
      }
      await _finish(tester);
    });
  }
}
