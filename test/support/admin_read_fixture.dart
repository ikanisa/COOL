// Synthetic values follow the source JSON fields of the current seven routed
// detail RPCs. They are contract probes, not deployed SQL or provider evidence.
const adminReadActor = '99740000-0000-4000-8000-000000000001';
const adminReadTarget = '99740000-0000-4000-8000-000000000002';
const adminReadDate = '2026-09-30T08:10:00.123456+00:00';

// Synthetic available measurement, including actual zero and pending/oldest
// consistency. Date bounds are generated from the observed Kigali day.
Map<String, dynamic> adminReceiptOverviewFixture(
  DateTime observed, {
  bool empty = false,
}) {
  final checked = observed.toUtc();
  final local = checked.add(const Duration(hours: 2));
  final start = DateTime.utc(
    local.year,
    local.month,
    local.day,
  ).subtract(const Duration(hours: 2));
  return {
    'contract_version': 1,
    'scope': 'rwanda_momo',
    'country_code': 'RW',
    'timezone': 'Africa/Kigali',
    'checked_at': checked.toIso8601String(),
    'sample_valid_until': checked
        .add(const Duration(seconds: 60))
        .toIso8601String(),
    'day_start': start.toIso8601String(),
    'day_end': start.add(const Duration(days: 1)).toIso8601String(),
    'posted': {'count': empty ? 0 : 2, 'value_rwf': empty ? '0' : '5000'},
    'receipts_state': 'available',
    'receipts': {
      'queued': empty ? 0 : 1,
      'awaiting_confirmation': 0,
      'oldest_pending_at': empty
          ? null
          : checked.subtract(const Duration(minutes: 1)).toIso8601String(),
      'failed_no_send': 0,
      'uncertain': 0,
      'send_started': 0,
    },
  };
}

Map<String, dynamic> adminIdentityFixture([String actor = adminReadActor]) => {
  'user_id': actor,
  'display_name': 'Collect ID 974001',
  'phone_masked': '+250•••001',
  'roles': ['admin'],
  'permissions': ['overview.read', 'users.read'],
};

Map<String, dynamic> adminRuntimeFixture() => {
  'navigation_items': [
    {
      'key': 'groups',
      'label': 'Groups',
      'icon_key': 'groups',
      'route_path': '/admin/groups',
      'required_permission': 'collections.read',
      'display_order': 20,
    },
  ],
  'queue_specs': [
    {
      'rpc_name': 'admin_list_collections',
      'title': 'Groups',
      'subtitle': 'Support group operations.',
      'required_permission': 'collections.read',
      'status_options': [
        {'value': '', 'label': 'All'},
        {'value': 'active', 'label': 'Active'},
      ],
      'sort_options': [
        {'value': 'created_at_desc', 'label': 'Newest'},
      ],
      'priority_signals': [
        {'icon_key': 'groups', 'label': 'Review group'},
      ],
      'workflow_steps': [],
    },
  ],
};

