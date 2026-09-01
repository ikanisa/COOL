part of 'admin_runtime.dart';

class AdminCollectTransactionDetailPage extends ConsumerWidget {
  const AdminCollectTransactionDetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(adminRealtimeTickProvider);
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    return AdminPage(
      title: 'Transaction detail',
      leading: IconButton(
        tooltip: 'Back to Transactions',
        onPressed: () => context.go('/admin/transactions'),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      child: FutureBuilder<Map<String, dynamic>>(
        future: ref
            .read(adminRepositoryProvider)
            .detail('admin_get_collect_transaction', id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AdminLoadingState(
              title: 'Loading transaction',
              message: 'Fetching parsed payment and payee details.',
            );
          }
          if (snapshot.hasError) {
            return AdminSafeErrorPanel(error: snapshot.error!);
          }
          final data = snapshot.data ?? const {};
          if (data.isEmpty) {
            return const AdminEmptyState(title: 'Transaction not found');
          }
          final rawSmsId = '${data['raw_sms_id'] ?? ''}'.trim();
          final rawBankEventId = '${data['raw_bank_event_id'] ?? ''}'.trim();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AdminRecordDetailPanel(
                title: 'Transaction detail',
                rpcName: 'admin_get_collect_transaction',
                id: id,
                data: data,
              ),
              if (rawSmsId.isNotEmpty &&
                  _adminHasPermission(identity, 'sms.raw.reveal')) ...[
                const SizedBox(height: 16),
                AdminSensitiveDataGate(
                  label: 'Raw transaction message',
                  onReveal: (reason) async {
                    final response = await ref
                        .read(adminRepositoryProvider)
                        .action('admin_reveal_raw_sms', {
                          'p_sms_id': rawSmsId,
                          'p_reason': reason,
                        });
                    return '${response['message'] ?? ''}';
                  },
                ),
              ],
              if (rawBankEventId.isNotEmpty &&
                  _adminHasPermission(
                    identity,
                    'bank_evidence.raw.reveal',
                  )) ...[
                const SizedBox(height: 16),
                AdminSensitiveDataGate(
                  label: 'Raw diaspora account message',
                  onReveal: (reason) async {
                    final response = await ref
                        .read(adminRepositoryProvider)
                        .action('admin_reveal_raw_bank_evidence', {
                          'p_event_id': rawBankEventId,
                          'p_reason': reason,
                        });
                    return '${response['body'] ?? ''}';
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class AdminSmsDetailPage extends ConsumerWidget {
  const AdminSmsDetailPage({
    required this.id,
    this.backPath,
    this.backLabel,
    super.key,
  });

  final String id;
  final String? backPath;
  final String? backLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    return AdminPage(
      title: 'SMS metadata detail',
      leading: backPath == null
          ? null
          : IconButton(
              tooltip: 'Back to ${backLabel ?? 'SMS metadata'}',
              onPressed: () => context.go(backPath!),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
      child: FutureBuilder<Map<String, dynamic>>(
        future: ref
            .read(adminRepositoryProvider)
            .detail('admin_get_sms_metadata', id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AdminLoadingState(
              title: 'Loading SMS metadata',
              message: 'Fetching protected receipt metadata.',
            );
          }
          if (snapshot.hasError) {
            return AdminSafeErrorPanel(error: snapshot.error!);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AdminRecordDetailPanel(
                title: 'SMS metadata detail',
                rpcName: 'admin_get_sms_metadata',
                id: id,
                data: snapshot.data ?? const {},
              ),
              if (identity?.permissions.contains('sms.raw.reveal') == true) ...[
                const SizedBox(height: 16),
                AdminSensitiveDataGate(
                  label: 'Raw MoMo receipt SMS',
                  onReveal: (reason) async {
                    final response = await ref
                        .read(adminRepositoryProvider)
                        .action('admin_reveal_raw_sms', {
                          'p_sms_id': id,
                          'p_reason': reason,
                        });
                    return (response['message'] as String?) ?? '';
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class AdminDetailPage extends ConsumerWidget {
  const AdminDetailPage({
    required this.title,
    required this.rpcName,
    required this.id,
    this.backPath,
    this.backLabel,
    super.key,
  });

  final String title;
  final String rpcName;
  final String id;
  final String? backPath;
  final String? backLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(adminRealtimeTickProvider);
    return AdminPage(
      title: title,
      leading: backPath == null
          ? null
          : IconButton(
              tooltip: 'Back to ${backLabel ?? 'admin list'}',
              onPressed: () => context.go(backPath!),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
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
              _AdminBankDetailActions(rpcName: rpcName, id: id, data: data),
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
    final fields = _adminDetailFields(spec, data)
        .where((field) {
          if (rpcName == 'admin_get_user' && field.label == 'WhatsApp') {
            return false;
          }
          if (rpcName == 'admin_get_user' &&
              title == 'User detail' &&
              field.label == 'Groups') {
            return false;
          }
          if (rpcName == 'admin_get_admin_user' && field.label == 'Phone') {
            return false;
          }
          if (rpcName == 'admin_get_collect_transaction' &&
              field.label == 'Reference') {
            return false;
          }
          if (rpcName == 'admin_get_notification' &&
              field.label == 'Delivery statuses') {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    final heading = _adminDetailHeading(rpcName, title, spec.heading, data);
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    final colors = context.collectColors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '$heading detail panel',
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
                    heading,
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
                    child: IconButton.filled(
                      tooltip: 'Retry failed delivery',
                      onPressed: () => _retryNotification(context, ref),
                      icon: const Icon(Icons.replay_outlined),
                    ),
                  ),
                ),
              ],
              if (rpcName == 'admin_get_admin_user' &&
                  _adminHasPermission(identity, 'admin_users.manage')) ...[
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton.filledTonal(
                    tooltip: _adminAccessIsActive(data)
                        ? 'Deactivate Admin access'
                        : 'Activate Admin access',
                    onPressed: () => _changeAdminAccess(
                      context,
                      ref,
                      active: _adminAccessIsActive(data),
                    ),
                    icon: Icon(
                      _adminAccessIsActive(data)
                          ? Icons.person_remove_outlined
                          : Icons.person_add_alt_1_outlined,
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
                      child: IconButton.outlined(
                        tooltip: 'Record note',
                        onPressed: () => _recordOperatorNote(
                          context,
                          ref,
                          spec.noteEntityType!,
                        ),
                        icon: const Icon(Icons.note_add_outlined),
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
              if (rpcName == 'admin_get_collection' &&
                  _adminHasPermission(identity, 'collections.moderate') &&
                  data['is_platform_sponsored'] == true) ...[
                const SizedBox(height: 12),
                _AdminPlatformPublicGroupEditor(collectionId: id, data: data),
              ],
            ],
          ),
        ),
      ),
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
    ref.read(adminRealtimeTickProvider.notifier).state += 1;
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Operator note recorded')));
  }

  Future<void> _changeAdminAccess(
    BuildContext context,
    WidgetRef ref, {
    required bool active,
  }) async {
    final verb = active ? 'Deactivate' : 'Activate';
    final reason = await showAdminReasonDialog(
      context,
      title: '$verb Admin access',
      actionLabel: verb,
    );
    if (reason == null) return;
    try {
      await ref.read(adminRepositoryProvider).action('admin_set_user_access', {
        'p_user_id': id,
        'p_active': !active,
        'p_reason': reason,
      });
      ref.read(adminRealtimeTickProvider.notifier).state += 1;
      ref.invalidate(adminIdentityProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Admin access ${active ? 'deactivated' : 'activated'}'),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_adminActionErrorMessage(error))));
    }
  }
}

bool _adminAccessIsActive(Map<String, dynamic> data) {
  final status = '${data['status'] ?? ''}'.trim().toLowerCase();
  if (status == 'active') return true;
  final roles = _detailStringList(data['active_roles']);
  return roles.contains('admin') || roles.contains('platform_owner');
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
  if (message.contains('last platform owner') ||
      message.contains('last admin')) {
    return 'The last Admin cannot be deactivated.';
  }
  if (message.contains('your own platform owner') ||
      message.contains('your own admin access')) {
    return 'You cannot deactivate your own Admin access.';
  }
  if (message.contains('already active')) {
    return 'Admin access is already active.';
  }
  if (message.contains('no retryable failed deliveries')) {
    return 'No active failed delivery is eligible for retry.';
  }
  if (message.contains('activate an official payee')) {
    return 'Activate an official payee before activating this public group.';
  }
  if (message.contains('collect profile')) {
    return 'The signed-in admin needs a Collect profile before creating a public group.';
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
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Group lifecycle actions',
      hint: 'Activates or deactivates the group with an audited reason.',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
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
          if (currentStatus == 'archived' || currentStatus == 'inactive')
            _AdminCollectionStatusButton(
              collectionId: collectionId,
              status: 'active',
              label: 'Activate',
              icon: Icons.play_circle_outline,
            )
          else
            _AdminCollectionStatusButton(
              collectionId: collectionId,
              status: 'inactive',
              label: 'Deactivate',
              icon: Icons.pause_circle_outline,
              destructive: true,
            ),
        ],
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
    final button = IconButton.outlined(
      tooltip: label,
      onPressed: () => _updateStatus(context, ref),
      icon: Icon(icon),
      style: destructive
          ? IconButton.styleFrom(foregroundColor: colors.danger)
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
    final lifecycleAction = status == 'active' || status == 'inactive';
    try {
      await ref
          .read(adminRepositoryProvider)
          .action(
            lifecycleAction
                ? 'admin_set_group_active'
                : 'admin_update_collection_support_status',
            lifecycleAction
                ? {
                    'p_collection_id': collectionId,
                    'p_active': status == 'active',
                    'p_reason': reason,
                  }
                : {
                    'p_collection_id': collectionId,
                    'p_status': status,
                    'p_reason': reason,
                  },
          );
      ref.read(adminRealtimeTickProvider.notifier).state += 1;
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Group updated: $label')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_adminActionErrorMessage(error))));
    }
  }
}

class _AdminPlatformPublicGroupEditor extends ConsumerStatefulWidget {
  const _AdminPlatformPublicGroupEditor({
    required this.collectionId,
    required this.data,
  });

  final String collectionId;
  final Map<String, dynamic> data;

  @override
  ConsumerState<_AdminPlatformPublicGroupEditor> createState() =>
      _AdminPlatformPublicGroupEditorState();
}

class _AdminPlatformPublicGroupEditorState
    extends ConsumerState<_AdminPlatformPublicGroupEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _categorySubtype;
  late final TextEditingController _purposeLabel;
  late final TextEditingController _receiverLabel;
  late String _collectionType;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: '${widget.data['title'] ?? ''}');
    _description = TextEditingController(
      text: '${widget.data['description'] ?? ''}',
    );
    _categorySubtype = TextEditingController(
      text: '${widget.data['category_subtype'] ?? ''}',
    );
    _purposeLabel = TextEditingController(
      text: '${widget.data['purpose_label'] ?? ''}',
    );
    _receiverLabel = TextEditingController(
      text: '${widget.data['receiver_display_label'] ?? ''}',
    );
    final type = '${widget.data['collection_type'] ?? 'other'}';
    _collectionType =
        const {'ikimina', 'sport', 'church', 'wedding', 'other'}.contains(type)
        ? type
        : 'other';
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _categorySubtype.dispose();
    _purposeLabel.dispose();
    _receiverLabel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Edit database-managed public group',
      hint:
          'Updates public group catalogue metadata. The payee MoMo route remains locked.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceMuted.withValues(alpha: 0.84),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.borderAccent),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit group',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: CollectTypography.weightBold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _publicGroupTextField(
                      controller: _title,
                      label: 'Group name',
                      validator: (value) => (value ?? '').trim().length < 3
                          ? 'Enter at least 3 characters'
                          : null,
                    ),
                    _publicGroupTextField(
                      controller: _description,
                      label: 'Description',
                      maxLines: 2,
                    ),
                    _publicGroupDropdown(
                      label: 'Collection type',
                      value: _collectionType,
                      items: const {
                        'ikimina': 'Group savings',
                        'sport': 'Sport',
                        'church': 'Church',
                        'wedding': 'Wedding',
                        'other': 'Other',
                      },
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _collectionType = value);
                        }
                      },
                    ),
                    _publicGroupTextField(
                      controller: _purposeLabel,
                      label: 'Purpose label',
                    ),
                    _publicGroupTextField(
                      controller: _receiverLabel,
                      label: 'Receiver name',
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Receiver name is required'
                          : null,
                    ),
                    _AdminImmutablePayeeRoute(data: widget.data),
                  ],
                ),
                const SizedBox(height: 14),
                IconButton.filled(
                  tooltip: 'Save group changes',
                  onPressed: _working ? null : _save,
                  icon: _working
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _publicGroupTextField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return SizedBox(
      width: 300,
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
      ),
    );
  }

  Widget _publicGroupDropdown({
    required String label,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: 300,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final item in items.entries)
            DropdownMenuItem(value: item.key, child: Text(item.value)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final reason = await showAdminReasonDialog(
      context,
      title: 'Update public group',
      actionLabel: 'Save changes',
    );
    if (reason == null || !mounted) return;
    setState(() => _working = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .action('admin_update_platform_public_group_metadata', {
            'p_collection_id': widget.collectionId,
            'p_title': _title.text.trim(),
            'p_description': _description.text.trim(),
            'p_collection_type': _collectionType,
            'p_category_subtype': _categorySubtype.text.trim(),
            'p_purpose_label': _purposeLabel.text.trim(),
            'p_receiver_label': _receiverLabel.text.trim(),
            'p_reason': reason,
          });
      ref.read(adminRealtimeTickProvider.notifier).state += 1;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Public group updated in Supabase')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_adminActionErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

class _AdminImmutablePayeeRoute extends StatelessWidget {
  const _AdminImmutablePayeeRoute({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final code = '${data['receiver_momo_code'] ?? 'Not configured'}';
    final network = '${data['receiver_network'] ?? 'Not configured'}';
    return Semantics(
      container: true,
      readOnly: true,
      label: 'Immutable payee route. MoMo code $code. Network $network.',
      child: SizedBox(
        width: 300,
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'MoMo route (locked)',
            helperText: 'The MoMo number or code can never be edited.',
          ),
          child: Text('$network · $code'),
        ),
      ),
    );
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Tooltip(
                    message: label,
                    excludeFromSemantics: true,
                    child: _adminDetailFieldGlyph(
                      label,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      value,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: CollectTypography.weightBold,
                      ),
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

Widget _adminDetailFieldGlyph(String label, {required Color color}) {
  if (label.toLowerCase().contains('whatsapp')) {
    return FaIcon(FontAwesomeIcons.whatsapp, size: 19, color: color);
  }
  return Icon(_adminDetailFieldIcon(label), size: 19, color: color);
}

IconData _adminDetailFieldIcon(String label) {
  final normalized = label.toLowerCase();
  if (normalized.contains('phone') || normalized.contains('sender')) {
    return Icons.phone_outlined;
  }
  if (normalized.contains('database')) return Icons.storage_outlined;
  if (normalized.contains('authentication')) {
    return Icons.verified_user_outlined;
  }
  if (normalized.contains('failed')) return Icons.error_outline_rounded;
  if (normalized.contains('processing')) return Icons.sync_rounded;
  if (normalized.contains('queued')) return Icons.schedule_send_outlined;
  if (normalized.contains('notification')) {
    return Icons.notifications_outlined;
  }
  if (normalized.contains('reconciliation') ||
      normalized.contains('exception')) {
    return Icons.balance_outlined;
  }
  if (normalized.contains('allocation')) return Icons.call_split_outlined;
  if (normalized.contains('amount') ||
      normalized.contains('currency') ||
      normalized.contains('raised')) {
    return Icons.payments_outlined;
  }
  if (normalized.contains('status') || normalized.contains('active')) {
    return Icons.verified_outlined;
  }
  if (normalized.contains('country') || normalized.contains('visibility')) {
    return Icons.public_outlined;
  }
  if (normalized.contains('payment')) {
    return Icons.account_balance_wallet_outlined;
  }
  if (normalized.contains('purpose')) return Icons.category_outlined;
  if (normalized.contains('created') ||
      normalized.contains('received') ||
      normalized.contains('checked') ||
      normalized.contains('updated') ||
      normalized.contains('expires')) {
    return Icons.schedule_outlined;
  }
  if (normalized.contains('group') || normalized.contains('collection')) {
    return Icons.groups_outlined;
  }
  if (normalized.contains('user') ||
      normalized.contains('member') ||
      normalized.contains('contributor') ||
      normalized.contains('owner')) {
    return Icons.person_outline;
  }
  if (normalized.contains('payee') || normalized.contains('receiver')) {
    return Icons.location_on_outlined;
  }
  if (normalized.contains('provider') ||
      normalized.contains('network') ||
      normalized.contains('route') ||
      normalized.contains('source')) {
    return Icons.swap_horiz_outlined;
  }
  if (normalized.contains('role')) return Icons.admin_panel_settings_outlined;
  if (normalized.contains('error')) return Icons.error_outline;
  if (normalized.contains('id') ||
      normalized.contains('reference') ||
      normalized.contains('code')) {
    return Icons.tag_outlined;
  }
  return Icons.info_outline;
}

bool _adminHasPermission(AdminIdentity? identity, String permission) {
  return identity?.permissions.contains(permission) == true;
}

bool _adminCanRecordNote(AdminIdentity? identity, String entityType) {
  return switch (entityType) {
    'collection' => _adminHasPermission(identity, 'collections.read'),
    'profile' => _adminHasPermission(identity, 'users.read'),
    _ => false,
  };
}
