import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';

const coreId = '11111111-1111-4111-8111-111111111111';
const coreDate = '2026-10-04T12:00:00.000Z';

Map<String, dynamic> coreSession({
  List<String>? permissions,
  String sessionId = 'core-session',
}) => {
  'user': {
    'id': coreId,
    'email': 'operator@example.test',
    'role': 'admin',
    'sessionId': sessionId,
    'permissions':
        permissions ??
        [
          'overview.read',
          'account.manage',
          ...CloudflareCoreArea.values.map((area) => area.permission).toSet(),
        ],
  },
  'expiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 1))
      .toIso8601String(),
};

Map<String, dynamic> coreOverview({
  int count = 0,
  Map<String, String>? amounts,
}) {
  const labels = {
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
  const amountLabels = {
    'total_collected_rwf': 'Total collected',
    'total_allocated_rwf': 'Total allocated',
    'total_unallocated_rwf': 'Total unallocated',
    'total_posted_contributions_rwf': 'Posted contributions',
  };
  final measuredAmounts = {
    for (final key in amountLabels.keys) key: amounts?[key] ?? '$count',
  };
  return {
    'country_code': 'RW',
    'measured_at': coreDate,
    'counts': {for (final key in labels.keys) key: count},
    'amounts': measuredAmounts,
    'collected_basis': 'confirmation_recorded_transactions',
    'contribution_basis': 'confirmation_recorded_allocations',
    'reconciliations_available': false,
    'metrics': [
      for (final entry in labels.entries)
        {
          'key': entry.key,
          'label': entry.value,
          'value': '$count',
          'status': 'measured',
        },
      for (final entry in amountLabels.entries)
        {
          'key': entry.key,
          'label': entry.value,
          'value': measuredAmounts[entry.key],
          'status': 'measured',
        },
    ],
  };
}

Map<String, dynamic> coreRow(CloudflareCoreArea area) => {
  'id': coreId,
  'title': 'Example record',
  'subtitle': 'Example context',
  'created_at': coreDate,
  'country_code': 'RW',
  'currency_code': 'RWF',
  ...switch (area) {
    CloudflareCoreArea.groups => {
      'status': 'active',
      'amount': '1 members',
      'slug': 'example',
      'collection_type': 'ikimina',
      'purpose_label': null,
      'visibility': 'private',
      'is_platform_sponsored': false,
      'active_members': 1,
    },
    CloudflareCoreArea.users || CloudflareCoreArea.members => {
      'title': '000123',
      'status': 'active',
      'amount': '1 groups',
      'public_id': '000123',
      'display_name': 'Example person',
      'display_name_recorded': true,
      'person_id': coreId,
      'collect_user_id': coreId,
      'operator_admin_id': null,
      'operator_public_id': null,
      'operator_role': null,
      'operator_status': null,
      'user_types': ['App'],
      'member_type': 'app',
      'phone_e164': '+250788001234',
      'whatsapp_number': '+250788001234',
      'email': 'example@example.test',
      'momo_provider': 'mtn_momo',
      'momo_number': '0788001234',
      'momo_pay_code': '008000',
      'total_contributed_rwf': 5000,
      'posted_contributed_rwf': 3000,
      'contribution_basis': 'confirmation_recorded_allocations',
      'name_verification': 'recorded_not_provider_verified',
      'phone_masked': '••••1234',
      'email_masked': 'e•••@example.test',
      'active_groups': 1,
      'account_status': 'active',
    },
    CloudflareCoreArea.payees => {
      'status': 'active',
      'amount': '008000',
      'group_id': coreId,
      'group_name': 'Example group',
      'network': 'mtn_momo',
      'momo_masked': '••••00',
      'momo_number_or_code': '008000',
      'momo_number': null,
      'momo_pay_code': '008000',
    },
    CloudflareCoreArea.transactions => {
      'title': '000000123456789012',
      'transaction_reference': '000000123456789012',
      'reference_payer_last3_known': false,
      'reference_payee_last3_known': false,
      'reference_random_source': 'sqlite_prng',
      'reference_source_fact_id': null,
      'source_fact_id': null,
      'source_link_basis': 'not_recorded',
      'source_review_id': null,
      for (final key in [
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
      ])
        key: null,
      'payer_last3_known': false,
      'timezone_known': false,
      'payee_momo_number_or_code': '008000',
      'payer_source_match_status': 'not_recorded',
      'payer_insights_status': 'not_attributed',
      'provider_confirmation': false,
      'settlement_status': 'not_asserted',
      'status': 'confirmation_recorded',
      'amount': '9007199254740991',
      'group_id': coreId,
      'group_name': 'Example group',
      'payee_id': coreId,
      'payee_label': 'Example payee',
      'network': 'mtn_momo',
      'rail': 'rwanda_momo',
      'provider_reference': 'Example record',
      'amount_rwf': 9007199254740991,
      'allocated_amount_rwf': 0,
      'allocation_status': 'unallocated',
      'posted_journals': 0,
      'observed_at': coreDate,
    },
    CloudflareCoreArea.ledgers => {
      'status': 'draft',
      'amount': '100',
      'group_id': coreId,
      'group_name': 'Example group',
      'transaction_id': null,
      'allocation_id': null,
      'debit_rwf': 100,
      'credit_rwf': 0,
      'entry_count': 1,
      'balanced': false,
      'posted_at': null,
    },
  },
};
