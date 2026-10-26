import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../core/data/exact_json_values.dart';
import 'admin_receipt_cancel_models.dart';

Never noticeInvalid() =>
    throw const FormatException('Notice evidence could not be validated.');
Map<String, dynamic> noticeObject(Object? raw, Set<String> keys) =>
    cancelObject(raw, keys);
String noticeUuid(Object? raw) => cancelUuid(raw);
String noticeHash(Object? raw) {
  if (raw is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw)) {
    noticeInvalid();
  }
  return raw;
}

String noticeText(Object? raw, {int maximum = 1000}) {
  if (raw is! String ||
      raw.isEmpty ||
      raw.runes.length > maximum ||
      raw.contains('\u0000')) {
    noticeInvalid();
  }
  return raw;
}

int noticeInteger(Object? raw, {int minimum = 0, int maximum = 1000000000}) =>
    exactJsonInteger(
      raw,
      field: 'notice evidence number',
      minimum: minimum,
      maximum: maximum,
    );
DateTime noticeTime(Object? raw) => cancelInstant(raw);
void _false(Map<String, dynamic> row, Iterable<String> keys) {
  for (final k in keys) {
    if (row[k] != false) noticeInvalid();
  }
}

void _contract(Map<String, dynamic> r) {
  if (r['contract_version'] is! int ||
      r['contract_version'] != 1 ||
      r['scope'] != 'rw_receipt_notice_content') {
    noticeInvalid();
  }
}

Object? noticeFreeze(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.unmodifiable(
      value.map((k, v) => MapEntry(k, noticeFreeze(v))),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(noticeFreeze));
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  noticeInvalid();
}

Object? _ordered(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final k in keys) k: _ordered(value[k])};
  }
  if (value is List) return value.map(_ordered).toList();
  return value;
}

String noticeFingerprint(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_ordered(value)))).toString();
bool noticeFresh(DateTime checked, DateTime until, DateTime now) =>
    !now.toUtc().isBefore(checked) && now.toUtc().isBefore(until);

enum AdminReceiptNoticeFamily {
  duplicateCopy('duplicate_copy', 'Historical receipt copy'),
  reversalNotice('reversal_notice', 'Collect ledger compensation'),
  correction('correction', 'Correction'),
  approvedResend('approved_resend', 'Approved resend');

  const AdminReceiptNoticeFamily(this.wire, this.label);
  final String wire, label;
  bool get contentSupported => this == duplicateCopy || this == reversalNotice;
  static AdminReceiptNoticeFamily parse(Object? value) =>
      values.firstWhere((v) => v.wire == value, orElse: noticeInvalid);
}

String noticeLanguage(Object? value) {
  if (!const {'rw', 'en', 'fr'}.contains(value)) noticeInvalid();
  return value as String;
}

const _templateKeys = {
  'family',
  'language',
  'body_frame',
  'consent_rule',
  'template_key',
  'recipient_rule',
  'disclosure_rule',
  'template_sha256',
  'semantic_version',
};
Map<String, dynamic> _template(
  Object? raw,
  AdminReceiptNoticeFamily family,
  String language,
) {
  final r = noticeObject(raw, _templateKeys);
  if (!family.contentSupported ||
      r['family'] != family.wire ||
      r['language'] != language ||
      r['semantic_version'] is! int ||
      r['semantic_version'] != 1 ||
      r['template_key'] != 'collect.notice.${family.wire}' ||
      r['recipient_rule'] != 'same_original_member' ||
      r['consent_rule'] != 'current_receipt_consent_required_no_override' ||
      r['disclosure_rule'] !=
          (family == AdminReceiptNoticeFamily.duplicateCopy
              ? 'original_recorded_receipt_facts_only'
              : 'collect_ledger_compensation_facts_only')) {
    noticeInvalid();
  }
  noticeText(r['body_frame']);
  noticeHash(r['template_sha256']);
  return noticeFreeze(r) as Map<String, dynamic>;
}

