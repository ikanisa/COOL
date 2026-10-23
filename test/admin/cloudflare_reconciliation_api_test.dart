import 'dart:convert';
import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_reconciliation_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'cloudflare_reconciliation_fixtures.dart';
import '../support/legacy_backend_fixture.dart';

http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
Future<CloudflareReconciliationApi> api(
  Future<http.Response> Function(http.Request) handler, {
  String role = 'staff',
  List<String>? permissions,
  AdminPendingAttemptStore? pendingStore,
}) async {
  final session = CloudflareAdminSession(
    MockClient(
      (request) async => request.url.path.endsWith('/auth/session')
          ? response(reconSession(role: role, permissions: permissions))
          : handler(request),
    ),
    origin: Uri.parse('https://admin.example.test'),
    environment: legacyBackendFixtureEnvironment,
  );
  addTearDown(session.dispose);
  await session.refresh();
  pendingStore?.bind(session.user);
  return CloudflareReconciliationApi(session, pendingStore: pendingStore);
}

void main() {
  test(
    'reload after thirty minutes restores only the original submitted key and requires lookup plus explicit reconfirmation',
    () async {
      final storage = MemoryAdminPendingAttemptStorage(),
          posts = <http.Request>[];
      var now = DateTime.now();
      var retry = false;
      Future<http.Response> handler(http.Request request) async {
        if (request.method == 'POST') {
          // Durability must precede transport, including its first attempt.
          expect(storage.values, isNotEmpty);
          posts.add(request);
          return retry
              ? response(reconReceipt())
              : response({'error': 'unavailable'}, 503);
        }
        return response({'status': 'not_found'});
      }

      final firstStore = AdminPendingAttemptStore(
        storage: storage,
        now: () => now,
      );
      addTearDown(firstStore.dispose);
      final first = await api(handler, pendingStore: firstStore);
      final original = first.propose(
        ReconciliationTransaction.parse(reconTransaction()),
        ReconciliationMember.parse(reconMember()),
        400,
        'Reviewed this recorded member payment.',
      );
      await expectLater(
        first.submit(original),
        throwsA(isA<CloudflareAdminRequestException>()),
      );
      now = now.add(const Duration(minutes: 30));
      final nextStore = AdminPendingAttemptStore(
        storage: storage,
        now: () => now,
      );
      addTearDown(nextStore.dispose);
      final next = await api(handler, pendingStore: nextStore);
      final restored = next.restorePending(reconTransactionId)!;
      expect(restored.key, original.key);
      expect(restored.body, original.body);
      expect(restored.needsReconfirmation, isTrue);
      final freshKeyAttempt = next.propose(
        ReconciliationTransaction.parse(reconTransaction()),
        ReconciliationMember.parse(reconMember()),
        400,
        'Reviewed this recorded member payment.',
      );
      await expectLater(
        next.submit(freshKeyAttempt),
        throwsA(isA<AdminAccountException>()),
      );
      expect(posts, hasLength(1));
      expect(() => restored.body['amount_rwf'] = 1, throwsUnsupportedError);
      await expectLater(
        next.submit(restored),
        throwsA(isA<AdminAccountException>()),
      );
      expect((await next.lookup(restored)).status, 'not_found');
      await expectLater(
        next.submit(restored),
        throwsA(isA<AdminAccountException>()),
      );
      expect(
        () => next.reconfirmRestored(
          restored,
          ReconciliationTransaction.parse(reconTransaction()),
          member: ReconciliationMember.parse(reconMember()),
          confirmationReviewed: false,
        ),
        throwsA(isA<AdminAccountException>()),
      );
      expect(
        () => next.reconfirmRestored(
          restored,
          ReconciliationTransaction.parse({
            ...reconTransaction(),
            'version': 3,
          }),
          member: ReconciliationMember.parse(reconMember()),
          confirmationReviewed: true,
        ),
        throwsFormatException,
      );
      expect(posts, hasLength(1));
      next.reconfirmRestored(
        restored,
        ReconciliationTransaction.parse(reconTransaction()),
        member: ReconciliationMember.parse(reconMember()),
        confirmationReviewed: true,
      );
      retry = true;
      await next.submit(restored);
      expect(posts, hasLength(2));
      expect(
        posts.last.headers['Idempotency-Key'],
        posts.first.headers['Idempotency-Key'],
      );
      expect(posts.last.body, posts.first.body);
      expect(storage.values, isEmpty);
    },
  );

  test(
    'authoritative committed receipt recovers after reload without resending or reading an eligible form',
    () async {
      final storage = MemoryAdminPendingAttemptStorage();
      var posts = 0;
      final firstStore = AdminPendingAttemptStore(storage: storage);
      addTearDown(firstStore.dispose);
      final first = await api((request) async {
        posts++;
        throw http.ClientException('lost');
      }, pendingStore: firstStore);
      final original = first.propose(
        ReconciliationTransaction.parse(reconTransaction()),
        ReconciliationMember.parse(reconMember()),
        400,
        'Reviewed this recorded member payment.',
      );
      await expectLater(
        first.submit(original),
        throwsA(isA<CloudflareAdminRequestException>()),
      );
      final nextStore = AdminPendingAttemptStore(storage: storage);
      addTearDown(nextStore.dispose);
      final next = await api((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, endsWith('/requests/${original.key}'));
        return response({
          'status': 'succeeded',
          'request_id': reconRequestId,
          'receipt': reconReceipt(),
        });
      }, pendingStore: nextStore);
      final restored = next.restorePending(reconTransactionId)!;
      expect((await next.lookup(restored)).receipt!.status, 'pending');
      expect(posts, 1);
      expect(storage.values, isEmpty);
    },
  );
  test(
    'Staff proposals freeze recorded identity, versions and original key without broad write rights',
    () async {
      final requests = <http.Request>[];
      final service = await api((request) async {
        requests.add(request);
        return response(reconReceipt());
      });
      final attempt = service.propose(
        ReconciliationTransaction.parse(reconTransaction()),
        ReconciliationMember.parse(reconMember()),
        400,
        'Reviewed this member payment.',
      );
      expect(attempt.key, matches(RegExp(r'^[a-f0-9-]{36}$')));
      expect(attempt.body.containsKey('group_id'), isFalse);
      expect(attempt.body['expected_transaction_version'], 2);
      expect(attempt.body['expected_member_version'], 1);
      expect(attempt.body['expected_membership_version'], 1);
      expect(
        () =>
            (attempt.body['expected_payment_identity']
                    as Map)['momo_pay_code'] =
                '1',
        throwsUnsupportedError,
      );
      final receipt = await service.submit(attempt);
      expect(receipt.status, 'pending');
      expect(
        requests.single.url.path,
        '/api/admin/reconciliations/$reconTransactionId/proposals',
      );
      expect(requests.single.headers['Idempotency-Key'], attempt.key);
      expect(jsonDecode(requests.single.body), attempt.body);
      expect(
        () => service.review(
          ReconciliationTransaction.parse(reconTransaction()),
          ReconciliationProposal.parse(reconProposal()),
          'approved',
          'Reviewed independently.',
          currentMember: ReconciliationMember.parse(reconMember()),
        ),
        throwsA(isA<AdminAccountException>()),
      );
    },
  );
  test(
    'queue/member/related paging validates source identity and never projects masked or rounded facts',
    () async {
      final service = await api((request) async {
        if (request.url.path.endsWith('/members')) {
          return response(reconPage([reconMember()]));
        }
        if (request.url.path.endsWith(reconTransactionId)) {
          return response(
            reconDetail(relation: request.url.queryParameters['related']),
          );
        }
        return response(reconPage([reconTransaction()]));
      });
      expect(
        (await service.queue(
          search: '008001',
        )).rows.single.values['payee_momo'],
        '0041258',
      );
      final member = (await service.members(
        reconTransactionId,
        search: '+250788123456',
      )).rows.single;
      expect(member.publicId, '000123');
      expect(member.identity.code, '008001');
      expect(
        (await service.detail(
          reconTransactionId,
          relation: 'allocations',
        )).related.keys,
        ['allocations'],
      );
      expect(
        () => service.queue(allocation: 'allocated'),
        throwsFormatException,
      );
      expect(() => service.members('pasted group'), throwsFormatException);
      for (final changed in [
        {'unallocated_amount_rwf': 900},
        {'amount_rwf': 1.5},
        {'settlement_status': 'settled'},
        {'password_hash': 'secret'},
      ]) {
        expect(
          () => ReconciliationTransaction.parse({
            ...reconTransaction(),
            ...changed,
          }),
          throwsFormatException,
        );
      }
      expect(
        () => ReconciliationPage.parse(
          reconPage([], total: 26),
          ReconciliationMember.parse,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'independent review blocks self, changed identity/versions and unconfirmed approvals but allows reasoned rejection',
    () async {
      final service = await api(
        (_) async => response(reconReceipt(status: 'approved')),
        role: 'admin',
      );
      final transaction = ReconciliationTransaction.parse(reconTransaction()),
          proposal = ReconciliationProposal.parse(reconProposal()),
          member = ReconciliationMember.parse(reconMember());
      final attempt = service.review(
        transaction,
        proposal,
        'approved',
        'Reviewed independently.',
        currentMember: member,
      );
      expect((await service.submit(attempt)).status, 'approved');
      for (final wrong in [
        ReconciliationProposal.parse(reconProposal(proposer: reconActorId)),
        ReconciliationProposal.parse({...reconProposal(), 'member_version': 2}),
      ]) {
        expect(
          () => service.review(
            transaction,
            wrong,
            'approved',
            'Reviewed independently.',
            currentMember: member,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => service.review(
          ReconciliationTransaction.parse(
            reconTransaction(verification: 'pending'),
          ),
          proposal,
          'approved',
          'Reviewed independently.',
          currentMember: member,
        ),
        throwsFormatException,
      );
      expect(
        () => service.review(
          transaction,
          proposal,
          'approved',
          'Reviewed independently.',
          currentMember: ReconciliationMember.parse({
            ...reconMember(),
            'momo_number': '0788000000',
            'payment_identity': {
              ...reconIdentity(),
              'momo_number': '0788000000',
            },
          }),
        ),
        throwsFormatException,
      );
      expect(
        service
            .review(
              ReconciliationTransaction.parse(
                reconTransaction(verification: 'pending'),
              ),
              proposal,
              'rejected',
              'Rejected pending verification.',
            )
            .body['outcome'],
        'rejected',
      );
    },
  );
  test(
    'unknown and malformed acknowledgements recover only actor-owned authoritative matching receipts',
    () async {
      var malformed = false;
      var lookup = 'not_found';
      final keys = <String>[];
      final service = await api((request) async {
        if (request.method == 'POST') {
          keys.add(request.headers['Idempotency-Key']!);
          if (malformed) return response({'status': 'succeeded'});
          throw http.ClientException('response lost');
        }
        if (lookup == 'unavailable') {
          return response({'error': 'service_unavailable'}, 503);
        }
        return response(
          lookup == 'not_found'
              ? {'status': 'not_found'}
              : {
                  'status': lookup,
                  'request_id': reconRequestId,
                  'receipt': lookup == 'succeeded' ? reconReceipt() : null,
                },
        );
      });
      final attempt = service.propose(
        ReconciliationTransaction.parse(reconTransaction()),
        ReconciliationMember.parse(reconMember()),
        400,
        'Reviewed this member payment.',
      );
      await expectLater(
        service.submit(attempt),
        throwsA(
          isA<CloudflareAdminRequestException>().having(
            (e) => e.outcomeUnknown,
            'unknown',
            true,
          ),
        ),
      );
      await expectLater(
        service.submit(attempt),
        throwsA(isA<AdminAccountException>()),
      );
      expect(keys, [attempt.key]);
      expect((await service.lookup(attempt)).status, 'not_found');
      for (final status in ['pending', 'failed', 'unavailable']) {
        lookup = status;
        if (status == 'unavailable') {
          await expectLater(
            service.lookup(attempt),
            throwsA(isA<CloudflareAdminRequestException>()),
          );
        } else {
          expect((await service.lookup(attempt)).status, status);
        }
        await expectLater(
          service.submit(attempt),
          throwsA(isA<AdminAccountException>()),
        );
        expect(keys, [attempt.key]);
        lookup = 'not_found';
        expect((await service.lookup(attempt)).status, 'not_found');
      }
      malformed = true;
      await expectLater(
        service.submit(attempt),
        throwsA(
          isA<CloudflareAdminRequestException>().having(
            (e) => e.outcomeUnknown,
            'unknown',
            true,
          ),
        ),
      );
      expect(keys, [attempt.key, attempt.key]);
      lookup = 'succeeded';
      expect((await service.lookup(attempt)).receipt!.status, 'pending');
      service.session.clear();
      await expectLater(
        service.lookup(attempt),
        throwsA(isA<AdminAccountException>()),
      );
    },
  );
  test(
    'same-authority refresh preserves API while capability removal fences reads and writes',
    () async {
      var permissions = ['reconciliations.read', 'reconciliations.propose'];
      var requests = 0;
      final session = CloudflareAdminSession(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/session')) {
            return response(reconSession(permissions: permissions));
          }
          requests++;
          return response(reconPage([reconTransaction()]));
        }),
        origin: Uri.parse('https://admin.example.test'),
        environment: legacyBackendFixtureEnvironment,
      );
      addTearDown(session.dispose);
      await session.refresh();
      final service = CloudflareReconciliationApi(session);
      await session.refresh();
      await service.queue();
      expect(requests, 1);
      permissions = ['account.manage'];
      await session.refresh();
      await expectLater(service.queue(), throwsA(isA<AdminAccountException>()));
      expect(requests, 1);
    },
  );
}
