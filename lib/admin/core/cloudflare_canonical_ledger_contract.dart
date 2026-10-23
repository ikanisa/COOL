part of 'cloudflare_admin_repository.dart';

const _canonicalMetricLabels = {
  'users': 'Users',
  'groups': 'Groups',
  'active_members': 'Active members',
  'payees': 'Payees',
  'transactions': 'Transactions',
  'app_users': 'App users',
  'direct_users': 'Direct users',
  'admin_users': 'Admin users',
  'staff_users': 'Staff users',
  'active_payees': 'Active payees',
  'unallocated_transactions': 'Unallocated transactions',
  'ledger_entries': 'Ledger entries',
  'reversed_entries': 'Reversal entries',
  'payment_evidence': 'Retained payment evidence',
};
const _canonicalAmountLabels = {
  'total_recorded_rwf': 'Recorded evidence amount',
  'total_reconciled_rwf': 'Reconciled evidence amount',
  'total_unallocated_rwf': 'Unallocated evidence amount',
  'total_net_contributions_rwf': 'Net recorded contributions',
};

bool _coreSignedInteger(Object? value) =>
    value is int && value != 0 && value.abs() <= _maximumExactInteger;

void _validateCanonicalCorePerson(Map<dynamic, dynamic> row) {
  final collectId = row['collect_user_id'],
      operatorId = row['operator_admin_id'];
  final role = row['operator_role'], memberType = row['member_type'];
  final expectedTypes = <String>[
    if (role != null) role == 'staff' ? 'Staff' : 'Admin',
    if (collectId != null && memberType == 'operator' && operatorId == null)
      'Operator',
    if (collectId != null && memberType == 'direct') 'Direct',
    if (collectId != null && memberType == 'app') 'App',
  ];
  if (row['person_id'] != row['id'] ||
      (collectId == null && operatorId == null) ||
      (collectId != null && (!_coreId(collectId) || row['id'] != collectId)) ||
      (collectId == null && row['id'] != operatorId) ||
      (operatorId != null && !_coreId(operatorId)) ||
      (operatorId == null
          ? role != null ||
                row['operator_status'] != null ||
                row['operator_public_id'] != null
          : !{'owner', 'admin', 'staff'}.contains(role) ||
                !{
                  'invited',
                  'active',
                  'revoked',
                }.contains(row['operator_status']) ||
                !_publicId(row['operator_public_id'])) ||
      (collectId == null
          ? memberType != null
          : !{'app', 'direct', 'operator'}.contains(memberType)) ||
      !_publicId(row['public_id']) ||
      row['title'] != row['public_id'] ||
      row['user_types'] is! List ||
      jsonEncode(row['user_types']) != jsonEncode(expectedTypes) ||
      !_optionalMatches(row['phone_e164'], r'^\+2507[2389][0-9]{7}$') ||
      row['whatsapp_number'] !=
          (memberType == 'app' ? row['phone_e164'] : null) ||
      !_optionalMatches(row['email'], r'^[^\s@]+@[^\s@]+$') ||
      !_optionalMatches(row['momo_number'], r'^07[2389][0-9]{7}$') ||
      !_optionalMatches(row['momo_pay_code'], r'^[0-9]{4,9}$') ||
      !{null, 'mtn_momo', 'airtel_money'}.contains(row['momo_provider']) ||
      !_coreInteger(row['total_contributed_rwf']) ||
      row['posted_contributed_rwf'] != null ||
      row['contribution_basis'] != 'reconciled_evidence_entries' ||
      row['display_name_recorded'] is! bool ||
      (row['display_name_recorded'] == true
          ? row['display_name'] is! String ||
                (row['display_name'] as String).trim().isEmpty ||
                row['name_verification'] != 'recorded_not_provider_verified'
          : row['display_name'] != null ||
                row['name_verification'] != 'not_recorded')) {
    _invalidCore();
  }
}