const _factsKeys = {
  'language',
  'payment_id',
  'collection_id',
  'root_outbox_id',
  'member_record_id',
  'original_reference',
  'financial_assertion',
  'original_amount_rwf',
  'original_recorded_at',
  'original_snapshot_id',
  'original_content_sha256',
  'original_journal_sha256',
  'bank_settlement_inferred',
  'current_consent_revision',
  'current_contact_revision',
  'original_snapshot_sha256',
  'original_journal_entry_id',
  'current_receipt_policy_revision',
  'original_member_balance_recorded_rwf',
};
const _reversalFactKeys = {
  'source_delta_rwf',
  'source_recorded_at',
  'source_snapshot_id',
  'source_journal_sha256',
  'source_snapshot_sha256',
  'source_journal_entry_id',
  'compensation_request_sha256',
  'source_member_balance_recorded_rwf',
};
const _sourceKeys = {
  'can_approve',
  'reason_code',
  'send_action',
  'source_facts',
  'carrier_proof',
  'notice_family',
  'root_revision',
  'emergency_stop',
  'quota_reserved',
  'send_authority',
  'delivery_proven',
  'notice_revision',
  'operations_mode',
  'financial_action',
  'source_snapshot_id',
  'notice_policy_status',
  'transport_observation',
  'notice_transport_status',
  'primary_receipt_retained',
  'financial_source_verified',
  'operations_policy_revision',
};
Map<String, dynamic> _source(
  Object? raw,
  AdminReceiptNoticeFamily family,
  String outbox,
  String source,
  String collection,
) {
  final r = noticeObject(raw, _sourceKeys);
  if (r['notice_family'] != family.wire ||
      r['source_snapshot_id'] != source ||
      r['notice_policy_status'] != 'unavailable' ||
      r['notice_transport_status'] != 'unavailable' ||
      r['primary_receipt_retained'] != true ||
      r['financial_source_verified'] is! bool ||
      r['emergency_stop'] is! bool ||
      !const {
        'Shadow',
        'Dry-run',
        'Live-limited',
        'Live',
        'Paused',
      }.contains(r['operations_mode'])) {
    noticeInvalid();
  }
  _false(r, [
    'can_approve',
    'send_action',
    'carrier_proof',
    'quota_reserved',
    'send_authority',
    'delivery_proven',
    'financial_action',
  ]);
  noticeText(r['reason_code'], maximum: 100);
  noticeInteger(r['root_revision'], minimum: 1);
  noticeInteger(r['notice_revision']);
  noticeInteger(r['operations_policy_revision'], minimum: 1);
  final t = r['transport_observation'];
  if (t is! Map<String, dynamic>) noticeInvalid();
  if (t['reason_code'] == 'complete_gateway_observations') {
    final v = noticeObject(t, {
      'reason_code',
      'attempt_id',
      'transport_sha256',
    });
    noticeUuid(v['attempt_id']);
    noticeHash(v['transport_sha256']);
  } else {
    final v = noticeObject(t, {'reason_code'});
    if (!const {
      'transport_topology_unavailable',
      'transport_unreconciled',
      'transport_uncertain',
    }.contains(v['reason_code'])) {
      noticeInvalid();
    }
  }
  if (r['source_facts'] != null) {
    final f = noticeObject(r['source_facts'], {
      ..._factsKeys,
      if (family == AdminReceiptNoticeFamily.reversalNotice)
        ..._reversalFactKeys,
    });
    for (final k in [
      'payment_id',
      'member_record_id',
      'original_snapshot_id',
      'original_journal_entry_id',
    ]) {
      noticeUuid(f[k]);
    }
    if (f['root_outbox_id'] != outbox ||
        f['collection_id'] != collection ||
        f['financial_assertion'] != 'collect_posted_ledger' ||
        f['bank_settlement_inferred'] != false) {
      noticeInvalid();
    }
    noticeLanguage(f['language']);
    noticeTime(f['original_recorded_at']);
    noticeInteger(
      f['original_amount_rwf'],
      minimum: 1,
      maximum: maxExactJsonInteger,
    );
    noticeInteger(
      f['original_member_balance_recorded_rwf'],
      maximum: maxExactJsonInteger,
    );
    for (final k in [
      'current_consent_revision',
      'current_contact_revision',
      'current_receipt_policy_revision',
    ]) {
      noticeInteger(f[k], minimum: 1);
    }
    for (final k in [
      'original_content_sha256',
      'original_journal_sha256',
      'original_snapshot_sha256',
    ]) {
      noticeHash(f[k]);
    }
    if (f['original_reference'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$',
        ).hasMatch(f['original_reference'] as String)) {
      noticeInvalid();
    }
    if (family == AdminReceiptNoticeFamily.reversalNotice) {
      if (f['source_snapshot_id'] != source ||
          noticeInteger(
                f['source_delta_rwf'],
                minimum: -maxExactJsonInteger,
                maximum: -1,
              ) !=
              -(f['original_amount_rwf'] as int)) {
        noticeInvalid();
      }
      noticeUuid(f['source_journal_entry_id']);
      noticeTime(f['source_recorded_at']);
      noticeInteger(
        f['source_member_balance_recorded_rwf'],
        maximum: maxExactJsonInteger,
      );
      for (final k in [
        'source_journal_sha256',
        'source_snapshot_sha256',
        'compensation_request_sha256',
      ]) {
        noticeHash(f[k]);
      }
    } else if (family != AdminReceiptNoticeFamily.correction &&
        f['original_snapshot_id'] != source) {
      noticeInvalid();
    }
  } else if (r['financial_source_verified'] == true) {
    noticeInvalid();
  }
  return noticeFreeze(r) as Map<String, dynamic>;
}

