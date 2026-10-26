part of 'cloudflare_admin_reconciliation_api.dart';

const reconciliationRelations = {
  'evidence',
  'verification_reviews',
  'allocations',
  'proposals',
  'journals',
};
const _maximum = 9007199254740991;
final _uuid = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
);
Never _invalid() => throw const FormatException(
  'The reconciliation response could not be verified.',
);
bool _id(Object? value) => value is String && _uuid.hasMatch(value);
bool _integer(Object? value, {int minimum = 0}) =>
    value is int && value >= minimum && value <= _maximum;
bool _epoch(Object? value) =>
    _integer(value, minimum: 1) && (value as int) <= 8640000000000;
bool _text(Object? value, {int minimum = 0, int maximum = 1000}) =>
    value is String &&
    value.trim().length >= minimum &&
    value.length <= maximum &&
    !RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(value);
Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : _invalid();
void _keys(Map<String, dynamic> data, Set<String> fields) {
  if (data.length != fields.length || !data.keys.every(fields.contains)) {
    _invalid();
  }
}

class ReconciliationPage<T> {
  const ReconciliationPage({
    required this.rows,
    required this.total,
    required this.limit,
    required this.offset,
    required this.nextOffset,
  });
  final List<T> rows;
  final int total, limit, offset;
  final int? nextOffset;
  static ReconciliationPage<T> parse<T>(
    Map<String, dynamic> data,
    T Function(Map<String, dynamic>) parse,
  ) {
    _keys(data, {'rows', 'total', 'limit', 'offset', 'next_offset'});
    if (data['rows'] is! List ||
        !_integer(data['total']) ||
        !_integer(data['limit'], minimum: 1) ||
        (data['limit'] as int) > 100 ||
        !_integer(data['offset']) ||
        (data['offset'] as int) > 2147483647 ||
        data['next_offset'] != null && !_integer(data['next_offset'])) {
      _invalid();
    }
    final total = data['total'] as int,
        limit = data['limit'] as int,
        offset = data['offset'] as int;
    final rows = (data['rows'] as List).map((row) => parse(_map(row))).toList();
    if (rows.length != (total - offset).clamp(0, limit) ||
        data['next_offset'] !=
            (offset + rows.length < total ? offset + rows.length : null)) {
      _invalid();
    }
    return ReconciliationPage(
      rows: List.unmodifiable(rows),
      total: total,
      limit: limit,
      offset: offset,
      nextOffset: data['next_offset'] as int?,
    );
  }
}

class ReconciliationTransaction {
  ReconciliationTransaction._(this.values);
  final Map<String, dynamic> values;
  String get id => values['id'] as String;
  int get version => values['version'] as int;
  int get remaining => values['unallocated_amount_rwf'] as int;
  String get groupId => values['group_id'] as String;
  bool get confirmed =>
      values['verification_status'] == 'confirmation_recorded';
  factory ReconciliationTransaction.parse(Map<String, dynamic> data) {
    const required = {
      'id',
      'group_id',
      'payee_id',
      'network',
      'provider_reference',
      'rail',
      'currency',
      'amount_rwf',
      'sender_phone_sha256',
      'verification_status',
      'verified_by_admin_id',
      'verified_at',
      'observed_at',
      'created_at',
      'version',
      'recorded_by_admin_id',
      'group_title',
      'group_status',
      'group_version',
      'payee_name',
      'payee_momo',
      'payee_status',
      'payee_version',
      'allocated_amount_rwf',
      'unallocated_amount_rwf',
      'pending_proposals',
      'allocation_status',
      'settlement_status',
    };
    final hasSourceFacts = data.containsKey('transaction_reference');
    _keys(data, {
      ...required,
      if (hasSourceFacts) ...cloudflareTransactionFactKeys,
    });
    if (hasSourceFacts) {
      validateCloudflareTransactionFacts(data, operating: true);
    }
    if (!['id', 'group_id', 'payee_id'].every((key) => _id(data[key])) ||
        ![
          'version',
          'group_version',
          'payee_version',
          'amount_rwf',
        ].every((key) => _integer(data[key], minimum: 1)) ||
        !['observed_at', 'created_at'].every((key) => _epoch(data[key])) ||
        ![
          'allocated_amount_rwf',
          'unallocated_amount_rwf',
          'pending_proposals',
        ].every((key) => _integer(data[key])) ||
        data['currency'] != 'RWF' ||
        data['rail'] != 'rwanda_momo' ||
        !{'mtn_momo', 'airtel_money'}.contains(data['network']) ||
        !{
          'pending',
          'confirmation_recorded',
          'rejection_recorded',
          'evidence_conflict',
        }.contains(data['verification_status']) ||
        !{'active', 'inactive'}.contains(data['payee_status']) ||
        !{
          'draft',
          'active',
          'suspended',
          'archived',
        }.contains(data['group_status']) ||
        ![
          'provider_reference',
          'group_title',
          'payee_name',
        ].every((key) => _text(data[key], minimum: 1)) ||
        data['payee_momo'] is! String ||
        !RegExp(r'^[0-9]{4,12}$').hasMatch(data['payee_momo'] as String) ||
        data['settlement_status'] != 'not_asserted' ||
        data['sender_phone_sha256'] != null &&
            !(data['sender_phone_sha256'] is String &&
                RegExp(
                  r'^[a-f0-9]{64}$',
                ).hasMatch(data['sender_phone_sha256'] as String)) ||
        data['recorded_by_admin_id'] != null &&
            !_id(data['recorded_by_admin_id'])) {
      _invalid();
    }
    final amount = data['amount_rwf'] as int,
        allocated = data['allocated_amount_rwf'] as int,
        remaining = data['unallocated_amount_rwf'] as int;
    if (allocated > amount ||
        remaining != amount - allocated ||
        data['allocation_status'] !=
            (remaining == 0
                ? 'allocated'
                : allocated == 0
                ? 'unallocated'
                : 'partially_allocated') ||
        (data['verification_status'] == 'pending'
            ? data['verified_at'] != null ||
                  data['verified_by_admin_id'] != null
            : !_epoch(data['verified_at']) ||
                  !_id(data['verified_by_admin_id']))) {
      _invalid();
    }
    return ReconciliationTransaction._(Map.unmodifiable(data));
  }
}

