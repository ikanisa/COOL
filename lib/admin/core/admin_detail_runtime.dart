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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AdminRecordDetailPanel(
                title: title,
                rpcName: rpcName,
                id: id,
                data: data,
              ),
              if (rpcName == 'admin_get_admin_user') ...[
                const SizedBox(height: 16),
                _AdminRoleManagementPanel(userId: id, data: data),
              ],
            ],
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
                      fontWeight: CollectTypography.weightBold,
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
                    child: FilledButton.icon(
                      onPressed: () => _requestReparse(context, ref),
                      icon: const Icon(Icons.replay_outlined),
                      label: const Text('Request reparse'),
                    ),
                  ),
                ),
              ],
              if (rpcName == 'admin_get_notification' &&
                  _adminHasPermission(identity, 'notifications.manage') &&
                  _detailInt(data['retryable_count']) > 0) ...[
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    button: true,
                    label: 'Retry failed notification deliveries',
                    hint:
                        'Opens a reason dialog before returning failed deliveries to the queue.',
                    child: FilledButton.icon(
                      onPressed: () => _retryNotification(context, ref),
                      icon: const Icon(Icons.replay_outlined),
                      label: const Text('Retry failed delivery'),
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
                    onTap: () =>
                        _recordOperatorNote(context, ref, spec.noteEntityType!),
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
                _AdminCollectionStatusActions(
                  collectionId: id,
                  currentStatus: _detailValue(data, const [
                    'public_status',
                    'visibility',
                    'status',
                  ]),
                ),
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

  Future<void> _retryNotification(BuildContext context, WidgetRef ref) async {
    final reason = await showAdminReasonDialog(
      context,
      title: 'Retry notification delivery',
      actionLabel: 'Retry delivery',
    );
    if (reason == null) return;
    try {
      await ref.read(adminRepositoryProvider).action(
        'admin_retry_notification',
        {'p_event_id': id, 'p_reason': reason},
      );
      ref.read(adminRealtimeTickProvider.notifier).state += 1;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed delivery returned to queue')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_adminActionErrorMessage(error))));
    }
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

class _AdminRoleManagementPanel extends ConsumerWidget {
  const _AdminRoleManagementPanel({required this.userId, required this.data});

  final String userId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    final canManage = _adminHasPermission(identity, 'admin_users.manage');
    final activeRoles = _detailStringList(data['active_roles']);
    final availableRoles = _detailStringList(data['available_roles']);
    final colors = context.collectColors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Admin role management',
      hint: canManage
          ? 'Grant or revoke roles with a required audit reason.'
          : 'Read-only role visibility.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceReadable.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: colors.borderAccent),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Role access',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                canManage
                    ? 'Every change requires a reason and is written to the audit log.'
                    : 'You can review roles but do not have role-management permission.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              if (availableRoles.isEmpty)
                const AdminEmptyState(title: 'No roles available')
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final role in availableRoles)
                      _AdminRoleActionChip(
                        userId: userId,
                        role: role,
                        active: activeRoles.contains(role),
                        canManage: canManage,
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

class _AdminRoleActionChip extends ConsumerWidget {
  const _AdminRoleActionChip({
    required this.userId,
    required this.role,
    required this.active,
    required this.canManage,
  });

  final String userId;
  final String role;
  final bool active;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = _labelizeDetailKey(role);
    final colors = context.collectColors;
    return Semantics(
      button: canManage,
      enabled: canManage,
      label: active ? '$label role active' : '$label role inactive',
      hint: canManage
          ? '${active ? 'Revoke' : 'Grant'} this role with a reason.'
          : 'Role-management permission is required.',
      child: active
          ? OutlinedButton.icon(
              onPressed: canManage ? () => _changeRole(context, ref) : null,
              icon: const Icon(Icons.verified_user_outlined),
              label: Text('$label · Revoke'),
              style: OutlinedButton.styleFrom(foregroundColor: colors.danger),
            )
          : OutlinedButton.icon(
              onPressed: canManage ? () => _changeRole(context, ref) : null,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text('$label · Grant'),
            ),
    );
  }

  Future<void> _changeRole(BuildContext context, WidgetRef ref) async {
    final verb = active ? 'Revoke' : 'Grant';
    final reason = await showAdminReasonDialog(
      context,
      title: '$verb ${_labelizeDetailKey(role)} role',
      actionLabel: '$verb role',
    );
    if (reason == null) return;
    try {
      await ref.read(adminRepositoryProvider).action(
        active ? 'admin_revoke_user_role' : 'admin_grant_user_role',
        {'p_user_id': userId, 'p_role_name': role, 'p_reason': reason},
      );
      ref.read(adminRealtimeTickProvider.notifier).state += 1;
      ref.invalidate(adminIdentityProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$role role ${active ? 'revoked' : 'granted'}')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_adminActionErrorMessage(error))));
    }
  }
}

int _detailInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

List<String> _detailStringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => '$item'.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String _adminActionErrorMessage(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('last platform owner')) {
    return 'The last platform owner cannot be revoked.';
  }
  if (message.contains('your own platform owner')) {
    return 'You cannot revoke your own platform owner role.';
  }
  if (message.contains('already active')) return 'That role is already active.';
  if (message.contains('no retryable failed deliveries')) {
    return 'No active failed delivery is eligible for retry.';
  }
  return 'The admin action failed. Refresh and try again.';
}

class _AdminCollectionStatusActions extends ConsumerWidget {
  const _AdminCollectionStatusActions({
    required this.collectionId,
    required this.currentStatus,
  });

  final String collectionId;
  final String currentStatus;

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
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Reason-gated actions update the group state and audit trail.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (currentStatus == 'public_requested') ...[
                    _AdminCollectionStatusButton(
                      collectionId: collectionId,
                      status: 'public_approved',
                      label: 'Approve public',
                      icon: Icons.public_rounded,
                    ),
                    _AdminCollectionStatusButton(
                      collectionId: collectionId,
                      status: 'public_rejected',
                      label: 'Reject public',
                      icon: Icons.block_outlined,
                    ),
                  ],
                  _AdminCollectionStatusButton(
                    collectionId: collectionId,
                    status: 'private',
                    label: 'Set private',
                    icon: Icons.lock_outline,
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
      child: button,
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
                      fontWeight: CollectTypography.weightBold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: CollectTypography.weightBold,
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
                    fontWeight: CollectTypography.weightBold,
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
