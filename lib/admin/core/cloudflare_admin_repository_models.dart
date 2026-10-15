part of 'cloudflare_admin_repository.dart';

enum CloudflareCoreArea {
  groups(
    'Groups',
    'admin_list_collections',
    'collections.read',
    'folder_copy',
    'Members',
    ['draft', 'active', 'suspended', 'archived'],
  ),
  users('Users', 'admin_list_users', 'users.read', 'person', 'Active groups', [
    'invited',
    'active',
    'suspended',
    'closed',
    'revoked',
  ]),
  members(
    'Members',
    'admin_list_members',
    'users.read',
    'people',
    'Active groups',
    ['invited', 'active', 'suspended', 'closed'],
  ),
  payees(
    'Payees',
    'admin_list_collect_payees',
    'receivers.read',
    'person_pin_circle',
    'Payment route',
    ['active', 'inactive'],
  ),
  transactions(
    'Transactions',
    'admin_list_collect_transactions',
    'payments.read',
    'receipt_long',
    'Amount',
    [
      'pending',
      'confirmation_recorded',
      'rejection_recorded',
      'evidence_conflict',
    ],
  ),
  ledgers(
    'Ledgers',
    'admin_list_collect_ledgers',
    'ledger.read',
    'menu_book',
    'Debit total',
    ['draft', 'posted'],
  );

  const CloudflareCoreArea(
    this.title,
    this.rpcName,
    this.permission,
    this.iconKey,
    this.valueLabel,
    this.statuses,
  );
  final String title, rpcName, permission, iconKey, valueLabel;
  final List<String> statuses;
  String get path => '/admin/$name';
  Map<String, String> get sortFields => {
    'created_at': 'Created',
    'status': 'Status',
    ...switch (this) {
      groups => {
        'title': 'Name',
        'slug': 'Slug',
        'collection_type': 'Type',
        'visibility': 'Visibility',
        'active_members': 'Members',
      },
      users || members => {
        'public_id': 'ID',
        'display_name': 'Name',
        'email': 'Email',
        'member_type': 'App / Direct type',
        'whatsapp_number': 'WhatsApp',
        'momo_number': 'MoMo number',
        'momo_pay_code': 'MoMo code',
        'active_groups': 'Groups',
        'total_contributed_rwf': 'Contributed',
        'posted_contributed_rwf': 'Posted contributions',
      },
      payees => {
        'label': 'Name',
        'group_title': 'Group',
        'momo_number_or_code': 'MoMo number / code',
      },
      transactions => {
        'public_reference': 'Transaction ID',
        'allocation_status': 'Allocation status',
        'amount_rwf': 'Amount',
        'allocated_amount_rwf': 'Allocated',
        'remaining_rwf': 'Remaining',
        'payer_name': 'Payer name',
        'payer_last3': 'Payer last 3',
        'payee_momo_number_or_code': 'Payee MoMo number / code',
        'group_title': 'Group',
        'payee_label': 'Payee',
        'observed_at': 'Observed',
      },
      ledgers => {
        'description': 'Description',
        'group_title': 'Group',
        'debit_rwf': 'Debit',
        'credit_rwf': 'Credit',
        'entry_count': 'Entries',
        'posted_at': 'Posted',
      },
    },
  };
  bool supportsSort(String value) =>
      RegExp(r'_(asc|desc)$').hasMatch(value) &&
      sortFields.containsKey(value.replaceFirst(RegExp(r'_(asc|desc)$'), ''));
}

const _maximumExactInteger = 9007199254740991;
final _coreUuid = RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$');
const _coreMetricLabels = {
  'users': 'Users',
  'groups': 'Groups',
  'active_members': 'Active members',
  'payees': 'Payees',
  'transactions': 'Transactions',
  'draft_journals': 'Draft journals',
  'posted_journals': 'Posted journals',
  'app_users': 'App users',
  'direct_users': 'Direct users',
  'admin_users': 'Admin users',
  'staff_users': 'Staff users',
  'active_payees': 'Active payees',
  'unallocated_transactions': 'Unallocated transactions',
  'sms_receipts': 'SMS receipts',
  'receipts_needing_review': 'Receipts needing review',
};
const _coreAmountLabels = {
  'total_collected_rwf': 'Total collected',
  'total_allocated_rwf': 'Total allocated',
  'total_unallocated_rwf': 'Total unallocated',
  'total_posted_contributions_rwf': 'Posted contributions',
};

