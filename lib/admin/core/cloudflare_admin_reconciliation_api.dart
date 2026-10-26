import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'admin_account_api.dart';
import 'admin_pending_attempt_store.dart';
import 'cloudflare_admin_repository.dart'
    show cloudflareTransactionFactKeys, validateCloudflareTransactionFacts;
import 'cloudflare_admin_session.dart';

part 'cloudflare_admin_reconciliation_models.dart';

class CloudflareReconciliationApi {
  CloudflareReconciliationApi(this.session, {this.pendingStore})
    : _authority = session.user?.authorityKey;
  final CloudflareAdminSession session;
  final AdminPendingAttemptStore? pendingStore;
  final Object? _authority;
  void _allow(String permission) {
    final user = session.user;
    if (_authority == null ||
        _authority != user?.authorityKey ||
        user?.permissions.contains(permission) != true ||
        permission == 'reconciliations.review' &&
            user?.role == AdminAccountRole.staff) {
      throw const AdminAccountException(
        'This reconciliation action is unavailable to your current account.',
      );
    }
  }

  String _query(Map<String, String> values) =>
      Uri(queryParameters: values).query;
  void _paging(int offset, int limit, String search) {
    if (offset < 0 ||
        offset > 2147483647 ||
        limit < 1 ||
        limit > 100 ||
        !_text(search, maximum: 200)) {
      throw const FormatException('Invalid reconciliation filter.');
    }
  }

  Future<Map<String, dynamic>> _read(String path) async {
    _allow('reconciliations.read');
    final result = await session.request(
      'reconciliations$path',
      authenticated: true,
    );
    _allow('reconciliations.read');
    return result;
  }

  Future<ReconciliationPage<ReconciliationTransaction>> queue({
    String search = '',
    String verification = '',
    String allocation = '',
    int offset = 0,
    int limit = 25,
  }) async {
    _paging(offset, limit, search);
    if (!{
          '',
          'pending',
          'confirmation_recorded',
          'evidence_conflict',
        }.contains(verification) ||
        !{'', 'unallocated', 'partially_allocated'}.contains(allocation)) {
      throw const FormatException('Invalid reconciliation status.');
    }
    final result = await _read(
      '?${_query({'limit': '$limit', 'offset': '$offset', if (search.isNotEmpty) 'search': search, if (verification.isNotEmpty) 'verification_status': verification, if (allocation.isNotEmpty) 'allocation_status': allocation})}',
    );
    final page = ReconciliationPage.parse(
      result,
      ReconciliationTransaction.parse,
    );
    if (page.offset != offset ||
        page.limit != limit ||
        page.rows.map((row) => row.id).toSet().length != page.rows.length ||
        page.rows.any(
          (row) =>
              row.remaining == 0 ||
              row.values['verification_status'] == 'rejection_recorded' ||
              verification.isNotEmpty &&
                  row.values['verification_status'] != verification ||
              allocation.isNotEmpty &&
                  row.values['allocation_status'] != allocation,
        )) {
      _invalid();
    }
    return page;
  }

  Future<ReconciliationDetail> detail(
    String id, {
    String? relation,
    int offset = 0,
    int limit = 25,
  }) async {
    _paging(offset, limit, '');
    if (!_id(id) ||
        relation != null && !reconciliationRelations.contains(relation)) {
      throw const FormatException('Select a valid reconciliation record.');
    }
    final result = await _read(
      '/$id?${_query({'limit': '$limit', 'offset': '$offset', 'related': ?relation})}',
    );
    _keys(result, {
      'resource_type',
      'resource',
      'current_actor_id',
      'can_propose',
      'can_review',
      'related',
    });
    if (result['resource_type'] != 'reconciliations' ||
        result['current_actor_id'] != session.user?.id ||
        result['can_propose'] is! bool ||
        result['can_review'] is! bool ||
        result['can_propose'] == true &&
            session.user?.permissions.contains('reconciliations.propose') !=
                true ||
        result['can_review'] == true &&
            (session.user?.permissions.contains('reconciliations.review') !=
                    true ||
                session.user?.role == AdminAccountRole.staff)) {
      _invalid();
    }
    final transaction = ReconciliationTransaction.parse(
      _map(result['resource']),
    );
    if (transaction.id != id) _invalid();
    final raw = _map(result['related']);
    final expected = relation == null ? reconciliationRelations : {relation};
    _keys(raw, expected);
    final related = <String, ReconciliationPage<Map<String, dynamic>>>{};
    for (final kind in expected) {
      final page = ReconciliationPage.parse(
        _map(raw[kind]),
        (row) => _relatedRow(kind, row, id),
      );
      if (page.offset != offset ||
          page.limit != limit ||
          page.rows.map((row) => row['id']).toSet().length !=
              page.rows.length) {
        _invalid();
      }
      related[kind] = page;
    }
    return ReconciliationDetail(
      transaction,
      result['current_actor_id'] as String,
      result['can_propose'] as bool,
      result['can_review'] as bool,
      Map.unmodifiable(related),
    );
  }