Map<String, dynamic> adminDetailFixture(
  String rpc, [
  String id = adminReadTarget,
]) => switch (rpc) {
  'admin_get_user' => {
    'id': id,
    'email': null,
    'display_name': null,
    'user_type': 'App',
    'public_id': '974002',
    'whatsapp_phone': '+250788000002',
    'momo_number': null,
    'momo_pay_code': null,
    'momo_provider': null,
    'groups_total': 0,
    'active_groups': 0,
    'status': 'registered',
    'created_at': adminReadDate,
    'updated_at': adminReadDate,
  },
  'admin_get_member_record' => {
    'id': id,
    'collect_id': '974002',
    'member_name': null,
    'momo_registered_name': null,
    'momo_number': null,
    'whatsapp_phone': null,
    'momo_pay_code': null,
    'member_type': 'Direct',
    'contributed_amount_rwf': null,
    'contribution_status': 'unavailable',
    'account_state': 'feature_phone',
    'origin': 'assisted_roster',
    'lifecycle': 'active',
    'active_groups': 1,
    'created_at': adminReadDate,
  },
  'admin_get_collection' => {
    'admin_operator_draft': false,
    'id': id,
    'slug': null,
    'title': 'Synthetic source fixture group',
    'description': null,
    'creator_user_id': null,
    'creator_label': null,
    'collection_type': 'ikimina',
    'category_subtype': null,
    'purpose_label': null,
    'receiver_display_label': null,
    'receiver_momo_code': null,
    'receiver_network': null,
    'is_platform_sponsored': false,
    'visibility': 'private',
    'public_status': 'active',
    'status': 'active',
    'creation_origin': 'member_app',
    'archived_at': null,
    'currency': 'RWF',
    'active_receivers': 0,
    'active_members': 1,
    'pending_payment_intents': 0,
    'created_at': adminReadDate,
    'updated_at': adminReadDate,
  },
  'admin_get_notification' => {
    'id': id,
    'type': 'contribution_receipt',
    'title': 'Synthetic receipt',
    'status': 'queued',
    'collect_id': '974002',
    'collection_id': null,
    'deep_link': null,
    'delivery_statuses': 'No registered delivery',
    'retryable_count': 0,
    'cumulative_attempt_count': 0,
    'last_error_code': null,
    'created_at': adminReadDate,
    'sent_at': null,
    'read_at': null,
  },
  'admin_get_hybrid_sms_receipt' => {
    'id': id,
    'state': 'queued',
    'channel': 'Assisted SMS operator',
    'member_collect_id': '974002',
    'collection_id': adminReadActor,
    'collection_title': 'Synthetic source fixture group',
    'destination_masked': '+250•••002',
    'amount_rwf': 500,
    'member_balance_rwf': 500,
    'group_balance_rwf': 500,
    'reference': 'SYNTHETIC974002',
    'template_key': 'buri_munsi.payment_received',
    'template_version': 1,
    'consent_revision': 1,
    'authorization_current': false,
    'body_sha256': 'a' * 64,
    'message_body': 'Hidden until a current fenced operator claim',
    'attempt_count': 0,
    'claim_expires_at': null,
    'suppression_reason': null,
    'created_at': adminReadDate,
    'observed_sent_at': null,
    'latest_attempt_state': null,
    'delivery_claim':
        'Observed sent is operator-recorded UI evidence, not handset delivery',
  },
  'admin_get_admin_user' => {
    'id': id,
    'user_id': id,
    'public_id': '974002',
    'phone_masked': '+250•••002',
    'approved_at': null,
    'expires_at': null,
    'status': 'revoked',
    'approved': false,
    'role_granted': false,
    'admin_access': false,
    'access_status': 'revoked',
    'whatsapp_approval': 'not_approved',
    'active_roles': [],
    'created_at': adminReadDate,
  },
  'admin_get_collect_transaction' => {
    'collect_transaction_id': null,
    'identity_status': 'missing_payer_and_payee_identity',
    'sms_details': {
      for (final key in const [
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
      ])
        key: key == 'raw_sms_id'
            ? id
            : key == 'allocation_status'
            ? 'unallocated'
            : null,
    },
    'payer_insights': {
      'status': 'identity_unresolved',
      'match_basis': null,
      'member': null,
      'groups': null,
      'transaction_counts': null,
    },
    'id': 'momo:$id',
    'transaction_id': 'SYNTHETIC974002',
    'payment_route': 'Rwanda MoMo USSD + receipt SMS',
    'rail': 'rw_momo',
    'raw_sms_id': id,
    'sms_sender': '•••',
    'parse_status': 'queued',
    'sender_name': null,
    'network': 'MTN MoMo',
    'reference': null,
    'amount': null,
    'payee': 'MoMo payee · number unavailable',
    'group_name': null,
    'allocation_status': 'queued',
    'received_at': adminReadDate,
    'created_at': adminReadDate,
  },
  _ => throw ArgumentError.value(rpc),
};
