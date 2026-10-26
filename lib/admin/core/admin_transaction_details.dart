import '../../core/data/exact_json_values.dart';
import 'admin_member_identity_contract.dart';

const adminTransactionIdentityStatuses = {
  'ready',
  'raw_missing',
  'not_rwanda_scope',
  'missing_payer_identity',
  'missing_payee_identity',
  'missing_payer_and_payee_identity',
};
final _uuid = RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$');
Never _invalid() =>
    throw const FormatException('Invalid transaction evidence.');
Map<String, dynamic> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) _invalid();
  return Map<String, dynamic>.from(value);
}

void _keys(Map<String, dynamic> row, Set<String> keys) {
  if (row.length != keys.length || !row.keys.every(keys.contains)) _invalid();
}

bool _id(Object? value) => value is String && _uuid.hasMatch(value);
bool _count(Object? value) =>
    value is int && value >= 0 && value <= maxExactJsonInteger;
bool _text(Object? value) =>
    value is String && value.trim().isNotEmpty && value.length <= 16000;

class AdminPayerGroup {
  AdminPayerGroup._(this.id, this.title, this.roles, this.membershipStatuses);
  final String id, title;
  final List<String> roles, membershipStatuses;
  factory AdminPayerGroup.parse(Object? value) {
    final row = _map(value);
    _keys(row, {'collection_id', 'title', 'roles', 'membership_statuses'});
    List<String> strings(
      Object? value,
      Set<String> allowed, {
      bool required = false,
    }) {
      if (value is! List ||
          required && value.isEmpty ||
          value.length > 20 ||
          !value.every((item) => item is String && allowed.contains(item)) ||
          value.toSet().length != value.length) {
        _invalid();
      }
      return List<String>.unmodifiable(value.cast<String>());
    }

    if (!_id(row['collection_id']) || !_text(row['title'])) _invalid();
    return AdminPayerGroup._(
      row['collection_id'] as String,
      row['title'] as String,
      strings(row['roles'], {
        'owner',
        'admin',
        'member',
        'receiver',
        'contributor',
        'viewer',
      }, required: true),
      strings(row['membership_statuses'], {
        'active',
        'invited',
        'removed',
        'left',
      }),
    );
  }
}

class AdminPayerGroupsPage {
  AdminPayerGroupsPage._(
    this.status,
    this.memberId,
    this.rows,
    this.total,
    this.limit,
    this.offset,
  );
  final String status;
  final String? memberId;
  final List<AdminPayerGroup> rows;
  final int total, limit, offset;
  factory AdminPayerGroupsPage.parse(
    Map<String, dynamic> row, {
    required int limit,
    required int offset,
  }) {
    _keys(row, {'status', 'member_id', 'rows', 'total', 'limit', 'offset'});
    if (!{
          'available',
          'not_authorized',
          'identity_unresolved',
        }.contains(row['status']) ||
        row['limit'] != limit ||
        row['offset'] != offset ||
        limit < 1 ||
        limit > 100 ||
        offset < 0 ||
        offset > 2147483647 ||
        !_count(row['total']) ||
        row['rows'] is! List) {
      _invalid();
    }
    final raw = row['rows'] as List;
    final total = row['total'] as int;
    if (row['status'] != 'available') {
      if (row['member_id'] != null || total != 0 || raw.isNotEmpty) _invalid();
    } else if (!_id(row['member_id']) ||
        raw.length != (total - offset).clamp(0, limit)) {
      {
        _invalid();
      }
    }
    final groups = raw.map(AdminPayerGroup.parse).toList();
    if (groups.map((group) => group.id).toSet().length != groups.length) {
      _invalid();
    }
    return AdminPayerGroupsPage._(
      row['status'] as String,
      row['member_id'] as String?,
      List.unmodifiable(groups),
      total,
      limit,
      offset,
    );
  }
}

