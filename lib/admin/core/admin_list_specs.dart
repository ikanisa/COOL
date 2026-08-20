part of 'admin_runtime.dart';

class _AdminListSpec {
  const _AdminListSpec({
    required this.title,
    required this.subtitle,
    required this.statusOptions,
    required this.sortOptions,
    this.prioritySignals = const [],
    this.workflowSteps = const [],
  });

  final String title;
  final String subtitle;
  final List<AdminFilterOption> statusOptions;
  final List<AdminFilterOption> sortOptions;
  final List<_AdminQueueSignal> prioritySignals;
  final List<_AdminQueueSignal> workflowSteps;

  static const _defaultStatuses = [
    AdminFilterOption(value: '', label: 'All'),
    AdminFilterOption(value: 'pending', label: 'Pending'),
    AdminFilterOption(value: 'active', label: 'Active'),
    AdminFilterOption(value: 'needs_review', label: 'Review'),
  ];

  static const _defaultSorts = [
    AdminFilterOption(value: 'created_at_desc', label: 'Newest'),
    AdminFilterOption(value: 'created_at_asc', label: 'Oldest'),
  ];

  factory _AdminListSpec.fromConfig(AdminQueueSpecConfig config) {
    return _AdminListSpec(
      title: config.title,
      subtitle: config.subtitle,
      statusOptions: [
        for (final option in config.statusOptions)
          AdminFilterOption(value: option.value, label: option.label),
      ],
      sortOptions: [
        for (final option in config.sortOptions)
          AdminFilterOption(value: option.value, label: option.label),
      ],
      prioritySignals: [
        for (final signal in config.prioritySignals)
          _AdminQueueSignal(
            _adminQueueIconForKey(signal.iconKey),
            signal.label,
          ),
      ],
      workflowSteps: [
        for (final signal in config.workflowSteps)
          _AdminQueueSignal(
            _adminQueueIconForKey(signal.iconKey),
            signal.label,
          ),
      ],
    );
  }

