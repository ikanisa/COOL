part of 'admin_runtime.dart';

class AdminDetailPage extends ConsumerWidget {
  const AdminDetailPage({
    required this.title,
    required this.rpcName,
    required this.id,
    super.key,
  });

  final String title;
  final String rpcName;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(adminRealtimeTickProvider);
    return AdminPage(
      title: title,
      child: FutureBuilder<Map<String, dynamic>>(
        future: ref.read(adminRepositoryProvider).detail(rpcName, id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return AdminLoadingState(
              title: 'Loading ${title.toLowerCase()}',
              message: 'Fetching record.',
            );
          }
          if (snapshot.hasError) {
            return AdminSafeErrorPanel(error: snapshot.error!);
          }
          final data = snapshot.data ?? const {};
          if (data.isEmpty) {
            return const AdminEmptyState(title: 'Record not found');
          }
          return _AdminRecordDetailPanel(
            title: title,
            rpcName: rpcName,
            id: id,
            data: data,
          );
        },
      ),
    );
  }
}

class AdminSmsDetailPage extends ConsumerWidget {
  const AdminSmsDetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(adminRealtimeTickProvider);
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    return AdminPage(
      title: 'SMS metadata',
      subtitle: 'Raw SMS stays gated.',
      child: FutureBuilder<Map<String, dynamic>>(
        future: ref
            .read(adminRepositoryProvider)
            .detail('admin_get_sms_metadata', id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AdminLoadingState(
              title: 'Loading SMS metadata',
              message: 'Fetching metadata.',
            );
          }
          if (snapshot.hasError) {
            return AdminSafeErrorPanel(error: snapshot.error!);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AdminRecordDetailPanel(
                title: 'SMS metadata',
                rpcName: 'admin_get_sms_metadata',
                id: id,
                data: snapshot.data ?? const {},
              ),
              const SizedBox(height: 16),
              if (identity?.permissions.contains('sms.raw.reveal') == true)
                AdminSensitiveDataGate(
                  label: 'Raw SMS',
                  onReveal: (reason) async {
                    final response = await ref
                        .read(adminRepositoryProvider)
                        .action('admin_reveal_raw_sms', {
                          'p_sms_id': id,
                          'p_reason': reason,
                        });
                    return (response['message'] as String?) ?? '';
                  },
                )
              else
                const AdminEmptyState(
                  title: 'Raw SMS restricted',
                  message: 'Reveal permission missing.',
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AdminRecordDetailPanel extends ConsumerWidget {
  const _AdminRecordDetailPanel({
    required this.title,
    required this.rpcName,
    required this.id,
    required this.data,
  });

  final String title;
  final String rpcName;
  final String id;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = _AdminDetailSpec.forRpc(rpcName, title);
    final fields = _adminDetailFields(spec, data);
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    final colors = context.collectColors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${spec.heading} detail panel',
      hint: spec.subtitle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceReadable.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: colors.borderAccent),
          boxShadow: [
            BoxShadow(
              color: colors.textPrimary.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    spec.heading,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (_detailValue(data, const ['status']).isNotEmpty)
                    AdminStatusChip(
                      label: _detailValue(data, const ['status']),
                    ),
                ],
              ),
              if (spec.subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  spec.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ],
              if (_detailValue(data, const ['status']).isNotEmpty) ...[
                const SizedBox(height: 8),
                SelectableText(
                  '"status": "${_detailValue(data, const ['status'])}"',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final field in fields)
                    _AdminDetailFieldCard(
                      label: field.label,
                      value: field.value,
                    ),
                ],
              ),
              if (rpcName == 'admin_get_payment_event' &&
                  _adminHasPermission(identity, 'payment_events.reparse')) ...[
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    container: true,
                    button: true,
                    label: 'Request SMS payment event reparse',
                    hint:
                        'Opens a reason dialog before queuing this payment event for parser review.',
                    child: ExcludeSemantics(
                      child: FilledButton.icon(
                        onPressed: () => _requestReparse(context, ref),
                        icon: const Icon(Icons.replay_outlined),
                        label: const Text('Request reparse'),
                      ),
                    ),
                  ),
                ),
              ],
              if (spec.noteEntityType != null &&
                  _adminCanRecordNote(identity, spec.noteEntityType!)) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    container: true,
                    button: true,
                    label: 'Record ${spec.heading} operator note',
                    hint:
                        'Opens a note dialog and persists the operator note to the audit-backed admin notes table.',
                    child: ExcludeSemantics(
                      child: OutlinedButton.icon(
                        onPressed: () => _recordOperatorNote(
                          context,
                          ref,
                          spec.noteEntityType!,
                        ),
                        icon: const Icon(Icons.note_add_outlined),
                        label: const Text('Record note'),
                      ),
                    ),
                  ),
                ),
              ],
              if (rpcName == 'admin_get_collection' &&
                  _adminHasPermission(identity, 'collections.moderate')) ...[
                const SizedBox(height: 12),
                _AdminCollectionStatusActions(collectionId: id),
              ],
              const SizedBox(height: 18),
              _AdminDetailWorkflowPanel(spec: spec),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestReparse(BuildContext context, WidgetRef ref) async {
    final reason = await showAdminReasonDialog(
      context,
      title: 'Request SMS reparse',
      actionLabel: 'Request reparse',
    );
    if (reason == null) return;
    await ref.read(adminRepositoryProvider).action(
      'admin_reparse_payment_event',
      {'p_event_id': id, 'p_reason': reason},
    );
  }

  Future<void> _recordOperatorNote(
    BuildContext context,
    WidgetRef ref,
    String entityType,
  ) async {
    final note = await showAdminReasonDialog(
      context,
      title: 'Record operator note',
      actionLabel: 'Record note',
    );
    if (note == null) return;
    await ref.read(adminRepositoryProvider).action(
      'admin_record_operator_note',
      {'p_entity_type': entityType, 'p_entity_id': id, 'p_body': note},
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Operator note recorded')));
  }
}