void _validateCanonicalCoreRow(
  CloudflareCoreArea area,
  Map<dynamic, dynamic> row,
) {
  const common = {
    'id',
    'title',
    'subtitle',
    'status',
    'amount',
    'created_at',
    'country_code',
    'currency_code',
  };
  final extra = switch (area) {
    CloudflareCoreArea.groups => {
      'slug',
      'collection_type',
      'purpose_label',
      'visibility',
      'is_platform_sponsored',
      'active_members',
      'version',
      'updated_at',
    },
    CloudflareCoreArea.users || CloudflareCoreArea.members => {
      'public_id',
      'display_name',
      'display_name_recorded',
      'phone_masked',
      'email_masked',
      'active_groups',
      'account_status',
      'person_id',
      'collect_user_id',
      'operator_admin_id',
      'operator_public_id',
      'operator_role',
      'operator_status',
      'user_types',
      'member_type',
      'phone_e164',
      'email',
      'whatsapp_number',
      'momo_provider',
      'momo_number',
      'momo_pay_code',
      'total_contributed_rwf',
      'posted_contributed_rwf',
      'contribution_basis',
      'name_verification',
      'version',
      'updated_at',
    },
    CloudflareCoreArea.payees => {
      'group_id',
      'group_name',
      'network',
      'momo_masked',
      'momo_number_or_code',
      'momo_number',
      'momo_pay_code',
      'receiver_basis',
      'version',
    },
    CloudflareCoreArea.transactions => {
      ..._canonicalPaymentFactKeys,
      'group_id',
      'group_name',
      'payee_id',
      'payee_label',
      'network',
      'rail',
      'provider_reference',
      'amount_rwf',
      'allocated_amount_rwf',
      'allocation_status',
      'observed_at',
      'public_reference',
      'reference_source',
      'evidence_id',
      'evidence_level',
      'version',
      'member_user_id',
      'contribution_basis',
    },
    CloudflareCoreArea.ledgers => {
      'group_id',
      'group_name',
      'transaction_id',
      'payment_id',
      'evidence_id',
      'member_user_id',
      'kind',
      'signed_amount_rwf',
      'amount_rwf',
      'reverses_entry_id',
      'posted_at',
      'contribution_basis',
      'provider_confirmation',
      'settlement_status',
    },
  };
  final allowed = {...common, ...extra};
  if (row.length != allowed.length || !row.keys.every(allowed.contains)) {
    _invalidCore();
  }
  switch (area) {
    case CloudflareCoreArea.groups:
      if (!_coreInteger(row['active_members']) ||
          row['amount'] != '${row['active_members']} members' ||
          row['slug'] is! String ||
          row['collection_type'] is! String ||
          !{
            'private',
            'public_pending',
            'public_approved',
          }.contains(row['visibility']) ||
          row['is_platform_sponsored'] is! bool ||
          !_coreInteger(row['version']) ||
          row['version'] == 0 ||
          !_coreTimestamp(row['updated_at']) ||
          (row['purpose_label'] != null && row['purpose_label'] is! String)) {
        _invalidCore();
      }
    case CloudflareCoreArea.users:
    case CloudflareCoreArea.members:
      _validateCanonicalCorePerson(row);
      if (!_coreInteger(row['active_groups']) ||
          row['amount'] != '${row['active_groups']} groups' ||
          (area == CloudflareCoreArea.members &&
              (row['active_groups'] == 0 ||
                  row['member_type'] == 'operator')) ||
          !_coreInteger(row['version']) ||
          row['version'] == 0 ||
          !_coreTimestamp(row['updated_at']) ||
          row['account_status'] != row['status'] ||
          (row['public_id'] != null &&
              (row['public_id'] is! String ||
                  !RegExp(
                    r'^[0-9]{6}$',
                  ).hasMatch(row['public_id'] as String))) ||
          (row['display_name'] != null && row['display_name'] is! String) ||
          (row['phone_masked'] != null && !_maskedRoute(row['phone_masked'])) ||
          (row['email_masked'] != null &&
              (row['email_masked'] is! String ||
                  !RegExp(
                    r'^.•••@[^\s@]+$',
                  ).hasMatch(row['email_masked'] as String)))) {
        _invalidCore();
      }
    case CloudflareCoreArea.payees:
      if (!_coreId(row['group_id']) ||
          row['group_name'] is! String ||
          !{'mtn_momo', 'airtel_money'}.contains(row['network']) ||
          !_maskedRoute(row['momo_masked']) ||
          !_optionalMatches(
            row['momo_number'],
            r'^(?:07[2389][0-9]{7}|\+?2507[2389][0-9]{7})$',
          ) ||
          !_optionalMatches(row['momo_pay_code'], r'^[0-9]{4,12}$') ||
          !_optionalMatches(
            row['momo_number_or_code'],
            r'^(?:[0-9]{4,12}|\+2507[2389][0-9]{7})$',
          ) ||
          row['momo_number_or_code'] == null ||
          row['receiver_basis'] != 'operator_recorded' ||
          !_coreInteger(row['version']) ||
          row['version'] == 0 ||
          (row['momo_number'] == null) == (row['momo_pay_code'] == null) ||
          row['momo_number_or_code'] !=
              (row['momo_number'] ?? row['momo_pay_code']) ||
          row['amount'] != row['momo_number_or_code']) {
        _invalidCore();
      }
    case CloudflareCoreArea.transactions:
      _validateCanonicalPaymentFacts(row);
      if (!_coreId(row['group_id']) ||
          !_coreId(row['payee_id']) ||
          row['group_name'] is! String ||
          row['payee_label'] is! String ||
          !{null, 'mtn_momo', 'airtel_money'}.contains(row['network']) ||
          row['rail'] != 'rwanda_momo' ||
          row['title'] != (row['provider_reference'] ?? row['id']) ||
          (row['provider_reference'] != null &&
              (row['provider_reference'] is! String ||
                  (row['provider_reference'] as String).trim().isEmpty)) ||
          !_coreInteger(row['amount_rwf']) ||
          row['amount_rwf'] == 0 ||
          !_coreInteger(row['allocated_amount_rwf']) ||
          (row['allocated_amount_rwf'] as int) > (row['amount_rwf'] as int) ||
          !_coreId(row['evidence_id']) ||
          !{
            'operator_recorded',
            'provider_authenticated',
          }.contains(row['evidence_level']) ||
          !_coreInteger(row['version']) ||
          row['version'] == 0 ||
          (row['member_user_id'] != null && !_coreId(row['member_user_id'])) ||
          row['public_reference'] != null ||
          row['reference_source'] != 'retained_evidence' ||
          row['contribution_basis'] != 'reconciled_evidence_entries' ||
          !_coreTimestamp(row['observed_at']) ||
          row['amount'] != '${row['amount_rwf']}') {
        _invalidCore();
      }
      final allocation = row['allocated_amount_rwf'] == row['amount_rwf']
          ? 'allocated'
          : (row['allocated_amount_rwf'] as int) > 0
          ? 'partial'
          : 'unallocated';
      if (row['allocation_status'] != allocation) _invalidCore();
    case CloudflareCoreArea.ledgers:
      if (!_coreId(row['group_id']) ||
          row['group_name'] is! String ||
          !_coreId(row['payment_id']) ||
          row['transaction_id'] != row['payment_id'] ||
          !_coreId(row['evidence_id']) ||
          (row['member_user_id'] != null && !_coreId(row['member_user_id'])) ||
          !{'contribution', 'reversal', 'correction'}.contains(row['kind']) ||
          row['status'] != row['kind'] ||
          !_coreSignedInteger(row['signed_amount_rwf']) ||
          !_coreInteger(row['amount_rwf']) ||
          row['amount_rwf'] != (row['signed_amount_rwf'] as int).abs() ||
          row['amount'] != '${row['signed_amount_rwf']}' ||
          !_coreTimestamp(row['posted_at']) ||
          row['created_at'] != row['posted_at'] ||
          row['contribution_basis'] != 'reconciled_evidence_entries' ||
          row['provider_confirmation'] != false ||
          row['settlement_status'] != 'not_asserted') {
        _invalidCore();
      }
      final signed = row['signed_amount_rwf'] as int;
      if ((row['kind'] == 'contribution' &&
              (signed <= 0 || row['reverses_entry_id'] != null)) ||
          (row['kind'] != 'contribution' &&
              (!_coreId(row['reverses_entry_id']) ||
                  row['reverses_entry_id'] == row['id'])) ||
          (row['kind'] == 'reversal' && signed >= 0)) {
        _invalidCore();
      }
  }
}

