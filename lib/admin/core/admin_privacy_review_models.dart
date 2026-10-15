import 'dart:convert';

Never privacyReviewInvalid() =>
    throw const FormatException('Privacy review evidence is unavailable.');

String privacyReviewUuid(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      ).hasMatch(value)) {
    privacyReviewInvalid();
  }
  return value;
}

Map<String, dynamic> _map(Object? value, Set<String> keys) {
  if (value is! Map ||
      value.keys.any((k) => k is! String) ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    privacyReviewInvalid();
  }
  return Map<String, dynamic>.unmodifiable(value);
}

int _integer(Object? value, {int minimum = 0, int maximum = 1000000000}) {
  if (value is! int || value < minimum || value > maximum) {
    privacyReviewInvalid();
  }
  return value;
}

DateTime _utc(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$',
      ).hasMatch(value)) {
    privacyReviewInvalid();
  }
  final date = DateTime.tryParse(value);
  if (date == null ||
      !date.isUtc ||
      date.toIso8601String().substring(0, 19) != value.substring(0, 19)) {
    privacyReviewInvalid();
  }
  return date;
}

const _flags = {
  'policy_acceptance_granted',
  'destructive_execution_available',
  'erasure_completed',
  'account_access_restricted',
  'auth_removed',
  'processor_operation_started',
};
const _envelopeKeys = {
  'contract_version',
  'scope',
  'checked_at',
  'completion',
  'blocking_reason',
  ..._flags,
};
void _identity(Map<String, dynamic> row) {
  if (row['contract_version'] != 1 ||
      row['contract_version'] is! int ||
      row['scope'] != 'account_privacy_review_only') {
    privacyReviewInvalid();
  }
}

void _falseFlags(Map<String, dynamic> row, Iterable<String> flags) {
  if (flags.any((k) => row[k] != false)) privacyReviewInvalid();
}

class AdminPrivacyReviewEvidence {
  AdminPrivacyReviewEvidence(Map<String, dynamic> row)
    : checkedAt = _utc(row['checked_at']) {
    _identity(row);
    _falseFlags(row, _flags);
    if (row['completion'] != 'blocked' ||
        row['blocking_reason'] != 'policy_authority_unavailable') {
      privacyReviewInvalid();
    }
  }
  final DateTime checkedAt;
  bool fresh(DateTime now) =>
      !now.toUtc().isBefore(checkedAt) &&
      now.toUtc().difference(checkedAt) < const Duration(minutes: 10);
}

enum AdminPrivacyReviewState {
  notStarted('not_started', 'Not started'),
  awaitingReview('awaiting_review', 'Awaiting review'),
  claimActive('claim_active', 'Review in progress'),
  claimExpired('claim_expired', 'Review claim expired'),
  blocked('blocked', 'Waiting for approved policy');

  const AdminPrivacyReviewState(this.wire, this.label);
  final String wire, label;
  static AdminPrivacyReviewState parse(Object? value) =>
      values.firstWhere((s) => s.wire == value, orElse: privacyReviewInvalid);
}

class AdminPrivacyReviewItem {
  AdminPrivacyReviewItem._(
    this.requestId,
    this.acceptedAt,
    this.revision,
    this.state,
    this.claimExpiresAt,
    this.outcomeRecordedAt,
  );
  factory AdminPrivacyReviewItem.parse(Object? value, DateTime checkedAt) {
    final r = _map(value, {
      'request_id',
      'accepted_at',
      'revision',
      'review_state',
      'claim_expires_at',
      'outcome_code',
      'outcome_recorded_at',
    });
    final id = privacyReviewUuid(r['request_id']),
        at = _utc(r['accepted_at']),
        revision = _integer(r['revision']),
        state = AdminPrivacyReviewState.parse(r['review_state']),
        expiry = r['claim_expires_at'] == null
            ? null
            : _utc(r['claim_expires_at']),
        outcome = r['outcome_recorded_at'] == null
            ? null
            : _utc(r['outcome_recorded_at']);
    if (at.isAfter(checkedAt)) privacyReviewInvalid();
    if (state == AdminPrivacyReviewState.notStarted ||
        state == AdminPrivacyReviewState.awaitingReview) {
      if (revision != 0 ||
          expiry != null ||
          outcome != null ||
          r['outcome_code'] != null) {
        privacyReviewInvalid();
      }
    } else if (state == AdminPrivacyReviewState.blocked) {
      if (revision < 2 ||
          expiry == null ||
          outcome == null ||
          r['outcome_code'] != 'policy_authority_unavailable' ||
          outcome.isBefore(at) ||
          outcome.isAfter(checkedAt) ||
          !outcome.isBefore(expiry)) {
        privacyReviewInvalid();
      }
    } else if (revision < 1 ||
        expiry == null ||
        outcome != null ||
        r['outcome_code'] != null ||
        (state == AdminPrivacyReviewState.claimActive) !=
            expiry.isAfter(checkedAt)) {
      privacyReviewInvalid();
    }
    return AdminPrivacyReviewItem._(id, at, revision, state, expiry, outcome);
  }
  final String requestId;
  final DateTime acceptedAt;
  final int revision;
  final AdminPrivacyReviewState state;
  final DateTime? claimExpiresAt, outcomeRecordedAt;
}

