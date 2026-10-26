import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/core/cloudflare_admin_sms_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cloudflare_core_fixtures.dart';
import 'cloudflare_reconciliation_fixtures.dart';
import '../support/legacy_backend_fixture.dart';

const otherId = '22222222-2222-4222-8222-222222222222';
const requestKey = '33333333-3333-4333-8333-333333333333';
const smsFactsId = '55555555-5555-4555-8555-555555555555';
Map<String, dynamic> requestReconciliationReceipt({
  String status = 'pending',
  String requestId = otherId,
}) => {...reconReceipt(status: status), 'request_id': requestId};
Map<String, dynamic> requestSmsFactsReceipt({
  String kind = 'member',
  String sourceId = coreId,
  String requestId = otherId,
}) => {
  'request_id': requestId,
  'status': 'succeeded',
  'resource_type': 'sms_facts',
  'resource_id': smsFactsId,
  'source_kind': kind,
  'source_id': sourceId,
  'parser_version': smsParserVersion,
};
Map<String, dynamic> operatingReceipt({
  String type = 'groups',
  String id = coreId,
  int version = 1,
}) => {
  'request_id': otherId,
  'resource_type': type,
  'resource_id': id,
  'version': version,
  'status': 'succeeded',
};
http.Response operatingResponse(Object value, {int status = 200}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(value)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> operatorOnlyDetail() => {
  'resource_type': 'users',
  'resource': {
    ...coreRow(CloudflareCoreArea.users),
    'created_at': 1792056432,
    'updated_at': 1792056432,
    'version': null,
    'collect_user_id': null,
    'operator_admin_id': coreId,
    'operator_public_id': '000123',
    'operator_role': 'staff',
    'operator_status': 'active',
    'member_type': null,
    'user_types': ['Staff'],
    'phone_e164': null,
    'whatsapp_number': null,
  },
  'current_actor_id': coreId,
  'can_manage': false,
  'related': {'memberships': <Map<String, dynamic>>[]},
  'related_pages': {
    'memberships': {'total': 0, 'limit': 50, 'offset': 0, 'next_offset': null},
  },
  'related_truncated': false,
};
Future<CloudflareAdminRepository> operatingRepository(
  Future<http.Response> Function(http.Request) respond, {
  bool staff = false,
  List<String> additionalPermissions = const [],
  String Function()? sessionActorId,
}) async {
  final session = CloudflareAdminSession(
    MockClient((request) async {
      if (request.url.path.endsWith('/auth/session')) {
        final data = coreSession(
          permissions: [
            ...CloudflareCoreArea.values.map((a) => a.permission),
            'overview.read',
            ...additionalPermissions,
            if (!staff) ...[
              ...CloudflareOperation.values.map((a) => a.permission),
              'collections.create',
            ],
          ],
        );
        (data['user'] as Map)['role'] = staff ? 'staff' : 'admin';
        (data['user'] as Map)['id'] = sessionActorId?.call() ?? coreId;
        return operatingResponse(data);
      }
      return respond(request);
    }),
    origin: Uri.parse('https://admin.example.test/'),
    environment: legacyBackendFixtureEnvironment,
  );
  addTearDown(() {
    if (session.mounted) session.dispose();
  });
  await session.refresh();
  return CloudflareAdminRepository(session);
}

void main() {
  test(
    'operator-only people open read-only without inventing a version',
    () async {
      final repo = await operatingRepository((request) async {
        expect(request.method, 'GET');
        return operatingResponse(operatorOnlyDetail());
      });
      final detail = await repo.operatingDetail('users', coreId);
      expect(detail.version, isNull);
      expect(detail.canManage, isFalse);
      expect(detail.resource['user_types'], ['Staff']);
    },
  );
  for (final defect in [
    'write_access',
    'fake_version',
    'wrong_identity',
    'unversioned_collect_person',
  ]) {
    test('operator-only detail rejects $defect', () async {
      final body = operatorOnlyDetail();
      final person = body['resource'] as Map<String, dynamic>;
      switch (defect) {
        case 'write_access':
          body['can_manage'] = true;
        case 'fake_version':
          person['version'] = 1;
        case 'wrong_identity':
          person['operator_admin_id'] = otherId;
        case 'unversioned_collect_person':
          person.addAll({
            'collect_user_id': coreId,
            'member_type': 'app',
            'user_types': ['Staff', 'App'],
          });
      }
      final repo = await operatingRepository(
        (_) async => operatingResponse(body),
      );
      await expectLater(
        repo.operatingDetail('users', coreId),
        throwsFormatException,
      );
    });
  }
  for (final operation in CloudflareOperation.values.where(
    (value) => value != CloudflareOperation.allocateTransaction,
  )) {
    test(
      '${operation.name} uses exact method and native path with one idempotency key',
      () async {
        var calls = 0;
        final id = operation.needsVersion
            ? (operation.resource == 'memberships'
                  ? '$coreId/$otherId'
                  : coreId)
            : null;
        final repo = await operatingRepository((request) async {
          calls++;
          expect(request.method, operation.method);
          expect(request.url.path, '/api/admin/${operation.path(id)}');
          expect(request.headers['Idempotency-Key'], requestKey);
          expect(request.headers['X-Collect-Admin'], '1');
          final body = jsonDecode(request.body) as Map;
          expect(body['reason'], 'Reviewed and approved');
          if (operation.needsVersion) expect(body['expected_version'], 7);
          return operatingResponse(
            operatingReceipt(
              type: operation.resource,
              id:
                  id ??
                  (operation.resource == 'memberships'
                      ? '$coreId/$otherId'
                      : coreId),
              version: operation.needsVersion ? 8 : 1,
            ),
          );
        });
        final receipt = await repo.operate(
          operation,
          id: id,
          key: requestKey,
          body: {
            'reason': 'Reviewed and approved',
            if (operation.needsVersion) 'expected_version': 7,
          },
        );
        expect(receipt.version, operation.needsVersion ? 8 : 1);
        expect(calls, 1);
      },
    );
  }
  test(
    'staff, invalid version, non-exact money and wrong paths fail without transport',
    () async {
      var calls = 0;
      final repo = await operatingRepository((_) async {
        calls++;
        return operatingResponse({});
      }, staff: true);
      await expectLater(
        repo.operate(
          CloudflareOperation.createGroup,
          key: requestKey,
          body: {'reason': 'Reviewed change'},
        ),
        throwsA(isA<AdminAccountException>()),
      );
      final authorized = await operatingRepository((_) async {
        calls++;
        return operatingResponse({});
      });
      await expectLater(
        authorized.operate(
          CloudflareOperation.updateGroup,
          id: '../users',
          key: requestKey,
          body: {'reason': 'Reviewed change', 'expected_version': 1},
        ),
        throwsFormatException,
      );
      await expectLater(
        authorized.operate(
          CloudflareOperation.updateGroup,
          id: coreId,
          key: requestKey,
          body: {'reason': 'Reviewed change', 'expected_version': 0},
        ),
        throwsFormatException,
      );
      await expectLater(
        authorized.operate(
          CloudflareOperation.createTransaction,
          key: requestKey,
          body: {'reason': 'Reviewed change', 'amount_rwf': 9007199254740992},
        ),
        throwsFormatException,
      );
      expect(calls, 0);
    },
  );
  test(
    'unknown outcome is not retried and receipt lookup reconciles it',
    () async {
      var writes = 0;
      final repo = await operatingRepository((request) async {
        if (request.method == 'POST') {
          writes++;
          throw http.ClientException('connection lost');
        }
        expect(request.url.path, '/api/admin/operations/requests/$requestKey');
        return operatingResponse({
          'status': 'succeeded',
          'request_id': otherId,
          'receipt': operatingReceipt(),
        });
      });
      await expectLater(
        repo.operate(
          CloudflareOperation.createGroup,
          key: requestKey,
          body: {'reason': 'Reviewed change'},
        ),
        throwsA(
          isA<CloudflareAdminRequestException>().having(
            (e) => e.outcomeUnknown,
            'unknown',
            true,
          ),
        ),
      );
      final result = await repo.operatingRequest(requestKey);
      expect(result['status'], 'succeeded');
      expect(writes, 1);
    },
  );
  test(
    'mismatched receipt and changed session cannot report success',
    () async {
      final repo = await operatingRepository(
        (_) async => operatingResponse(operatingReceipt(type: 'users')),
      );
      await expectLater(
        repo.operate(
          CloudflareOperation.createGroup,
          key: requestKey,
          body: {'reason': 'Reviewed change'},
        ),
        throwsFormatException,
      );
      final pending = Completer<http.Response>();
      final next = await operatingRepository((_) => pending.future);
      final result = next.operate(
        CloudflareOperation.createGroup,
        key: requestKey,
        body: {'reason': 'Reviewed change'},
      );
      final assertion = expectLater(
        result,
        throwsA(
          isA<CloudflareAdminRequestException>().having(
            (e) => e.outcomeUnknown,
            'unknown',
            true,
          ),
        ),
      );
      next.session.clear();
      pending.complete(operatingResponse(operatingReceipt()));
      await assertion;
    },
  );
  test(
    'detail and active lookup reject malformed versions and monetary values',
    () async {
      final repo = await operatingRepository((request) async {
        if (request.url.path.contains('lookups')) {
          return operatingResponse({
            'rows': [
              {'id': coreId, 'label': 'Example', 'version': 0},
            ],
          });
        }
        return operatingResponse({
          'resource_type': 'transactions',
          'resource': {'id': coreId, 'version': 1, 'amount_rwf': '100'},
          'current_actor_id': coreId,
          'can_manage': true,
          'related': {},
          'related_truncated': false,
        });
      });
      await expectLater(repo.operatingLookups('groups'), throwsFormatException);
      await expectLater(
        repo.operatingDetail('transactions', coreId),
        throwsFormatException,
      );
    },
  );
  test('request history rejects false empty and unrelated receipts', () async {
    final repo = await operatingRepository(
      (_) async => operatingResponse({'rows': [], 'total': 1}),
    );
    await expectLater(repo.operatingRequests(), throwsFormatException);
  });
  for (final kind in const ['member', 'receiver']) {
    test(
      '$kind SMS request history and lookup preserve unversioned source identity',
      () async {
        final sms = requestSmsFactsReceipt(kind: kind);
        const genericId = '44444444-4444-4444-8444-444444444444';
        final generic = {
          ...operatingReceipt(version: 7),
          'request_id': genericId,
        };
        final requests = <http.Request>[];
        final repo = await operatingRepository((request) async {
          requests.add(request);
          if (request.url.path == '/api/admin/operations/requests') {
            return operatingResponse({
              'rows': [
                {
                  'id': otherId,
                  'idempotency_key': requestKey,
                  'scope': 'sms.extract',
                  'status': 'succeeded',
                  'created_at': 1760000000,
                  'completed_at': 1760000001,
                  'receipt': sms,
                },
                {
                  'id': genericId,
                  'idempotency_key': 'generic-request-key',
                  'scope': 'groups.patch',
                  'status': 'succeeded',
                  'created_at': 1760000000,
                  'completed_at': 1760000001,
                  'receipt': generic,
                },
              ],
              'total': 2,
            });
          }
          expect(
            request.url.path,
            '/api/admin/operations/requests/$requestKey',
          );
          return operatingResponse({
            'status': 'succeeded',
            'request_id': otherId,
            'receipt': sms,
          });
        });
        final history = await repo.operatingRequests();
        expect(history.total, 2);
        expect(history.rows.first['receipt'], sms);
        final result = await repo.operatingRequest(requestKey);
        final receipt = CloudflareRequestReceipt.parse(
          result['receipt'] as Map<String, dynamic>,
        );
        expect(receipt, isA<CloudflareSmsFactsRequestReceipt>());
        final extraction = receipt as CloudflareSmsFactsRequestReceipt;
        expect(extraction.requestId, otherId);
        expect(extraction.resourceId, smsFactsId);
        expect(extraction.sourceKind, kind);
        expect(extraction.sourceId, coreId);
        expect(extraction.parserVersion, smsParserVersion);
        expect(extraction.extraction.values.containsKey('version'), isFalse);
        expect(
          CloudflareRequestReceipt.parse(generic),
          isA<CloudflareVersionedRequestReceipt>(),
        );
        expect(requests.every((request) => request.method == 'GET'), isTrue);
        expect(requests, hasLength(2));
        expect(
          () => CloudflareOperationReceipt.parse(sms),
          throwsFormatException,
          reason: 'Operating writes still require a versioned receipt.',
        );
      },
    );
  }
  test(
    'request reads reject malformed SMS variants, unrelated request IDs and wrong scopes',
    () async {
      final valid = requestSmsFactsReceipt();
      final malformed = <Map<String, dynamic>>[
        {...valid}..remove('source_id'),
        {...valid, 'version': 1},
        {...valid, 'source_kind': 'operator'},
        {...valid, 'source_id': '../other'},
        {...valid, 'resource_id': 'not-a-facts-id'},
        {...valid, 'parser_version': 'unrecognised-parser'},
        {...valid, 'provider_confirmation': true},
        {...valid, 'resource_type': 'sms_receipts'},
        {...valid, 'request_id': coreId},
      ];
      for (final receipt in malformed) {
        final repo = await operatingRepository((request) async {
          if (request.url.path == '/api/admin/operations/requests') {
            return operatingResponse({
              'rows': [
                {
                  'id': otherId,
                  'idempotency_key': requestKey,
                  'scope': 'sms.extract',
                  'status': 'succeeded',
                  'created_at': 1760000000,
                  'receipt': receipt,
                },
              ],
              'total': 1,
            });
          }
          return operatingResponse({
            'status': 'succeeded',
            'request_id': otherId,
            'receipt': receipt,
          });
        });
        await expectLater(repo.operatingRequests(), throwsFormatException);
        await expectLater(
          repo.operatingRequest(requestKey),
          throwsFormatException,
        );
      }
      for (final receipt in [valid, operatingReceipt()]) {
        final repo = await operatingRepository(
          (_) async => operatingResponse({
            'rows': [
              {
                'id': otherId,
                'idempotency_key': requestKey,
                'scope': receipt['resource_type'] == 'sms_facts'
                    ? 'groups.post'
                    : 'sms.extract',
                'status': 'succeeded',
                'created_at': 1760000000,
                'receipt': receipt,
              },
            ],
            'total': 1,
          }),
        );
        await expectLater(repo.operatingRequests(), throwsFormatException);
      }
    },
  );
  for (final status in const ['pending', 'approved', 'rejected']) {
    test(
      '$status reconciliation receipt coexists with SMS and operating request history',
      () async {
        final reconciliation = requestReconciliationReceipt(status: status);
        const smsId = '44444444-4444-4444-8444-444444444444';
        const genericId = '66666666-6666-4666-8666-666666666666';
        final records = [
          (
            requestKey,
            status == 'pending'
                ? 'reconciliations.propose'
                : 'reconciliations.review',
            reconciliation,
          ),
          (
            'sms-request-reference',
            'sms.extract',
            requestSmsFactsReceipt(requestId: smsId),
          ),
          (
            'generic-request-reference',
            'groups.post',
            {...operatingReceipt(), 'request_id': genericId},
          ),
        ];
        final requests = <http.Request>[];
        final repo = await operatingRepository((request) async {
          requests.add(request);
          if (request.url.path == '/api/admin/operations/requests') {
            return operatingResponse({
              'rows': [
                for (final record in records)
                  {
                    'id': record.$3['request_id'],
                    'idempotency_key': record.$1,
                    'scope': record.$2,
                    'status': 'succeeded',
                    'created_at': 1760000000,
                    'completed_at': 1760000001,
                    'receipt': record.$3,
                  },
              ],
              'total': records.length,
            });
          }
          expect(
            request.url.path,
            '/api/admin/operations/requests/$requestKey',
          );
          return operatingResponse({
            'status': 'succeeded',
            'request_id': otherId,
            'receipt': reconciliation,
          });
        });
        final history = await repo.operatingRequests();
        expect(history.total, 3);
        expect(
          history.rows.map((row) => row['receipt']),
          records.map((record) => record.$3),
        );
        final result = await repo.operatingRequest(requestKey);
        final receipt = CloudflareRequestReceipt.parse(
          result['receipt'] as Map<String, dynamic>,
        );
        expect(receipt, isA<CloudflareReconciliationRequestReceipt>());
        final typed = receipt as CloudflareReconciliationRequestReceipt;
        expect(typed.requestId, otherId);
        expect(typed.resourceId, reconProposalId);
        expect(typed.transactionId, reconTransactionId);
        expect(typed.reconciliation.status, status);
        expect(typed.reconciliation.values, reconciliation);
        expect(
          () => CloudflareOperationReceipt.parse(reconciliation),
          throwsFormatException,
        );
        expect(requests, hasLength(2));
        expect(requests.every((request) => request.method == 'GET'), isTrue);
      },
    );
  }
  test(
    'reconciliation request history rejects malformed receipts and conflicting scopes',
    () async {
      final pending = requestReconciliationReceipt();
      final approved = requestReconciliationReceipt(status: 'approved');
      final malformed = <Map<String, dynamic>>[
        {...pending}..remove('transaction_id'),
        {...pending, 'transaction_id': '../other'},
        {...pending, 'version': 2},
        {...pending, 'proposal_status': 'settled'},
        {...pending, 'request_id': coreId},
        {...pending, 'resource_id': 'invalid-proposal'},
        {...pending, 'resource_type': 'transactions'},
        {...pending, 'provider_confirmation': true},
        {...approved}..remove('review_id'),
        {...approved, 'allocation_id': null},
        {...approved, 'review_id': 'invalid-review'},
        {...approved, 'transaction_version': 0},
        {...approved, 'settlement_status': 'settled'},
        {
          ...requestReconciliationReceipt(status: 'rejected'),
          'allocation_id': reconAllocationId,
        },
      ];
      for (final receipt in malformed) {
        final repo = await operatingRepository(
          (request) async => operatingResponse(
            request.url.path == '/api/admin/operations/requests'
                ? {
                    'rows': [
                      {
                        'id': otherId,
                        'idempotency_key': requestKey,
                        'scope': receipt['proposal_status'] == 'pending'
                            ? 'reconciliations.propose'
                            : 'reconciliations.review',
                        'status': 'succeeded',
                        'created_at': 1760000000,
                        'receipt': receipt,
                      },
                    ],
                    'total': 1,
                  }
                : {
                    'status': 'succeeded',
                    'request_id': otherId,
                    'receipt': receipt,
                  },
          ),
        );
        await expectLater(repo.operatingRequests(), throwsFormatException);
        await expectLater(
          repo.operatingRequest(requestKey),
          throwsFormatException,
        );
      }
      for (final record in [
        ('groups.post', pending),
        ('reconciliations.review', pending),
        ('reconciliations.propose', approved),
        ('reconciliations.propose', operatingReceipt()),
        ('reconciliations.review', requestSmsFactsReceipt()),
      ]) {
        final repo = await operatingRepository(
          (_) async => operatingResponse({
            'rows': [
              {
                'id': otherId,
                'idempotency_key': requestKey,
                'scope': record.$1,
                'status': 'succeeded',
                'created_at': 1760000000,
                'receipt': record.$2,
              },
            ],
            'total': 1,
          }),
        );
        await expectLater(repo.operatingRequests(), throwsFormatException);
      }
    },
  );
  test(
    'a different actor cannot consume a preceding reconciliation lookup response',
    () async {
      var actor = coreId;
      var reads = 0;
      final previous = Completer<http.Response>();
      final repo = await operatingRepository((request) async {
        expect(request.method, 'GET');
        reads++;
        if (reads == 1) return previous.future;
        return operatingResponse({'status': 'not_found'});
      }, sessionActorId: () => actor);
      final lookup = repo.operatingRequest(requestKey);
      final assertion = expectLater(
        lookup,
        throwsA(isA<AdminAccountException>()),
      );
      actor = reconActorId;
      await repo.session.refresh();
      previous.complete(
        operatingResponse({
          'status': 'succeeded',
          'request_id': otherId,
          'receipt': requestReconciliationReceipt(status: 'approved'),
        }),
      );
      await assertion;
      expect(repo.session.user!.id, reconActorId);
      expect(await repo.operatingRequest(requestKey), {'status': 'not_found'});
      expect(reads, 2);
    },
  );
  test(
    'request history binds every supported operating producer scope to its receipt resource',
    () async {
      const producerScopes = <String, List<String>>{
        'groups': ['groups.post', 'groups.patch'],
        'users': ['users.post', 'users.patch'],
        'memberships': ['memberships.post', 'memberships.patch'],
        'payees': ['payees.post', 'payees.patch'],
        'accounts': ['accounts.post', 'accounts.patch'],
        'transactions': [
          'transactions.post',
          'transactions.post.evidence',
          'transactions.post.verification',
          'transactions.post.allocations',
        ],
        'journals': ['journals.post', 'journals.patch', 'journals.post.post'],
        'gateway_devices': [
          'gateway.enroll',
          'gateway.activate',
          'gateway.revoke',
        ],
        'member_receipts': ['receipt.review'],
        'receiver_capture_grants': [
          'gateway.receiver.grant',
          'gateway.receiver.revoke',
        ],
        'email_dispatch': ['email_dispatch'],
        'allocations': ['transactions.post.allocations'],
        'evidence': ['transactions.post.evidence'],
      };
      Map<String, dynamic> receiptFor(String type) => {
        ...operatingReceipt(
          type: type,
          id: type == 'memberships'
              ? '$coreId/$otherId'
              : type == 'email_dispatch'
              ? otherId
              : coreId,
        ),
        if (type == 'email_dispatch') ...{
          'accepted': 0,
          'uncertain': 0,
          'suppressed': 0,
        },
      };
      Future<CloudflareAdminRepository> repositoryFor(
        String type,
        String scope,
      ) => operatingRepository(
        (_) async => operatingResponse({
          'rows': [
            {
              'id': otherId,
              'idempotency_key': requestKey,
              'scope': scope,
              'status': 'succeeded',
              'created_at': 1760000000,
              'receipt': receiptFor(type),
            },
          ],
          'total': 1,
        }),
      );
      for (final producer in producerScopes.entries) {
        for (final scope in producer.value) {
          final repo = await repositoryFor(producer.key, scope);
          final history = await repo.operatingRequests();
          expect(history.rows.single['receipt'], receiptFor(producer.key));
        }
      }
      for (final mismatch in const [
        ('groups', 'users.patch'),
        ('users', 'groups.post'),
        ('journals', 'journals.posting'),
        ('email_dispatch', 'groups.post'),
        ('gateway_devices', 'gateway.unknown'),
        ('member_receipts', 'gateway.enroll'),
        ('receiver_capture_grants', 'gateway.activate'),
        ('allocations', 'allocations.post'),
        ('evidence', 'evidence.post'),
        ('transactions', 'arbitrary.scope'),
      ]) {
        final repo = await repositoryFor(mismatch.$1, mismatch.$2);
        await expectLater(repo.operatingRequests(), throwsFormatException);
      }
    },
  );
  test(
    'retired allocation cannot bypass member MoMo confirmation through transport',
    () async {
      for (final staff in [false, true]) {
        var calls = 0;
        final repo = await operatingRepository(
          (_) async {
            calls++;
            return operatingResponse({});
          },
          staff: staff,
          additionalPermissions: ['payments.manage'],
        );
        await expectLater(
          repo.operate(
            CloudflareOperation.allocateTransaction,
            id: coreId,
            key: requestKey,
            body: {
              'reason': 'Reviewed and approved',
              'expected_version': 1,
              'member_user_id': null,
            },
          ),
          throwsA(isA<AdminAccountException>()),
        );
        expect(calls, 0);
      }
    },
  );
}
