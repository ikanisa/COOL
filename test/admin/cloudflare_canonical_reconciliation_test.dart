import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_request_identity.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/core/cloudflare_canonical_reconciliation_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'cloudflare_canonical_reconciliation_support.dart';

Map<String, dynamic> _receiverFixture(String route, {required bool phone}) {
  final data = financialFixture('detail');
  final resource = data['resource'] as Map<String, dynamic>;
  resource['payee_momo_number'] = phone ? route : null;
  resource['payee_momo_code'] = phone ? null : route;
  resource['payee_momo_number_or_code'] = route;
  final groupReceiver = data['group_state']['receiver'] as Map<String, dynamic>;
  final snapshotReceiver =
      _proposalRow(data)['receiver_identity'] as Map<String, dynamic>;
  groupReceiver['momo_number_or_code'] = route;
  snapshotReceiver['momo_number_or_code'] = route;
  return data;
}

Map<String, dynamic> _proposalRow(Map<String, dynamic> data) =>
    ((data['related']['proposals']['rows'] as List).single
        as Map<String, dynamic>);

Future<FinancialHarness> _receiverHarness(Map<String, dynamic> data) =>
    FinancialHarness.create(
      reply: (request) async {
        if (request.method != 'GET') {
          throw StateError('The receiver contract fixture permits reads only.');
        }
        return financialResponse(
          request.url.path.endsWith('/members')
              ? financialFixture('members')
              : data,
        );
      },
    );