class AdminPrivacyReviewCursor {
  AdminPrivacyReviewCursor(this.acceptedAt, this.requestId);
  factory AdminPrivacyReviewCursor.parse(Object? value) {
    final r = _map(value, {'accepted_at', 'request_id'});
    return AdminPrivacyReviewCursor(
      _utc(r['accepted_at']),
      privacyReviewUuid(r['request_id']),
    );
  }
  final DateTime acceptedAt;
  final String requestId;
  bool before(AdminPrivacyReviewItem i) =>
      i.acceptedAt.isBefore(acceptedAt) ||
      i.acceptedAt == acceptedAt && i.requestId.compareTo(requestId) < 0;
}

class AdminPrivacyReviewPage extends AdminPrivacyReviewEvidence {
  AdminPrivacyReviewPage._(super.row, this.items, this.next);
  factory AdminPrivacyReviewPage.parse(
    Object? value, {
    required int limit,
    AdminPrivacyReviewCursor? before,
  }) {
    final r = _map(value, {..._envelopeKeys, 'items', 'limit', 'next_cursor'}),
        evidence = AdminPrivacyReviewEvidence(r);
    if (_integer(r['limit'], minimum: 1, maximum: 100) != limit ||
        r['items'] is! List) {
      privacyReviewInvalid();
    }
    final items = [
      for (final item in r['items'] as List)
        AdminPrivacyReviewItem.parse(item, evidence.checkedAt),
    ];
    if (items.length > limit ||
        items.map((i) => i.requestId).toSet().length != items.length) {
      privacyReviewInvalid();
    }
    var cursor = before;
    for (final i in items) {
      if (cursor != null && !cursor.before(i)) privacyReviewInvalid();
      cursor = AdminPrivacyReviewCursor(i.acceptedAt, i.requestId);
    }
    final next = r['next_cursor'] == null
        ? null
        : AdminPrivacyReviewCursor.parse(r['next_cursor']);
    if (next != null &&
        (items.length != limit ||
            next.requestId != items.last.requestId ||
            next.acceptedAt != items.last.acceptedAt)) {
      privacyReviewInvalid();
    }
    return AdminPrivacyReviewPage._(r, List.unmodifiable(items), next);
  }
  final List<AdminPrivacyReviewItem> items;
  final AdminPrivacyReviewCursor? next;
}