const _canonicalPaymentFactKeys = <String>{
  'source_fact_id',
  'source_kind',
  'parser_version',
  'source_link_basis',
  'source_review_id',
  'source_extraction_status',
  'source_body_sha256',
  'source_payload_sha256',
  'source_parsed_at',
  'payer_name',
  'payer_phone',
  'payer_masked_phone',
  'payer_last3',
  'payer_last3_known',
  'payee_momo_number',
  'payee_momo_code',
  'payee_momo_number_or_code',
  'momo_transaction_reference',
  'momo_timestamp_local',
  'momo_timezone_offset',
  'timezone_known',
  'source_amount_rwf',
  'wallet_balance_rwf',
  'source_network',
  'direction',
  'is_payment',
  'payer_source_match_status',
  'payer_insights_status',
  'public_reference_source_fact_id',
  'public_reference_random_source',
  'payee_last3_known',
  'provider_confirmation',
  'settlement_status',
};

void _validateCanonicalPaymentFacts(Map<dynamic, dynamic> row) {
  const unavailableFacts = {
    'source_fact_id',
    'source_kind',
    'parser_version',
    'source_review_id',
    'source_extraction_status',
    'source_body_sha256',
    'source_payload_sha256',
    'source_parsed_at',
    'payer_phone',
    'payer_masked_phone',
    'payer_last3',
    'momo_transaction_reference',
    'momo_timestamp_local',
    'momo_timezone_offset',
    'source_amount_rwf',
    'wallet_balance_rwf',
    'source_network',
    'direction',
    'is_payment',
    'public_reference_source_fact_id',
    'public_reference_random_source',
  };
  if (unavailableFacts.any((key) => row[key] != null) ||
      row['source_link_basis'] != 'not_recorded' ||
      row['payer_last3_known'] != false ||
      row['payee_last3_known'] != false ||
      row['timezone_known'] != false ||
      row['payer_source_match_status'] != 'not_recorded' ||
      row['payer_insights_status'] !=
          (row['member_user_id'] == null ? 'not_attributed' : 'available') ||
      (row['payer_name'] != null &&
          (row['payer_name'] is! String ||
              (row['payer_name'] as String).trim().isEmpty)) ||
      !_optionalMatches(
        row['payee_momo_number'],
        r'^(?:07[2389][0-9]{7}|\+?2507[2389][0-9]{7})$',
      ) ||
      !_optionalMatches(row['payee_momo_code'], r'^[0-9]{4,12}$') ||
      !_optionalMatches(
        row['payee_momo_number_or_code'],
        r'^(?:[0-9]{4,12}|\+2507[2389][0-9]{7})$',
      ) ||
      (row['payee_momo_number'] != null && row['payee_momo_code'] != null) ||
      row['payee_momo_number_or_code'] !=
          (row['payee_momo_number'] ?? row['payee_momo_code']) ||
      row['provider_confirmation'] != false ||
      row['settlement_status'] != 'not_asserted') {
    _invalidCore();
  }
}

