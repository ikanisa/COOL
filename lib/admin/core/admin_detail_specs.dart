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
            Icons.settings_phone_outlined,
            'Check receiver setup',
          ),
          _AdminDetailAction(Icons.note_alt_outlined, 'Record support note'),
        ],
        fields: [
          _AdminDetailFieldSpec('Group ID', ['id']),
          _AdminDetailFieldSpec('Group name', ['name', 'title']),
          _AdminDetailFieldSpec('Public ID', ['public_id', 'collect_id']),
          _AdminDetailFieldSpec('Visibility', ['visibility']),
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
          _AdminDetailFieldSpec('Phone', ['phone_masked', 'phone']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_payment_intent' => const _AdminDetailSpec(
        heading: 'Payment intent review',
        subtitle: 'MoMo intent state.',
        noteEntityType: 'payment_intent',
        actions: [
          _AdminDetailAction(
            Icons.compare_arrows_outlined,
            'Compare SMS events',
          ),
          _AdminDetailAction(
            Icons.receipt_long_outlined,
            'Check ledger impact',
          ),
          _AdminDetailAction(Icons.note_alt_outlined, 'Document decision'),
        ],
        fields: [
          _AdminDetailFieldSpec('Intent ID', ['id']),
          _AdminDetailFieldSpec('Group', ['collection_id', 'group_id']),
          _AdminDetailFieldSpec('Member', ['user_id', 'member_id']),
          _AdminDetailFieldSpec('Expected amount', [
            'amount',
            'expected_amount_rwf',
          ]),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Expires', ['expires_at']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_payment' => const _AdminDetailSpec(
        heading: 'Transaction review',
        subtitle: 'Posted MoMo transaction.',
        noteEntityType: 'payment',
        actions: [
          _AdminDetailAction(Icons.compare_arrows_outlined, 'Compare intent'),
          _AdminDetailAction(Icons.account_balance_outlined, 'Check ledger'),
          _AdminDetailAction(Icons.history_outlined, 'Review posting history'),
        ],
        fields: [
          _AdminDetailFieldSpec('Transaction ID', ['transaction_id', 'id']),
          _AdminDetailFieldSpec('Payment ID', ['id']),
          _AdminDetailFieldSpec('Payment intent', ['payment_intent_id']),
          _AdminDetailFieldSpec('Group', ['collection_id']),
          _AdminDetailFieldSpec('Amount', ['amount_rwf', 'amount']),
          _AdminDetailFieldSpec('Source', ['source']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Posted', ['posted_at', 'created_at']),
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
      'admin_get_payment_event' => const _AdminDetailSpec(
        heading: 'SMS payment event review',
        subtitle: 'Parsed payment event.',
        noteEntityType: 'parsed_payment_event',
        actions: [
          _AdminDetailAction(
            Icons.replay_outlined,
            'Request reparse if needed',
          ),
          _AdminDetailAction(Icons.rule_outlined, 'Resolve allocation status'),
          _AdminDetailAction(Icons.policy_outlined, 'Reason is required'),
        ],
        fields: [
          _AdminDetailFieldSpec('Event ID', ['id']),
          _AdminDetailFieldSpec('Transaction', [
            'transaction_id',
            'momo_reference',
          ]),
          _AdminDetailFieldSpec('Amount', ['amount', 'amount_rwf']),
          _AdminDetailFieldSpec('Sender', ['sender_masked', 'payer_masked']),
          _AdminDetailFieldSpec('Receiver', [
            'receiver_masked',
            'receiver_momo_masked',
          ]),
          _AdminDetailFieldSpec('Payment intent', ['payment_intent_id']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Parsed', ['parsed_at', 'created_at']),
        ],
      ),
      'admin_get_receiver' => const _AdminDetailSpec(
        heading: 'Receiver route review',
        subtitle: 'MoMo receiver route.',
        noteEntityType: 'payment_receiver',
        actions: [
          _AdminDetailAction(
            Icons.verified_user_outlined,
            'Confirm owner scope',
          ),
          _AdminDetailAction(Icons.visibility_off_outlined, 'Keep MoMo masked'),
          _AdminDetailAction(Icons.history_outlined, 'Review receiver changes'),
        ],
        fields: [
          _AdminDetailFieldSpec('Receiver ID', ['id']),
          _AdminDetailFieldSpec('Label', ['label', 'receiver_label']),
          _AdminDetailFieldSpec('MoMo route', ['momo_masked', 'phone_masked']),
          _AdminDetailFieldSpec('Group', ['collection_id', 'group_id']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_sms_metadata' => const _AdminDetailSpec(
        heading: 'SMS metadata review',
        subtitle: 'Metadata only.',
        noteEntityType: 'raw_payment_sms',
        actions: [
          _AdminDetailAction(Icons.security_outlined, 'Gate raw reveal'),
          _AdminDetailAction(Icons.policy_outlined, 'Capture reveal reason'),
          _AdminDetailAction(
            Icons.note_alt_outlined,
            'Document support context',
          ),
        ],
        fields: [
          _AdminDetailFieldSpec('SMS ID', ['id']),
          _AdminDetailFieldSpec('Sender', ['sender_masked']),
          _AdminDetailFieldSpec('Receiver', ['receiver_masked']),
          _AdminDetailFieldSpec('Parser status', ['status', 'parser_status']),
          _AdminDetailFieldSpec('Received', ['received_at', 'created_at']),
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
          _AdminDetailFieldSpec('Pending SMS', ['parser_pending_sms']),
          _AdminDetailFieldSpec('Failed SMS parse', ['failed_sms_parse']),
          _AdminDetailFieldSpec('Unallocated events', ['unallocated_events']),
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