class AdminPrivacyReviewClaim {
  AdminPrivacyReviewClaim._(
    this.requestId,
    this.operationId,
    this.claimId,
    this.revision,
    this.fence,
    this.claimedAt,
    this.expiresAt,
  );
  factory AdminPrivacyReviewClaim.parse(Object? value) {
    final r = _map(value, {
      'contract_version',
      'scope',
      'request_id',
      'claim_request_id',
      'claim_id',
      'revision',
      'fence',
      'claimed_at',
      'expires_at',
      'policy_acceptance_granted',
      'destructive_execution_available',
      'erasure_completed',
    });
    _identity(r);
    _falseFlags(r, const {
      'policy_acceptance_granted',
      'destructive_execution_available',
      'erasure_completed',
    });
    final claimed = _utc(r['claimed_at']), expires = _utc(r['expires_at']);
    final duration = expires.difference(claimed);
    if (duration < const Duration(seconds: 1) ||
        duration > const Duration(seconds: 120)) {
      privacyReviewInvalid();
    }
    final revision = _integer(r['revision'], minimum: 1),
        fence = _integer(r['fence'], minimum: 1);
    if (fence > revision) privacyReviewInvalid();
    return AdminPrivacyReviewClaim._(
      privacyReviewUuid(r['request_id']),
      privacyReviewUuid(r['claim_request_id']),
      privacyReviewUuid(r['claim_id']),
      revision,
      fence,
      claimed,
      expires,
    );
  }
  final String requestId, operationId, claimId;
  final int revision, fence;
  final DateTime claimedAt, expiresAt;
}

class AdminPrivacyReviewOutcome {
  AdminPrivacyReviewOutcome._(
    this.requestId,
    this.operationId,
    this.claimId,
    this.revision,
    this.fence,
    this.recordedAt,
  );
  factory AdminPrivacyReviewOutcome.parse(Object? value) {
    final r = _map(value, {
      'contract_version',
      'scope',
      'request_id',
      'outcome_request_id',
      'claim_id',
      'revision',
      'fence',
      'outcome_code',
      'recorded_at',
      'completion',
      ..._flags,
    });
    _identity(r);
    _falseFlags(r, _flags);
    if (r['outcome_code'] != 'policy_authority_unavailable' ||
        r['completion'] != 'blocked') {
      privacyReviewInvalid();
    }
    return AdminPrivacyReviewOutcome._(
      privacyReviewUuid(r['request_id']),
      privacyReviewUuid(r['outcome_request_id']),
      privacyReviewUuid(r['claim_id']),
      _integer(r['revision'], minimum: 2),
      _integer(r['fence'], minimum: 1),
      _utc(r['recorded_at']),
    );
  }
  final String requestId, operationId, claimId;
  final int revision, fence;
  final DateTime recordedAt;
}

class AdminPrivacyReviewDetail extends AdminPrivacyReviewEvidence {
  AdminPrivacyReviewDetail._(
    super.row,
    this.item,
    this.claim,
    this.outcome,
    this.claimAuthorityCurrent,
  );
  factory AdminPrivacyReviewDetail.parse(Object? value, String requestId) {
    final r = _map(value, {
          ..._envelopeKeys,
          'item',
          'own_claim_receipt',
          'own_outcome_receipt',
          'own_claim_authority_current',
        }),
        e = AdminPrivacyReviewEvidence(r);
    final item = r['item'] == null
            ? null
            : AdminPrivacyReviewItem.parse(r['item'], e.checkedAt),
        claim = r['own_claim_receipt'] == null
            ? null
            : AdminPrivacyReviewClaim.parse(r['own_claim_receipt']),
        outcome = r['own_outcome_receipt'] == null
            ? null
            : AdminPrivacyReviewOutcome.parse(r['own_outcome_receipt']);
    if (r['own_claim_authority_current'] is! bool ||
        item?.requestId != (item == null ? null : requestId) ||
        claim != null && claim.requestId != requestId ||
        outcome != null && outcome.requestId != requestId ||
        item == null &&
            (claim != null ||
                outcome != null ||
                r['own_claim_authority_current'] != false)) {
      privacyReviewInvalid();
    }
    final current = r['own_claim_authority_current'] as bool;
    if (current &&
        (item?.state != AdminPrivacyReviewState.claimActive ||
            claim == null ||
            claim.revision != item!.revision ||
            claim.expiresAt != item.claimExpiresAt ||
            !claim.expiresAt.isAfter(e.checkedAt) ||
            claim.claimedAt.isAfter(e.checkedAt) ||
            claim.claimedAt.isBefore(item.acceptedAt) ||
            outcome != null)) {
      privacyReviewInvalid();
    }
    if (outcome != null &&
        (item?.state != AdminPrivacyReviewState.blocked ||
            outcome.revision != item!.revision ||
            outcome.recordedAt != item.outcomeRecordedAt ||
            claim == null ||
            outcome.claimId != claim.claimId ||
            outcome.fence != claim.fence ||
            outcome.revision != claim.revision + 1 ||
            outcome.recordedAt.isBefore(claim.claimedAt) ||
            !outcome.recordedAt.isBefore(claim.expiresAt))) {
      privacyReviewInvalid();
    }
    return AdminPrivacyReviewDetail._(r, item, claim, outcome, current);
  }
  final AdminPrivacyReviewItem? item;
  final AdminPrivacyReviewClaim? claim;
  final AdminPrivacyReviewOutcome? outcome;
  final bool claimAuthorityCurrent;
  bool canStart(DateTime now) =>
      fresh(now) &&
      item != null &&
      {
        AdminPrivacyReviewState.notStarted,
        AdminPrivacyReviewState.awaitingReview,
        AdminPrivacyReviewState.claimExpired,
      }.contains(item!.state) &&
      item!.revision < 999999999;
  bool canRecord(DateTime now) =>
      fresh(now) &&
      claimAuthorityCurrent &&
      claim != null &&
      claim!.expiresAt.isAfter(now.toUtc());
}