class _AdminCollectionStatusActions extends ConsumerWidget {
  const _AdminCollectionStatusActions({required this.collectionId});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Group support status actions',
      hint: 'Updates group public support status with an audited reason.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceMuted.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.borderAccent),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Group support status',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Reason-gated actions update the group state and audit trail.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _AdminCollectionStatusButton(
                    collectionId: collectionId,
                    status: 'private',
                    label: 'Set private',
                    icon: Icons.lock_outline,
                  ),
                  _AdminCollectionStatusButton(
                    collectionId: collectionId,
                    status: 'public_rejected',
                    label: 'Reject public',
                    icon: Icons.block_outlined,
                  ),
                  _AdminCollectionStatusButton(
                    collectionId: collectionId,
                    status: 'archived',
                    label: 'Archive',
                    icon: Icons.archive_outlined,
                    destructive: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminCollectionStatusButton extends ConsumerWidget {
  const _AdminCollectionStatusButton({
    required this.collectionId,
    required this.status,
    required this.label,
    required this.icon,
    this.destructive = false,
  });

  final String collectionId;
  final String status;
  final String label;
  final IconData icon;
  final bool destructive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.collectColors;
    final button = OutlinedButton.icon(
      onPressed: () => _updateStatus(context, ref),
      icon: Icon(icon),
      label: Text(label),
      style: destructive
          ? OutlinedButton.styleFrom(foregroundColor: colors.danger)
          : null,
    );
    return Semantics(
      button: true,
      label: '$label group support status',
      hint: 'Opens a reason dialog before updating the group status.',
      child: ExcludeSemantics(child: button),
    );
  }

  Future<void> _updateStatus(BuildContext context, WidgetRef ref) async {
    final reason = await showAdminReasonDialog(
      context,
      title: '$label group',
      actionLabel: label,
    );
    if (reason == null) return;
    await ref.read(adminRepositoryProvider).action(
      'admin_update_collection_support_status',
      {'p_collection_id': collectionId, 'p_status': status, 'p_reason': reason},
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Group status updated: $label')));
  }
}

class _AdminDetailFieldCard extends StatelessWidget {
  const _AdminDetailFieldCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      label: label,
      value: value,
      readOnly: true,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceMuted.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(CollectRadius.md),
              border: Border.all(color: colors.borderAccent),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminDetailWorkflowPanel extends StatelessWidget {
  const _AdminDetailWorkflowPanel({required this.spec});

  final _AdminDetailSpec spec;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label: '${spec.heading} operator next steps',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.textPrimary.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: colors.surfaceReadable.withValues(alpha: 0.12),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final action in spec.actions)
                _AdminDetailActionChip(action: action),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminDetailActionChip extends StatelessWidget {
  const _AdminDetailActionChip({required this.action});

  final _AdminDetailAction action;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceReadable.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(CollectRadius.md),
          border: Border.all(
            color: colors.surfaceReadable.withValues(alpha: 0.14),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 18, color: colors.surfaceReadable),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  action.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.surfaceReadable,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
      'admin_get_payment' => const _AdminDetailSpec(
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
          _AdminDetailFieldSpec('Edge functions', ['edge_functions']),
          _AdminDetailFieldSpec('Realtime', ['realtime']),
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

class _AdminDetailFieldValue {
  const _AdminDetailFieldValue({required this.label, required this.value});

  final String label;
  final String value;
}

List<_AdminDetailFieldValue> _adminDetailFields(
  _AdminDetailSpec spec,
  Map<String, dynamic> data,
) {
  final usedKeys = <String>{};
  final fields = <_AdminDetailFieldValue>[];
  for (final field in spec.fields) {
    final value = _detailValue(data, field.keys, usedKeys: usedKeys);
    if (value.isNotEmpty) {
      fields.add(_AdminDetailFieldValue(label: field.label, value: value));
    }
  }
  final extras = data.entries
      .where((entry) {
        return !usedKeys.contains(entry.key) && _isSafeDetailKey(entry.key);
      })
      .take(6);
  for (final entry in extras) {
    final value = _formatDetailValue(entry.value);
    if (value.isNotEmpty) {
      fields.add(
        _AdminDetailFieldValue(
          label: _labelizeDetailKey(entry.key),
          value: value,
        ),
      );
    }
  }
  return fields;
}

String _detailValue(
  Map<String, dynamic> data,
  List<String> keys, {
  Set<String>? usedKeys,
}) {
  for (final key in keys) {
    if (!_isSafeDetailKey(key)) continue;
    if (!data.containsKey(key)) continue;
    final value = _formatDetailValue(data[key]);
    if (value.isEmpty) continue;
    usedKeys?.add(key);
    return value;
  }
  return '';
}

String _formatDetailValue(Object? value) {
  if (value == null) return '';
  if (value is DateTime) return _formatDetailDate(value);
  if (value is num) return value.toString();
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is List) {
    return value.map(_formatDetailValue).where((v) => v.isNotEmpty).join(', ');
  }
  if (value is Map) return '';
  return value.toString().trim();
}

String _labelizeDetailKey(String key) {
  final words = key.split('_').where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return 'Field';
  final label = words.join(' ');
  return label[0].toUpperCase() + label.substring(1);
}

bool _isSafeDetailKey(String key) {
  final normalized = key.toLowerCase();
  return !normalized.contains('raw') &&
      !normalized.contains('secret') &&
      !normalized.contains('token') &&
      !normalized.contains('hash') &&
      !normalized.contains('body') &&
      !normalized.contains('pin');
}

String _formatDetailDate(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

bool _adminHasPermission(AdminIdentity? identity, String permission) {
  return identity?.permissions.contains(permission) == true;
}

bool _adminCanRecordNote(AdminIdentity? identity, String entityType) {
  return switch (entityType) {
    'collection' => _adminHasPermission(identity, 'collections.read'),
    'profile' => _adminHasPermission(identity, 'users.read'),
    'payment_intent' => _adminHasPermission(identity, 'payments.read'),
    'parsed_payment_event' =>
      _adminHasPermission(identity, 'payment_events.read') ||
          _adminHasPermission(identity, 'payments.read'),
    'payment_receiver' => _adminHasPermission(identity, 'collections.read'),
    'raw_payment_sms' => _adminHasPermission(identity, 'sms.metadata.read'),
    _ => false,
  };
}
