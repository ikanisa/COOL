import 'admin_receipt_notice_content_models.dart';

void dispatchContract(
  Map<String, dynamic> row, [
  String scope = 'rw_receipt_notice_transport',
]) {
  if (row['contract_version'] is! int ||
      row['contract_version'] != 1 ||
      row['scope'] != scope ||
      row['send_authority'] != false) {
    noticeInvalid();
  }
}

/// A durable record of a validated content request, never current send authority.
class AdminReceiptNoticePreparedReference {
  AdminReceiptNoticePreparedReference._(this.row, this.original, this.recorded);
  final Map<String, dynamic> row;
  final AdminReceiptNoticeIntent original;
  final AdminReceiptNoticeRequest recorded;
  String get actorId => original.actorId;
  String get sessionId => original.sessionId;
  String get originalRequestId => original.requestId;
  String get preparedReviewId => recorded.result!['review_id'] as String;
  String get outboxId => original.inspection.outboxId!;
  String get collectionId => original.inspection.collectionId;
  String get memberRecordId =>
      original.inspection.candidate['member_record_id'] as String;
  String get sourceSnapshotId => original.inspection.sourceSnapshotId!;
  AdminReceiptNoticeFamily get family => original.inspection.family;
  String get bodySha256 => recorded.result!['body_sha256'] as String;
  String get destinationSha256 =>
      recorded.result!['destination_sha256'] as String;
  String get fingerprint => noticeFingerprint(row);
  factory AdminReceiptNoticePreparedReference.fromRecorded({
    required AdminReceiptNoticeInspection inspection,
    required AdminReceiptNoticeRequest recorded,
    required AdminReceiptNoticeIntent original,
    required String actorId,
    required String sessionId,
  }) {
    if (inspection.policy ||
        original.policy ||
        !recorded.recorded ||
        original.actorId != noticeUuid(actorId) ||
        original.sessionId != noticeUuid(sessionId) ||
        noticeFingerprint(inspection.row) !=
            noticeFingerprint(original.inspection.row)) {
      noticeInvalid();
    }
    return AdminReceiptNoticePreparedReference.parse({
      'version': 1,
      'original': original.row,
      'recorded': recorded.result,
    });
  }
  factory AdminReceiptNoticePreparedReference.parse(Object? raw) {
    final row = noticeObject(raw, {'version', 'original', 'recorded'});
    if (row['version'] is! int || row['version'] != 1) noticeInvalid();
    final original = AdminReceiptNoticeIntent.parse(row['original']);
    if (original.policy) noticeInvalid();
    final recorded = AdminReceiptNoticeRequest.recorded(
      row['recorded'],
      original,
    );
    return AdminReceiptNoticePreparedReference._(
      noticeFreeze(row) as Map<String, dynamic>,
      original,
      recorded,
    );
  }
}

class AdminReceiptNoticeDispatchConfiguration {
  AdminReceiptNoticeDispatchConfiguration._(
    this.row,
    this.checkedAt,
    this.validUntil,
  );
  final Map<String, dynamic> row;
  final DateTime checkedAt, validUntil;
  bool get enabled => row['enabled'] as bool;
  int get revision => row['configuration_revision'] as int;
  bool fresh(DateTime now) => noticeFresh(checkedAt, validUntil, now);
  factory AdminReceiptNoticeDispatchConfiguration.parse(Object? raw) {
    final row = noticeObject(raw, {
      'contract_version',
      'scope',
      'enabled',
      'configuration_revision',
      'updated_at',
      'checked_at',
      'sample_valid_until',
      'send_authority',
    });
    dispatchContract(row, 'rw_receipt_notice_configuration');
    if (row['enabled'] is! bool) noticeInvalid();
    noticeInteger(row['configuration_revision'], minimum: 1);
    final checked = noticeTime(row['checked_at']),
        until = noticeTime(row['sample_valid_until']);
    if (noticeTime(row['updated_at']).isAfter(checked) ||
        until.difference(checked) != const Duration(seconds: 60)) {
      noticeInvalid();
    }
    return AdminReceiptNoticeDispatchConfiguration._(
      noticeFreeze(row) as Map<String, dynamic>,
      checked,
      until,
    );
  }
}