class ReconciliationPaymentIdentity {
  const ReconciliationPaymentIdentity(
    this.name,
    this.provider,
    this.number,
    this.code,
  );
  final String name, provider, number, code;
  Map<String, dynamic> get json => {
    'display_name': name,
    'momo_provider': provider,
    'momo_number': number,
    'momo_pay_code': code,
  };
  bool get eligible => name.trim().length >= 2 && number.isNotEmpty;
  bool sameAs(ReconciliationPaymentIdentity other) =>
      name == other.name &&
      provider == other.provider &&
      number == other.number &&
      code == other.code;
  factory ReconciliationPaymentIdentity.parse(Map<String, dynamic> data) {
    _keys(data, {
      'display_name',
      'momo_provider',
      'momo_number',
      'momo_pay_code',
    });
    if (!_text(data['display_name'], maximum: 120) ||
        !{'', 'mtn_momo', 'airtel_money'}.contains(data['momo_provider']) ||
        data['momo_number'] is! String ||
        data['momo_number'] != '' &&
            !RegExp(
              r'^07[2389][0-9]{7}$',
            ).hasMatch(data['momo_number'] as String) ||
        data['momo_pay_code'] is! String ||
        data['momo_pay_code'] != '' &&
            !RegExp(
              r'^[0-9]{4,9}$',
            ).hasMatch(data['momo_pay_code'] as String)) {
      _invalid();
    }
    return ReconciliationPaymentIdentity(
      data['display_name'] as String,
      data['momo_provider'] as String,
      data['momo_number'] as String,
      data['momo_pay_code'] as String,
    );
  }
}

class ReconciliationMember {
  ReconciliationMember._(this.values, this.identity);
  final Map<String, dynamic> values;
  final ReconciliationPaymentIdentity identity;
  String get id => values['member_user_id'] as String;
  String get publicId => values['public_id'] as String;
  String get groupId => values['group_id'] as String;
  int get memberVersion => values['member_version'] as int;
  int get membershipVersion => values['membership_version'] as int;
  factory ReconciliationMember.parse(Map<String, dynamic> data) {
    _keys(data, {
      'member_user_id',
      'member_version',
      'member_type',
      'public_id',
      'display_name',
      'momo_provider',
      'momo_number',
      'momo_pay_code',
      'membership_version',
      'membership_role',
      'group_id',
      'group_title',
      'group_version',
      'payment_identity',
    });
    final identity = ReconciliationPaymentIdentity.parse(
      _map(data['payment_identity']),
    );
    if (!_id(data['member_user_id']) ||
        !_id(data['group_id']) ||
        ![
          'member_version',
          'membership_version',
          'group_version',
        ].every((key) => _integer(data[key], minimum: 1)) ||
        !{'app', 'direct'}.contains(data['member_type']) ||
        data['public_id'] is! String ||
        !RegExp(r'^[0-9]{6}$').hasMatch(data['public_id'] as String) ||
        !{
          'owner',
          'admin',
          'receiver',
          'member',
          'contributor',
          'viewer',
        }.contains(data['membership_role']) ||
        !_text(data['group_title'], minimum: 1) ||
        !identity.json.entries.every(
          (entry) => data[entry.key] == entry.value,
        )) {
      _invalid();
    }
    return ReconciliationMember._(Map.unmodifiable(data), identity);
  }
}

