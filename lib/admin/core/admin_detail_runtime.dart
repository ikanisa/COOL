part of 'admin_runtime.dart';

class AdminCollectTransactionDetailPage extends ConsumerWidget {
  const AdminCollectTransactionDetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(adminRealtimeTickProvider);
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    final identityRevision = ref.watch(_adminIdentityRevisionProvider);
    return AdminPage(
      title: 'Transaction detail',
      leading: IconButton(
        tooltip: 'Back to Transactions',
        onPressed: () => context.go('/admin/transactions'),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      child: FutureBuilder<Map<String, dynamic>>(
        key: ValueKey(ref.watch(adminAuthSessionScopeProvider)),
        future: ref.watch(
          adminDetailRecordProvider((
            rpc: 'admin_get_collect_transaction',
            id: id,
          )).future,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AdminLoadingState(
              title: 'Loading transaction',
              message: 'Fetching parsed payment and payee details.',
            );
          }
          if (snapshot.hasError) {
            return AdminSafeErrorPanel(
              error: snapshot.error!,
              onRetry: () =>
                  ref.read(adminRealtimeTickProvider.notifier).state += 1,
            );
          }
          final data = snapshot.data ?? const {};
          if (data.isEmpty) {
            return const AdminEmptyState(title: 'Transaction not found');
          }
          final rawSmsId = '${data['raw_sms_id'] ?? ''}'.trim();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AdminRecordDetailPanel(
                title: 'Transaction detail',
                rpcName: 'admin_get_collect_transaction',
                id: id,
                data: data,
              ),
              if (id.startsWith('momo:')) ...[
                const SizedBox(height: 16),
                AdminInvestigationView(
                  kind: 'transaction',
                  id: id.substring(5),
                ),
              ],
              if (rawSmsId.isNotEmpty &&
                  _adminHasPermission(identity, 'sms.raw.reveal')) ...[
                const SizedBox(height: 16),
                AdminSensitiveDataGate(
                  key: ValueKey((
                    id,
                    ref.watch(adminAuthSessionScopeProvider),
                    identityRevision,
                  )),
                  label: 'Raw transaction message',
                  onReveal: (reason) async {
                    final scope = _AdminActionScope(ref);
                    if (!scope.isCurrent) throw const AdminSessionChanged();
                    final response = await scope.repository.action(
                      'admin_reveal_raw_sms',
                      {'p_sms_id': rawSmsId, 'p_reason': reason},
                    );
                    if (!scope.isCurrent) throw const AdminSessionChanged();
                    return '${response['message'] ?? ''}';
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
    ref.watch(adminRealtimeTickProvider);
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    final identityRevision = ref.watch(_adminIdentityRevisionProvider);
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
        key: ValueKey(ref.watch(adminAuthSessionScopeProvider)),
        future: ref.watch(
          adminDetailRecordProvider((
            rpc: 'admin_get_sms_metadata',
            id: id,
          )).future,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AdminLoadingState(
              title: 'Loading SMS metadata',
              message: 'Fetching protected receipt metadata.',
            );
          }
          if (snapshot.hasError) {
            return AdminSafeErrorPanel(
              error: snapshot.error!,
              onRetry: () =>
                  ref.read(adminRealtimeTickProvider.notifier).state += 1,
            );
          }
          final data = snapshot.data ?? const {};
          if (data.isEmpty) {
            return const AdminEmptyState(title: 'SMS metadata not found');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AdminRecordDetailPanel(
                title: 'SMS metadata detail',
                rpcName: 'admin_get_sms_metadata',
                id: id,
                data: data,
              ),
              if (identity?.permissions.contains('sms.raw.reveal') == true) ...[
                const SizedBox(height: 16),
                AdminSensitiveDataGate(
                  key: ValueKey((
                    id,
                    ref.watch(adminAuthSessionScopeProvider),
                    identityRevision,
                  )),
                  label: 'Raw MoMo receipt SMS',
                  onReveal: (reason) async {
                    final scope = _AdminActionScope(ref);
                    if (!scope.isCurrent) throw const AdminSessionChanged();
                    final response = await scope.repository.action(
                      'admin_reveal_raw_sms',
                      {'p_sms_id': id, 'p_reason': reason},
                    );
                    if (!scope.isCurrent) throw const AdminSessionChanged();
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
        key: ValueKey(ref.watch(adminAuthSessionScopeProvider)),
        future: ref.watch(
          adminDetailRecordProvider((rpc: rpcName, id: id)).future,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return AdminLoadingState(
              title: 'Loading ${title.toLowerCase()}',
              message: 'Fetching record.',
            );
          }
          if (snapshot.hasError) {
            return AdminSafeErrorPanel(
              error: snapshot.error!,
              onRetry: () =>
                  ref.read(adminRealtimeTickProvider.notifier).state += 1,
            );
          }
          final data = snapshot.data ?? const {};
          if (rpcName == 'admin_system_health') {
            return AdminOperationalHealthPanel(
              data: data,
              clock: ref.watch(adminClockProvider),
              onRefresh: () =>
                  ref.read(adminRealtimeTickProvider.notifier).state += 1,
            );
          }
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
              if (rpcName == 'admin_get_hybrid_sms_receipt') ...[
                const SizedBox(height: 16),
                AdminInvestigationView(kind: 'receipt', id: id),
              ],
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
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    final colors = context.collectColors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '$heading detail panel',
      hint: spec.subtitle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceReadable.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.borderAccent),
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
              if ((rpcName == 'admin_get_admin_user' ||
                      rpcName == 'admin_get_user') &&
                  _adminHasPermission(identity, 'admin_users.read')) ...[
                const SizedBox(height: 18),
                AdminPlatformAccessPanel(userId: id),
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
                  operatorDraft: data['admin_operator_draft'] != false,
                  // Lifecycle decisions use the typed raw enum. The display
                  // formatter humanizes public_requested and other statuses.
                  currentStatus:
                      '${data['public_status'] ?? data['visibility'] ?? data['status'] ?? ''}'
                          .trim(),
                ),
              ],
              if (rpcName == 'admin_get_collection' &&
                  _adminHasPermission(identity, 'collections.moderate') &&
                  _adminHasPermission(identity, 'users.read') &&
                  data['creation_origin'] == 'admin_assisted' &&
                  data['visibility'] == 'private' &&
                  data['public_status'] == 'private' &&
                  data['archived_at'] == null &&
                  data['currency'] == 'RWF' &&
                  data['diaspora_enabled'] == false) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => createAdminAssistedGroup(
                    context,
                    ref,
                    collectionId: id,
                    onDone: () {},
                  ),
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Add reviewed members'),
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
    final scope = _AdminActionScope(ref);
    final reason = await showAdminReasonDialog(
      context,
      dialogWrapper: (_, child) =>
          _AdminSessionDialog(scope: scope, child: child),
      title: 'Retry notification delivery',
      actionLabel: 'Retry delivery',
    );
    if (reason == null || !context.mounted || !scope.isCurrent) return;
    try {
      await scope.repository.action('admin_retry_notification', {
        'p_event_id': id,
        'p_reason': reason,
      });
      if (!context.mounted || !scope.isCurrent) return;
      ref.read(adminRealtimeTickProvider.notifier).state += 1;
      if (!context.mounted || !scope.isCurrent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed delivery returned to queue')),
      );
    } catch (error) {
      if (!context.mounted || !scope.isCurrent) return;
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
    final scope = _AdminActionScope(ref);
    final note = await showAdminReasonDialog(
      context,
      dialogWrapper: (_, child) =>
          _AdminSessionDialog(scope: scope, child: child),
      title: 'Record operator note',
      actionLabel: 'Record note',
    );
    if (note == null || !context.mounted || !scope.isCurrent) return;
    try {
      await scope.repository.action('admin_record_operator_note', {
        'p_entity_type': entityType,
        'p_entity_id': id,
        'p_body': note,
        'p_request_id': const Uuid().v4(),
      });
      if (!context.mounted || !scope.isCurrent) return;
      ref.read(adminRealtimeTickProvider.notifier).state += 1;
      if (!context.mounted || !scope.isCurrent) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Operator note recorded')));
    } catch (error) {
      if (!context.mounted || !scope.isCurrent) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_adminActionErrorMessage(error))));
    }
  }
}

int _detailInt(Object? value) {
  try {
    return exactJsonInteger(
      value,
      field: 'action count',
      minimum: 0,
      allowDigitString: true,
    );
  } on FormatException {
    return 0; // Unknown counts cannot enable a retry control.
  }
}

String _adminActionErrorMessage(Object error) {
  if (error is AdminSessionChanged) return error.toString();
  if (error is FormatException) {
    return 'The action was not acknowledged. Refresh the record before trying again.';
  }
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