const _dispatchCandidateKeys = {
  'reason_code',
  'prepared_review_id',
  'root_outbox_id',
  'notice_family',
  'source_snapshot_id',
  'collection_id',
  'member_record_id',
  'notice_policy_revision',
  'template_sha256',
  'semantic_version',
  'language',
  'source_facts',
  'primary_transport_observation',
  'root_revision',
  'body',
  'body_sha256',
  'destination_sha256',
  'segment_count',
  'primary_receipt_retained',
  'bank_settlement_inferred',
};

class AdminReceiptNoticeDispatchInspection {
  AdminReceiptNoticeDispatchInspection._(
    this.row,
    this.reference,
    this.checkedAt,
    this.validUntil,
  );
  final Map<String, dynamic> row;
  final AdminReceiptNoticePreparedReference reference;
  final DateTime checkedAt, validUntil;
  int get revision => row['transport_revision'] as int;
  String get candidateSha256 => row['candidate_sha256'] as String;
  String get reason => row['reason_code'] as String;
  bool get canApprove => row['can_approve'] as bool;
  bool get dispatchEnabled => row['dispatch_enabled'] as bool;
  Map<String, dynamic> get candidate =>
      row['candidate'] as Map<String, dynamic>;
  bool fresh(DateTime now) => noticeFresh(checkedAt, validUntil, now);
  factory AdminReceiptNoticeDispatchInspection.parse(
    Object? raw,
    AdminReceiptNoticePreparedReference reference,
  ) {
    final row = noticeObject(raw, {
      'contract_version',
      'scope',
      'prepared_review_id',
      'outbox_id',
      'notice_family',
      'transport_revision',
      'candidate',
      'candidate_sha256',
      'reason_code',
      'can_approve',
      'dispatch_enabled',
      'send_authority',
      'checked_at',
      'sample_valid_until',
    });
    dispatchContract(row);
    if (row['prepared_review_id'] != reference.preparedReviewId ||
        row['outbox_id'] != reference.outboxId ||
        row['notice_family'] != reference.family.wire ||
        row['can_approve'] is! bool ||
        row['dispatch_enabled'] is! bool) {
      noticeInvalid();
    }
    noticeInteger(row['transport_revision']);
    noticeHash(
      row['candidate_sha256'],
    ); // Opaque server token: destination is redacted.
    final reason = noticeText(row['reason_code'], maximum: 100),
        rawCandidate = row['candidate'];
    if (rawCandidate is! Map<String, dynamic>) noticeInvalid();
    final c = rawCandidate;
    if (c['reason_code'] == 'notice_review_eligible') {
      noticeObject(c, _dispatchCandidateKeys);
      final old = reference.original.inspection.candidate,
          evidence = old['source_evidence'] as Map;
      if (!const {
            'notice_review_eligible',
            'notice_approval_pending',
            'notice_already_materialized',
          }.contains(reason) ||
          row['can_approve'] != (reason == 'notice_review_eligible') ||
          c['prepared_review_id'] != reference.preparedReviewId ||
          c['root_outbox_id'] != reference.outboxId ||
          c['notice_family'] != reference.family.wire ||
          c['source_snapshot_id'] != reference.sourceSnapshotId ||
          c['collection_id'] != reference.collectionId ||
          c['member_record_id'] != reference.memberRecordId ||
          c['notice_policy_revision'] != old['policy_revision'] ||
          c['template_sha256'] != old['template_sha256'] ||
          c['semantic_version'] != old['semantic_version'] ||
          c['language'] != old['language'] ||
          c['body'] != old['body'] ||
          c['body_sha256'] != reference.bodySha256 ||
          c['destination_sha256'] != reference.destinationSha256 ||
          c['primary_receipt_retained'] != true ||
          c['bank_settlement_inferred'] != false ||
          c['root_revision'] != evidence['root_revision'] ||
          noticeFingerprint(c['source_facts']) !=
              noticeFingerprint(evidence['source_facts']) ||
          noticeFingerprint(c['primary_transport_observation']) !=
              noticeFingerprint(evidence['transport_observation'])) {
        noticeInvalid();
      }
      noticeInteger(c['segment_count'], minimum: 1, maximum: 10);
      if (c['segment_count'] != old['segment_count']) noticeInvalid();
    } else {
      noticeObject(c, {'reason_code'});
      if (noticeText(c['reason_code'], maximum: 100) != reason ||
          row['can_approve'] != false ||
          const {
            'notice_review_eligible',
            'notice_approval_pending',
            'notice_already_materialized',
          }.contains(reason)) {
        noticeInvalid();
      }
    }
    final checked = noticeTime(row['checked_at']),
        until = noticeTime(row['sample_valid_until']);
    final duration = until.difference(checked);
    if (duration < const Duration(seconds: 60) ||
        duration > const Duration(seconds: 65)) {
      noticeInvalid();
    }
    return AdminReceiptNoticeDispatchInspection._(
      noticeFreeze(row) as Map<String, dynamic>,
      reference,
      checked,
      until,
    );
  }
}

