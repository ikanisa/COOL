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
              const SizedBox(height: 16),
              _AdminTransactionDetailSupplement(
                transactionId: id,
                details: AdminTransactionDetails.parse(data),
                key: ValueKey((
                  'transaction-details',
                  id,
                  ref.watch(adminAuthSessionScopeProvider),
                  identityRevision,
                )),
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

final _adminUserGroupsProvider = FutureProvider.autoDispose
    .family<
      ({AdminUserGroupsPage page, int offset}),
      ({String userId, int offset})
    >((ref, key) async {
      ref.watch(adminAuthSessionScopeProvider);
      ref.watch(adminRealtimeTickProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (identity?.permissions.contains('users.read') != true) {
        throw const _AdminPrivateReadDenied();
      }
      var offset = key.offset;
      var page = await repository.userGroups(key.userId, offset: offset);
      if (!current) throw const AdminSessionChanged();
      // A removal can empty the last page. Recover once using the authoritative
      // count, so a stale page does not hide the user's remaining groups.
      if (offset > 0 && page.rows.isEmpty) {
        offset = page.total == 0 ? 0 : ((page.total - 1) ~/ 25) * 25;
        page = await repository.userGroups(key.userId, offset: offset);
        if (!current) throw const AdminSessionChanged();
      }
      return (page: page, offset: offset);
    });

class _AdminUserGroupsPanel extends ConsumerStatefulWidget {
  const _AdminUserGroupsPanel({required this.userId});
  final String userId;

  @override
  ConsumerState<_AdminUserGroupsPanel> createState() =>
      _AdminUserGroupsPanelState();
}

class _AdminUserGroupsPanelState extends ConsumerState<_AdminUserGroupsPanel> {
  int _offset = 0;
  AdminSessionScope? _session;

  @override
  void didUpdateWidget(covariant _AdminUserGroupsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _offset = 0;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminAuthSessionScopeProvider);
    if (_session != session) {
      _session = session;
      _offset = 0;
    }
    final key = (userId: widget.userId, offset: _offset);
    final result = ref.watch(_adminUserGroupsProvider(key));
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    if (result.isLoading) {
      return const AdminLoadingState(
        title: 'Loading user groups',
        message: 'Fetching roles and recorded contributions.',
      );
    }
    if (result.hasError) {
      return AdminSafeErrorPanel(
        error: result.error!,
        onRetry: () => ref.invalidate(_adminUserGroupsProvider(key)),
      );
    }
    if (identity == null) {
      return const AdminSafeErrorPanel(error: _AdminPrivateReadDenied());
    }
    final value = result.requireValue;
    final page = value.page;
    final offset = value.offset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Groups (${page.total})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (page.total == 0)
          const AdminEmptyState(title: 'No group relationships recorded')
        else ...[
          _AdminPremiumTable(
            minimumWidth: 1300,
            columns: const [
              DataColumn(
                label: _AdminColumnLabel(
                  icon: Icons.folder_outlined,
                  label: 'Group',
                ),
              ),
              DataColumn(
                label: _AdminColumnLabel(
                  icon: Icons.visibility_outlined,
                  label: 'Visibility',
                ),
              ),
              DataColumn(
                label: _AdminColumnLabel(
                  icon: Icons.toggle_on_outlined,
                  label: 'Status',
                ),
              ),
              DataColumn(
                label: _AdminColumnLabel(
                  icon: Icons.person_outline,
                  label: 'Roles',
                ),
              ),
              DataColumn(
                label: _AdminColumnLabel(
                  icon: Icons.group_outlined,
                  label: 'Membership states',
                ),
              ),
              DataColumn(
                numeric: true,
                label: _AdminColumnLabel(
                  icon: Icons.payments_outlined,
                  label: 'Contributed',
                ),
              ),
              DataColumn(
                label: _AdminColumnLabel(
                  icon: Icons.open_in_new_outlined,
                  label: 'Open',
                ),
              ),
            ],
            rows: [
              for (final group in page.rows)
                DataRow(
                  cells: [
                    DataCell(Text(group.title, softWrap: false)),
                    DataCell(
                      Text(
                        _adminUserGroupWords(group.visibility),
                        softWrap: false,
                      ),
                    ),
                    DataCell(
                      AdminStatusChip(
                        label: group.active ? 'active' : 'inactive',
                      ),
                    ),
                    DataCell(
                      Text(
                        group.roles.map(_adminUserGroupWords).join(', '),
                        softWrap: false,
                      ),
                    ),
                    DataCell(
                      Text(
                        group.membershipStatuses.isEmpty
                            ? 'No membership record'
                            : group.membershipStatuses
                                  .map(_adminUserGroupWords)
                                  .join(', '),
                        softWrap: false,
                      ),
                    ),
                    DataCell(
                      Text(
                        group.contributionStatus == 'available'
                            ? adminFormatRwfAmount(
                                'RWF ${group.contributedAmountRwf!}',
                              )
                            : 'Unavailable',
                        softWrap: false,
                      ),
                    ),
                    DataCell(
                      IconButton.filledTonal(
                        tooltip: 'Open ${group.title}',
                        onPressed:
                            _adminHasPermission(identity, 'collections.read')
                            ? () => context.go(
                                '/admin/groups/${group.collectionId}',
                              )
                            : null,
                        icon: const Icon(Icons.arrow_outward, size: 18),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${offset + 1}–${offset + page.rows.length} of ${page.total} groups',
              ),
              IconButton.outlined(
                key: const ValueKey('user-groups-previous'),
                tooltip: 'Previous user groups',
                onPressed: offset == 0
                    ? null
                    : () => setState(
                        () => _offset = (offset - 25).clamp(0, offset),
                      ),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton.outlined(
                key: const ValueKey('user-groups-next'),
                tooltip: 'Next user groups',
                onPressed: offset + page.rows.length >= page.total
                    ? null
                    : () => setState(() => _offset = offset + 25),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String _adminUserGroupWords(String value) => value
    .split('_')
    .map((word) => '${word.substring(0, 1).toUpperCase()}${word.substring(1)}')
    .join(' ');

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
    final detailData = rpcName == 'admin_get_member_record'
        ? {
            ...data,
            'contributed_amount_rwf': data['contribution_status'] == 'available'
                ? adminFormatRwfAmount('RWF ${data['contributed_amount_rwf']}')
                : 'Unavailable',
          }
        : data;
    final fields = _adminDetailFields(spec, detailData)
        .where((field) {
          if (rpcName == 'admin_get_member_record' &&
              field.label == 'WhatsApp' &&
              data['member_type'] != 'App') {
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
    final heading = rpcName == 'admin_get_user'
        ? 'User'
        : _adminDetailHeading(rpcName, title, spec.heading, data);
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    final colors = context.collectColors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '$heading detail panel',
      hint: spec.subtitle,
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
            ],
          ),
          if (spec.subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              spec.subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: 16),
          AdminRecordFactsTable(
            key: const ValueKey('record-detail-facts'),
            semanticLabel: '$heading facts',
            fields: [
              for (final field in fields) (field.label, field.value),
              if (_detailValue(data, const ['status']).isNotEmpty &&
                  fields.every((field) => field.label != 'Status'))
                (
                  'Status',
                  _humanizeDetailValue(_detailValue(data, const ['status'])),
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
          if (rpcName == 'admin_get_user') ...[
            const SizedBox(height: 18),
            _AdminUserGroupsPanel(userId: id),
          ],
          if (rpcName == 'admin_get_user' &&
              _adminHasPermission(identity, 'admin_users.manage') &&
              (data['user_type'] == 'Staff' ||
                  data['user_type'] == 'Admin' &&
                      data['status'] == 'registered')) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.go('/admin/staff/$id'),
              icon: const Icon(Icons.supervisor_account_outlined),
              label: const Text('Review Staff access'),
            ),
          ],
          if (rpcName == 'admin_get_admin_user' &&
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
                    onPressed: () =>
                        _recordOperatorNote(context, ref, spec.noteEntityType!),
                    icon: const Icon(Icons.note_add_outlined),
                  ),
                ),
              ),
            ),
          ],
          if (rpcName == 'admin_get_collection' &&
              data['admin_operator_draft'] == true) ...[
            const SizedBox(height: 12),
            AdminOperatorDraftOwnerPanel(
              collectionId: id,
              markedDraft: true,
              key: ValueKey(('operator-draft-owner', id)),
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
              data['admin_operator_draft'] == false &&
              data['visibility'] == 'private' &&
              data['public_status'] == 'private' &&
              data['archived_at'] == null &&
              data['currency'] == 'RWF') ...[
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

/// Read-only record facts remain a two-column listing at every viewport.
class AdminRecordFactsTable extends StatelessWidget {
  const AdminRecordFactsTable({
    required this.fields,
    this.semanticLabel = 'Record facts',
    super.key,
  });

  final List<(String, String)> fields;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: semanticLabel,
    child: _AdminPremiumTable(
      minimumWidth: 720,
      columns: const [
        DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.list_alt_outlined,
            label: 'Field',
          ),
        ),
        DataColumn(
          label: _AdminColumnLabel(
            icon: Icons.description_outlined,
            label: 'Value',
          ),
        ),
      ],
      rows: [
        for (final (label, value) in fields)
          DataRow(
            cells: [
              DataCell(
                Tooltip(message: label, child: Text(label, softWrap: false)),
              ),
              DataCell(
                Semantics(
                  readOnly: true,
                  child: SelectionArea(
                    child: Text(value.isEmpty ? '—' : value, softWrap: false),
                  ),
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

bool _adminHasPermission(AdminIdentity? identity, String permission) {
  return identity?.permissions.contains(permission) == true;
}

bool _adminCanRecordNote(AdminIdentity? identity, String entityType) {
  if (identity == null ||
      !identity.roles.any(
        (role) => role == 'admin' || role == 'platform_owner',
      )) {
    return false;
  }
  return switch (entityType) {
    'collection' => _adminHasPermission(identity, 'collections.read'),
    'profile' => _adminHasPermission(identity, 'users.read'),
    _ => false,
  };
}