  factory _AdminListSpec.forRpc(
    String rpcName, {
    AdminRuntimeConfig? runtimeConfig,
  }) {
    final configured = runtimeConfig?.queueSpecs.where(
      (spec) => spec.rpcName == rpcName,
    );
    if (configured != null && configured.isNotEmpty) {
      return _AdminListSpec.fromConfig(configured.first);
    }
    return switch (rpcName) {
      'admin_list_payment_events' => const _AdminListSpec(
        title: 'SMS parsing',
        subtitle: 'Triage MoMo SMS events.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'All'),
          AdminFilterOption(value: 'needs_review', label: 'Review'),
          AdminFilterOption(value: 'unallocated', label: 'Unallocated'),
          AdminFilterOption(value: 'ambiguous', label: 'Ambiguous'),
          AdminFilterOption(value: 'allocated', label: 'Allocated'),
        ],
        sortOptions: [
          AdminFilterOption(value: 'created_at_desc', label: 'Newest'),
          AdminFilterOption(value: 'created_at_asc', label: 'Oldest'),
          AdminFilterOption(value: 'amount_desc', label: 'Amount high'),
          AdminFilterOption(value: 'amount_asc', label: 'Amount low'),
        ],
        prioritySignals: [
          _AdminQueueSignal(Icons.rule_outlined, 'Ambiguous matches'),
          _AdminQueueSignal(Icons.replay_outlined, 'Reason required'),
          _AdminQueueSignal(Icons.privacy_tip_outlined, 'Raw SMS hidden'),
        ],
        workflowSteps: [
          _AdminQueueSignal(Icons.filter_alt_outlined, 'Filter review queue'),
          _AdminQueueSignal(Icons.open_in_new_outlined, 'Open event detail'),
          _AdminQueueSignal(
            Icons.replay_outlined,
            'Request reparse with reason',
          ),
        ],
      ),
      'admin_list_allocations' => const _AdminListSpec(
        title: 'Allocations',
        subtitle: 'Review matched payments.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'All'),
          AdminFilterOption(value: 'allocated', label: 'Allocated'),
          AdminFilterOption(value: 'needs_review', label: 'Review'),
        ],
        sortOptions: _defaultSorts,
        prioritySignals: [
          _AdminQueueSignal(Icons.account_tree_outlined, 'Matched events'),
          _AdminQueueSignal(Icons.history_outlined, 'Audit history first'),
        ],
        workflowSteps: [
          _AdminQueueSignal(
            Icons.fact_check_outlined,
            'Compare intent and event',
          ),
          _AdminQueueSignal(Icons.history_outlined, 'Review audit trail'),
          _AdminQueueSignal(Icons.note_alt_outlined, 'Document exceptions'),
        ],
      ),
      'admin_list_unallocated' => const _AdminListSpec(
        title: 'Exceptions',
        subtitle: 'Resolve open MoMo events.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'Open'),
          AdminFilterOption(value: 'needs_review', label: 'Review'),
          AdminFilterOption(value: 'unallocated', label: 'Unallocated'),
          AdminFilterOption(value: 'ambiguous', label: 'Ambiguous'),
        ],
        sortOptions: [
          AdminFilterOption(value: 'created_at_desc', label: 'Newest'),
          AdminFilterOption(value: 'created_at_asc', label: 'Oldest'),
          AdminFilterOption(value: 'amount_desc', label: 'Amount high'),
          AdminFilterOption(value: 'amount_asc', label: 'Amount low'),
        ],
        prioritySignals: [
          _AdminQueueSignal(Icons.priority_high_outlined, 'Open exceptions'),
          _AdminQueueSignal(Icons.notes_outlined, 'Document decisions'),
          _AdminQueueSignal(Icons.lock_outline, 'No raw SMS in queue'),
        ],
        workflowSteps: [
          _AdminQueueSignal(Icons.rule_folder_outlined, 'Classify exception'),
          _AdminQueueSignal(
            Icons.person_search_outlined,
            'Check group context',
          ),
          _AdminQueueSignal(
            Icons.escalator_warning_outlined,
            'Escalate if unresolved',
          ),
        ],
      ),
      'admin_list_sms_metadata' => const _AdminListSpec(
        title: 'SMS metadata',
        subtitle: 'Review SMS metadata.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'All'),
          AdminFilterOption(value: 'needs_review', label: 'Review'),
          AdminFilterOption(value: 'parsed', label: 'Parsed'),
          AdminFilterOption(value: 'failed', label: 'Failed'),
        ],
        sortOptions: _defaultSorts,
        prioritySignals: [
          _AdminQueueSignal(Icons.sms_outlined, 'Metadata only'),
          _AdminQueueSignal(Icons.verified_user_outlined, 'Reveal is audited'),
        ],
        workflowSteps: [
          _AdminQueueSignal(Icons.search_outlined, 'Find metadata'),
          _AdminQueueSignal(Icons.security_outlined, 'Gate raw reveal'),
          _AdminQueueSignal(Icons.policy_outlined, 'Log access reason'),
        ],
      ),
      'admin_list_collections' => const _AdminListSpec(
        title: 'Groups',
        subtitle: 'Support group operations.',
        statusOptions: _defaultStatuses,
        sortOptions: _defaultSorts,
        prioritySignals: [
          _AdminQueueSignal(Icons.folder_copy_outlined, 'Group profile'),
          _AdminQueueSignal(Icons.groups_outlined, 'Member context'),
          _AdminQueueSignal(Icons.settings_phone_outlined, 'Receiver setup'),
        ],
        workflowSteps: [
          _AdminQueueSignal(Icons.open_in_new_outlined, 'Open group detail'),
          _AdminQueueSignal(
            Icons.verified_outlined,
            'Check receiver readiness',
          ),
          _AdminQueueSignal(Icons.note_alt_outlined, 'Record support decision'),
        ],
      ),
      'admin_list_users' => const _AdminListSpec(
        title: 'Members',
        subtitle: 'Support member accounts.',
        statusOptions: _defaultStatuses,
        sortOptions: _defaultSorts,
        prioritySignals: [
          _AdminQueueSignal(Icons.badge_outlined, 'Collect ID first'),
          _AdminQueueSignal(Icons.phone_android_outlined, 'Phone masked'),
          _AdminQueueSignal(
            Icons.privacy_tip_outlined,
            'Private data minimized',
          ),
        ],
        workflowSteps: [
          _AdminQueueSignal(Icons.open_in_new_outlined, 'Open member detail'),
          _AdminQueueSignal(Icons.group_outlined, 'Check group membership'),
          _AdminQueueSignal(
            Icons.support_agent_outlined,
            'Escalate support path',
          ),
        ],
      ),
      'admin_list_payment_intents' => const _AdminListSpec(
        title: 'Payment intents',
        subtitle: 'Review contribution intent lifecycle.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'All'),
          AdminFilterOption(value: 'pending', label: 'Pending'),
          AdminFilterOption(value: 'matched', label: 'Matched'),
          AdminFilterOption(value: 'expired', label: 'Expired'),
          AdminFilterOption(value: 'cancelled', label: 'Cancelled'),
        ],
        sortOptions: [
          AdminFilterOption(value: 'created_at_desc', label: 'Newest'),
          AdminFilterOption(value: 'created_at_asc', label: 'Oldest'),
          AdminFilterOption(value: 'amount_desc', label: 'Amount high'),
          AdminFilterOption(value: 'amount_asc', label: 'Amount low'),
        ],
        prioritySignals: [
          _AdminQueueSignal(Icons.payments_outlined, 'Intent status'),
          _AdminQueueSignal(
            Icons.account_balance_wallet_outlined,
            'MoMo amount',
          ),
          _AdminQueueSignal(Icons.rule_outlined, 'Review exceptions'),
        ],
        workflowSteps: [
          _AdminQueueSignal(Icons.open_in_new_outlined, 'Open intent detail'),
          _AdminQueueSignal(Icons.compare_arrows_outlined, 'Compare events'),
          _AdminQueueSignal(Icons.receipt_long_outlined, 'Check ledger impact'),
        ],
      ),
      'admin_list_payments' => const _AdminListSpec(
        title: 'Transactions',
        subtitle: 'Review posted MoMo transactions.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'All'),
          AdminFilterOption(value: 'posted', label: 'Posted'),
          AdminFilterOption(value: 'review', label: 'Review'),
          AdminFilterOption(value: 'reversed', label: 'Reversed'),
        ],
        sortOptions: [
          AdminFilterOption(value: 'created_at_desc', label: 'Newest'),
          AdminFilterOption(value: 'created_at_asc', label: 'Oldest'),
          AdminFilterOption(value: 'amount_desc', label: 'Amount high'),
          AdminFilterOption(value: 'amount_asc', label: 'Amount low'),
        ],
        prioritySignals: [
          _AdminQueueSignal(Icons.receipt_long_outlined, 'Posted records'),
          _AdminQueueSignal(Icons.account_balance_outlined, 'Ledger impact'),
        ],
        workflowSteps: [
          _AdminQueueSignal(Icons.open_in_new_outlined, 'Open transaction'),
          _AdminQueueSignal(Icons.compare_arrows_outlined, 'Compare intent'),
          _AdminQueueSignal(Icons.history_outlined, 'Review posting history'),
        ],
      ),
      'admin_list_notifications' => const _AdminListSpec(
        title: 'Notifications',
        subtitle: 'Monitor event and delivery health.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'All'),
          AdminFilterOption(value: 'queued', label: 'Queued'),
          AdminFilterOption(value: 'sent', label: 'Sent'),
          AdminFilterOption(value: 'failed', label: 'Failed'),
          AdminFilterOption(value: 'read', label: 'Read'),
        ],
        sortOptions: _defaultSorts,
        prioritySignals: [
          _AdminQueueSignal(Icons.notifications_outlined, 'Delivery health'),
          _AdminQueueSignal(Icons.privacy_tip_outlined, 'Message body hidden'),
        ],
        workflowSteps: [
          _AdminQueueSignal(Icons.open_in_new_outlined, 'Open event detail'),
          _AdminQueueSignal(Icons.replay_outlined, 'Retry with reason'),
          _AdminQueueSignal(Icons.policy_outlined, 'Review audit entry'),
        ],
      ),
      'admin_list_receivers' => const _AdminListSpec(
        title: 'Receivers',
        subtitle: 'Review MoMo receiver routes.',
        statusOptions: _defaultStatuses,
        sortOptions: _defaultSorts,
        prioritySignals: [
          _AdminQueueSignal(Icons.settings_phone_outlined, 'Receiver route'),
          _AdminQueueSignal(Icons.visibility_off_outlined, 'MoMo masked'),
          _AdminQueueSignal(Icons.verified_user_outlined, 'Owner controlled'),
        ],
        workflowSteps: [
          _AdminQueueSignal(Icons.open_in_new_outlined, 'Open receiver detail'),
          _AdminQueueSignal(Icons.fact_check_outlined, 'Check owner setup'),
          _AdminQueueSignal(Icons.policy_outlined, 'Preserve audit trail'),
        ],
      ),
      'admin_list_ledger' => const _AdminListSpec(
        title: 'Ledger',
        subtitle: 'Review posted contribution records.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'All'),
          AdminFilterOption(value: 'confirmed', label: 'Confirmed'),
          AdminFilterOption(value: 'pending', label: 'Pending'),
          AdminFilterOption(value: 'needs_review', label: 'Review'),
        ],
        sortOptions: _defaultSorts,
        prioritySignals: [
          _AdminQueueSignal(Icons.account_balance_outlined, 'Ledger-safe view'),
          _AdminQueueSignal(Icons.history_outlined, 'Immutable history'),
        ],
        workflowSteps: [
          _AdminQueueSignal(Icons.filter_list_outlined, 'Filter by status'),
          _AdminQueueSignal(
            Icons.receipt_long_outlined,
            'Compare source intent',
          ),
          _AdminQueueSignal(
            Icons.note_alt_outlined,
            'Document correction path',
          ),
        ],
      ),
      'admin_list_audit_logs' => const _AdminListSpec(
        title: 'Audit logs',
        subtitle: 'Review operator and system actions.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'All'),
          AdminFilterOption(value: 'logged', label: 'Logged'),
          AdminFilterOption(value: 'sensitive', label: 'Sensitive'),
        ],
        sortOptions: _defaultSorts,
        prioritySignals: [
          _AdminQueueSignal(Icons.policy_outlined, 'Audit trail'),
          _AdminQueueSignal(Icons.security_outlined, 'Sensitive actions'),
        ],
        workflowSteps: [
          _AdminQueueSignal(Icons.search_outlined, 'Search action'),
          _AdminQueueSignal(Icons.person_search_outlined, 'Review actor'),
          _AdminQueueSignal(Icons.report_outlined, 'Escalate anomalies'),
        ],
      ),
      'admin_list_settings' => const _AdminListSpec(
        title: 'Settings',
        subtitle: 'Review platform configuration.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'All'),
          AdminFilterOption(value: 'enabled', label: 'Enabled'),
          AdminFilterOption(value: 'disabled', label: 'Disabled'),
        ],
        sortOptions: _defaultSorts,
        prioritySignals: [
          _AdminQueueSignal(Icons.tune_outlined, 'Configuration'),
          _AdminQueueSignal(Icons.lock_outline, 'Change control'),
        ],
        workflowSteps: [
          _AdminQueueSignal(
            Icons.fact_check_outlined,
            'Confirm owner approval',
          ),
          _AdminQueueSignal(Icons.history_outlined, 'Review previous value'),
          _AdminQueueSignal(Icons.policy_outlined, 'Record governance note'),
        ],
      ),
      'admin_list_feature_flags' => const _AdminListSpec(
        title: 'Feature flags',
        subtitle: 'Review feature rollout controls.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'All'),
          AdminFilterOption(value: 'enabled', label: 'Enabled'),
          AdminFilterOption(value: 'disabled', label: 'Disabled'),
        ],
        sortOptions: _defaultSorts,
        prioritySignals: [
          _AdminQueueSignal(Icons.flag_outlined, 'Rollout control'),
          _AdminQueueSignal(Icons.groups_outlined, 'Audience impact'),
        ],
        workflowSteps: [
          _AdminQueueSignal(Icons.rule_outlined, 'Check rollout condition'),
          _AdminQueueSignal(
            Icons.monitor_heart_outlined,
            'Watch health signals',
          ),
          _AdminQueueSignal(Icons.undo_outlined, 'Keep rollback path'),
        ],
      ),
      'admin_list_admin_users' => const _AdminListSpec(
        title: 'Admin users',
        subtitle: 'Review operator access.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'All'),
          AdminFilterOption(value: 'admin', label: 'Admin'),
          AdminFilterOption(value: 'active', label: 'Active'),
          AdminFilterOption(value: 'revoked', label: 'Revoked'),
        ],
        sortOptions: _defaultSorts,
        prioritySignals: [
          _AdminQueueSignal(Icons.admin_panel_settings_outlined, 'Role scope'),
          _AdminQueueSignal(Icons.verified_user_outlined, 'Least privilege'),
        ],
        workflowSteps: [
          _AdminQueueSignal(Icons.person_search_outlined, 'Review identity'),
          _AdminQueueSignal(Icons.rule_outlined, 'Check role matrix'),
          _AdminQueueSignal(Icons.block_outlined, 'Revoke stale access'),
        ],
      ),
      _ => const _AdminListSpec(
        title: 'Admin queue',
        subtitle: 'Review records.',
        statusOptions: _defaultStatuses,
        sortOptions: _defaultSorts,
      ),
    };
  }
}