class AdminTransactionDetails {
  AdminTransactionDetails._(
    this.collectId,
    this.identityStatus,
    this.sms,
    this.payerStatus,
    this.member,
    this.groups,
    this.counts,
  );
  final String? collectId;
  final String identityStatus, payerStatus;
  final Map<String, dynamic> sms;
  final Map<String, dynamic>? member, counts;
  final AdminPayerGroupsPage? groups;
  factory AdminTransactionDetails.parse(Map<String, dynamic> detail) {
    final collectId = detail['collect_transaction_id'];
    if (collectId != null &&
            (collectId is! String ||
                !RegExp(r'^[0-9]{15}$').hasMatch(collectId)) ||
        !adminTransactionIdentityStatuses.contains(detail['identity_status']) ||
        (detail['identity_status'] == 'ready') != (collectId != null)) {
      _invalid();
    }
    final sms = _map(detail['sms_details']);
    _keys(sms, {
      'raw_sms_id',
      'event_id',
      'payment_id',
      'provider_transaction_id',
      'provider_occurred_at',
      'payer_name',
      'payer_last_three',
      'payee_momo_number_or_code',
      'amount_rwf',
      'wallet_balance_rwf',
      'currency',
      'network',
      'direction',
      'allocation_status',
      'parse_status',
      'parser_model',
      'parser_schema_version',
      'confidence',
      'received_at_device',
      'ingested_at',
      'raw_created_at',
      'parsed_at',
      'body_sha256',
      'client_envelope_id',
      'native_action_capability_id',
      'attestation_request_sha256',
      'device_attested_at',
    });
    if (!_id(sms['raw_sms_id']) || sms['raw_sms_id'] != detail['raw_sms_id']) {
      _invalid();
    }
    for (final key in [
      'event_id',
      'payment_id',
      'client_envelope_id',
      'native_action_capability_id',
    ]) {
      if (sms[key] != null && !_id(sms[key])) _invalid();
    }
    for (final key in [
      'provider_transaction_id',
      'payer_name',
      'payee_momo_number_or_code',
      'currency',
      'network',
      'direction',
      'parse_status',
      'parser_model',
      'parser_schema_version',
    ]) {
      if (sms[key] != null && !_text(sms[key])) _invalid();
    }
    final destination = sms['payee_momo_number_or_code'];
    if (destination != null &&
        (destination is! String ||
            !RegExp(
              r'^(?:\+2507[2389][0-9]{7}|[0-9]{4,9})$',
            ).hasMatch(destination))) {
      _invalid();
    }
    for (final key in ['amount_rwf', 'wallet_balance_rwf']) {
      if (sms[key] != null &&
          (sms[key] is! String ||
              !RegExp(
                r'^(?:0|[1-9][0-9]{0,18})$',
              ).hasMatch(sms[key] as String))) {
        _invalid();
      }
    }
    for (final key in ['amount_rwf', 'wallet_balance_rwf']) {
      if (sms[key] != null &&
          BigInt.parse(sms[key] as String) >
              BigInt.parse('9223372036854775807')) {
        _invalid();
      }
    }
    for (final key in [
      'provider_occurred_at',
      'received_at_device',
      'ingested_at',
      'raw_created_at',
      'parsed_at',
      'device_attested_at',
    ]) {
      if (sms[key] != null) exactJsonTimestamp(sms[key], field: key);
    }
    for (final key in ['body_sha256', 'attestation_request_sha256']) {
      if (sms[key] != null &&
          (sms[key] is! String ||
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(sms[key] as String))) {
        _invalid();
      }
    }
    if (sms['payer_last_three'] != null &&
            (sms['payer_last_three'] is! String ||
                !RegExp(
                  r'^[0-9]{3}$',
                ).hasMatch(sms['payer_last_three'] as String)) ||
        !{'allocated', 'unallocated'}.contains(sms['allocation_status']) ||
        sms['confidence'] != null &&
            (sms['confidence'] is! num ||
                !(sms['confidence'] as num).isFinite ||
                (sms['confidence'] as num) < 0 ||
                (sms['confidence'] as num) > 1)) {
      _invalid();
    }
    final insights = _map(detail['payer_insights']);
    _keys(insights, {
      'status',
      'match_basis',
      'member',
      'groups',
      'transaction_counts',
    });
    final status = insights['status'];
    if (!{
      'available',
      'not_authorized',
      'identity_unresolved',
    }.contains(status)) {
      _invalid();
    }
    Map<String, dynamic>? member, counts;
    AdminPayerGroupsPage? groups;
    if (status == 'available') {
      if (insights['match_basis'] != 'full_payer_hash') _invalid();
      member = _map(insights['member']);
      validateAdminMemberIdentity(member);
      final first = _map(insights['groups']);
      _keys(first, {'rows', 'total', 'limit', 'offset'});
      groups = AdminPayerGroupsPage.parse(
        {'status': 'available', 'member_id': member['id'], ...first},
        limit: 10,
        offset: 0,
      );
      counts = _map(insights['transaction_counts']);
      _keys(counts, {'total', 'allocated', 'unallocated'});
      if (!counts.values.every(_count) ||
          counts['total'] != counts['allocated'] + counts['unallocated']) {
        _invalid();
      }
    } else if (insights.entries.any(
      (entry) => entry.key != 'status' && entry.value != null,
    )) {
      {
        _invalid();
      }
    }
    return AdminTransactionDetails._(
      collectId as String?,
      detail['identity_status'] as String,
      Map.unmodifiable(sms),
      status as String,
      member == null ? null : Map.unmodifiable(member),
      groups,
      counts == null ? null : Map.unmodifiable(counts),
    );
  }
}