List<AdminMetric> _canonicalOverviewMetrics(Map<String, dynamic> result) {
  const fields = {
    'contract_version',
    'model',
    'country_code',
    'measured_at',
    'counts',
    'amounts',
    'metrics',
    'contribution_basis',
    'collected_basis',
    'reconciliations_available',
  };
  if (result.length != fields.length ||
      !result.keys.every(fields.contains) ||
      result['contract_version'] != 2 ||
      result['model'] != 'canonical_evidence_ledger' ||
      result['country_code'] != 'RW' ||
      !_coreTimestamp(result['measured_at']) ||
      result['counts'] is! Map ||
      result['amounts'] is! Map ||
      result['contribution_basis'] != 'reconciled_evidence_entries' ||
      result['collected_basis'] != 'retained_received_evidence' ||
      result['reconciliations_available'] != true ||
      result['metrics'] is! List) {
    _invalidCore();
  }
  final counts = result['counts'] as Map;
  final amounts = result['amounts'] as Map;
  final metrics = result['metrics'] as List;
  if (counts.length != _canonicalMetricLabels.length ||
      !counts.keys.every(_canonicalMetricLabels.containsKey) ||
      counts.values.any(
        (value) => value is! int || value < 0 || value > _maximumExactInteger,
      ) ||
      amounts.length != _canonicalAmountLabels.length ||
      !amounts.keys.every(_canonicalAmountLabels.containsKey) ||
      !amounts.values.every(_decimalAmount) ||
      metrics.length !=
          _canonicalMetricLabels.length + _canonicalAmountLabels.length) {
    _invalidCore();
  }
  final labels = {..._canonicalMetricLabels, ..._canonicalAmountLabels};
  final seen = <String>{};
  for (final metric in metrics) {
    if (metric is! Map ||
        metric.length != 4 ||
        !labels.containsKey(metric['key']) ||
        labels[metric['key']] != metric['label'] ||
        metric['status'] != 'measured' ||
        metric['value'] is! String ||
        !seen.add(metric['key'] as String)) {
      _invalidCore();
    }
    final key = metric['key'] as String;
    if (metric['value'] != '${counts[key] ?? amounts[key]}') _invalidCore();
  }
  return List.unmodifiable([
    for (final entry in labels.entries)
      AdminMetric(
        label: entry.value,
        value: '${counts[entry.key] ?? amounts[entry.key]}',
        status: 'measured',
        sourceModel: 'canonical_evidence_ledger',
      ),
  ]);
}