IconData _adminQueueIconForKey(String iconKey) {
  return switch (iconKey.trim().toLowerCase()) {
    'account_balance' => Icons.account_balance_outlined,
    'account_balance_wallet' => Icons.account_balance_wallet_outlined,
    'account_tree' => Icons.account_tree_outlined,
    'admin_panel_settings' => Icons.admin_panel_settings_outlined,
    'badge' => Icons.badge_outlined,
    'block' => Icons.block_outlined,
    'call_split' => Icons.call_split_outlined,
    'compare_arrows' => Icons.compare_arrows_outlined,
    'dashboard' => Icons.dashboard_outlined,
    'escalator_warning' => Icons.escalator_warning_outlined,
    'fact_check' => Icons.fact_check_outlined,
    'filter_alt' => Icons.filter_alt_outlined,
    'filter_list' => Icons.filter_list_outlined,
    'flag' => Icons.flag_outlined,
    'folder_copy' => Icons.folder_copy_outlined,
    'group' => Icons.group_outlined,
    'groups' => Icons.groups_outlined,
    'history' => Icons.history_outlined,
    'lock' => Icons.lock_outline,
    'monitor_heart' => Icons.monitor_heart_outlined,
    'note_alt' => Icons.note_alt_outlined,
    'notes' => Icons.notes_outlined,
    'notifications' => Icons.notifications_outlined,
    'open_in_new' => Icons.open_in_new_outlined,
    'payments' => Icons.payments_outlined,
    'person_search' => Icons.person_search_outlined,
    'phone_android' => Icons.phone_android_outlined,
    'policy' => Icons.policy_outlined,
    'privacy_tip' => Icons.privacy_tip_outlined,
    'priority_high' => Icons.priority_high_outlined,
    'receipt_long' => Icons.receipt_long_outlined,
    'replay' => Icons.replay_outlined,
    'report' => Icons.report_outlined,
    'rule' => Icons.rule_outlined,
    'rule_folder' => Icons.rule_folder_outlined,
    'search' => Icons.search_outlined,
    'security' => Icons.security_outlined,
    'settings_phone' => Icons.settings_phone_outlined,
    'sms' => Icons.sms_outlined,
    'support_agent' => Icons.support_agent_outlined,
    'tune' => Icons.tune_outlined,
    'undo' => Icons.undo_outlined,
    'verified' => Icons.verified_outlined,
    'verified_user' => Icons.verified_user_outlined,
    'visibility_off' => Icons.visibility_off_outlined,
    _ => Icons.info_outline,
  };
}

class _AdminQueueSignal {
  const _AdminQueueSignal(this.icon, this.label);

  final IconData icon;
  final String label;
}
