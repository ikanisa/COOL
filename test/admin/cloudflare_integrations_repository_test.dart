import 'dart:convert';
import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'cloudflare_core_fixtures.dart';
import 'cloudflare_integrations_fixtures.dart';
import 'cloudflare_operating_repository_test.dart'
    show operatingResponse, operatingReceipt, otherId, requestKey;

void main() {
  test(
    'gateway public key, list, detail and native activation receipt are verified',
    () async {
      final repo = await integrationRepository((request) async {
        if (request.method == 'POST') {
          expect(
            request.url.path,
            '/api/admin/gateway/devices/$coreId/activate',
          );
          expect(request.headers['Idempotency-Key'], requestKey);
          final body = jsonDecode(request.body) as Map;
          expect(body['expected_key_sha256'], integrationKeyHash);
          return operatingResponse(
            operatingReceipt(type: 'gateway_devices', version: 2),
          );
        }
        if (request.url.path.endsWith('/$coreId')) {
          return operatingResponse(integrationGatewayDetail());
        }
        return operatingResponse({
          'rows': [integrationDevice()],
          'total': 1,
        });
      });
      expect(
        validCloudflareGatewayKey(integrationPublicKey, integrationKeyHash),
        isTrue,
      );
      expect((await repo.gatewayDeviceList()).rows.single.state, 'pending');
      final detail = await repo.gatewayDevice(coreId);
      expect(detail.canManage, isTrue);
      final result = await repo.gatewayAction(
        CloudflareGatewayAction.activate,
        id: coreId,
        key: requestKey,
        body: {
          'expected_version': 1,
          'expected_key_sha256': integrationKeyHash,
          'expected_signing_certificate_sha256': integrationCert,
          'reason': 'Reviewed handset identity',
        },
      );
      expect(result.version, 2);
    },
  );
  test(
    'invented sending authority and wrong fingerprints fail closed',
    () async {
      expect(
        validCloudflareGatewayKey(integrationPublicKey, integrationCert),
        isFalse,
      );
      final repo = await integrationRepository(
        (_) async => operatingResponse({
          'rows': [integrationDevice()..['send_authority'] = true],
          'total': 1,
        }),
      );
      await expectLater(repo.gatewayDeviceList(), throwsFormatException);
    },
  );
  test(
    'masked email metadata and counts remain distinct from delivery',
    () async {
      final repo = await integrationRepository((request) async {
        if (request.method == 'POST') {
          return operatingResponse({
            ...operatingReceipt(type: 'email_dispatch', id: otherId),
            'accepted': 1,
            'uncertain': 2,
            'suppressed': 3,
          });
        }
        return operatingResponse({
          'rows': [integrationEmail()],
          'total': 1,
          'limit': 25,
          'offset': 0,
        });
      });
      final emails = await repo.emailEvents();
      expect(emails.rows.single['delivered_at'], isNull);
      final receipt = await repo.dispatchEmails(
        key: requestKey,
        reason: 'Process pending notifications',
      );
      expect(receipt.accepted, 1);
      expect(receipt.uncertain, 2);
      expect(receipt.suppressed, 3);
      expect(
        () => CloudflareOperationReceipt.parse({
          ...operatingReceipt(type: 'email_dispatch', id: otherId),
          'accepted': 21,
          'uncertain': 0,
          'suppressed': 0,
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'raw recipient fields and false empty email results are rejected',
    () async {
      for (final payload in [
        {
          'rows': [integrationEmail()..['recipient'] = 'raw@example.test'],
          'total': 1,
          'limit': 25,
          'offset': 0,
        },
        {'rows': [], 'total': 1, 'limit': 25, 'offset': 0},
      ]) {
        final repo = await integrationRepository(
          (_) async => operatingResponse(payload),
        );
        await expectLater(repo.emailEvents(), throwsFormatException);
      }
    },
  );
  test(
    'receipt content needs audited reason and matching hash before display',
    () async {
      var reads = 0;
      final repo = await integrationRepository((request) async {
        reads++;
        expect(
          request.headers['X-Collect-Review-Reason'],
          'Review submitted payment',
        );
        return operatingResponse(integrationContent());
      });
      final receipt = CloudflareMemberReceipt.parse(integrationReceipt());
      final content = await repo.memberReceiptContent(
        receipt,
        reason: 'Review submitted payment',
      );
      expect(content['raw_body'], integrationBody);
      expect(reads, 1);
      final bad = await integrationRepository(
        (_) async => operatingResponse(
          integrationContent()..['raw_body'] = 'Modified source',
        ),
      );
      await expectLater(
        bad.memberReceiptContent(receipt, reason: 'Review submitted payment'),
        throwsFormatException,
      );
    },
  );
  test(
    'staff cannot dispatch, manage devices or reveal source content',
    () async {
      var calls = 0;
      final repo = await integrationRepository((_) async {
        calls++;
        return operatingResponse({});
      }, staff: true);
      await expectLater(
        repo.dispatchEmails(
          key: requestKey,
          reason: 'Process pending notifications',
        ),
        throwsA(isA<AdminAccountException>()),
      );
      await expectLater(
        repo.memberReceiptContent(
          CloudflareMemberReceipt.parse(integrationReceipt()),
          reason: 'Review submitted payment',
        ),
        throwsA(isA<AdminAccountException>()),
      );
      await expectLater(
        repo.gatewayAction(
          CloudflareGatewayAction.revoke,
          id: coreId,
          key: requestKey,
          body: {
            'reason': 'Remove trusted device',
            'expected_version': 1,
            'expected_key_sha256': integrationKeyHash,
            'expected_signing_certificate_sha256': integrationCert,
          },
        ),
        throwsA(isA<AdminAccountException>()),
      );
      expect(calls, 0);
    },
  );
  test(
    'receipt classification uses its version and does not confirm a payment',
    () async {
      final repo = await integrationRepository((request) async {
        expect(request.url.path, '/api/admin/gateway/receipts/$coreId/review');
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'expected_version': 1,
          'outcome': 'reviewed',
          'transaction_id': otherId,
          'reason': 'Reviewed original member submission',
        });
        return operatingResponse(
          operatingReceipt(type: 'member_receipts', version: 2),
        );
      });
      final saved = await repo.reviewMemberReceipt(
        CloudflareMemberReceipt.parse(integrationReceipt()),
        key: requestKey,
        outcome: 'reviewed',
        transactionId: otherId,
        reason: 'Reviewed original member submission',
      );
      expect(saved.version, 2);
    },
  );
}
