part of 'admin_runtime.dart';

class _AdminDetailSpec {
  const _AdminDetailSpec({
    required this.heading,
    required this.subtitle,
    required this.fields,
    this.noteEntityType,
    this.actions = const [
      _AdminDetailAction(Icons.history_outlined, 'Review history'),
      _AdminDetailAction(Icons.note_alt_outlined, 'Add support note'),
      _AdminDetailAction(
        Icons.escalator_warning_outlined,
        'Escalate if needed',
      ),
    ],
  });

  final String heading;
  final String subtitle;
  final List<_AdminDetailFieldSpec> fields;
  final String? noteEntityType;
  final List<_AdminDetailAction> actions;

  factory _AdminDetailSpec.forRpc(String rpcName, String fallbackTitle) {
    return switch (rpcName) {
      'admin_get_collection' => const _AdminDetailSpec(
        heading: 'Group operations profile',
        subtitle: 'Group support context.',
        noteEntityType: 'collection',
        actions: [
          _AdminDetailAction(Icons.groups_outlined, 'Review members'),
          _AdminDetailAction(
            Icons.account_balance_outlined,
            'Check bank contribution setup',
          ),
          _AdminDetailAction(Icons.note_alt_outlined, 'Record support note'),
        ],
        fields: [
          _AdminDetailFieldSpec('Group ID', ['id']),
          _AdminDetailFieldSpec('Group name', ['name', 'title']),
          _AdminDetailFieldSpec('Public ID', ['public_id', 'collect_id']),
          _AdminDetailFieldSpec('Visibility', ['visibility']),
          _AdminDetailFieldSpec('Public status', ['public_status']),
          _AdminDetailFieldSpec('Platform sponsored', [
            'is_platform_sponsored',
          ]),
          _AdminDetailFieldSpec('Collection type', ['collection_type']),
          _AdminDetailFieldSpec('Category', ['category_subtype']),
          _AdminDetailFieldSpec('Purpose', ['purpose_label']),
          _AdminDetailFieldSpec('Receiver', ['receiver_display_label']),
          _AdminDetailFieldSpec('MoMo code', ['receiver_momo_code']),
          _AdminDetailFieldSpec('MoMo network', ['receiver_network']),
          _AdminDetailFieldSpec('Members', ['member_count', 'members_count']),
          _AdminDetailFieldSpec('Raised', ['total_raised', 'amount']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_user' => const _AdminDetailSpec(
        heading: 'Member support profile',
        subtitle: 'Scoped member context.',
        noteEntityType: 'profile',
        actions: [
          _AdminDetailAction(Icons.group_outlined, 'Review memberships'),
          _AdminDetailAction(Icons.privacy_tip_outlined, 'Keep phone masked'),
          _AdminDetailAction(
            Icons.support_agent_outlined,
            'Escalate support path',
          ),
        ],
        fields: [
          _AdminDetailFieldSpec('User ID', ['id', 'user_id']),
          _AdminDetailFieldSpec('Collect ID', ['collect_id', 'public_id']),
          _AdminDetailFieldSpec('Display name', ['display_name', 'name']),
          _AdminDetailFieldSpec('WhatsApp', ['phone_masked', 'phone']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_notification' => const _AdminDetailSpec(
        heading: 'Notification delivery review',
        subtitle: 'Message body and device token remain hidden.',
        noteEntityType: 'notification_event',
        actions: [
          _AdminDetailAction(Icons.replay_outlined, 'Retry failed delivery'),
          _AdminDetailAction(Icons.devices_outlined, 'Check device health'),
          _AdminDetailAction(Icons.policy_outlined, 'Review audit history'),
        ],
        fields: [
          _AdminDetailFieldSpec('Event ID', ['id']),
          _AdminDetailFieldSpec('Type', ['type']),
          _AdminDetailFieldSpec('Title', ['title']),
          _AdminDetailFieldSpec('Collect ID', ['collect_id']),
          _AdminDetailFieldSpec('Group', ['collection_id']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Delivery statuses', ['delivery_statuses']),
          _AdminDetailFieldSpec('Retryable', ['retryable_count']),
          _AdminDetailFieldSpec('Last error', ['last_error_code']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_admin_user' => const _AdminDetailSpec(
        heading: 'Admin access profile',
        subtitle: 'Reason-gated least-privilege role management.',
        actions: [
          _AdminDetailAction(
            Icons.admin_panel_settings_outlined,
            'Review roles',
          ),
          _AdminDetailAction(Icons.policy_outlined, 'Record every change'),
          _AdminDetailAction(Icons.block_outlined, 'Protect last owner'),
        ],
        fields: [
          _AdminDetailFieldSpec('User ID', ['id']),
          _AdminDetailFieldSpec('Collect ID', ['public_id']),
          _AdminDetailFieldSpec('Phone', ['phone_masked']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Roles', ['active_roles']),
          _AdminDetailFieldSpec('Legacy owner', ['legacy_platform_owner']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_collect_transaction' => const _AdminDetailSpec(
        heading: 'Collect transaction',
        subtitle:
            'Received message, parsed payment, linked payee, and allocation.',
        actions: [
          _AdminDetailAction(
            Icons.receipt_long_outlined,
            'Review parsed details',
          ),
          _AdminDetailAction(Icons.person_pin_circle_outlined, 'Confirm payee'),
          _AdminDetailAction(Icons.balance_outlined, 'Confirm allocation'),
        ],
        fields: [
          _AdminDetailFieldSpec('Transaction ID', ['transaction_id', 'id']),
          _AdminDetailFieldSpec('Payment route', ['payment_route', 'rail']),
          _AdminDetailFieldSpec('Message sender', ['sms_sender', 'source']),
          _AdminDetailFieldSpec('Message status', ['parse_status']),
          _AdminDetailFieldSpec('Parsed payer', ['sender_name', 'payer_name']),
          _AdminDetailFieldSpec('Provider', ['network', 'provider']),
          _AdminDetailFieldSpec('Reference', ['reference']),
          _AdminDetailFieldSpec('Amount', ['amount']),
          _AdminDetailFieldSpec('Payee', ['payee']),
          _AdminDetailFieldSpec('Group', ['group_name', 'collection_title']),
          _AdminDetailFieldSpec('Allocation', ['allocation_status', 'status']),
          _AdminDetailFieldSpec('Received', ['received_at', 'created_at']),
        ],
      ),
      'admin_get_payment_intent' => const _AdminDetailSpec(
        heading: 'MoMo contribution intent',
        subtitle: 'Expected Rwanda payer, amount, and matching window.',
        fields: [
          _AdminDetailFieldSpec('Intent ID', ['id']),
          _AdminDetailFieldSpec('Group', ['collection_id']),
          _AdminDetailFieldSpec('Contributor', ['contributor_user_id']),
          _AdminDetailFieldSpec('Contribution code', ['contribution_code']),
          _AdminDetailFieldSpec('Expected RWF', ['expected_amount_rwf']),
          _AdminDetailFieldSpec('Reported transaction', [
            'reported_transaction_id',
          ]),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Created', ['created_at']),
          _AdminDetailFieldSpec('Expires', ['expires_at']),
        ],
      ),
      'admin_get_payment' => const _AdminDetailSpec(
        heading: 'Posted MoMo transaction',
        subtitle: 'Canonical RWF contribution and linked intent.',
        fields: [
          _AdminDetailFieldSpec('Payment ID', ['id']),
          _AdminDetailFieldSpec('Transaction ID', ['transaction_id']),
          _AdminDetailFieldSpec('Group', ['collection_id']),
          _AdminDetailFieldSpec('Intent', ['payment_intent_id']),
          _AdminDetailFieldSpec('Source', ['source']),
          _AdminDetailFieldSpec('Amount RWF', ['amount_rwf']),
          _AdminDetailFieldSpec('Currency', ['currency']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_payment_event' => const _AdminDetailSpec(
        heading: 'Parsed MoMo receipt',
        subtitle: 'Deterministic receipt fields and allocation state.',
        fields: [
          _AdminDetailFieldSpec('Event ID', ['id']),
          _AdminDetailFieldSpec('Provider', ['provider', 'network']),
          _AdminDetailFieldSpec('Transaction ID', ['transaction_id']),
          _AdminDetailFieldSpec('Sender', ['sender_phone_masked']),
          _AdminDetailFieldSpec('Receiver', ['receiver_phone_masked']),
          _AdminDetailFieldSpec('Amount RWF', ['amount_rwf']),
          _AdminDetailFieldSpec('Currency', ['currency']),
          _AdminDetailFieldSpec('Parse status', ['parse_status']),
          _AdminDetailFieldSpec('Allocation', ['allocation_status']),
          _AdminDetailFieldSpec('Received', ['received_at', 'created_at']),
        ],
      ),
      'admin_get_receiver' => const _AdminDetailSpec(
        heading: 'MoMo receiver',
        subtitle: 'Masked, consent-bound Rwanda group receiver.',
        fields: [
          _AdminDetailFieldSpec('Receiver ID', ['id']),
          _AdminDetailFieldSpec('Group', ['collection_id']),
          _AdminDetailFieldSpec('Receiver user', ['receiver_user_id']),
          _AdminDetailFieldSpec('MoMo number', [
            'momo_number_masked',
            'momo_number',
          ]),
          _AdminDetailFieldSpec('Provider', ['network']),
          _AdminDetailFieldSpec('Label', ['label']),
          _AdminDetailFieldSpec('Active', ['is_active']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_sms_metadata' => const _AdminDetailSpec(
        heading: 'MoMo receipt SMS metadata',
        subtitle: 'Raw body remains hidden unless separately authorized.',
        fields: [
          _AdminDetailFieldSpec('SMS ID', ['id']),
          _AdminDetailFieldSpec('Sender', ['sender_masked', 'raw_sender']),
          _AdminDetailFieldSpec('Body hash', ['body_hash']),
          _AdminDetailFieldSpec('Parse status', ['parse_status']),
          _AdminDetailFieldSpec('Received', ['received_at', 'ingested_at']),
          _AdminDetailFieldSpec('Raw body access', ['raw_body']),
        ],
      ),
      'admin_get_bank_destination' => const _AdminDetailSpec(
        heading: 'Bank beneficiary version',
        subtitle: 'Approved EUR transfer destination.',
        actions: [
          _AdminDetailAction(
            Icons.account_balance_outlined,
            'Verify beneficiary',
          ),
          _AdminDetailAction(
            Icons.fact_check_outlined,
            'Review approval chain',
          ),
          _AdminDetailAction(Icons.history_outlined, 'Review version history'),
        ],
        fields: [
          _AdminDetailFieldSpec('Destination ID', ['id']),
          _AdminDetailFieldSpec('Version', ['version']),
          _AdminDetailFieldSpec('Beneficiary', ['beneficiary_name']),
          _AdminDetailFieldSpec('IBAN', ['iban_masked', 'iban']),
          _AdminDetailFieldSpec('BIC / SWIFT', ['bic']),
          _AdminDetailFieldSpec('Bank', ['bank_name']),
          _AdminDetailFieldSpec('Currency', ['currency']),
          _AdminDetailFieldSpec('SEPA Instant', ['supports_instant']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Approved', ['approved_at']),
        ],
      ),
      'admin_get_bank_destination_change_request' => const _AdminDetailSpec(
        heading: 'Bank detail approval',
        subtitle: 'Independent maker-checker beneficiary review.',
        actions: [
          _AdminDetailAction(Icons.person_outline, 'Confirm maker identity'),
          _AdminDetailAction(
            Icons.rule_outlined,
            'Enforce independent checker',
          ),
          _AdminDetailAction(Icons.policy_outlined, 'Record review note'),
        ],
        fields: [
          _AdminDetailFieldSpec('Request ID', ['id']),
          _AdminDetailFieldSpec('Beneficiary', ['beneficiary_name']),
          _AdminDetailFieldSpec('IBAN', ['iban_masked', 'iban']),
          _AdminDetailFieldSpec('BIC / SWIFT', ['bic']),
          _AdminDetailFieldSpec('Bank', ['bank_name']),
          _AdminDetailFieldSpec('SEPA Instant', ['supports_instant']),
          _AdminDetailFieldSpec('Reason', ['reason']),
          _AdminDetailFieldSpec('Maker', ['proposed_by']),
          _AdminDetailFieldSpec('Checker', ['reviewed_by']),
          _AdminDetailFieldSpec('Status', ['status']),
        ],
      ),
      'admin_get_bank_transfer_intent' => const _AdminDetailSpec(
        heading: 'Transfer request',
        subtitle: 'Member EUR reference and receipt lifecycle.',
        fields: [
          _AdminDetailFieldSpec('Request ID', ['id']),
          _AdminDetailFieldSpec('Reference', ['transfer_reference']),
          _AdminDetailFieldSpec('Group', ['collection_title', 'collection_id']),
          _AdminDetailFieldSpec('Contributor', ['contributor_user_id']),
          _AdminDetailFieldSpec('Amount minor', ['amount_minor']),
          _AdminDetailFieldSpec('Currency', ['currency']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Expires', ['expires_at']),
          _AdminDetailFieldSpec('Evidence received', ['evidence_received_at']),
          _AdminDetailFieldSpec('Reconciled', ['reconciled_at']),
        ],
      ),
      'admin_get_bank_transaction' => const _AdminDetailSpec(
        heading: 'Incoming bank transaction',
        subtitle: 'Canonical receipt linked to protected evidence.',
        fields: [
          _AdminDetailFieldSpec('Transaction ID', ['id']),
          _AdminDetailFieldSpec('Bank transaction ID', ['bank_transaction_id']),
          _AdminDetailFieldSpec('End-to-end ID', ['end_to_end_id']),
          _AdminDetailFieldSpec('Reference', ['transfer_reference']),
          _AdminDetailFieldSpec('Payer', ['payer_name']),
          _AdminDetailFieldSpec('Amount minor', ['amount_minor']),
          _AdminDetailFieldSpec('Currency', ['currency']),
          _AdminDetailFieldSpec('Value date', ['value_date']),
          _AdminDetailFieldSpec('Status', ['status']),
        ],
      ),
      'admin_get_bank_evidence' => const _AdminDetailSpec(
        heading: 'Bank evidence',
        subtitle: 'Parsed metadata; raw content requires audited reveal.',
        fields: [
          _AdminDetailFieldSpec('Evidence event ID', ['id']),
          _AdminDetailFieldSpec('Channel', ['channel']),
          _AdminDetailFieldSpec('Sender', ['sender']),
          _AdminDetailFieldSpec('Reference', ['transfer_reference']),
          _AdminDetailFieldSpec('Bank transaction ID', ['bank_transaction_id']),
          _AdminDetailFieldSpec('Amount minor', ['amount_minor']),
          _AdminDetailFieldSpec('Currency', ['currency']),
          _AdminDetailFieldSpec('Confidence', ['confidence']),
          _AdminDetailFieldSpec('Parse status', ['parse_status']),
          _AdminDetailFieldSpec('Allocation status', ['allocation_status']),
          _AdminDetailFieldSpec('Received', ['received_at']),
        ],
      ),
      'admin_get_reconciliation_run' => const _AdminDetailSpec(
        heading: 'Daily reconciliation run',
        subtitle: 'Statement, evidence, allocation, and close controls.',
        fields: [
          _AdminDetailFieldSpec('Run ID', ['id']),
          _AdminDetailFieldSpec('Run date', ['run_date']),
          _AdminDetailFieldSpec('Currency', ['currency']),
          _AdminDetailFieldSpec('Statement lines', ['statement_line_count']),
          _AdminDetailFieldSpec('Matched', ['matched_count']),
          _AdminDetailFieldSpec('Exceptions', ['exception_count']),
          _AdminDetailFieldSpec('Matched total minor', ['matched_total_minor']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Completed', ['completed_at']),
        ],
      ),
      'admin_get_reconciliation_exception' => const _AdminDetailSpec(
        heading: 'Reconciliation exception',
        subtitle: 'Controlled resolution or dismissal with an audit reason.',
        fields: [
          _AdminDetailFieldSpec('Exception ID', ['id']),
          _AdminDetailFieldSpec('Type', ['exception_type']),
          _AdminDetailFieldSpec('Transaction', ['bank_transaction_id']),
          _AdminDetailFieldSpec('Transfer request', [
            'bank_transfer_intent_id',
          ]),
          _AdminDetailFieldSpec('Details', ['details']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Resolution', ['resolution_note']),
          _AdminDetailFieldSpec('Resolved', ['resolved_at']),
        ],
      ),
      'admin_get_bank_allocation_request' => const _AdminDetailSpec(
        heading: 'Manual allocation approval',
        subtitle: 'Exact amount and currency maker-checker control.',
        fields: [
          _AdminDetailFieldSpec('Request ID', ['id']),
          _AdminDetailFieldSpec('Transaction', ['bank_transaction_id']),
          _AdminDetailFieldSpec('Transfer request', [
            'bank_transfer_intent_id',
          ]),
          _AdminDetailFieldSpec('Reason', ['reason']),
          _AdminDetailFieldSpec('Maker', ['proposed_by']),
          _AdminDetailFieldSpec('Checker', ['reviewed_by']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Review note', ['review_note']),
        ],
      ),
      'admin_get_journal_entry' => const _AdminDetailSpec(
        heading: 'Immutable journal entry',
        subtitle: 'Balanced double-entry posting record.',
        fields: [
          _AdminDetailFieldSpec('Entry ID', ['id']),
          _AdminDetailFieldSpec('Type', ['entry_type']),
          _AdminDetailFieldSpec('Reference', ['external_reference']),
          _AdminDetailFieldSpec('Description', ['description']),
          _AdminDetailFieldSpec('Currency', ['currency']),
          _AdminDetailFieldSpec('Group', ['collection_id']),
          _AdminDetailFieldSpec('Balanced', ['balanced']),
          _AdminDetailFieldSpec('Posted', ['posted_at', 'created_at']),
        ],
      ),
      'admin_system_health' => const _AdminDetailSpec(
        heading: 'System health',
        subtitle: 'Platform readiness.',
        actions: [
          _AdminDetailAction(
            Icons.monitor_heart_outlined,
            'Review health signal',
          ),
          _AdminDetailAction(
            Icons.warning_amber_outlined,
            'Escalate degraded checks',
          ),
          _AdminDetailAction(Icons.history_outlined, 'Compare latest run'),
        ],
        fields: [
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Database', ['database', 'db']),
          _AdminDetailFieldSpec('Auth', ['auth']),
          _AdminDetailFieldSpec('Pending bank evidence', [
            'bank_evidence_pending',
          ]),
          _AdminDetailFieldSpec('Reconciliation exceptions', [
            'reconciliation_exceptions',
          ]),
          _AdminDetailFieldSpec('Allocation approvals', [
            'allocation_approvals_pending',
          ]),
          _AdminDetailFieldSpec('Queued notifications', [
            'queued_notifications',
          ]),
          _AdminDetailFieldSpec('Processing notifications', [
            'processing_notifications',
          ]),
          _AdminDetailFieldSpec('Failed notifications', [
            'failed_notifications',
          ]),
          _AdminDetailFieldSpec('Checked', ['checked_at', 'created_at']),
        ],
      ),
      _ => _AdminDetailSpec(
        heading: fallbackTitle,
        subtitle: 'Record fields.',
        fields: const [
          _AdminDetailFieldSpec('Record ID', ['id']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
    };
  }
}

class _AdminDetailAction {
  const _AdminDetailAction(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _AdminDetailFieldSpec {
  const _AdminDetailFieldSpec(this.label, this.keys);

  final String label;
  final List<String> keys;
}