void main() {
  test('canonical receiver contract accepts codes and phone strings', () async {
    for (final example in const [
      (route: '0000', phone: false),
      (route: '001234567890', phone: false),
      (route: '0788123456', phone: true),
      (route: '250788123456', phone: true),
      (route: '+250788123456', phone: true),
    ]) {
      final h = await _receiverHarness(
        _receiverFixture(example.route, phone: example.phone),
      );
      final api = h.api;
      final detail = await api.detail(
        financialFixture('detail')['resource']['id'] as String,
      );
      final members = await api.members(detail);
      final proposal = CanonicalReconciliationProposal.parse(
        detail.related['proposals']!.rows.single,
        transactionId: detail.id,
        evidenceId: detail.transaction['evidence_id'] as String,
      );
      expect(detail.group['receiver']['momo_number_or_code'], example.route);
      expect(
        proposal.values['receiver_identity']['momo_number_or_code'],
        example.route,
      );
      expect(detail.transaction['payee_momo_number_or_code'], example.route);
      expect(proposal.currentFor(detail, members.rows.single), isTrue);
      final attempt = api.review(
        detail,
        proposal,
        'approved',
        'Independent synthetic evidence review',
        member: members.rows.single,
      );
      expect(
        attempt.body['expected_proposal_version'],
        proposal.values['version'],
      );
      expect(
        attempt.body['expected_transaction_version'],
        detail.transaction['version'],
      );
    }
  });

  test('canonical receiver contract rejects malformed fields', () async {
    for (final field in const [
      (name: 'momo_number_or_code', value: null),
      (name: 'momo_number_or_code', value: 1234),
      (name: 'momo_number_or_code', value: '123'),
      (name: 'momo_number_or_code', value: '1234567890123'),
      (name: 'momo_number_or_code', value: '+250688123456'),
      (name: 'momo_number_or_code', value: '12A4'),
      (name: 'momo_number_or_code', value: ' 1234'),
      (name: 'network', value: 'unknown'),
      (name: 'label', value: '   '),
    ]) {
      for (final snapshot in [false, true]) {
        final data = financialFixture('detail');
        final receiver = snapshot
            ? _proposalRow(data)['receiver_identity'] as Map<String, dynamic>
            : data['group_state']['receiver'] as Map<String, dynamic>;
        receiver[field.name] = field.value;
        final h = await _receiverHarness(data);
        await expectLater(
          h.api.detail(data['resource']['id'] as String),
          throwsFormatException,
          reason:
              '${snapshot ? 'snapshot' : 'group'}: ${field.name}=${field.value}',
        );
      }
    }
  });

  test('canonical receiver contract holds stale snapshots', () async {
    for (final change in const [
      (field: 'momo_number_or_code', value: '0001', receiver: true),
      (field: 'network', value: 'airtel_money', receiver: true),
      (field: 'label', value: 'Different receiver', receiver: true),
      (field: 'expected_payment_version', value: 2, receiver: false),
      (field: 'member_version', value: 2, receiver: false),
      (field: 'membership_version', value: 2, receiver: false),
      (field: 'group_version', value: 2, receiver: false),
    ]) {
      final data = _receiverFixture('0000', phone: false);
      final row = _proposalRow(data);
      if (change.receiver) {
        (row['receiver_identity'] as Map<String, dynamic>)[change.field] =
            change.value;
      } else {
        row[change.field] = change.value;
      }
      final h = await _receiverHarness(data);
      final api = h.api;
      final detail = await api.detail(data['resource']['id'] as String);
      final member = (await api.members(detail)).rows.single;
      final proposal = CanonicalReconciliationProposal.parse(
        detail.related['proposals']!.rows.single,
        transactionId: detail.id,
        evidenceId: detail.transaction['evidence_id'] as String,
      );
      expect(
        proposal.currentFor(detail, member),
        isFalse,
        reason: change.field,
      );
      expect(
        () => api.review(
          detail,
          proposal,
          'approved',
          'Independent synthetic evidence review',
          member: member,
        ),
        throwsFormatException,
      );
      expect(
        api
            .review(
              detail,
              proposal,
              'rejected',
              'Independent synthetic evidence review',
              member: member,
            )
            .body['outcome'],
        'rejected',
      );
    }
  });

  test(
    'request identity agrees with independently executed Worker D1 receipts',
    () {
      final captured =
          jsonDecode(
                File('test/admin/admin-dto-examples.json').readAsStringSync(),
              )
              as Map;
      final rows = captured['request_identities'] as List;
      expect(rows.length, greaterThanOrEqualTo(5));
      for (final row in rows) {
        expect(
          canonicalAdminRequestId(
            row['principal_id'] as String,
            row['idempotency_key'] as String,
          ),
          row['request_id'],
        );
      }
    },
  );
  test(
    'consumes the actual D1 evidence queue, review snapshots and current members',
    () async {
      final h = await FinancialHarness.create(), api = h.api;
      final queue = await api.queue(),
          detail = await api.detail(queue.rows.single['id'] as String),
          members = await api.members(detail);
      expect(queue.total, 1);
      expect(detail.canPropose, isTrue);
      expect(detail.canReview, isTrue);
      expect(detail.transaction['provider_confirmation'], isFalse);
      expect(detail.transaction['settlement_status'], 'not_asserted');
      final proposal = CanonicalReconciliationProposal.parse(
        detail.related['proposals']!.rows.single,
        transactionId: detail.id,
        evidenceId: detail.transaction['evidence_id'] as String,
      );
      expect(proposal.currentFor(detail, members.rows.single), isTrue);
      expect(
        proposal.values['reason'],
        'Attribute this retained evidence to the reviewed member',
      );
      expect(
        () => proposal.values['receiver_identity']['label'] = 'Substituted',
        throwsUnsupportedError,
      );
      expect(
        () => detail.group['receiver']['label'] = 'Substituted',
        throwsUnsupportedError,
      );
    },
  );

  for (final damage in [
    'actor',
    'principal',
    'wrong_payment',
    'wrong_evidence',
    'duplicate_proposal',
    'page_total',
    'page_next',
    'fake_settlement',
    'stale_receiver',
    'bad_timestamp',
    'wrong_model',
    'staff_review',
  ]) {
    test(
      'rejects malformed or substituted financial detail: $damage',
      () async {
        final data = financialFixture('detail'),
            proposals = (data['related'] as Map)['proposals'] as Map;
        switch (damage) {
          case 'actor':
            data['current_actor_id'] = '11111111-1111-4111-8111-111111111111';
          case 'principal':
            data['current_principal_id'] =
                '11111111-1111-4111-8111-111111111111';
          case 'wrong_payment':
            ((proposals['rows'] as List).single as Map)['payment_id'] =
                '11111111-1111-4111-8111-111111111111';
          case 'wrong_evidence':
            ((proposals['rows'] as List).single as Map)['evidence_id'] =
                '11111111-1111-4111-8111-111111111111';
          case 'duplicate_proposal':
            (proposals['rows'] as List).add((proposals['rows'] as List).single);
            proposals['total'] = 2;
          case 'page_total':
            proposals['total'] = 0;
          case 'page_next':
            proposals['next_offset'] = 1;
          case 'fake_settlement':
            (data['resource'] as Map)['provider_confirmation'] = true;
          case 'stale_receiver':
            ((data['group_state'] as Map)['receiver'] as Map)['network'] =
                'unknown';
          case 'bad_timestamp':
            ((proposals['rows'] as List).single as Map)['created_at'] =
                '2026-02-30T10:00:00Z';
          case 'wrong_model':
            data['model'] = 'transaction_journals';
          case 'staff_review':
            break;
        }
        final h = await FinancialHarness.create(
          auth: canonicalSession(
            role: damage == 'staff_review' ? 'staff' : 'owner',
          ),
          reply: (_) async => financialResponse(data),
        );
        await expectLater(
          h.api.detail(financialFixture('detail')['resource']['id'] as String),
          throwsFormatException,
        );
      },
    );
  }

  test(
    'proposal binds full amount and exact identity; the proposer cannot approve their own snapshot',
    () async {
      final h = await FinancialHarness.create(),
          api = h.api,
          detail = await api.detail(
            financialFixture('detail')['resource']['id'] as String,
          ),
          members = await api.members(detail);
      final attempt = api.propose(
        detail,
        members.rows.single,
        'Reviewed the retained member identity',
      );
      expect(attempt.body['amount_rwf'], detail.transaction['amount_rwf']);
      expect(
        attempt.body['expected_payment_identity'],
        members.rows.single.identity.json,
      );
      expect(
        () => attempt.body['expected_payment_identity']['momo_number'] =
            '0788000000',
        throwsUnsupportedError,
      );
      final row = Map<String, dynamic>.from(
        detail.related['proposals']!.rows.single,
      )..['proposed_by_principal_id'] = detail.principalId;
      final own = CanonicalReconciliationProposal.parse(
        row,
        transactionId: detail.id,
        evidenceId: detail.transaction['evidence_id'] as String,
      );
      expect(
        () => api.review(
          detail,
          own,
          'approved',
          'Independent review reason',
          member: members.rows.single,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'lost response survives replacement and only an explicitly reviewed same-key retry can send again',
    () async {
      final calls =
          <({String key, Map<String, dynamic> body, String encoded})>[];
      var fail = true;
      late String principal;
      Future<http.Response> reply(http.Request request) async {
        if (request.method == 'POST') {
          final key =
              request.headers['Idempotency-Key'] ??
              request.headers['idempotency-key']!;
          calls.add((
            key: key,
            body: Map<String, dynamic>.from(jsonDecode(request.body) as Map),
            encoded: request.body,
          ));
          if (fail) {
            return financialResponse({
              'error': {'code': 'service_unavailable'},
            }, 503);
          }
          return financialResponse({
            ...financialFixture('proposal_receipt'),
            'request_id': canonicalAdminRequestId(principal, key),
          });
        }
        if (request.url.path.contains('/operations/requests/')) {
          return financialResponse({
            'contract_version': 2,
            'model': 'canonical_evidence_ledger',
            'status': 'not_found',
          });
        }
        return FinancialHarness.defaultRead(request);
      }

      final first = await FinancialHarness.create(reply: reply);
      principal = first.session.user!.principalId!;
      final api = first.api,
          detail = await api.detail(
            financialFixture('detail')['resource']['id'] as String,
          ),
          members = await api.members(detail);
      final original = api.propose(
        detail,
        members.rows.single,
        'Retain and review original member attribution',
      );
      await expectLater(
        api.submit(original),
        throwsA(isA<CloudflareAdminRequestException>()),
      );
      expect(calls, hasLength(1));
      expect(original.needsLookup, isTrue);
      expect(first.storage.values.values.single, contains(original.key));
      final replacement = await FinancialHarness.create(
            reply: reply,
            storage: first.storage,
            auth: first.auth,
          ),
          newApi = replacement.api;
      final restored = newApi.restore(detail.id)!;
      expect(restored.key, original.key);
      expect(restored.body, original.body);
      await expectLater(
        newApi.submit(restored),
        throwsA(isA<AdminAccountException>()),
      );
      expect(calls, hasLength(1));
      expect((await newApi.lookup(restored)).status, 'not_found');
      await expectLater(
        newApi.submit(restored),
        throwsA(isA<AdminAccountException>()),
      );
      expect(calls, hasLength(1));
      fail = false;
      final receipt = await newApi.submit(restored, confirmedRetry: true);
      expect(receipt.sourceModel, 'canonical_evidence_ledger');
      expect(calls, hasLength(2));
      expect(calls.last.key, calls.first.key);
      expect(calls.last.body, calls.first.body);
      expect(calls.last.encoded, calls.first.encoded);
      expect(replacement.storage.values, isEmpty);
      expect(restored.needsLookup, isFalse);
    },
  );

  test(
    'a 403 after dispatch stays unconfirmed and a successful lookup resolves its receipt without resending',
    () async {
      late String principal, key;
      var posts = 0;
      final h = await FinancialHarness.create(
        reply: (request) async {
          if (request.method == 'POST') {
            posts++;
            key =
                request.headers['Idempotency-Key'] ??
                request.headers['idempotency-key']!;
            return financialResponse({
              'error': {'code': 'permission_required'},
            }, 403);
          }
          if (request.url.path.contains('/operations/requests/')) {
            final receipt = {
              ...financialFixture('proposal_receipt'),
              'request_id': canonicalAdminRequestId(principal, key),
            };
            return financialResponse({
              'contract_version': 2,
              'model': 'canonical_evidence_ledger',
              'status': 'succeeded',
              'request_id': receipt['request_id'],
              'receipt': receipt,
            });
          }
          return FinancialHarness.defaultRead(request);
        },
      );
      principal = h.session.user!.principalId!;
      final api = h.api,
          detail = await api.detail(
            financialFixture('detail')['resource']['id'] as String,
          ),
          member = (await api.members(detail)).rows.single;
      final attempt = api.propose(
        detail,
        member,
        'Review post-commit denial recovery',
      );
      await expectLater(
        api.submit(attempt),
        throwsA(isA<CloudflareAdminRequestException>()),
      );
      expect(attempt.needsLookup, isTrue);
      expect((await api.lookup(attempt)).status, 'succeeded');
      expect(posts, 1);
      expect(h.storage.values, isEmpty);
    },
  );

  test(
    'authority replacement while a read waits releases no old financial result',
    () async {
      final held = Completer<http.Response>();
      var hold = false;
      final h = await FinancialHarness.create(
        reply: (request) async =>
            hold ? held.future : FinancialHarness.defaultRead(request),
      );
      final api = h.api;
      hold = true;
      final result = api.detail(
        financialFixture('detail')['resource']['id'] as String,
      );
      final check = expectLater(result, throwsA(isA<AdminAccountException>()));
      h.auth = {
        ...h.auth,
        'user': {
          ...h.auth['user'] as Map,
          'id': '11111111-1111-4111-8111-111111111111',
          'sessionId': 'replacement-session',
        },
      };
      await h.session.refresh();
      held.complete(financialResponse(financialFixture('detail')));
      await check;
    },
  );
}