const _policyCandidateKeys = {
  'enabled',
  'template',
  'collection_id',
  'notice_family',
  'approval_basis',
  'current_policy',
  'recipient_rule',
  'send_authority',
  'consent_override',
  'financial_mutation',
  'current_policy_status',
  'expected_policy_revision',
  'notice_transport_available',
};
const _preparedCandidateKeys = {
  'body',
  'language',
  'body_sha256',
  'can_approve',
  'can_prepare',
  'reason_code',
  'consent_rule',
  'template_key',
  'carrier_proof',
  'collection_id',
  'notice_family',
  'segment_count',
  'recipient_rule',
  'root_outbox_id',
  'send_authority',
  'delivery_proven',
  'disclosure_rule',
  'policy_revision',
  'source_evidence',
  'template_sha256',
  'financial_action',
  'member_record_id',
  'semantic_version',
  'policy_request_id',
  'destination_masked',
  'destination_sha256',
  'source_snapshot_id',
  'content_review_revision',
  'primary_receipt_retained',
  'notice_transport_available',
};

class AdminReceiptNoticeInspection {
  AdminReceiptNoticeInspection._(
    this.row,
    this.policy,
    this.collectionId,
    this.family,
    this.outboxId,
    this.sourceSnapshotId,
    this.checkedAt,
    this.validUntil,
  );
  final Map<String, dynamic> row;
  final bool policy;
  final String collectionId;
  final AdminReceiptNoticeFamily family;
  final String? outboxId, sourceSnapshotId;
  final DateTime checkedAt, validUntil;
  Map<String, dynamic> get candidate =>
      row['candidate'] as Map<String, dynamic>;
  String get candidateSha256 => row['candidate_sha256'] as String;
  bool get canPrepare => !policy && candidate['can_prepare'] == true;
  bool fresh(DateTime now) => noticeFresh(checkedAt, validUntil, now);
  factory AdminReceiptNoticeInspection.policy(
    Object? raw,
    String collection,
    AdminReceiptNoticeFamily family,
    String language,
    bool enabled,
  ) {
    noticeUuid(collection);
    final r = noticeObject(raw, {
      'scope',
      'candidate',
      'checked_at',
      'candidate_sha256',
      'contract_version',
      'sample_valid_until',
    });
    _contract(r);
    final c = noticeObject(r['candidate'], _policyCandidateKeys);
    if (!family.contentSupported ||
        c['notice_family'] != family.wire ||
        c['collection_id'] != collection ||
        c['enabled'] != enabled ||
        c['approval_basis'] != 'actual_current_owner_policy_action' ||
        c['recipient_rule'] != 'same_original_member' ||
        !const {
          'unapproved',
          'approved_active',
          'approved_inactive',
        }.contains(c['current_policy_status'])) {
      noticeInvalid();
    }
    _false(c, [
      'send_authority',
      'consent_override',
      'financial_mutation',
      'notice_transport_available',
    ]);
    noticeInteger(c['expected_policy_revision'], maximum: 999999999);
    _template(c['template'], family, language);
    if (c['current_policy'] != null) {
      final p = noticeObject(c['current_policy'], {
        'enabled',
        'actor_id',
        'audit_id',
        'language',
        'request_id',
        'approved_at',
        'approval_basis',
        'policy_revision',
        'template_sha256',
        'semantic_version',
      });
      for (final k in ['actor_id', 'audit_id', 'request_id']) {
        noticeUuid(p[k]);
      }
      noticeLanguage(p['language']);
      noticeTime(p['approved_at']);
      noticeHash(p['template_sha256']);
      if (p['enabled'] is! bool ||
          p['policy_revision'] != c['expected_policy_revision'] ||
          p['semantic_version'] is! int ||
          p['semantic_version'] != 1 ||
          p['approval_basis'] != 'actual_current_owner_policy_action' ||
          c['current_policy_status'] !=
              (p['enabled'] == true
                  ? 'approved_active'
                  : 'approved_inactive')) {
        noticeInvalid();
      }
    } else if (c['expected_policy_revision'] != 0 ||
        c['current_policy_status'] != 'unapproved') {
      noticeInvalid();
    }
    return _parse(r, true, collection, family, null, null);
  }
  factory AdminReceiptNoticeInspection.content(
    Object? raw,
    String outbox,
    String source,
    String collection,
    AdminReceiptNoticeFamily family,
  ) {
    noticeUuid(outbox);
    noticeUuid(source);
    noticeUuid(collection);
    final r = noticeObject(raw, {
      'scope',
      'candidate',
      'outbox_id',
      'checked_at',
      'candidate_sha256',
      'contract_version',
      'sample_valid_until',
    });
    _contract(r);
    if (r['outbox_id'] != outbox) noticeInvalid();
    final c = r['candidate'];
    if (c is! Map<String, dynamic>) noticeInvalid();
    if (c['can_prepare'] == true) {
      noticeObject(c, _preparedCandidateKeys);
      if (!family.contentSupported ||
          c['notice_family'] != family.wire ||
          c['reason_code'] != 'notice_content_preparable' ||
          c['root_outbox_id'] != outbox ||
          c['source_snapshot_id'] != source ||
          c['collection_id'] != collection ||
          c['primary_receipt_retained'] != true ||
          c['semantic_version'] is! int ||
          c['semantic_version'] != 1 ||
          c['recipient_rule'] != 'same_original_member' ||
          c['consent_rule'] != 'current_receipt_consent_required_no_override' ||
          c['template_key'] != 'collect.notice.${family.wire}' ||
          c['disclosure_rule'] !=
              (family == AdminReceiptNoticeFamily.duplicateCopy
                  ? 'original_recorded_receipt_facts_only'
                  : 'collect_ledger_compensation_facts_only')) {
        noticeInvalid();
      }
      _false(c, [
        'can_approve',
        'send_authority',
        'carrier_proof',
        'delivery_proven',
        'financial_action',
        'notice_transport_available',
      ]);
      noticeLanguage(c['language']);
      noticeHash(c['template_sha256']);
      noticeHash(c['destination_sha256']);
      noticeUuid(c['member_record_id']);
      noticeUuid(c['policy_request_id']);
      noticeInteger(c['policy_revision'], minimum: 1);
      noticeInteger(c['content_review_revision'], maximum: 24);
      noticeInteger(c['segment_count'], minimum: 1, maximum: 10);
      if (c['destination_masked'] is! String ||
          !RegExp(
            r'^\+250 \*\*\* [0-9]{4}$',
          ).hasMatch(c['destination_masked'] as String)) {
        noticeInvalid();
      }
      if (sha256.convert(utf8.encode(noticeText(c['body']))).toString() !=
          noticeHash(c['body_sha256'])) {
        noticeInvalid();
      }
    } else {
      noticeObject(c, {
        'can_approve',
        'can_prepare',
        'notice_family',
        'reason_code',
        'send_authority',
        'source_evidence',
      });
      _false(c, ['can_approve', 'can_prepare', 'send_authority']);
      if (c['notice_family'] != family.wire) noticeInvalid();
      noticeText(c['reason_code'], maximum: 100);
    }
    final evidence = _source(
      c['source_evidence'],
      family,
      outbox,
      source,
      collection,
    );
    if (c['can_prepare'] == true &&
        (evidence['financial_source_verified'] != true ||
            evidence['reason_code'] != 'notice_policy_unavailable' ||
            (evidence['source_facts'] as Map)['member_record_id'] !=
                c['member_record_id'])) {
      noticeInvalid();
    }
    return _parse(r, false, collection, family, outbox, source);
  }
  static AdminReceiptNoticeInspection _parse(
    Map<String, dynamic> r,
    bool policy,
    String collection,
    AdminReceiptNoticeFamily family,
    String? outbox,
    String? source,
  ) {
    final checked = noticeTime(r['checked_at']),
        until = noticeTime(r['sample_valid_until']);
    noticeHash(r['candidate_sha256']);
    if (until.difference(checked) < const Duration(seconds: 60) ||
        until.difference(checked) > const Duration(seconds: 65)) {
      noticeInvalid();
    }
    return AdminReceiptNoticeInspection._(
      noticeFreeze(r) as Map<String, dynamic>,
      policy,
      collection,
      family,
      outbox,
      source,
      checked,
      until,
    );
  }
}