class ReconciliationProposal {
  ReconciliationProposal._(this.values, this.identity, this.payeeIdentity);
  final Map<String, dynamic> values, payeeIdentity;
  final ReconciliationPaymentIdentity identity;
  String get id => values['id'] as String;
  String get status => values['status'] as String;
  int get version => values['version'] as int;
  bool independent(String actorId) =>
      status == 'pending' && values['proposed_by_admin_id'] != actorId;
  bool currentFor(
    ReconciliationTransaction transaction,
    ReconciliationMember? member,
  ) =>
      member != null &&
      identity.eligible &&
      identity.sameAs(member.identity) &&
      member.id == values['member_user_id'] &&
      member.groupId == transaction.groupId &&
      member.memberVersion == values['member_version'] &&
      member.membershipVersion == values['membership_version'] &&
      member.values['group_version'] == values['group_version'] &&
      transaction.values['group_version'] == values['group_version'] &&
      transaction.values['payee_version'] == values['payee_version'] &&
      transaction.version == values['transaction_version'] &&
      transaction.groupId == values['group_id'] &&
      payeeIdentity['payee_id'] == transaction.values['payee_id'] &&
      payeeIdentity['network'] == transaction.values['network'] &&
      payeeIdentity['momo_number_or_code'] ==
          transaction.values['payee_momo'] &&
      transaction.remaining >= (values['amount_rwf'] as int) &&
      transaction.confirmed &&
      transaction.values['group_status'] == 'active' &&
      transaction.values['payee_status'] == 'active';
  factory ReconciliationProposal.parse(Map<String, dynamic> data) {
    _keys(data, {
      'id',
      'transaction_id',
      'group_id',
      'member_user_id',
      'amount_rwf',
      'transaction_version',
      'member_version',
      'membership_version',
      'group_version',
      'payee_version',
      'proposed_by_admin_id',
      'operation_request_id',
      'reason',
      'created_at',
      'status',
      'version',
      'review_id',
      'allocation_id',
      'reviewed_by_admin_id',
      'review_reason',
      'reviewed_at',
      'public_id',
      'current_display_name',
      'payment_identity',
      'payee_identity',
    });
    final identity = ReconciliationPaymentIdentity.parse(
      _map(data['payment_identity']),
    );
    final payee = _map(data['payee_identity']);
    _keys(payee, {'payee_id', 'network', 'momo_number_or_code'});
    if (![
          'id',
          'transaction_id',
          'group_id',
          'member_user_id',
          'proposed_by_admin_id',
          'operation_request_id',
        ].every((key) => _id(data[key])) ||
        ![
          'amount_rwf',
          'transaction_version',
          'member_version',
          'membership_version',
          'group_version',
          'payee_version',
        ].every((key) => _integer(data[key], minimum: 1)) ||
        !_epoch(data['created_at']) ||
        !_text(data['reason'], minimum: 8) ||
        !{'pending', 'approved', 'rejected'}.contains(data['status']) ||
        !_id(payee['payee_id']) ||
        !{'mtn_momo', 'airtel_money'}.contains(payee['network']) ||
        payee['momo_number_or_code'] is! String ||
        !RegExp(
          r'^[0-9]{4,12}$',
        ).hasMatch(payee['momo_number_or_code'] as String) ||
        data['public_id'] != null &&
            !(data['public_id'] is String &&
                RegExp(r'^[0-9]{6}$').hasMatch(data['public_id'] as String)) ||
        data['current_display_name'] != null &&
            !_text(data['current_display_name'])) {
      _invalid();
    }
    final pending = data['status'] == 'pending';
    if (data['version'] != (pending ? 1 : 2) ||
        (pending
            ? [
                'review_id',
                'allocation_id',
                'reviewed_by_admin_id',
                'review_reason',
                'reviewed_at',
              ].any((key) => data[key] != null)
            : !_id(data['review_id']) ||
                  !_id(data['reviewed_by_admin_id']) ||
                  !_epoch(data['reviewed_at']) ||
                  !_text(data['review_reason'], minimum: 8) ||
                  data['reviewed_by_admin_id'] ==
                      data['proposed_by_admin_id'] ||
                  (data['status'] == 'approved'
                      ? !_id(data['allocation_id'])
                      : data['allocation_id'] != null))) {
      _invalid();
    }
    return ReconciliationProposal._(
      Map.unmodifiable(data),
      identity,
      Map.unmodifiable(payee),
    );
  }
}