extension CanonicalCoreArea on CloudflareCoreArea {
  List<String> get canonicalStatuses => switch (this) {
    CloudflareCoreArea.groups => const ['active', 'suspended', 'archived'],
    CloudflareCoreArea.users ||
    CloudflareCoreArea.members => const ['active', 'suspended', 'deleted'],
    CloudflareCoreArea.payees => const ['active', 'inactive'],
    CloudflareCoreArea.transactions => const [
      'recorded',
      'reconciled',
      'confirmed',
      'ambiguous',
      'corrected',
      'reversed',
    ],
    CloudflareCoreArea.ledgers => const [
      'contribution',
      'reversal',
      'correction',
    ],
  };
  bool acceptsStatus(String value) =>
      statuses.contains(value) || canonicalStatuses.contains(value);
  Map<String, String> get canonicalSortFields => {
    'created_at': 'Created',
    'status': 'Status',
    ...switch (this) {
      CloudflareCoreArea.groups => {
        'title': 'Name',
        'slug': 'Slug',
        'collection_type': 'Type',
        'visibility_status': 'Visibility',
        'active_members': 'Members',
      },
      CloudflareCoreArea.users || CloudflareCoreArea.members => {
        'public_id': 'ID',
        'full_name': 'Name',
        'email': 'Email',
        'member_type': 'App / Direct type',
        'phone': 'WhatsApp',
        'momo_number': 'MoMo number',
        'momo_pay_code': 'MoMo code',
        'active_groups': 'Groups',
        'net_contributed_rwf': 'Contributed',
      },
      CloudflareCoreArea.payees => {
        'label': 'Name',
        'group_title': 'Group',
        'momo_number_or_code': 'MoMo number / code',
      },
      CloudflareCoreArea.transactions => {
        'amount_minor': 'Amount',
        'net_amount': 'Net contributions',
        'payer_display_name': 'Payer name',
        'receiver_momo_number': 'Recorded receiver',
        'external_reference': 'Evidence reference',
        'group_title': 'Group',
        'observed_at': 'Observed',
      },
      CloudflareCoreArea.ledgers => {
        'amount_minor': 'Signed amount (RWF)',
        'group_title': 'Group',
        'payment_id': 'Payment ID',
        'evidence_id': 'Evidence ID',
      },
    },
  };
  bool acceptsSort(String value) {
    final field = value.replaceFirst(RegExp(r'_(asc|desc)$'), '');
    return RegExp(r'_(asc|desc)$').hasMatch(value) &&
        (sortFields.containsKey(field) ||
            canonicalSortFields.containsKey(field));
  }
}