enum AdminReceiptNoticeDispatchAction {
  configure('configure_notice_transport'),
  approve('approve_notice_transport'),
  revoke('revoke_notice_transport');

  const AdminReceiptNoticeDispatchAction(this.wire);
  final String wire;
  static AdminReceiptNoticeDispatchAction parse(Object? raw) =>
      values.firstWhere((e) => e.wire == raw, orElse: noticeInvalid);
}

class AdminReceiptNoticeDispatchIntent {
  AdminReceiptNoticeDispatchIntent._(
    this.row,
    this.action,
    this.reference,
    this.inspection,
    this.configuration,
    this.approval,
  );
  final Map<String, dynamic> row;
  final AdminReceiptNoticeDispatchAction action;
  final AdminReceiptNoticePreparedReference? reference;
  final AdminReceiptNoticeDispatchInspection? inspection;
  final AdminReceiptNoticeDispatchConfiguration? configuration;
  final Map<String, dynamic>? approval;
  String get requestId => row['request_id'] as String;
  String get actorId => row['actor_id'] as String;
  String get sessionId => row['session_id'] as String;
  String get fingerprint => row['fingerprint'] as String;
  String get reason => row['reason'] as String;
  bool fresh(DateTime now) =>
      configuration?.fresh(now) ?? inspection!.fresh(now);
  Map<String, dynamic> get parameters => Map.unmodifiable({
    'p_request_id': requestId,
    'p_reason': reason,
    if (action == AdminReceiptNoticeDispatchAction.configure) ...{
      'p_expected_revision': configuration!.revision,
      'p_enabled': row['enabled'],
      'p_expires_at': configuration!.row['sample_valid_until'],
    },
    if (action == AdminReceiptNoticeDispatchAction.approve) ...{
      'p_prepared_review_id': reference!.preparedReviewId,
      'p_expected_transport_revision': inspection!.revision,
      'p_candidate_sha256': inspection!.candidateSha256,
      'p_sample_valid_until': inspection!.row['sample_valid_until'],
    },
    if (action == AdminReceiptNoticeDispatchAction.revoke) ...{
      'p_approval_id': approval!['approval_id'],
      'p_expected_transport_revision': inspection!.revision,
    },
  });
  static AdminReceiptNoticeDispatchIntent create({
    required AdminReceiptNoticeDispatchAction action,
    required String actorId,
    required String sessionId,
    required String requestId,
    required String reason,
    required DateTime now,
    AdminReceiptNoticePreparedReference? reference,
    AdminReceiptNoticeDispatchInspection? inspection,
    AdminReceiptNoticeDispatchConfiguration? configuration,
    bool? enabled,
    Map<String, dynamic>? approval,
  }) {
    final row = <String, dynamic>{
      'version': 1,
      'actor_id': actorId,
      'session_id': sessionId,
      'request_id': requestId,
      'action': action.wire,
      'reason': reason,
      'reference': reference?.row,
      'inspection': inspection?.row,
      'configuration': configuration?.row,
      'enabled': enabled,
      'approval': approval,
    };
    row['fingerprint'] = noticeFingerprint(row);
    final value = AdminReceiptNoticeDispatchIntent.parse(row);
    if (!value.fresh(now)) noticeInvalid();
    return value;
  }

