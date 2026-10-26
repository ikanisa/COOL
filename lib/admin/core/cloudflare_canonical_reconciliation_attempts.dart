part of 'cloudflare_canonical_reconciliation_api.dart';

const _pendingFamily = 'canonical-reconciliation';
const _pendingSchema = AdminPendingAttemptSchema(
  fields: {'kind', 'path', 'transaction_id', 'proposal_id', 'body'},
  nestedFields: {
    'body': {
      'member_user_id',
      'amount_rwf',
      'expected_transaction_version',
      'expected_member_version',
      'expected_membership_version',
      'expected_payment_identity',
      'reason',
      'outcome',
      'expected_proposal_version',
    },
    'body.expected_payment_identity': {
      'display_name',
      'momo_provider',
      'momo_number',
      'momo_pay_code',
    },
  },
);

class CanonicalFinancialAttempt {
  CanonicalFinancialAttempt._(
    this.key,
    this.transactionId,
    this.proposalId,
    this.kind,
    this.permission,
    this.path,
    Map<String, dynamic> body,
    this.authority,
  ) : body =
          _pendingSchema.canonical({'body': body})['body']
              as Map<String, dynamic>;
  final String key, transactionId, kind, permission, path;
  final String? proposalId;
  final Map<String, dynamic> body;
  final Object authority;
  bool _submitted = false, _retryAllowed = false, _completed = false;
  bool get needsLookup => _submitted && !_completed;
  bool get canRetry => _retryAllowed && !_completed;
  Map<String, dynamic> get intent => {
    'kind': kind,
    'path': path,
    'transaction_id': transactionId,
    'proposal_id': proposalId,
    'body': body,
  };
}

class CanonicalFinancialLookup {
  const CanonicalFinancialLookup(this.status, this.receipt);
  final String status;
  final ReconciliationReceipt? receipt;
}

extension CanonicalReconciliationRecovery on CanonicalReconciliationApi {
  void _owned(CanonicalFinancialAttempt attempt, {bool fresh = false}) {
    _user(attempt.permission, fresh: fresh);
    if (attempt.authority != _fence || attempt._completed) {
      throw const AdminAccountException(
        'This request belongs to its original account and verification context.',
      );
    }
  }

  CanonicalFinancialAttempt? restore(String transactionId) {
    _user('reconciliations.read');
    if (!_id(transactionId)) {
      throw const FormatException('Choose a valid payment.');
    }
    final checkpoint = pendingStore?.restore(
      family: _pendingFamily,
      resourceId: transactionId,
      schema: _pendingSchema,
    );
    if (checkpoint == null) return null;
    final value = checkpoint.intent,
        body = _map(value['body']),
        review = value['kind'] == 'review';
    final permission = review
        ? 'reconciliations.review'
        : 'reconciliations.propose';
    _keys(value, const {
      'kind',
      'path',
      'transaction_id',
      'proposal_id',
      'body',
    });
    if (!const {'propose', 'review'}.contains(value['kind']) ||
        value['transaction_id'] != transactionId ||
        checkpoint.permission != permission ||
        !_id(checkpoint.requestKey) ||
        (review ? !_id(value['proposal_id']) : value['proposal_id'] != null) ||
        value['path'] !=
            (review
                ? '/proposals/${value['proposal_id']}/reviews'
                : '/$transactionId/proposals')) {
      _invalid();
    }
    _user(permission);
    _keys(
      body,
      review
          ? const {
              'outcome',
              'expected_proposal_version',
              'expected_transaction_version',
              'reason',
            }
          : const {
              'member_user_id',
              'amount_rwf',
              'expected_transaction_version',
              'expected_member_version',
              'expected_membership_version',
              'expected_payment_identity',
              'reason',
            },
    );
    if (!_int(body['expected_transaction_version'], minimum: 1) ||
        body['reason'] is! String) {
      _invalid();
    }
    _reason(body['reason'] as String);
    if (review) {
      if (!const {'approved', 'rejected'}.contains(body['outcome']) ||
          body['expected_proposal_version'] != 1) {
        _invalid();
      }
    } else if (!_id(body['member_user_id']) ||
        !_int(body['amount_rwf'], minimum: 1) ||
        !_int(body['expected_member_version'], minimum: 1) ||
        !_int(body['expected_membership_version'], minimum: 1) ||
        !ReconciliationPaymentIdentity.parse(
          _map(body['expected_payment_identity']),
        ).eligible) {
      _invalid();
    }
    final attempt = CanonicalFinancialAttempt._(
      checkpoint.requestKey,
      transactionId,
      value['proposal_id'] as String?,
      value['kind'] as String,
      permission,
      value['path'] as String,
      body,
      _fence,
    );
    attempt._submitted = true;
    return attempt;
  }