class AdminReceiptNoticeIntent {
  AdminReceiptNoticeIntent._(this.row, this.inspection);
  final Map<String, dynamic> row;
  final AdminReceiptNoticeInspection inspection;
  String get requestId => row['request_id'] as String;
  String get actorId => row['actor_id'] as String;
  String get sessionId => row['session_id'] as String;
  String get fingerprint => row['fingerprint'] as String;
  bool get policy => inspection.policy;
  String get action => policy ? 'policy' : 'prepare_content';
  String get reason => row['reason'] as String;
  Map<String, dynamic> get parameters => Map.unmodifiable({
    'p_request_id': requestId,
    'p_notice_family': inspection.family.wire,
    'p_candidate_sha256': inspection.candidateSha256,
    'p_sample_valid_until': inspection.row['sample_valid_until'],
    'p_reason': reason,
    if (policy) ...{
      'p_collection_id': inspection.collectionId,
      'p_language': (inspection.candidate['template'] as Map)['language'],
      'p_enabled': inspection.candidate['enabled'],
      'p_expected_policy_revision':
          inspection.candidate['expected_policy_revision'],
    } else ...{
      'p_outbox_id': inspection.outboxId,
      'p_source_snapshot_id': inspection.sourceSnapshotId,
      'p_expected_content_review_revision':
          inspection.candidate['content_review_revision'],
      'p_expected_policy_revision': inspection.candidate['policy_revision'],
    },
  });
  factory AdminReceiptNoticeIntent.create({
    required AdminReceiptNoticeInspection inspection,
    required String requestId,
    required String actorId,
    required String sessionId,
    required String reason,
    required DateTime now,
  }) {
    if (!inspection.fresh(now) ||
        !inspection.policy && !inspection.canPrepare ||
        !inspection.family.contentSupported ||
        reason.trim() != reason ||
        reason.runes.length < 8 ||
        reason.runes.length > 500) {
      noticeInvalid();
    }
    final r = <String, dynamic>{
      'version': 1,
      'request_id': noticeUuid(requestId),
      'actor_id': noticeUuid(actorId),
      'session_id': noticeUuid(sessionId),
      'action': inspection.policy ? 'policy' : 'prepare_content',
      'collection_id': inspection.collectionId,
      'outbox_id': inspection.outboxId,
      'source_snapshot_id': inspection.sourceSnapshotId,
      'reason': reason,
      'inspection': inspection.row,
    };
    r['fingerprint'] = noticeFingerprint(r);
    return AdminReceiptNoticeIntent.parse(r);
  }
  factory AdminReceiptNoticeIntent.parse(Object? raw) {
    final r = noticeObject(raw, {
      'version',
      'request_id',
      'actor_id',
      'session_id',
      'action',
      'collection_id',
      'outbox_id',
      'source_snapshot_id',
      'reason',
      'inspection',
      'fingerprint',
    });
    if (r['version'] is! int ||
        r['version'] != 1 ||
        !const {'policy', 'prepare_content'}.contains(r['action'])) {
      noticeInvalid();
    }
    for (final k in ['request_id', 'actor_id', 'session_id', 'collection_id']) {
      noticeUuid(r[k]);
    }
    final reason = noticeText(r['reason'], maximum: 500);
    if (reason.trim() != reason || reason.runes.length < 8) noticeInvalid();
    final h = noticeHash(r['fingerprint']),
        copy = Map<String, dynamic>.from(r)..remove('fingerprint');
    if (noticeFingerprint(copy) != h) noticeInvalid();
    final v = r['inspection'];
    if (v is! Map<String, dynamic> || v['candidate'] is! Map<String, dynamic>) {
      noticeInvalid();
    }
    final c = v['candidate'] as Map<String, dynamic>,
        family = AdminReceiptNoticeFamily.parse(c['notice_family']);
    final policy = r['action'] == 'policy';
    late AdminReceiptNoticeInspection inspection;
    if (policy) {
      if (r['outbox_id'] != null || r['source_snapshot_id'] != null) {
        noticeInvalid();
      }
      final t = c['template'];
      if (t is! Map || c['enabled'] is! bool) noticeInvalid();
      inspection = AdminReceiptNoticeInspection.policy(
        v,
        r['collection_id'] as String,
        family,
        noticeLanguage(t['language']),
        c['enabled'] as bool,
      );
    } else {
      inspection = AdminReceiptNoticeInspection.content(
        v,
        noticeUuid(r['outbox_id']),
        noticeUuid(r['source_snapshot_id']),
        r['collection_id'] as String,
        family,
      );
      if (!inspection.canPrepare) noticeInvalid();
    }
    return AdminReceiptNoticeIntent._(
      noticeFreeze(r) as Map<String, dynamic>,
      inspection,
    );
  }
}

