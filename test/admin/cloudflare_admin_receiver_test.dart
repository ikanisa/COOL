import 'dart:convert';

import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/admin/core/cloudflare_admin_receiver_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_receiver_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crypto/crypto.dart';

const actor = '00000000-0000-4000-8000-000000000001',
    grantId = '00000000-0000-4000-8000-000000000002',
    deviceId = '00000000-0000-4000-8000-000000000003',
    payeeId = '00000000-0000-4000-8000-000000000004',
    key = '00000000-0000-4000-8000-000000000005',
    operationId = '00000000-0000-4000-8000-000000000006';
Map<String, dynamic> grant({bool revoked = false}) => {
  'id': grantId,
  'device_id': deviceId,
  'device_label': 'Receiver handset',
  'installation_id': deviceId,
  'key_sha256': 'a' * 64,
  'payee_id': payeeId,
  'payee_label': 'Recorded payee',
  'payee_network': 'mtn_momo',
  'payee_momo_number_or_code': '008000',
  'status': revoked ? 'revoked' : 'active',
  'version': revoked ? 2 : 1,
  'created_by_admin_id': actor,
  'created_at': '2026-10-05T08:00:00.000Z',
  'revoked_by_admin_id': revoked ? actor : null,
  'revoked_at': revoked ? '2026-10-05T09:00:00.000Z' : null,
  'capture_authority': !revoked,
  'send_authority': false,
  'financial_authority': false,
};
Map<String, dynamic> receipt({int version = 2}) => {
  'request_id': operationId,
  'resource_type': 'receiver_capture_grants',
  'resource_id': grantId,
  'version': version,
  'status': 'succeeded',
};
http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class Fixture {
  Fixture({this.role = 'owner', this.handler}) {
    session = CloudflareAdminSession(
      MockClient((r) async {
        if (r.url.path == '/api/admin/auth/session') {
          return response({
            'user': {
              'id': actor,
              'email': 'receiver@example.test',
              'role': role,
              'sessionId': 'same-tab-session',
              'permissions': [
                'gateway.read',
                'gateway.manage',
                'receivers.read',
              ],
            },
            'expiresAt': DateTime.now()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          });
        }
        requests.add(r);
        return handler?.call(r) ??
            response({
              'rows': [grant()],
              'total': 1,
              'limit': 25,
              'offset': 0,
            });
      }),
      origin: Uri.parse('https://admin.example.test/'),
    );
  }
  String role;
  final Future<http.Response> Function(http.Request)? handler;
  late CloudflareAdminSession session;
  final requests = <http.Request>[];
  Future<CloudflareAdminReceiverApi> api() async {
    await session.refresh();
    return CloudflareAdminReceiverApi(session);
  }
}

