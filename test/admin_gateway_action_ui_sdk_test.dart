import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_automations_page.dart';
import 'package:collect_app/admin/core/admin_gateway_contracts.dart';
import 'package:collect_app/admin/core/admin_gateway_checkpoint.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'admin_action_session_test.dart' as auth;
import 'admin_gateway_contracts_test.dart' as keys;
import 'support/admin_gateway_fixture.dart';
import 'support/admin_gateway_checkpoint_store.dart';

final _clock = DateTime.utc(2026, 10, 1, 0, 0, 20);
const _listedDevice = '99790000-0000-4000-8000-000000000001';
const _identity = AdminIdentity(
  userId: auth.actor,
  displayName: 'Synthetic integration reviewer',
  roles: ['admin'],
  permissions: [
    'notifications.read',
    'notifications.manage',
    'system_health.read',
  ],
);
final _authority = StateProvider<Future<AdminIdentity?>>(
  (_) => Future.value(_identity),
);
final _repository = StateProvider<AdminRepositoryBase>(
  (_) => throw StateError('fixture'),
);

// Exercises the current Cloudflare client and repository with controlled HTTP replies.
class _Harness {
  late CollectCloudflareClient client;
  late AdminRepository repository;
  late ProviderContainer container;
  late AdminGatewayOwnerAction action;
  final requests = <http.Request>[];
  final entered = Completer<void>();
  Completer<void>? release;
  String outcome = 'success';
  AdminIdentity freshActor = _identity;
  DateTime now = _clock;
  http.Request? write;
  String? capturedToken;
  Future<void> start() async {
    client = CollectCloudflareClient(
      'https://synthetic.invalid',
      httpClient: MockClient(
        (request) =>
            (() async {
              if (request.url.path.endsWith('/verify')) {
                final parts = (jsonDecode(request.body)['token'] as String)
                    .split('|');
                return auth.response(auth.authReceipt(parts[0], parts[1]));
              }
              if (request.url.path.endsWith('/logout')) {
                return auth.response({});
              }
              requests.add(request);
              final name = request.url.pathSegments.last;
              if (name == 'admin_current_user') {
                return auth.response({
                  'user_id': freshActor.userId,
                  'display_name': freshActor.displayName,
                  'phone_masked': null,
                  'roles': freshActor.roles,
                  'permissions': freshActor.permissions,
                });
              }
              if (name == 'admin_list_gateway_devices_v1') {
                final raw = adminGatewayListFixture(_clock);
                final row = (raw['rows'] as List).single as Map;
                // A recent pending identity permits activation; no historical receipt
                // can be mistaken for the newly requested result in this fixture.
                row['state'] = 'pending';
                row['activated_at'] = null;
                row['last_owner_action'] = null;
                return auth.response(raw);
              }
              if (name == action.rpc) {
                write = request;
                if (!entered.isCompleted) entered.complete();
                if (release != null) await release!.future;
                if (outcome == 'lost') throw TimeoutException('PRIVATE_CANARY');
                if (outcome == 'denied' || outcome == '503') {
                  return auth.response({
                    'code': outcome == 'denied' ? '42501' : 'unavailable',
                    'message': 'PRIVATE_CANARY',
                  }, outcome == 'denied' ? 403 : 503);
                }
                final body = jsonDecode(request.body) as Map;
                return auth.response({
                  'request_id': outcome == 'wrong-request'
                      ? keys.gatewayRequest
                      : body['p_request_id'],
                  'device_id': outcome == 'wrong-device'
                      ? '99790000-0000-4000-8000-000000000099'
                      : body['p_device_id'] ?? keys.gatewayDevice,
                  'state_at_action': action.resultState.name,
                  'recorded_at': _clock.toIso8601String(),
                  'replay': false,
                  if (outcome == 'private-extra')
                    'private_context': 'PRIVATE_CANARY',
                });
              }
              throw StateError('Unexpected synthetic endpoint: $name');
            })().then(
              (response) => http.Response.bytes(
                response.bodyBytes,
                response.statusCode,
                headers: response.headers,
                request: request,
              ),
            ),
      ),
    );
    await auth.session(client, 'gateway-ui-a');
    repository = AdminRepository(client);
    container = ProviderContainer(
      overrides: [
        adminGatewayCheckpointStoreProvider.overrideWithValue(
          MemoryAdminGatewayCheckpointStore(),
        ),
        collectBackendClientProvider.overrideWithValue(client),
        _repository.overrideWith((_) => repository),
        adminRepositoryProvider.overrideWith((ref) => ref.watch(_repository)),
        adminIdentityProvider.overrideWith((ref) => ref.watch(_authority)),
        adminClockProvider.overrideWithValue(() => now),
        // Shell-only wiring is deliberately excluded from HTTP action counters.
        adminRuntimeConfigProvider.overrideWith((_) async => null),
        adminRealtimeSubscriptionProvider.overrideWith((_) {}),
        adminSmsQueueHealthProvider.overrideWith(
          (_) async =>
              throw UnsupportedError('Synthetic shell banner unavailable'),
        ),
      ],
    );
    // Resolve the actual SDK read outside WidgetTest's fake async zone. The
    // action/session probes begin only once a real authorized sample exists.
    container.listen(
      adminGatewayDevicesProvider(const AdminGatewayQuery()),
      (_, _) {},
    );
    await container.read(
      adminGatewayDevicesProvider(const AdminGatewayQuery()).future,
    );
  }