Never _invalidCore() => throw const FormatException(
  'The workspace response could not be verified.',
);

bool _coreTimestamp(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
      ).hasMatch(value)) {
    return false;
  }
  return DateTime.tryParse(value)?.toUtc().toIso8601String() == value;
}

bool _coreInteger(Object? value) =>
    value is int && value >= 0 && value <= _maximumExactInteger;
bool _coreId(Object? value) => value is String && _coreUuid.hasMatch(value);
bool _maskedRoute(Object? value) =>
    value is String && RegExp(r'^••••(?:[0-9]{2}|[0-9]{4})$').hasMatch(value);
bool _publicId(Object? value) =>
    value is String && RegExp(r'^[0-9]{6}$').hasMatch(value);
bool _decimalAmount(Object? value) =>
    value is String && RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value);
bool _optionalMatches(Object? value, String pattern) =>
    value == null || value is String && RegExp(pattern).hasMatch(value);

void _validateCorePerson(Map<dynamic, dynamic> row) {
  final collectId = row['collect_user_id'],
      operatorId = row['operator_admin_id'];
  final role = row['operator_role'], memberType = row['member_type'];
  final expectedTypes = <String>[
    if (role != null) role == 'staff' ? 'Staff' : 'Admin',
    if (collectId != null) memberType == 'direct' ? 'Direct' : 'App',
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
          : !{'app', 'direct'}.contains(memberType)) ||
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
      !_coreInteger(row['posted_contributed_rwf']) ||
      (row['posted_contributed_rwf'] as int) >
          (row['total_contributed_rwf'] as int) ||
      row['contribution_basis'] != 'confirmation_recorded_allocations' ||
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

void _validateCoreRow(CloudflareCoreArea area, Map<dynamic, dynamic> row) {
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
    },
    CloudflareCoreArea.payees => {
      'group_id',
      'group_name',
      'network',
      'momo_masked',
      'momo_number_or_code',
      'momo_number',
      'momo_pay_code',
    },
    CloudflareCoreArea.transactions => {
      ...cloudflareTransactionFactKeys,
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
      'posted_journals',
      'observed_at',
    },
    CloudflareCoreArea.ledgers => {
      'group_id',
      'group_name',
      'transaction_id',
      'allocation_id',
      'debit_rwf',
      'credit_rwf',
      'entry_count',
      'balanced',
      'posted_at',
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
          !{'private', 'public_approved'}.contains(row['visibility']) ||
          row['is_platform_sponsored'] is! bool ||
          (row['purpose_label'] != null && row['purpose_label'] is! String)) {
        _invalidCore();
      }
    case CloudflareCoreArea.users:
    case CloudflareCoreArea.members:
      _validateCorePerson(row);
      if (!_coreInteger(row['active_groups']) ||
          row['amount'] != '${row['active_groups']} groups' ||
          (area == CloudflareCoreArea.members && row['active_groups'] == 0) ||
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
            r'^(?:07[2389][0-9]{7}|2507[2389][0-9]{7})$',
          ) ||
          !_optionalMatches(row['momo_pay_code'], r'^[0-9]{4,12}$') ||
          !_optionalMatches(row['momo_number_or_code'], r'^[0-9]{4,12}$') ||
          row['momo_number_or_code'] == null ||
          (row['momo_number'] == null) == (row['momo_pay_code'] == null) ||
          row['momo_number_or_code'] !=
              (row['momo_number'] ?? row['momo_pay_code']) ||
          row['amount'] != row['momo_number_or_code']) {
        _invalidCore();
      }
    case CloudflareCoreArea.transactions:
      validateCloudflareTransactionFacts(Map<String, dynamic>.from(row));
      if (!_coreId(row['group_id']) ||
          !_coreId(row['payee_id']) ||
          row['group_name'] is! String ||
          row['payee_label'] is! String ||
          !{'mtn_momo', 'airtel_money'}.contains(row['network']) ||
          row['rail'] != 'rwanda_momo' ||
          row['transaction_reference'] != row['title'] ||
          row['provider_reference'] is! String ||
          !_coreInteger(row['amount_rwf']) ||
          row['amount_rwf'] == 0 ||
          !_coreInteger(row['allocated_amount_rwf']) ||
          (row['allocated_amount_rwf'] as int) > (row['amount_rwf'] as int) ||
          !_coreInteger(row['posted_journals']) ||
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
          ((row['transaction_id'] == null) != (row['allocation_id'] == null)) ||
          (row['transaction_id'] != null && !_coreId(row['transaction_id'])) ||
          (row['allocation_id'] != null && !_coreId(row['allocation_id'])) ||
          !_coreInteger(row['debit_rwf']) ||
          !_coreInteger(row['credit_rwf']) ||
          !_coreInteger(row['entry_count']) ||
          row['balanced'] is! bool ||
          row['amount'] != '${row['debit_rwf']}') {
        _invalidCore();
      }
      final balanced =
          (row['entry_count'] as int) >= 2 &&
          (row['debit_rwf'] as int) > 0 &&
          row['debit_rwf'] == row['credit_rwf'];
      if (row['balanced'] != balanced ||
          (row['status'] == 'posted' &&
              (!balanced || !_coreTimestamp(row['posted_at']))) ||
          (row['status'] == 'draft' && row['posted_at'] != null)) {
        _invalidCore();
      }
  }
}