  Future<ReconciliationPage<ReconciliationMember>> members(
    String transactionId, {
    String search = '',
    int offset = 0,
    int limit = 25,
  }) async {
    _paging(offset, limit, search);
    if (!_id(transactionId)) {
      throw const FormatException('Select a valid transaction.');
    }
    final result = await _read(
      '/members?${_query({'transaction_id': transactionId, 'search': search, 'limit': '$limit', 'offset': '$offset'})}',
    );
    final page = ReconciliationPage.parse(result, ReconciliationMember.parse);
    if (page.offset != offset ||
        page.limit != limit ||
        page.rows.map((row) => '${row.groupId}/${row.id}').toSet().length !=
            page.rows.length) {
      _invalid();
    }
    return page;
  }

  ReconciliationAttempt propose(
    ReconciliationTransaction transaction,
    ReconciliationMember member,
    int amount,
    String reason,
  ) {
    _allow('reconciliations.propose');
    if (member.groupId != transaction.groupId ||
        !member.identity.eligible ||
        amount < 1 ||
        amount > transaction.remaining ||
        !_integer(amount, minimum: 1) ||
        !_text(reason, minimum: 8)) {
      throw const FormatException(
        'Confirm a current member, an available whole amount, and a reason of at least 8 characters.',
      );
    }
    return _attempt(
      '/${transaction.id}/proposals',
      'reconciliations.propose',
      {
        'member_user_id': member.id,
        'amount_rwf': amount,
        'expected_transaction_version': transaction.version,
        'expected_member_version': member.memberVersion,
        'expected_membership_version': member.membershipVersion,
        'expected_payment_identity': member.identity.json,
        'reason': reason.trim(),
      },
      transaction.id,
      null,
      member.publicId,
    );
  }

  ReconciliationAttempt review(
    ReconciliationTransaction transaction,
    ReconciliationProposal proposal,
    String outcome,
    String reason, {
    ReconciliationMember? currentMember,
  }) {
    _allow('reconciliations.review');
    if (!proposal.independent(session.user!.id) ||
        proposal.values['transaction_id'] != transaction.id ||
        !{'approved', 'rejected'}.contains(outcome) ||
        !_text(reason, minimum: 8) ||
        outcome == 'approved' &&
            !proposal.currentFor(transaction, currentMember)) {
      throw const FormatException(
        'An independent review requires current confirmed evidence and a recorded reason.',
      );
    }
    return _attempt(
      '/proposals/${proposal.id}/reviews',
      'reconciliations.review',
      {
        'outcome': outcome,
        'expected_proposal_version': proposal.version,
        'expected_transaction_version': transaction.version,
        'reason': reason.trim(),
      },
      transaction.id,
      proposal.id,
      proposal.values['public_id'] as String?,
    );
  }

  ReconciliationAttempt _attempt(
    String path,
    String permission,
    Map<String, dynamic> body,
    String transactionId, [
    String? proposalId,
    String? memberPublicId,
  ]) => ReconciliationAttempt._(
    const Uuid().v4(),
    path,
    permission,
    _pendingSchema.canonical({'body': body})['body'] as Map<String, dynamic>,
    _authority!,
    transactionId,
    proposalId,
    memberPublicId,
  );