  Future<void> mount(WidgetTester tester, {bool shell = false}) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: CollectTheme.light(),
          home: shell
              ? const AdminShell(
                  location: '/admin/sms-gateway',
                  child: AdminGatewayPage(),
                )
              : const Scaffold(body: AdminGatewayPage()),
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('Identity pending'), findsOneWidget);
  }

  Future<void> review(WidgetTester tester) async {
    final label = action == AdminGatewayOwnerAction.enroll
        ? 'Enroll device'
        : action == AdminGatewayOwnerAction.activate
        ? 'Activate identity'
        : 'Revoke identity';
    final launch = action == AdminGatewayOwnerAction.enroll
        ? find.widgetWithText(FilledButton, label)
        : find.widgetWithText(OutlinedButton, label);
    await tester.ensureVisible(launch);
    await tester.tap(launch);
    await _settle(tester);
    if (action == AdminGatewayOwnerAction.enroll) {
      await tester.enterText(
        find.byKey(const Key('gateway-public-identity')),
        jsonEncode(keys.gatewayPublicIdentity()),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Review identity'));
      await _settle(tester);
    }
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Request ID'), findsOneWidget);
  }

  Future<void> submit(WidgetTester tester) async {
    capturedToken = client.auth.currentSession!.accessToken;
    await tester.tap(
      find.widgetWithText(
        FilledButton,
        action == AdminGatewayOwnerAction.enroll
            ? 'Enroll pending device'
            : action == AdminGatewayOwnerAction.activate
            ? 'Activate identity'
            : 'Revoke identity',
      ),
    );
    // Allow asynchronous Cloudflare client replies to complete outside widget fake time.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await _settle(tester);
      if (release != null && writes != 0 ||
          find
              .textContaining('Device action recorded.')
              .evaluate()
              .isNotEmpty ||
          find
              .textContaining('Device action outcome unconfirmed.')
              .evaluate()
              .isNotEmpty ||
          find.textContaining('Device change refused').evaluate().isNotEmpty) {
        break;
      }
    }
  }

  Future<void> depart(WidgetTester tester, String state) async {
    if (state == 'session' || state == 'A-B-A') {
      await tester.runAsync(() => auth.session(client, 'gateway-ui-b'));
      if (state == 'A-B-A') {
        await tester.runAsync(
          () => auth.session(client, 'gateway-ui-a', nonce: 2),
        );
      }
    } else if (state == 'repository') {
      container.read(_repository.notifier).state = AdminRepository(client);
    } else if (state == 'loading' || state == 'error') {
      final waiting = Completer<AdminIdentity?>();
      container.read(_authority.notifier).state = waiting.future;
      await _settle(tester);
      if (state == 'error') {
        final observed = container
            .read(adminIdentityProvider.future)
            .then<Object?>((value) => value, onError: (Object value) => value);
        waiting.completeError(StateError('PRIVATE_CANARY'));
        await _settle(tester);
        expect(await observed, isA<StateError>());
      }
    } else {
      container.read(_authority.notifier).state = Future.value(
        AdminIdentity(
          userId: _identity.userId,
          displayName: _identity.displayName,
          roles: state == 'role' ? ['auditor'] : _identity.roles,
          permissions: state == 'permission'
              ? _identity.permissions
                    .where((v) => v != 'notifications.manage')
                    .toList()
              : _identity.permissions,
        ),
      );
    }
    await _settle(tester);
  }

  int get writes =>
      requests.where((v) => v.url.path.endsWith('/${action.rpc}')).length;
  int get lists => requests
      .where((v) => v.url.path.endsWith('/admin_list_gateway_devices_v1'))
      .length;
  void assertRequest() {
    expect(
      writes,
      1,
      reason:
          'Actual SDK requests: ${requests.map((v) => v.url.pathSegments.last).toList()}',
    );
    expect(write!.method, 'POST');
    expect(write!.headers['Authorization'], 'Bearer $capturedToken');
    final body = jsonDecode(write!.body) as Map;
    expect(gatewayUuid(body['p_request_id']), body['p_request_id']);
    if (action == AdminGatewayOwnerAction.enroll) {
      final identity = AdminGatewayPublicIdentity.parse(
        keys.gatewayPublicIdentity(),
      );
      expect(body, {
        'p_request_id': body['p_request_id'],
        'p_installation_id': identity.installationId,
        'p_public_key_spki_base64': identity.publicKey,
        'p_key_sha256': identity.keySha256,
        'p_signing_certificate_sha256': identity.signingCertificateSha256,
      });
    } else {
      expect(body, {
        'p_request_id': body['p_request_id'],
        'p_device_id': _listedDevice,
        'p_expected_key_sha256': 'a' * 64,
        'p_expected_signing_certificate_sha256': 'b' * 64,
      });
    }
  }

  Future<void> finish(WidgetTester tester) async {
    if (release != null && !release!.isCompleted) release!.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
    expect(tester.takeException(), isNull);
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final action in AdminGatewayOwnerAction.values) {
    group(action.name, () {
      late _Harness h;
      setUp(() async {
        h = _Harness()..action = action;
        await h.start();
      });
      tearDown(() async {
        h.container.dispose();
        await h.client.dispose();
      });
      testWidgets(
        '${action.name} production dialog SDK success validates exact intent before refresh',
        (tester) async {
          await h.mount(tester);
          await h.review(tester);
          await h.submit(tester);
          h.assertRequest();
          expect(
            find.text('State at action: ${action.resultState.name}'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Device action recorded.'),
            findsOneWidget,
          );
          for (var i = 0; i < 20 && h.lists < 2; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await _settle(tester);
          }
          expect(h.lists, 2);
          await h.finish(tester);
        },
      );
      for (final state in [
        'permission',
        'role',
        'loading',
        'error',
        'repository',
        'session',
        'A-B-A',
      ]) {
        testWidgets(
          '${action.name} production dialog SDK clears $state draft without write',
          (tester) async {
            await h.mount(tester);
            await h.review(tester);
            await h.depart(tester, state);
            expect(find.byType(AlertDialog), findsNothing);
            expect(
              find.byKey(const Key('gateway-public-identity')),
              findsNothing,
            );
            expect(h.writes, 0);
            await h.finish(tester);
          },
        );
        testWidgets(
          '${action.name} production dialog SDK suppresses late ACK after $state',
          (tester) async {
            h.release = Completer<void>();
            await h.mount(tester);
            await h.review(tester);
            await h.submit(tester);
            expect(h.entered.isCompleted, isTrue);
            h.assertRequest();
            await h.depart(tester, state);
            final before = h.lists;
            h.release!.complete();
            await _settle(tester);
            expect(
              find.textContaining('Device action recorded.'),
              findsNothing,
            );
            expect(find.text('Immutable action receipt'), findsNothing);
            expect(find.text('Handset enrollment document'), findsNothing);
            expect(
              h.lists,
              before,
              reason: 'Departed ACK must not invalidate the new workspace',
            );
            expect(h.writes, 1);
            await h.finish(tester);
          },
        );
      }
      for (final outcome in [
        'denied',
        '503',
        'lost',
        'wrong-request',
        'private-extra',
        if (action != AdminGatewayOwnerAction.enroll) 'wrong-device',
      ]) {
        testWidgets(
          '${action.name} production dialog SDK $outcome redacts and preserves uncertainty',
          (tester) async {
            h.outcome = outcome;
            await h.mount(tester);
            await h.review(tester);
            await h.submit(tester);
            h.assertRequest();
            expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
            expect(
              find.textContaining('Device action recorded.'),
              findsNothing,
            );
            expect(find.text('Immutable action receipt'), findsNothing);
            expect(h.lists, 1);
            if (outcome == 'denied') {
              expect(
                find.textContaining('Device change refused'),
                findsOneWidget,
              );
            } else {
              expect(
                find.textContaining('Device action outcome unconfirmed.'),
                findsOneWidget,
              );
              expect(
                tester
                    .widget<TextField>(
                      find.byKey(const Key('gateway-request-lookup')),
                    )
                    .controller!
                    .text,
                (jsonDecode(h.write!.body) as Map)['p_request_id'],
              );
              expect(
                tester
                    .widget<FilledButton>(
                      find.widgetWithText(FilledButton, 'Enroll device'),
                    )
                    .onPressed,
                isNull,
              );
            }
            await h.finish(tester);
          },
        );
      }
      testWidgets(
        '${action.name} production dialog SDK fresh actor permission denial prevents write',
        (tester) async {
          h.freshActor = const AdminIdentity(
            userId: auth.actor,
            displayName: 'Denied current actor',
            roles: ['admin'],
            permissions: ['notifications.read', 'system_health.read'],
          );
          await h.mount(tester);
          await h.review(tester);
          await h.submit(tester);
          expect(h.writes, 0);
          expect(h.lists, 1);
          expect(find.textContaining('Device change refused'), findsOneWidget);
          await h.finish(tester);
        },
      );
    });
  }
}