class AdminReceiptNoticeRequest {
  AdminReceiptNoticeRequest._(
    this.result,
    this.recorded,
    this.preview,
    this.template,
  );
  final Map<String, dynamic>? result, preview, template;
  final bool recorded;
  static Map<String, dynamic> _result(Object? raw, AdminReceiptNoticeIntent i) {
    final keys = i.policy
        ? {
            'scope',
            'action',
            'approval_basis',
            'audit_id',
            'collection_id',
            'contract_version',
            'enabled',
            'financial_action',
            'language',
            'notice_family',
            'notice_transport_available',
            'policy_revision',
            'recorded_at',
            'request_id',
            'semantic_version',
            'send_authority',
            'template_sha256',
          }
        : {
            'scope',
            'action',
            'audit_id',
            'body_sha256',
            'can_approve',
            'carrier_proof',
            'content_review_revision',
            'contract_version',
            'delivery_proven',
            'destination_sha256',
            'financial_action',
            'notice_family',
            'notice_transport_available',
            'outbox_id',
            'policy_revision',
            'preview_sha256',
            'primary_receipt_retained',
            'quota_reserved',
            'recorded_at',
            'request_id',
            'review_id',
            'send_action',
            'send_authority',
            'source_snapshot_id',
            'status',
          };
    final r = noticeObject(raw, keys);
    _contract(r);
    _false(r, [
      'send_authority',
      'financial_action',
      'notice_transport_available',
    ]);
    if (r['request_id'] != i.requestId ||
        r['action'] != i.action ||
        r['notice_family'] != i.inspection.family.wire) {
      noticeInvalid();
    }
    noticeUuid(r['audit_id']);
    final recordedAt = noticeTime(r['recorded_at']);
    if (recordedAt.isBefore(i.inspection.checkedAt) ||
        !recordedAt.isBefore(i.inspection.validUntil)) {
      noticeInvalid();
    }
    noticeInteger(r['policy_revision'], minimum: 1);
    if (i.policy) {
      noticeInteger(r['semantic_version'], minimum: 1, maximum: 1);
    } else {
      noticeInteger(r['content_review_revision'], minimum: 1, maximum: 25);
    }
    if (i.policy) {
      final c = i.inspection.candidate, t = c['template'] as Map;
      if (r['collection_id'] != i.inspection.collectionId ||
          r['language'] != t['language'] ||
          r['enabled'] != c['enabled'] ||
          r['template_sha256'] != t['template_sha256'] ||
          r['semantic_version'] != 1 ||
          r['policy_revision'] !=
              noticeInteger(c['expected_policy_revision']) + 1 ||
          r['approval_basis'] != 'actual_current_owner_policy_action') {
        noticeInvalid();
      }
    } else {
      final c = i.inspection.candidate;
      _false(r, [
        'can_approve',
        'carrier_proof',
        'delivery_proven',
        'quota_reserved',
        'send_action',
      ]);
      if (r['outbox_id'] != i.inspection.outboxId ||
          r['source_snapshot_id'] != i.inspection.sourceSnapshotId ||
          r['status'] != 'content_prepared' ||
          r['primary_receipt_retained'] != true ||
          r['content_review_revision'] !=
              noticeInteger(c['content_review_revision']) + 1 ||
          r['policy_revision'] != c['policy_revision'] ||
          r['preview_sha256'] != i.inspection.candidateSha256 ||
          r['body_sha256'] != c['body_sha256'] ||
          r['destination_sha256'] != c['destination_sha256']) {
        noticeInvalid();
      }
      noticeUuid(r['review_id']);
    }
    return noticeFreeze(r) as Map<String, dynamic>;
  }