enum AdminPrivacyReviewOperationKind { claim, outcome }

/// Contains only the original review command, never subject or contact data.
class AdminPrivacyReviewIntent {
  AdminPrivacyReviewIntent._(
    this.kind,
    this.operationId,
    this.actorId,
    this.sessionId,
    this.requestId,
    this.parameters,
  );
  factory AdminPrivacyReviewIntent.claim({
    required String operationId,
    required String actorId,
    required String sessionId,
    required AdminPrivacyReviewDetail detail,
  }) => AdminPrivacyReviewIntent._(
    AdminPrivacyReviewOperationKind.claim,
    privacyReviewUuid(operationId),
    privacyReviewUuid(actorId),
    privacyReviewUuid(sessionId),
    detail.item!.requestId,
    Map.unmodifiable({
      'p_request_id': detail.item!.requestId,
      'p_claim_request_id': operationId,
      'p_expected_revision': detail.item!.revision,
      'p_lease_seconds': 60,
    }),
  );
  factory AdminPrivacyReviewIntent.outcome({
    required String operationId,
    required String actorId,
    required String sessionId,
    required AdminPrivacyReviewDetail detail,
  }) => AdminPrivacyReviewIntent._(
    AdminPrivacyReviewOperationKind.outcome,
    privacyReviewUuid(operationId),
    privacyReviewUuid(actorId),
    privacyReviewUuid(sessionId),
    detail.item!.requestId,
    Map.unmodifiable({
      'p_outcome_request_id': operationId,
      'p_claim_id': detail.claim!.claimId,
      'p_fence': detail.claim!.fence,
      'p_outcome_code': 'policy_authority_unavailable',
    }),
  );
  factory AdminPrivacyReviewIntent.parse(Object? value) {
    final r = _map(value, {
      'kind',
      'operation_id',
      'actor_id',
      'session_id',
      'request_id',
      'parameters',
    });
    final kind = AdminPrivacyReviewOperationKind.values.firstWhere(
          (k) => k.name == r['kind'],
          orElse: privacyReviewInvalid,
        ),
        id = privacyReviewUuid(r['operation_id']),
        request = privacyReviewUuid(r['request_id']),
        p = _map(
          r['parameters'],
          kind == AdminPrivacyReviewOperationKind.claim
              ? {
                  'p_request_id',
                  'p_claim_request_id',
                  'p_expected_revision',
                  'p_lease_seconds',
                }
              : {
                  'p_outcome_request_id',
                  'p_claim_id',
                  'p_fence',
                  'p_outcome_code',
                },
        );
    if (kind == AdminPrivacyReviewOperationKind.claim) {
      if (privacyReviewUuid(p['p_request_id']) != request ||
          privacyReviewUuid(p['p_claim_request_id']) != id ||
          _integer(p['p_lease_seconds'], minimum: 60, maximum: 60) != 60) {
        privacyReviewInvalid();
      }
      _integer(p['p_expected_revision'], maximum: 999999998);
    } else {
      if (privacyReviewUuid(p['p_outcome_request_id']) != id ||
          p['p_outcome_code'] != 'policy_authority_unavailable') {
        privacyReviewInvalid();
      }
      privacyReviewUuid(p['p_claim_id']);
      _integer(p['p_fence'], minimum: 1);
    }
    return AdminPrivacyReviewIntent._(
      kind,
      id,
      privacyReviewUuid(r['actor_id']),
      privacyReviewUuid(r['session_id']),
      request,
      p,
    );
  }
  final AdminPrivacyReviewOperationKind kind;
  final String operationId, actorId, sessionId, requestId;
  final Map<String, dynamic> parameters;
  String get rpcName => kind == AdminPrivacyReviewOperationKind.claim
      ? 'admin_claim_account_deletion_review_v1'
      : 'admin_record_account_deletion_review_v1';
  Map<String, dynamic> get row => {
    'kind': kind.name,
    'operation_id': operationId,
    'actor_id': actorId,
    'session_id': sessionId,
    'request_id': requestId,
    'parameters': parameters,
  };
  String get fingerprint => jsonEncode(row);
  bool applicable(AdminPrivacyReviewDetail d, DateTime now) =>
      d.item?.requestId == requestId &&
      (kind == AdminPrivacyReviewOperationKind.claim
          ? d.canStart(now) &&
                d.item!.revision == parameters['p_expected_revision']
          : d.canRecord(now) &&
                d.claim!.claimId == parameters['p_claim_id'] &&
                d.claim!.fence == parameters['p_fence']);
  void checkReceipt(Object receipt) {
    if (kind == AdminPrivacyReviewOperationKind.claim) {
      if (receipt is! AdminPrivacyReviewClaim ||
          receipt.operationId != operationId ||
          receipt.requestId != requestId ||
          receipt.revision != (parameters['p_expected_revision'] as int) + 1 ||
          receipt.expiresAt.difference(receipt.claimedAt) !=
              Duration(seconds: parameters['p_lease_seconds'] as int)) {
        privacyReviewInvalid();
      }
    } else if (receipt is! AdminPrivacyReviewOutcome ||
        receipt.operationId != operationId ||
        receipt.requestId != requestId ||
        receipt.claimId != parameters['p_claim_id'] ||
        receipt.fence != parameters['p_fence']) {
      privacyReviewInvalid();
    }
  }
}

