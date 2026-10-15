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
        heading: 'Group',
        subtitle: '',
        noteEntityType: 'collection',
        actions: [
          _AdminDetailAction(Icons.groups_outlined, 'Review members'),
          _AdminDetailAction(
            Icons.account_balance_outlined,
            'Check MoMo receiver setup',
          ),
          _AdminDetailAction(Icons.note_alt_outlined, 'Record support note'),
        ],
        fields: [
          _AdminDetailFieldSpec('Visibility', ['visibility']),
          _AdminDetailFieldSpec('Purpose', ['purpose_label']),
          _AdminDetailFieldSpec('Members', [
            'active_members',
            'member_count',
            'members_count',
          ]),
          _AdminDetailFieldSpec('Receiver', ['receiver_display_label']),
          _AdminDetailFieldSpec('MoMo code', ['receiver_momo_code']),
          _AdminDetailFieldSpec('MoMo network', ['receiver_network']),
          _AdminDetailFieldSpec('Raised', ['total_raised', 'amount']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_user' => const _AdminDetailSpec(
        heading: 'Profile',
        subtitle: '',
        actions: [],
        fields: [
          _AdminDetailFieldSpec('Name', ['display_name']),
          _AdminDetailFieldSpec('Type', ['user_type']),
          _AdminDetailFieldSpec('Email', ['email']),
          _AdminDetailFieldSpec('Collect ID', ['public_id']),
          _AdminDetailFieldSpec('WhatsApp', ['whatsapp_phone']),
          _AdminDetailFieldSpec('MoMo number', ['momo_number']),
          _AdminDetailFieldSpec('MoMo code', ['momo_pay_code']),
          _AdminDetailFieldSpec('MoMo provider', ['momo_provider']),
          _AdminDetailFieldSpec('Groups', ['groups_total']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_member_record' => const _AdminDetailSpec(
        heading: 'Member',
        subtitle: 'App and Direct group member record.',
        noteEntityType: 'member_record',
        actions: [],
        fields: [
          _AdminDetailFieldSpec('Collect ID', ['collect_id']),
          _AdminDetailFieldSpec('Member name', ['member_name']),
          _AdminDetailFieldSpec('Registered MoMo name', [
            'momo_registered_name',
          ]),
          _AdminDetailFieldSpec('MoMo number', ['momo_number']),
          _AdminDetailFieldSpec('WhatsApp', ['whatsapp_phone']),
          _AdminDetailFieldSpec('MoMo code', ['momo_pay_code']),
          _AdminDetailFieldSpec('Member type', ['member_type']),
          _AdminDetailFieldSpec('Total contributed', [
            'contributed_amount_rwf',
          ]),
          _AdminDetailFieldSpec('Lifecycle', ['lifecycle']),
          _AdminDetailFieldSpec('Groups', ['active_groups']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_notification' => const _AdminDetailSpec(
        heading: 'Notification',
        subtitle: '',
        noteEntityType: 'notification_event',
        actions: [
          _AdminDetailAction(Icons.replay_outlined, 'Retry failed delivery'),
          _AdminDetailAction(Icons.devices_outlined, 'Check device health'),
          _AdminDetailAction(Icons.policy_outlined, 'Review audit history'),
        ],
        fields: [
          _AdminDetailFieldSpec('Collect ID', ['collect_id']),
          _AdminDetailFieldSpec('Group', ['collection_id']),
          _AdminDetailFieldSpec('Delivery statuses', ['delivery_statuses']),
          _AdminDetailFieldSpec('Attempts', ['retryable_count']),
          _AdminDetailFieldSpec('Last error', ['last_error_code']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_hybrid_sms_receipt' => const _AdminDetailSpec(
        heading: 'Feature-phone SMS receipt',
        subtitle:
            'Masked queue metadata. Exact destination and message remain available only to a current fenced operator claim.',
        actions: [],
        fields: [
          _AdminDetailFieldSpec('State', ['state']),
          _AdminDetailFieldSpec('Channel', ['channel']),
          _AdminDetailFieldSpec('Collect ID', ['member_collect_id']),
          _AdminDetailFieldSpec('Group', ['collection_title', 'collection_id']),
          _AdminDetailFieldSpec('Destination', ['destination_masked']),
          _AdminDetailFieldSpec('Amount RWF', ['amount_rwf']),
          _AdminDetailFieldSpec('Member balance at receipt posting RWF', [
            'member_balance_rwf',
          ]),
          _AdminDetailFieldSpec('Group balance at receipt posting RWF', [
            'group_balance_rwf',
          ]),
          _AdminDetailFieldSpec('Reference', ['reference']),
          _AdminDetailFieldSpec('Template', ['template_key']),
          _AdminDetailFieldSpec('Template version', ['template_version']),
          _AdminDetailFieldSpec('Claim-protected original message', [
            'message_body',
          ]),
          _AdminDetailFieldSpec('Attempts', ['attempt_count']),
          _AdminDetailFieldSpec('Latest attempt', ['latest_attempt_state']),
          _AdminDetailFieldSpec('Suppression reason', ['suppression_reason']),
          _AdminDetailFieldSpec('Created', ['created_at']),
          _AdminDetailFieldSpec('Observed sent', ['observed_sent_at']),
          _AdminDetailFieldSpec('Delivery evidence', ['delivery_claim']),
        ],
      ),
      'admin_get_admin_user' => const _AdminDetailSpec(
        heading: 'Admin access',
        subtitle: '',
        actions: [],
        fields: [
          _AdminDetailFieldSpec('Collect ID', ['public_id']),
          _AdminDetailFieldSpec('Phone', ['phone_masked']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_collect_transaction' => const _AdminDetailSpec(
        heading: 'Transaction',
        subtitle: '',
        actions: [],
        fields: [
          _AdminDetailFieldSpec('Group', ['group_name']),
          _AdminDetailFieldSpec('Received by Collect', ['received_at']),
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
      'admin_system_health' => const _AdminDetailSpec(
        heading: 'Current health',
        subtitle: '',
        actions: [],
        fields: [
          _AdminDetailFieldSpec('Database', ['database', 'db']),
          _AdminDetailFieldSpec('Authentication', ['auth']),
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