  factory AdminReceiptNoticeDispatchIntent.parse(Object? raw) {
    final row = noticeObject(raw, {
      'version',
      'actor_id',
      'session_id',
      'request_id',
      'action',
      'reason',
      'reference',
      'inspection',
      'configuration',
      'enabled',
      'approval',
      'fingerprint',
    });
    if (row['version'] is! int || row['version'] != 1) noticeInvalid();
    for (final k in ['actor_id', 'session_id', 'request_id']) {
      noticeUuid(row[k]);
    }
    final reason = noticeText(row['reason'], maximum: 500);
    if (reason.trim() != reason || reason.runes.length < 8) noticeInvalid();
    final copy = Map<String, dynamic>.from(row)..remove('fingerprint');
    if (noticeHash(row['fingerprint']) != noticeFingerprint(copy)) {
      noticeInvalid();
    }
    final action = AdminReceiptNoticeDispatchAction.parse(row['action']);
    AdminReceiptNoticePreparedReference? reference;
    AdminReceiptNoticeDispatchInspection? inspection;
    AdminReceiptNoticeDispatchConfiguration? configuration;
    Map<String, dynamic>? approval;
    if (action == AdminReceiptNoticeDispatchAction.configure) {
      if (row['reference'] != null ||
          row['inspection'] != null ||
          row['approval'] != null ||
          row['enabled'] is! bool) {
        noticeInvalid();
      }
      configuration = AdminReceiptNoticeDispatchConfiguration.parse(
        row['configuration'],
      );
      if (configuration.revision >= 1000000000) noticeInvalid();
    } else {
      if (row['configuration'] != null || row['enabled'] != null) {
        noticeInvalid();
      }
      reference = AdminReceiptNoticePreparedReference.parse(row['reference']);
      if (reference.actorId != row['actor_id'] ||
          reference.sessionId != row['session_id'] ||
          row['request_id'] == reference.originalRequestId) {
        noticeInvalid();
      }
      inspection = AdminReceiptNoticeDispatchInspection.parse(
        row['inspection'],
        reference,
      );
      if (inspection.revision >= 1000000000) noticeInvalid();
      if (action == AdminReceiptNoticeDispatchAction.approve) {
        if (row['approval'] != null || !inspection.canApprove) noticeInvalid();
      } else {
        approval = dispatchApproval(row['approval'], reference);
        if (approval['transport_revision'] != inspection.revision ||
            !const {
              'notice_approval_pending',
              'notice_already_materialized',
            }.contains(inspection.reason)) {
          noticeInvalid();
        }
      }
    }
    return AdminReceiptNoticeDispatchIntent._(
      noticeFreeze(row) as Map<String, dynamic>,
      action,
      reference,
      inspection,
      configuration,
      approval,
    );
  }
}