class AdminPrivacyReviewOperation extends AdminPrivacyReviewEvidence {
  AdminPrivacyReviewOperation._(
    super.row,
    this.observed,
    this.receipt,
    this.claimAuthorityCurrent,
  );
  factory AdminPrivacyReviewOperation.parse(
    Object? value,
    AdminPrivacyReviewIntent intent,
  ) {
    final r = _map(value, {
      ..._envelopeKeys,
      'operation_kind',
      'operation_id',
      'observed',
      'receipt',
      'claim_authority_current',
    });
    if (r['operation_kind'] != intent.kind.name ||
        r['operation_id'] != intent.operationId ||
        r['observed'] is! bool ||
        r['claim_authority_current'] is! bool) {
      privacyReviewInvalid();
    }
    final observed = r['observed'] as bool;
    if (observed != (r['receipt'] != null) ||
        (!observed || intent.kind == AdminPrivacyReviewOperationKind.outcome) &&
            r['claim_authority_current'] != false) {
      privacyReviewInvalid();
    }
    final receipt = !observed
        ? null
        : intent.kind == AdminPrivacyReviewOperationKind.claim
        ? AdminPrivacyReviewClaim.parse(r['receipt'])
        : AdminPrivacyReviewOutcome.parse(r['receipt']);
    if (receipt != null) intent.checkReceipt(receipt);
    final result = AdminPrivacyReviewOperation._(
      r,
      observed,
      receipt,
      r['claim_authority_current'] as bool,
    );
    if (result.claimAuthorityCurrent &&
        (receipt is! AdminPrivacyReviewClaim ||
            !receipt.expiresAt.isAfter(result.checkedAt))) {
      privacyReviewInvalid();
    }
    return result;
  }
  final bool observed, claimAuthorityCurrent;
  final Object? receipt;
}