Future<ProviderContainer> mount(
  WidgetTester tester,
  Fixture f,
  Widget child,
  MemoryAdminPendingAttemptStorage storage,
) async {
  await tester.runAsync(f.session.refresh);
  final c = ProviderContainer(
    overrides: [
      cloudflareAdminSessionProvider.overrideWith((_) => f.session),
      adminRepositoryProvider.overrideWithValue(
        CloudflareAdminRepository(f.session),
      ),
      adminPendingAttemptStorageProvider.overrideWithValue(storage),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: child is CloudflareReceiverGrantForm
              ? SingleChildScrollView(child: child)
              : child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  for (final variant in [
    'unchanged',
    'changed version',
    'null name',
    'empty name',
    'wrong name type',
    'null route',
    'labelled route',
    'wrong route type',
  ]) {
    testWidgets(
      'new-grant recovery verifies original review context: $variant',
      (tester) async {
        final storage = MemoryAdminPendingAttemptStorage();
        final first = Fixture();
        final c = await mount(
          tester,
          first,
          CloudflareReceiverGrantForm(onSaved: () {}),
          storage,
        );
        const intent = {
          'device_id': deviceId,
          'expected_device_version': 2,
          'payee_id': payeeId,
          'expected_payee_version': 3,
          'reason': 'Checked recorded capture identity',
        };
        c
            .read(adminPendingAttemptStoreProvider)
            .retain(
              family: 'receiver-capture-grant',
              resourceId: 'new',
              requestKey: key,
              permission: 'gateway.manage',
              intent: intent,
              schema: const AdminPendingAttemptSchema(
                fields: {
                  'device_id',
                  'expected_device_version',
                  'payee_id',
                  'expected_payee_version',
                  'reason',
                },
              ),
            );
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        final keyBytes = [
          0x30,
          0x59,
          0x30,
          0x13,
          0x06,
          0x07,
          0x2a,
          0x86,
          0x48,
          0xce,
          0x3d,
          0x02,
          0x01,
          0x06,
          0x08,
          0x2a,
          0x86,
          0x48,
          0xce,
          0x3d,
          0x03,
          0x01,
          0x07,
          0x03,
          0x42,
          0x00,
          0x04,
          ...List.filled(64, 1),
        ];
        final fingerprint = sha256.convert(keyBytes).toString();
        var writes = 0;
        final next = Fixture(
          handler: (r) async {
            if (r.method == 'POST') {
              writes++;
              expect(r.headers['Idempotency-Key'], key);
              expect(jsonDecode(r.body), intent);
              return response(receipt(version: 1));
            }
            if (r.url.path.contains('receiver-requests')) {
              expect(r.url.path, '/api/admin/gateway/receiver-requests/$key');
              return response({'found': false});
            }
            if (r.url.path == '/api/admin/gateway/devices/$deviceId') {
              return response({
                'resource_type': 'gateway_devices',
                'resource': {
                  'id': deviceId,
                  'label': 'Original receiver handset',
                  'app_id': 'com.collect.gateway',
                  'installation_id': deviceId,
                  'key_sha256': fingerprint,
                  'signing_certificate_sha256': 'b' * 64,
                  'state': 'active',
                  'version': variant == 'changed version' ? 3 : 2,
                  'created_at': '2026-10-05T08:00:00.000Z',
                  'activated_at': '2026-10-05T09:00:00.000Z',
                  'revoked_at': null,
                  'last_heartbeat_at': null,
                  'carrier_proof': false,
                  'send_authority': false,
                  'public_key_spki_base64': base64Encode(keyBytes),
                },
                'current_actor_id': actor,
                'can_manage': true,
                'related_truncated': false,
                'related': {'heartbeats': []},
                'enrollment': {
                  'contract_version': 1,
                  'device_id': deviceId,
                  'installation_id': deviceId,
                  'key_sha256': fingerprint,
                  'signing_certificate_sha256': 'b' * 64,
                },
              });
            }
            expect(r.url.path, '/api/admin/operations/payees/$payeeId');
            return response({
              'resource_type': 'payees',
              'current_actor_id': actor,
              'can_manage': true,
              'related_truncated': false,
              'related': {},
              'resource': {
                'id': payeeId,
                'version': 3,
                'status': 'active',
                'label': switch (variant) {
                  'null name' => null,
                  'empty name' => '',
                  'wrong name type' => 8000,
                  _ => 'Original recorded payee',
                },
                'momo_number_or_code': switch (variant) {
                  'null route' => null,
                  'labelled route' => 'MTN MoMo 8000',
                  'wrong route type' => ['008000'],
                  _ => '008000',
                },
              },
            });
          },
        );
        final restored = await mount(
          tester,
          next,
          CloudflareReceiverGrantForm(onSaved: () {}),
          storage,
        );
        expect(writes, 0);
        expect(find.text('Review identical retry'), findsNothing);
        await tester.tap(find.text('Check original receipt'));
        await tester.pumpAndSettle();
        expect(writes, 0);
        if (variant != 'unchanged') {
          expect(find.text('Review identical retry'), findsNothing);
          expect(find.textContaining('request remains locked'), findsOneWidget);
          expect(storage.values, isNotEmpty);
        } else {
          await tester.tap(find.text('Review identical retry'));
          await tester.pumpAndSettle();
          expect(find.text('Original receiver handset'), findsOneWidget);
          expect(find.text('Original recorded payee'), findsOneWidget);
          expect(find.text('008000'), findsOneWidget);
          expect(writes, 0);
          await tester.tap(find.text('Confirm identical retry'));
          await tester.pumpAndSettle();
          expect(writes, 1);
          expect(storage.values, isEmpty);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        restored.dispose();
      },
    );
  }
  test(
    'capture grant parser denies false authority and malformed provenance',
    () {
      expect(ReceiverCaptureGrant.parse(grant()).active, isTrue);
      expect(ReceiverCaptureGrant.parse(grant(revoked: true)).active, isFalse);
      for (final change in [
        {'send_authority': true},
        {'financial_authority': true},
        {'capture_authority': false},
        {'created_at': '2026-02-30T00:00:00.000Z'},
        {'payee_momo_number_or_code': 'MTN MoMo 8000'},
        {'version': 2},
        {'unexpected': 'raw message'},
      ]) {
        expect(
          () => ReceiverCaptureGrant.parse({...grant(), ...change}),
          throwsFormatException,
        );
      }
    },
  );
  test('Staff cannot mutate even with an accidental manage grant', () async {
    final f = Fixture(role: 'staff');
    final api = await f.api();
    expect(api.canManage, isFalse);
    await expectLater(
      api.submit(
        key: key,
        body: {'expected_version': 1, 'reason': 'Recorded review reason'},
        revokeId: grantId,
      ),
      throwsA(isA<Exception>()),
    );
    expect(f.requests, isEmpty);
    f.session.dispose();
  });
  test(
    'server operation ID is distinct from original idempotency key',
    () async {
      final f = Fixture(
        handler: (r) async {
          if (r.method == 'POST') {
            expect(r.headers['Idempotency-Key'], key);
            return response(receipt());
          }
          expect(r.url.path, '/api/admin/gateway/receiver-requests/$key');
          return response({'found': true, 'receipt': receipt()});
        },
      );
      final api = await f.api();
      final saved = await api.submit(
        key: key,
        body: {'expected_version': 1, 'reason': 'Recorded review reason'},
        revokeId: grantId,
      );
      expect(saved.requestId, operationId);
      expect(
        (await api.lookup(key, revokeId: grantId))!.requestId,
        operationId,
      );
      f.session.dispose();
    },
  );
  test(
    'complete capture paging validates windows and source timestamp precision',
    () async {
      final capture = {
        'id': key,
        'request_id': key,
        'client_sms_id': key,
        'ingress_id': key,
        'payload_sha256': 'b' * 64,
        'issued_at': '2026-10-05T08:00:00Z',
        'source_received_at': '2026-10-05T08:00:00.000Z',
        'accepted_at': '2026-10-05T08:00:02.000Z',
        'metadata_accepted': true,
        'provider_confirmation': false,
        'send_authority': false,
        'financial_authority': false,
      };
      final f = Fixture(
        handler: (r) async => response({
          'resource_type': 'receiver_capture_grants',
          'resource': grant(),
          'current_actor_id': actor,
          'can_manage': true,
          'related': {
            'captures': [capture],
          },
          'related_total': 226,
          'related_limit': 25,
          'related_offset': 225,
        }),
      );
      final api = await f.api();
      final p = await api.detail(grantId, offset: 225);
      expect(p.total, 226);
      expect(p.captures.single['issued_at'], '2026-10-05T08:00:00Z');
      f.session.dispose();
    },
  );
  testWidgets('Staff sees dedicated columns without grant actions', (
    tester,
  ) async {
    final f = Fixture(role: 'staff');
    final c = await mount(
      tester,
      f,
      const CloudflareReceiverGrantListPage(),
      MemoryAdminPendingAttemptStorage(),
    );
    expect(find.byType(AdminDataTable), findsOneWidget);
    expect(find.text('Payee MoMo'), findsOneWidget);
    expect(find.text('Review capture grant'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
  testWidgets(
    'hard reload restores original key, requires lookup and explicit identical review',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage();
      String? original;
      var writes = 0;
      final f = Fixture(
        handler: (r) async {
          writes++;
          original = r.headers['Idempotency-Key'];
          return response({
            'error': 'receiver_outcome_unknown',
            'message': 'Unconfirmed',
          }, 503);
        },
      );
      final c = await mount(
        tester,
        f,
        CloudflareReceiverGrantForm(
          grant: ReceiverCaptureGrant.parse(grant()),
          onSaved: () {},
        ),
        storage,
      );
      await tester.enterText(
        find.byType(TextField),
        'Checked recorded capture identity',
      );
      await tester.tap(find.text('Review revocation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm capture change'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('Check original receipt'), findsOneWidget);
      expect(storage.values, isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      final f2 = Fixture(
        handler: (r) async {
          if (r.method == 'GET') {
            expect(
              r.url.path,
              '/api/admin/gateway/receiver-requests/$original',
            );
            return response({'found': false});
          }
          writes++;
          expect(r.headers['Idempotency-Key'], original);
          expect(jsonDecode(r.body), {
            'expected_version': 1,
            'reason': 'Checked recorded capture identity',
          });
          return response(receipt());
        },
      );
      final c2 = await mount(
        tester,
        f2,
        CloudflareReceiverGrantForm(
          grant: ReceiverCaptureGrant.parse(grant()),
          onSaved: () {},
        ),
        storage,
      );
      expect(writes, 1);
      expect(find.text('Review revocation'), findsNothing);
      await tester.tap(find.text('Check original receipt'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      await tester.tap(find.text('Review identical retry'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      await tester.tap(find.text('Confirm identical retry'));
      await tester.pumpAndSettle();
      expect(writes, 2);
      expect(storage.values, isEmpty);
      expect(find.textContaining('Capture change saved.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c2.dispose();
    },
  );
}