  /// Rehydration validates retained financial intent but never sends it.
  /// Its original key stays locked until lookup and an explicit fresh review.
  ReconciliationAttempt? restorePending(String transactionId) {
    _allow('reconciliations.read');
    final checkpoint = pendingStore?.restore(
      family: 'reconciliation',
      resourceId: transactionId,
      schema: _pendingSchema,
    );
    if (checkpoint == null) return null;
    try {
      final intent = checkpoint.intent, body = _map(checkpoint.intent['body']);
      final review = checkpoint.permission == 'reconciliations.review';
      if (!{
            'reconciliations.propose',
            'reconciliations.review',
          }.contains(checkpoint.permission) ||
          !_id(transactionId) ||
          intent['transaction_id'] != transactionId ||
          (intent['member_public_id'] != null &&
              !(intent['member_public_id'] is String &&
                  RegExp(
                    r'^\d{6}$',
                  ).hasMatch(intent['member_public_id'] as String))) ||
          intent['path'] !=
              (review
                  ? '/proposals/${intent['proposal_id']}/reviews'
                  : '/$transactionId/proposals') ||
          (review
              ? !_id(intent['proposal_id'])
              : intent['proposal_id'] != null)) {
        _invalid();
      }
      _allow(checkpoint.permission);
      _keys(
        body,
        review
            ? {
                'outcome',
                'expected_proposal_version',
                'expected_transaction_version',
                'reason',
              }
            : {
                'member_user_id',
                'amount_rwf',
                'expected_transaction_version',
                'expected_member_version',
                'expected_membership_version',
                'expected_payment_identity',
                'reason',
              },
      );
      if (!_integer(body['expected_transaction_version'], minimum: 1) ||
          !_text(body['reason'], minimum: 8) ||
          (review
              ? !{'approved', 'rejected'}.contains(body['outcome']) ||
                    body['expected_proposal_version'] != 1
              : !_id(body['member_user_id']) ||
                    !_integer(body['amount_rwf'], minimum: 1) ||
                    !_integer(body['expected_member_version'], minimum: 1) ||
                    !_integer(
                      body['expected_membership_version'],
                      minimum: 1,
                    ) ||
                    !ReconciliationPaymentIdentity.parse(
                      _map(body['expected_payment_identity']),
                    ).eligible)) {
        _invalid();
      }
      return ReconciliationAttempt._(
          checkpoint.requestKey,
          intent['path'] as String,
          checkpoint.permission,
          Map<String, dynamic>.unmodifiable(body),
          _authority!,
          transactionId,
          intent['proposal_id'] as String?,
          intent['member_public_id'] as String?,
        )
        .._submitted = true
        .._needsReconfirmation = true;
    } catch (_) {
      pendingStore?.clear(family: 'reconciliation', resourceId: transactionId);
      rethrow;
    }
  }

  void reconfirmRestored(
    ReconciliationAttempt attempt,
    ReconciliationTransaction transaction, {
    ReconciliationMember? member,
    ReconciliationProposal? proposal,
    required bool confirmationReviewed,
  }) {
    _owns(attempt);
    if (!attempt._needsReconfirmation ||
        !attempt._retryAllowed ||
        !confirmationReviewed) {
      throw const AdminAccountException(
        'Check the original request and explicitly review its confirmation before retrying.',
      );
    }
    final expected = attempt.proposalId == null
        ? (member == null
              ? null
              : propose(
                  transaction,
                  member,
                  attempt.body['amount_rwf'] as int,
                  attempt.body['reason'] as String,
                ))
        : (proposal == null
              ? null
              : review(
                  transaction,
                  proposal,
                  attempt.body['outcome'] as String,
                  attempt.body['reason'] as String,
                  currentMember: member,
                ));
    if (expected == null ||
        expected.transactionId != attempt.transactionId ||
        expected.proposalId != attempt.proposalId ||
        jsonEncode(_pendingSchema.canonical({'body': expected.body})['body']) !=
            jsonEncode(
              _pendingSchema.canonical({'body': attempt.body})['body'],
            )) {
      throw const FormatException(
        'The original confirmation differs from the current record. Refresh and resolve the changed identity or version.',
      );
    }
    attempt._needsReconfirmation = false;
  }