Map<String, dynamic> dispatchApproval(
  Object? raw,
  AdminReceiptNoticePreparedReference reference,
) {
  final row = noticeObject(raw, {
    'contract_version',
    'scope',
    'request_id',
    'action',
    'approval_id',
    'prepared_review_id',
    'outbox_id',
    'notice_family',
    'transport_revision',
    'candidate_sha256',
    'recorded_at',
    'expires_at',
    'audit_id',
    'send_authority',
    'financial_action',
  });
  dispatchContract(row);
  if (row['action'] != AdminReceiptNoticeDispatchAction.approve.wire ||
      row['financial_action'] != false ||
      row['prepared_review_id'] != reference.preparedReviewId ||
      row['outbox_id'] != reference.outboxId ||
      row['notice_family'] != reference.family.wire) {
    noticeInvalid();
  }
  for (final k in ['request_id', 'approval_id', 'audit_id']) {
    noticeUuid(row[k]);
  }
  if (row['request_id'] == reference.originalRequestId) noticeInvalid();
  noticeInteger(row['transport_revision'], minimum: 1);
  noticeHash(row['candidate_sha256']);
  if (noticeTime(
        row['expires_at'],
      ).difference(noticeTime(row['recorded_at'])) !=
      const Duration(minutes: 15)) {
    noticeInvalid();
  }
  return noticeFreeze(row) as Map<String, dynamic>;
}

class AdminReceiptNoticeDispatchRequest {
  AdminReceiptNoticeDispatchRequest._(this.result, this.recorded);
  final Map<String, dynamic>? result;
  final bool recorded;
  factory AdminReceiptNoticeDispatchRequest.recorded(
    Object? raw,
    AdminReceiptNoticeDispatchIntent intent,
  ) {
    late Map<String, dynamic> row;
    if (intent.action == AdminReceiptNoticeDispatchAction.approve) {
      row = dispatchApproval(raw, intent.reference!);
      if (row['transport_revision'] != intent.inspection!.revision + 1 ||
          row['candidate_sha256'] != intent.inspection!.candidateSha256) {
        noticeInvalid();
      }
    } else if (intent.action == AdminReceiptNoticeDispatchAction.configure) {
      row = noticeObject(raw, {
        'contract_version',
        'scope',
        'request_id',
        'action',
        'enabled',
        'configuration_revision',
        'recorded_at',
        'audit_id',
        'send_authority',
      });
      dispatchContract(row);
      if (row['enabled'] != intent.row['enabled'] ||
          row['configuration_revision'] != intent.configuration!.revision + 1) {
        noticeInvalid();
      }
    } else {
      row = noticeObject(raw, {
        'contract_version',
        'scope',
        'request_id',
        'action',
        'approval_id',
        'transport_revision',
        'status',
        'recorded_at',
        'audit_id',
        'send_authority',
      });
      dispatchContract(row);
      if (row['approval_id'] != intent.approval!['approval_id'] ||
          row['transport_revision'] != intent.inspection!.revision + 1 ||
          row['status'] != 'revoked_unarmed') {
        noticeInvalid();
      }
    }
    if (row['action'] != intent.action.wire ||
        row['request_id'] != intent.requestId) {
      noticeInvalid();
    }
    noticeUuid(row['audit_id']);
    final at = noticeTime(row['recorded_at']),
        checked =
            intent.configuration?.checkedAt ?? intent.inspection!.checkedAt;
    if (at.isBefore(checked) ||
        intent.action != AdminReceiptNoticeDispatchAction.revoke &&
            !at.isBefore(
              intent.configuration?.validUntil ?? intent.inspection!.validUntil,
            )) {
      noticeInvalid();
    }
    return AdminReceiptNoticeDispatchRequest._(
      noticeFreeze(row) as Map<String, dynamic>,
      true,
    );
  }
  factory AdminReceiptNoticeDispatchRequest.lookup(
    Object? raw,
    AdminReceiptNoticeDispatchIntent intent,
  ) {
    final row = noticeObject(raw, {
      'contract_version',
      'scope',
      'request_id',
      'status',
      'result',
      'send_authority',
    });
    dispatchContract(row);
    if (row['request_id'] != intent.requestId ||
        !const {'recorded', 'not_recorded'}.contains(row['status'])) {
      noticeInvalid();
    }
    if (row['status'] == 'not_recorded') {
      if (row['result'] != null) noticeInvalid();
      return AdminReceiptNoticeDispatchRequest._(null, false);
    }
    return AdminReceiptNoticeDispatchRequest.recorded(row['result'], intent);
  }
}