  factory AdminReceiptNoticeRequest.recorded(
    Object? raw,
    AdminReceiptNoticeIntent i,
  ) => AdminReceiptNoticeRequest._(_result(raw, i), true, null, null);
  factory AdminReceiptNoticeRequest.lookup(
    Object? raw,
    AdminReceiptNoticeIntent i,
  ) {
    final r = noticeObject(raw, {
      'scope',
      'result',
      'status',
      'request_id',
      'send_authority',
      'policy_template',
      'contract_version',
      'financial_action',
      'prepared_preview',
      'notice_transport_available',
    });
    _contract(r);
    _false(r, [
      'send_authority',
      'financial_action',
      'notice_transport_available',
    ]);
    if (r['request_id'] != i.requestId ||
        !const {'recorded', 'not_recorded'}.contains(r['status'])) {
      noticeInvalid();
    }
    if (r['status'] == 'not_recorded') {
      if (r['result'] != null ||
          r['prepared_preview'] != null ||
          r['policy_template'] != null) {
        noticeInvalid();
      }
      return AdminReceiptNoticeRequest._(null, false, null, null);
    }
    final result = _result(r['result'], i);
    Map<String, dynamic>? preview, template;
    if (i.policy) {
      if (r['prepared_preview'] != null) noticeInvalid();
      template = _template(
        r['policy_template'],
        i.inspection.family,
        ((i.inspection.candidate['template'] as Map)['language']) as String,
      );
      if (noticeFingerprint(template) !=
          noticeFingerprint(i.inspection.candidate['template'])) {
        noticeInvalid();
      }
    } else {
      if (r['policy_template'] != null ||
          noticeFingerprint(r['prepared_preview']) !=
              noticeFingerprint(i.inspection.candidate)) {
        noticeInvalid();
      }
      preview = noticeFreeze(r['prepared_preview']) as Map<String, dynamic>;
    }
    return AdminReceiptNoticeRequest._(result, true, preview, template);
  }
}