  Map<String, dynamic> _retainedIntent(ReconciliationAttempt attempt) => {
    'path': attempt.path,
    'transaction_id': attempt.transactionId,
    'proposal_id': attempt.proposalId,
    'member_public_id': attempt.memberPublicId,
    'body': attempt.body,
  };
  void _owns(ReconciliationAttempt attempt) {
    _allow(attempt.permission);
    if (_authority != attempt.authority) {
      throw const AdminAccountException(
        'Reopen this record with the original account before checking its request.',
      );
    }
  }

  ReconciliationReceipt _receipt(
    Map<String, dynamic> data,
    ReconciliationAttempt attempt,
  ) {
    final receipt = ReconciliationReceipt.parse(data);
    if (receipt.values['transaction_id'] != attempt.transactionId ||
        attempt.proposalId != null &&
            receipt.proposalId != attempt.proposalId ||
        receipt.status != (attempt.body['outcome'] ?? 'pending')) {
      _invalid();
    }
    return receipt;
  }

  Future<ReconciliationReceipt> submit(ReconciliationAttempt attempt) async {
    _owns(attempt);
    if (attempt._completed || attempt._submitted && !attempt._retryAllowed) {
      throw const AdminAccountException(
        'Check the original request. A retry needs an authoritative not-found result.',
      );
    }
    if (attempt._needsReconfirmation) {
      throw const AdminAccountException(
        'Review the restored confirmation before retrying its original request.',
      );
    }
    pendingStore?.retain(
      family: 'reconciliation',
      resourceId: attempt.transactionId,
      requestKey: attempt.key,
      permission: attempt.permission,
      intent: _retainedIntent(attempt),
      schema: _pendingSchema,
    );
    attempt._submitted = true;
    attempt._retryAllowed = false;
    late Map<String, dynamic> result;
    try {
      result = await session.request(
        'reconciliations${attempt.path}',
        authenticated: true,
        method: 'POST',
        body: attempt.body,
        idempotencyKey: attempt.key,
      );
    } on CloudflareAdminRequestException catch (error) {
      if (!error.outcomeUnknown && error.code != 'request_pending') {
        pendingStore?.clear(
          family: 'reconciliation',
          resourceId: attempt.transactionId,
        );
      }
      rethrow;
    }
    _owns(attempt);
    try {
      final receipt = _receipt(result, attempt);
      attempt._completed = true;
      pendingStore?.clear(
        family: 'reconciliation',
        resourceId: attempt.transactionId,
      );
      return receipt;
    } on FormatException {
      throw const CloudflareAdminRequestException(
        'The response did not confirm the operation. Check the original request receipt.',
        outcomeUnknown: true,
      );
    }
  }

  Future<ReconciliationLookup> lookup(ReconciliationAttempt attempt) async {
    _owns(attempt);
    // A prior not-found receipt cannot authorize retry after a newer pending,
    // failed or unavailable lookup.
    attempt._retryAllowed = false;
    final result = await _read('/requests/${attempt.key}');
    if (result['status'] == 'not_found') {
      _keys(result, {'status'});
      if (attempt._completed) _invalid();
      attempt._retryAllowed = true;
      return const ReconciliationLookup('not_found', null);
    }
    _keys(result, {'status', 'request_id', 'receipt'});
    if (!_id(result['request_id']) ||
        !{'pending', 'succeeded', 'failed'}.contains(result['status'])) {
      _invalid();
    }
    if (result['status'] == 'succeeded') {
      final receipt = _receipt(_map(result['receipt']), attempt);
      if (receipt.values['request_id'] != result['request_id']) _invalid();
      attempt._completed = true;
      attempt._retryAllowed = false;
      pendingStore?.clear(
        family: 'reconciliation',
        resourceId: attempt.transactionId,
      );
      return ReconciliationLookup('succeeded', receipt);
    }
    if (result['status'] == 'pending' && result['receipt'] != null) _invalid();
    return ReconciliationLookup(result['status'] as String, null);
  }
}