const cloudflareTransactionFactKeys = <String>{
  'transaction_reference',
  'reference_payer_last3_known',
  'reference_payee_last3_known',
  'reference_source_fact_id',
  'reference_random_source',
  'source_fact_id',
  'source_link_basis',
  'source_review_id',
  'source_kind',
  'parser_version',
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
  'provider_confirmation',
  'settlement_status',
};
void validateCloudflareTransactionFacts(
  Map<String, dynamic> row, {
  bool operating = false,
}) {
  if (!cloudflareTransactionFactKeys.every(row.containsKey) ||
      !_optionalMatches(row['transaction_reference'], r'^[0-9]{18}$') ||
      row['transaction_reference'] == null ||
      ![
        'reference_payer_last3_known',
        'reference_payee_last3_known',
        'payer_last3_known',
        'timezone_known',
      ].every((key) => row[key] is bool) ||
      !_optionalMatches(row['payee_momo_number_or_code'], r'^[0-9]{4,12}$') ||
      row['payee_momo_number_or_code'] == null ||
      ![
        'source_fact_id',
        'reference_source_fact_id',
        'source_review_id',
      ].every((key) => row[key] == null || _coreId(row[key])) ||
      !{
        null,
        'crypto_get_random_values',
        'sqlite_prng',
      }.contains(row['reference_random_source']) ||
      !{null, 'member', 'receiver'}.contains(row['source_kind']) ||
      !{
        null,
        'parsed',
        'needs_review',
      }.contains(row['source_extraction_status']) ||
      !['payer_name', 'momo_transaction_reference', 'parser_version'].every(
        (key) =>
            row[key] == null ||
            row[key] is String && (row[key] as String).isNotEmpty,
      ) ||
      !['payer_phone', 'payee_momo_number'].every(
        (key) => _optionalMatches(
          row[key],
          r'^(?:\+?2507[2389][0-9]{7}|07[2389][0-9]{7})$',
        ),
      ) ||
      !_optionalMatches(row['payer_masked_phone'], r'^\*{3,}[0-9]{3}$') ||
      !_optionalMatches(row['payer_last3'], r'^[0-9]{3}$') ||
      !_optionalMatches(row['payee_momo_code'], r'^[0-9]{4,9}$') ||
      ![
        'source_body_sha256',
        'source_payload_sha256',
      ].every((key) => _optionalMatches(row[key], r'^[a-f0-9]{64}$')) ||
      !_optionalMatches(
        row['momo_timestamp_local'],
        r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$',
      ) ||
      !_optionalMatches(
        row['momo_timezone_offset'],
        r'^[+-](?:0[0-9]|1[0-4]):[0-5][0-9]$',
      ) ||
      ![
        'source_amount_rwf',
        'wallet_balance_rwf',
      ].every((key) => row[key] == null || _coreInteger(row[key])) ||
      !{null, 'mtn_momo', 'airtel_money'}.contains(row['source_network']) ||
      !{null, 'incoming', 'outgoing'}.contains(row['direction']) ||
      row['is_payment'] != null && row['is_payment'] is! bool ||
      !{
        'unique_recorded_match',
        'ambiguous',
        'unmatched',
        'not_recorded',
      }.contains(row['payer_source_match_status']) ||
      !{
        'available',
        'ambiguous',
        'not_attributed',
      }.contains(row['payer_insights_status']) ||
      row['provider_confirmation'] != false ||
      row['settlement_status'] != 'not_asserted' ||
      !{
        'public_reference',
        'reviewed_member_receipt',
        'not_recorded',
      }.contains(row['source_link_basis']) ||
      row['payer_last3_known'] != (row['payer_last3'] != null) ||
      row['timezone_known'] != (row['momo_timezone_offset'] != null)) {
    _invalidCore();
  }
  final reference = row['transaction_reference'] as String;
  final localTimestamp = row['momo_timestamp_local'] as String?;
  final offset = row['momo_timezone_offset'] as String?;
  if (localTimestamp != null && !_coreTimestamp('$localTimestamp.000Z') ||
      offset != null &&
          offset.substring(1, 3) == '14' &&
          offset.substring(4) != '00' ||
      row['is_payment'] == true &&
          (row['source_amount_rwf'] == null ||
              row['source_amount_rwf'] == 0 ||
              row['source_network'] == null ||
              row['direction'] == null ||
              row['momo_transaction_reference'] == null) ||
      row['source_fact_id'] != null &&
          (row['direction'] != 'incoming' ||
              row['is_payment'] != true ||
              row['source_extraction_status'] != 'parsed' ||
              row.containsKey('amount_rwf') &&
                  row['source_amount_rwf'] != row['amount_rwf'] ||
              row.containsKey('network') &&
                  row['source_network'] != row['network'] ||
              row.containsKey('provider_reference') &&
                  row['momo_transaction_reference'] !=
                      row['provider_reference'])) {
    _invalidCore();
  }
  switch (row['source_link_basis']) {
    case 'public_reference':
      if (row['source_fact_id'] == null ||
          row['source_fact_id'] != row['reference_source_fact_id'] ||
          row['source_review_id'] != null) {
        _invalidCore();
      }
    case 'reviewed_member_receipt':
      if (row['source_kind'] != 'member' ||
          row['source_fact_id'] == null ||
          row['source_review_id'] == null ||
          row['reference_source_fact_id'] != null) {
        _invalidCore();
      }
    case 'not_recorded':
      if (row['source_fact_id'] != null ||
          row['source_review_id'] != null ||
          row['reference_source_fact_id'] != null) {
        _invalidCore();
      }
  }
  if (row['reference_payer_last3_known'] == false &&
          reference.substring(0, 3) != '000' ||
      row['reference_payer_last3_known'] == true &&
          reference.substring(0, 3) != row['payer_last3'] ||
      row['reference_payee_last3_known'] == false &&
          reference.substring(3, 6) != '000' ||
      row['reference_payee_last3_known'] == true &&
          reference.substring(3, 6) !=
              (row['payee_momo_number_or_code'] as String).substring(
                (row['payee_momo_number_or_code'] as String).length - 3,
              ) ||
      row['payer_phone'] != null && row['payer_masked_phone'] != null ||
      row['momo_timezone_offset'] != null &&
          row['momo_timestamp_local'] == null) {
    _invalidCore();
  }
  final payer = (row['payer_phone'] ?? row['payer_masked_phone']) as String?;
  if (row['payer_last3'] != payer?.substring(payer.length - 3)) {
    _invalidCore();
  }
  const sourceKeys = <String>{
    'source_kind',
    'parser_version',
    'source_extraction_status',
    'source_body_sha256',
    'source_payload_sha256',
    'source_parsed_at',
    'payer_name',
    'payer_phone',
    'payer_masked_phone',
    'payer_last3',
    'payee_momo_number',
    'payee_momo_code',
    'momo_transaction_reference',
    'momo_timestamp_local',
    'momo_timezone_offset',
    'source_amount_rwf',
    'wallet_balance_rwf',
    'source_network',
    'direction',
    'is_payment',
  };
  if (row['source_fact_id'] == null) {
    if (sourceKeys.any((key) => row[key] != null) ||
        row['reference_payer_last3_known'] != false ||
        row['reference_payee_last3_known'] != false) {
      _invalidCore();
    }
  } else if (row['source_kind'] == null ||
      row['parser_version'] == null ||
      row['source_body_sha256'] == null ||
      row['source_payload_sha256'] == null ||
      row['source_extraction_status'] == null ||
      row['is_payment'] == null ||
      (operating
          ? !_coreInteger(row['source_parsed_at']) ||
                row['source_parsed_at'] == 0
          : !_coreTimestamp(row['source_parsed_at']))) {
    _invalidCore();
  }
}