class ReconciliationDetail {
  const ReconciliationDetail(
    this.transaction,
    this.actorId,
    this.canPropose,
    this.canReview,
    this.related,
  );
  final ReconciliationTransaction transaction;
  final String actorId;
  final bool canPropose, canReview;
  final Map<String, ReconciliationPage<Map<String, dynamic>>> related;
}

Map<String, dynamic> _relatedRow(
  String kind,
  Map<String, dynamic> row,
  String transactionId,
) {
  const schemas = {
    'evidence': {
      'id',
      'kind',
      'reference',
      'sha256',
      'recorded_by_admin_id',
      'created_at',
    },
    'verification_reviews': {
      'id',
      'transaction_id',
      'evidence_id',
      'outcome',
      'transaction_version',
      'reviewed_by_admin_id',
      'operation_request_id',
      'reason',
      'reviewed_at',
      'created_at',
    },
    'allocations': {
      'id',
      'transaction_id',
      'group_id',
      'member_user_id',
      'amount_rwf',
      'operation_request_id',
      'created_by_admin_id',
      'created_at',
      'public_id',
      'display_name',
    },
    'journals': {
      'id',
      'description',
      'status',
      'version',
      'created_by_admin_id',
      'edited_by_admin_id',
      'posted_by_admin_id',
      'allocation_id',
      'created_at',
    },
  };
  if (kind == 'proposals') {
    final proposal = ReconciliationProposal.parse(row);
    if (row['transaction_id'] != transactionId) _invalid();
    return proposal.values;
  }
  _keys(row, schemas[kind]!);
  if (!_id(row['id']) ||
      !_epoch(row['created_at']) ||
      row.containsKey('transaction_id') &&
          row['transaction_id'] != transactionId) {
    _invalid();
  }
  for (final entry in row.entries) {
    if (entry.value == null) continue;
    if (entry.key.endsWith('_id') &&
        entry.key != 'public_id' &&
        !_id(entry.value)) {
      _invalid();
    }
    if ((entry.key.endsWith('_version') ||
            entry.key == 'version' ||
            entry.key.endsWith('_rwf') ||
            entry.key == 'reviewed_at') &&
        !_integer(entry.value, minimum: 1)) {
      _invalid();
    }
    if (entry.key == 'reviewed_at' && !_epoch(entry.value)) _invalid();
    if (entry.key == 'public_id' &&
        !(entry.value is String &&
            RegExp(r'^[0-9]{6}$').hasMatch(entry.value as String))) {
      _invalid();
    }
    if (entry.value is! String && entry.value is! int) _invalid();
  }
  if (kind == 'evidence' &&
      (!{
            'receiver_statement',
            'provider_statement',
            'payer_receipt',
            'operator_observation',
          }.contains(row['kind']) ||
          !_text(row['reference'], minimum: 1) ||
          row['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(row['sha256'] as String))) {
    _invalid();
  }
  if (kind == 'verification_reviews' &&
      (!{
            'confirmation_recorded',
            'rejection_recorded',
            'evidence_conflict',
          }.contains(row['outcome']) ||
          !_text(row['reason'], minimum: 8))) {
    _invalid();
  }
  if (kind == 'journals' &&
      (!{'draft', 'posted'}.contains(row['status']) ||
          !_text(row['description'], minimum: 1))) {
    _invalid();
  }
  return Map.unmodifiable(row);
}

class ReconciliationReceipt {
  ReconciliationReceipt._(
    this.values, {
    this.sourceModel = 'transaction_journals',
  });
  final Map<String, dynamic> values;
  final String sourceModel;
  String get proposalId => values['resource_id'] as String;
  String get status => values['proposal_status'] == 'proposed'
      ? 'pending'
      : values['proposal_status'] as String;
  factory ReconciliationReceipt.parse(Map<String, dynamic> data) {
    if (data.containsKey('contract_version') || data.containsKey('model')) {
      final review = data['proposal_status'] != 'proposed';
      _keys(data, {
        'contract_version',
        'model',
        'request_id',
        'status',
        'resource_type',
        'resource_id',
        'transaction_id',
        'version',
        'proposal_status',
        'settlement_status',
        if (review) 'transaction_version',
      });
      if (data['contract_version'] != 2 ||
          data['model'] != 'canonical_evidence_ledger' ||
          data['status'] != 'succeeded' ||
          data['resource_type'] != 'reconciliation_proposals' ||
          ![
            'request_id',
            'resource_id',
            'transaction_id',
          ].every((key) => _id(data[key])) ||
          !{
            'proposed',
            'approved',
            'rejected',
          }.contains(data['proposal_status']) ||
          data['version'] != (review ? 2 : 1) ||
          data['settlement_status'] != 'not_asserted' ||
          (review && !_integer(data['transaction_version'], minimum: 1))) {
        _invalid();
      }
      return ReconciliationReceipt._(
        Map.unmodifiable(data),
        sourceModel: 'canonical_evidence_ledger',
      );
    }
    final review = data['proposal_status'] != 'pending';
    _keys(data, {
      'request_id',
      'status',
      'resource_type',
      'resource_id',
      'transaction_id',
      'version',
      'proposal_status',
      if (review) ...{
        'review_id',
        'allocation_id',
        'transaction_version',
        'settlement_status',
      },
    });
    if (data['status'] != 'succeeded' ||
        data['resource_type'] != 'reconciliation_proposals' ||
        ![
          'request_id',
          'resource_id',
          'transaction_id',
        ].every((key) => _id(data[key])) ||
        !{
          'pending',
          'approved',
          'rejected',
        }.contains(data['proposal_status']) ||
        data['version'] != (review ? 2 : 1) ||
        review &&
            (!_id(data['review_id']) ||
                !_integer(data['transaction_version'], minimum: 1) ||
                data['settlement_status'] != 'not_asserted' ||
                (data['proposal_status'] == 'approved'
                    ? !_id(data['allocation_id'])
                    : data['allocation_id'] != null))) {
      _invalid();
    }
    return ReconciliationReceipt._(Map.unmodifiable(data));
  }
}

/// One immutable attempt survives response loss. Only its actor can reconcile it.
class ReconciliationAttempt {
  ReconciliationAttempt._(
    this.key,
    this.path,
    this.permission,
    this.body,
    this.authority,
    this.transactionId,
    this.proposalId,
    this.memberPublicId,
  );
  final String key, path, permission, transactionId;
  final String? proposalId;
  final String? memberPublicId;
  final Map<String, dynamic> body;
  final Object authority;
  bool _submitted = false;
  bool _retryAllowed = false;
  bool _completed = false;
  bool _needsReconfirmation = false;
  bool get needsReconfirmation => _needsReconfirmation;
}

const _pendingSchema = AdminPendingAttemptSchema(
  fields: {'path', 'transaction_id', 'proposal_id', 'member_public_id', 'body'},
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

class ReconciliationLookup {
  const ReconciliationLookup(this.status, this.receipt);
  final String status;
  final ReconciliationReceipt? receipt;
}

/// A route change cannot discard an uncertain mutation. The store resets when
/// the authenticated authority changes and never persists a session secret.
final cloudflareReconciliationAttemptsProvider =
    StateProvider<Map<String, ReconciliationAttempt>>((ref) {
      ref.watch(
        cloudflareAdminSessionProvider.select(
          (state) => state.asData?.value?.authorityKey,
        ),
      );
      return const {};
    });

final cloudflareReconciliationApiProvider =
    Provider<CloudflareReconciliationApi>((ref) {
      ref.watch(
        cloudflareAdminSessionProvider.select(
          (state) => state.asData?.value?.authorityKey,
        ),
      );
      return CloudflareReconciliationApi(
        ref.read(cloudflareAdminSessionProvider.notifier),
        pendingStore: ref.read(adminPendingAttemptStoreProvider),
      );
    });