  ReconciliationReceipt _receipt(
    CanonicalFinancialAttempt attempt,
    Map<String, dynamic> data,
  ) {
    final receipt = ReconciliationReceipt.parse(data),
        review = attempt.kind == 'review';
    if (receipt.sourceModel != 'canonical_evidence_ledger' ||
        data['transaction_id'] != attempt.transactionId ||
        data['request_id'] !=
            canonicalAdminRequestId(
              _user(attempt.permission).principalId!,
              attempt.key,
            ) ||
        (review
            ? receipt.proposalId != attempt.proposalId ||
                  data['proposal_status'] != attempt.body['outcome'] ||
                  data['transaction_version'] !=
                      (attempt.body['expected_transaction_version'] as int) +
                          (attempt.body['outcome'] == 'approved' ? 1 : 0)
            : data['proposal_status'] != 'proposed')) {
      _invalid();
    }
    return receipt;
  }

  void _clear(CanonicalFinancialAttempt attempt) {
    if (pendingStore == null) return;
    final current = pendingStore!.restore(
      family: _pendingFamily,
      resourceId: attempt.transactionId,
      schema: _pendingSchema,
    );
    if (current == null) return;
    if (current.requestKey != attempt.key ||
        jsonEncode(current.intent) !=
            jsonEncode(_pendingSchema.canonical(attempt.intent))) {
      throw const AdminAccountException(
        'The retained request changed. Reopen its status before continuing.',
      );
    }
    pendingStore!.clear(
      family: _pendingFamily,
      resourceId: attempt.transactionId,
    );
  }

  Future<ReconciliationReceipt> submit(
    CanonicalFinancialAttempt attempt, {
    bool confirmedRetry = false,
  }) async {
    _owned(attempt, fresh: true);
    if (attempt._submitted && (!attempt._retryAllowed || !confirmedRetry)) {
      throw const AdminAccountException(
        'Check the original request and review an identical retry explicitly.',
      );
    }
    pendingStore?.retain(
      family: _pendingFamily,
      resourceId: attempt.transactionId,
      requestKey: attempt.key,
      permission: attempt.permission,
      intent: attempt.intent,
      schema: _pendingSchema,
    );
    attempt._submitted = true;
    attempt._retryAllowed = false;
    // Every non-success remains recoverable, including a post-commit authority
    // denial. A denial alone does not prove that an earlier effect rolled back.
    final result = await session.request(
      'reconciliations${attempt.path}',
      body: attempt.body,
      authenticated: true,
      method: 'POST',
      idempotencyKey: attempt.key,
    );
    _owned(attempt);
    final receipt = _receipt(attempt, result);
    _clear(attempt);
    attempt._completed = true;
    return receipt;
  }

  Future<CanonicalFinancialLookup> lookup(
    CanonicalFinancialAttempt attempt,
  ) async {
    _owned(attempt);
    attempt._retryAllowed = false;
    final data = await _get(
      'operations/requests/${attempt.key}',
      permission: 'account.manage',
    );
    _owned(attempt);
    final status = data['status'];
    if (status == 'not_found') {
      _keys(data, const {'contract_version', 'model', 'status'});
      attempt._retryAllowed = true;
      return const CanonicalFinancialLookup('not_found', null);
    }
    _keys(data, const {
      'contract_version',
      'model',
      'status',
      'request_id',
      'receipt',
    });
    if (!_id(data['request_id'])) _invalid();
    if (data['request_id'] !=
        canonicalAdminRequestId(
          _user(attempt.permission).principalId!,
          attempt.key,
        )) {
      _invalid();
    }
    if (status == 'cancelled' && data['receipt'] == null) {
      if (data['request_id'] !=
          canonicalAdminRequestId(
            _user(attempt.permission).principalId!,
            attempt.key,
          )) {
        _invalid();
      }
      _clear(attempt);
      attempt._completed = true;
      return const CanonicalFinancialLookup('cancelled', null);
    }
    if (status == 'unconfirmed' && data['receipt'] == null) {
      return const CanonicalFinancialLookup('unconfirmed', null);
    }
    if (status != 'succeeded') _invalid();
    final receipt = _receipt(attempt, _map(data['receipt']));
    if (data['request_id'] != receipt.values['request_id']) _invalid();
    _clear(attempt);
    attempt._completed = true;
    return CanonicalFinancialLookup('succeeded', receipt);
  }
}
