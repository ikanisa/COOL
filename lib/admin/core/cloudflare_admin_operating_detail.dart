part of 'cloudflare_admin_operating_pages.dart';

class CloudflareOperatingDetailPage extends ConsumerStatefulWidget {
  const CloudflareOperatingDetailPage({
    required this.type,
    required this.id,
    required this.backPath,
    super.key,
  });
  final String type, id, backPath;
  @override
  ConsumerState<CloudflareOperatingDetailPage> createState() =>
      _DetailPageState();
}

class _DetailPageState extends ConsumerState<CloudflareOperatingDetailPage> {
  late Future<CloudflareOperatingDetail> _future;
  bool _paging = false;
  bool _hasLiveChanges = false;
  String? _pageError;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CloudflareOperatingDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.type != oldWidget.type || widget.id != oldWidget.id) _load();
  }

  void _load() {
    _future = _repository(ref).operatingDetail(widget.type, widget.id);
  }

  void _refresh() => setState(() {
    _hasLiveChanges = false;
    _load();
  });
  Future<void> _relatedPage(
    CloudflareOperatingDetail current,
    String relation,
    int offset,
  ) async {
    if (_paging) return;
    setState(() {
      _paging = true;
      _pageError = null;
    });
    try {
      final page = current.relatedPages[relation]!;
      final fetched = await _repository(ref).operatingDetail(
        widget.type,
        widget.id,
        relation: relation,
        limit: page.limit,
        offset: offset,
      );
      if (!mounted) return;
      // A changed resource needs fresh complete detail before any financial action.
      if (fetched.version != current.version) {
        setState(_load);
        return;
      }
      final merged = CloudflareOperatingDetail(
        type: fetched.type,
        resource: fetched.resource,
        actorId: fetched.actorId,
        canManage: fetched.canManage,
        sourceModel: fetched.sourceModel,
        allowedOperations: fetched.allowedOperations,
        related: {...current.related, ...fetched.related},
        relatedPages: {...current.relatedPages, ...fetched.relatedPages},
        truncated: false,
      );
      setState(() => _future = Future.value(merged));
    } catch (failure) {
      if (mounted) setState(() => _pageError = _safeOperatingError(failure));
    } finally {
      if (mounted) setState(() => _paging = false);
    }
  }

  Widget _relatedPager(CloudflareOperatingDetail detail, String relation) {
    final page = detail.relatedPages[relation];
    if (page == null) return const SizedBox.shrink();
    final rows = detail.related[relation]?.length ?? 0;
    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          page.total == 0
              ? '0 records'
              : '${rows == 0 ? 0 : page.offset + 1}–${page.offset + rows} of ${page.total}',
        ),
        TextButton(
          onPressed: _paging || page.offset == 0
              ? null
              : () => _relatedPage(
                  detail,
                  relation,
                  (page.offset - page.limit).clamp(0, page.total),
                ),
          child: const Text('Previous'),
        ),
        TextButton(
          onPressed: _paging || page.nextOffset == null
              ? null
              : () => _relatedPage(detail, relation, page.nextOffset!),
          child: const Text('Next'),
        ),
      ],
    );
  }

  bool _can(String permission) {
    final user = ref.read(cloudflareAdminSessionProvider).asData?.value;
    return user != null &&
        user.role != AdminAccountRole.staff &&
        user.permissions.contains(permission);
  }

  Future<void> _action(
    CloudflareOperation operation,
    CloudflareOperatingDetail detail, {
    Map<String, dynamic> initial = const {},
    Map<String, dynamic> fixed = const {},
    String? targetId,
  }) async {
    if (!_can(operation.permission) || !detail.allows(operation)) return;
    if (operation.update && operation != CloudflareOperation.updateMembership) {
      final base = detail.type == 'accounts'
          ? '/admin/ledger-accounts'
          : detail.type == 'journals'
          ? '/admin/ledgers'
          : '/admin/${detail.type}';
      await context.push('$base/${detail.id}/edit');
      if (mounted) _refresh();
      return;
    }
    await showDialog<void>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _actionTitle(operation),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close action',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  detail.usesCanonicalEvidence
                      ? _canonicalActionExplanation(operation)
                      : _actionExplanation(operation),
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    child: CloudflareOperatingForm(
                      operation: operation,
                      detail: detail,
                      initial: initial,
                      fixed: fixed,
                      targetId: targetId,
                      onSaved: () {
                        if (mounted) _refresh();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(adminRealtimeTickProvider, (_, _) {
      setState(() => _hasLiveChanges = true);
    });
    return FutureBuilder<CloudflareOperatingDetail>(
      future: _future,
      builder: (context, snapshot) {
        final detail = snapshot.data;
        final loading = snapshot.connectionState != ConnectionState.done;
        return AdminPage(
          title: detail == null || loading
              ? 'Record details'
              : _recordTitle(detail),
          subtitle: detail == null || loading
              ? null
              : detail.usesCanonicalEvidence && detail.type == 'ledgers'
              ? 'Evidence ledger entry · Read-only'
              : detail.version == null
              ? 'Team access record · Managed in Admins and staff'
              : 'Version ${detail.version}',
          leading: IconButton(
            tooltip: 'Back to records',
            onPressed: () => context.go(widget.backPath),
            icon: const Icon(Icons.arrow_back),
          ),
          trailing: IconButton(
            tooltip: 'Refresh record',
            onPressed: loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          child: loading
              ? const AdminLoadingState(title: 'Loading record')
              : snapshot.hasError
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OperatingMessage(
                      _safeOperatingError(snapshot.error!),
                      error: true,
                    ),
                    FilledButton.tonal(
                      onPressed: _refresh,
                      child: const Text('Refresh record'),
                    ),
                  ],
                )
              : detail == null
              ? const AdminEmptyState(
                  title: 'Record unavailable',
                  message: 'Return to the list and refresh.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_hasLiveChanges)
                      const _OperatingMessage(
                        'New changes are available. Refresh this record before starting another action. Your current form is unchanged.',
                      ),
                    _RecordFacts(
                      detail.resource,
                      _fieldsForResource(detail.type),
                    ),
                    const SizedBox(height: 20),
                    _OperatingPendingRequests(
                      key: ValueKey('${detail.type}:${detail.id}'),
                      type: detail.type,
                      id: detail.id,
                    ),
                    _actions(detail),
                    const SizedBox(height: 24),
                    if (detail.usesCanonicalEvidence &&
                        {'groups', 'users'}.contains(detail.type)) ...[
                      CloudflareOperatorNotes(
                        key: ValueKey('notes:${detail.type}:${detail.id}'),
                        type: detail.type,
                        id: detail.id,
                      ),
                      const SizedBox(height: 24),
                    ],
                    for (final entry in detail.related.entries) ...[
                      _relatedSection(detail, entry.key, entry.value),
                      _relatedPager(detail, entry.key),
                      const SizedBox(height: 24),
                    ],
                    if (_pageError != null)
                      _OperatingMessage(_pageError!, error: true),
                  ],
                ),
        );
      },
    );
  }

  Widget _actions(CloudflareOperatingDetail detail) {
    if (!detail.canManage) {
      if (detail.type == 'transactions' &&
          ref
                  .read(cloudflareAdminSessionProvider)
                  .asData
                  ?.value
                  ?.permissions
                  .contains('reconciliations.read') ==
              true) {
        return Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => context.go('/admin/reconciliations/${detail.id}'),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Reconcile with a member'),
          ),
        );
      }
      return const SizedBox.shrink();
    }
    final buttons = <Widget>[];
    void add(
      CloudflareOperation operation, {
      Map<String, dynamic> fixed = const {},
      Map<String, dynamic> initial = const {},
    }) {
      if (_can(operation.permission) && detail.allows(operation)) {
        buttons.add(
          OutlinedButton.icon(
            onPressed: () =>
                _action(operation, detail, fixed: fixed, initial: initial),
            icon: Icon(
              operation == CloudflareOperation.postJournal
                  ? Icons.lock_outline
                  : Icons.edit_outlined,
            ),
            label: Text(_actionTitle(operation)),
          ),
        );
      }
    }

    switch (detail.type) {
      case 'groups':
        if (detail.resource['status'] == 'archived') {
          return const Text(
            'This archived group cannot be changed or reopened.',
          );
        }
        add(CloudflareOperation.updateGroup);
        add(
          CloudflareOperation.createMembership,
          fixed: {'group_id': detail.id},
          initial: {'group_id_label': _recordTitle(detail)},
        );
        add(
          CloudflareOperation.createPayee,
          fixed: {'group_id': detail.id},
          initial: {'group_id_label': _recordTitle(detail)},
        );
        add(
          CloudflareOperation.createAccount,
          fixed: {'group_id': detail.id},
          initial: {'group_id_label': _recordTitle(detail)},
        );
        if (detail.resource['status'] == 'active') {
          add(
            CloudflareOperation.createTransaction,
            fixed: {'group_id': detail.id},
            initial: {'group_id_label': _recordTitle(detail)},
          );
          add(
            CloudflareOperation.createJournal,
            fixed: {'group_id': detail.id},
            initial: {'group_id_label': _recordTitle(detail)},
          );
        }
      case 'users':
        if (detail.resource['status'] == 'closed') {
          return const Text(
            'This closed app account cannot be changed or reopened.',
          );
        }
        add(CloudflareOperation.updateUser);
        add(
          CloudflareOperation.createMembership,
          fixed: {'user_id': detail.id},
          initial: {'user_id_label': _recordTitle(detail)},
        );
      case 'payees':
        add(CloudflareOperation.updatePayee);
      case 'accounts':
        add(CloudflareOperation.updateAccount);
      case 'transactions':
        if (detail.usesCanonicalEvidence) {
          add(CloudflareOperation.reverseTransaction);
        }
        add(CloudflareOperation.addEvidence);
        final evidence = detail.related['evidence'] ?? [];
        if (evidence.any(
              (row) => row['recorded_by_admin_id'] != detail.actorId,
            ) &&
            (detail.related['journals'] ?? []).every(
              (row) => row['status'] != 'posted',
            )) {
          add(CloudflareOperation.verifyTransaction);
        }
        final user = ref.read(cloudflareAdminSessionProvider).asData?.value;
        if (user?.permissions.contains('reconciliations.read') == true) {
          buttons.add(
            OutlinedButton.icon(
              onPressed: () =>
                  context.go('/admin/reconciliations/${detail.id}'),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Reconcile with a member'),
            ),
          );
        }
      case 'journals':
        if (detail.resource['status'] == 'draft') {
          add(CloudflareOperation.updateJournal);
          if (detail.resource['created_by_admin_id'] != detail.actorId &&
              detail.resource['edited_by_admin_id'] != detail.actorId) {
            add(CloudflareOperation.postJournal);
          } else if (_can('ledger.manage')) {
            buttons.add(
              const Text('A different administrator must post this draft.'),
            );
          }
        }
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: buttons,
    );
  }

  Widget _relatedSection(
    CloudflareOperatingDetail detail,
    String name,
    List<Map<String, dynamic>> rows,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(operatingLabel(name), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      if (rows.isEmpty)
        Text('No ${name.replaceAll('_', ' ')} recorded.')
      else
        AdminDataTable(
          tableLabel: operatingLabel(name),
          rows: [
            for (final row in rows)
              AdminTableRowData(
                id: '${row['id'] ?? '${row['group_id']}:${row['user_id']}'}',
                title: '${row['display_name'] ?? row['id'] ?? name}',
                subtitle: '',
                status: '',
                amount: '',
                extra: row,
              ),
          ],
          columns: [
            for (final field in _relatedFields(
              name,
              canonical: detail.usesCanonicalEvidence,
            ))
              if (rows.any((row) => row.containsKey(field)))
                _operatingColumn(field),
          ],
          trailingBuilder: (tableRow) {
            final row = tableRow.extra;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (detail.canManage &&
                    name == 'memberships' &&
                    detail.allows(CloudflareOperation.updateMembership) &&
                    (!detail.usesCanonicalEvidence || row['role'] != 'owner') &&
                    !{
                      'archived',
                      'closed',
                    }.contains(detail.resource['status']) &&
                    _can('users.manage'))
                  TextButton(
                    onPressed: () => _action(
                      CloudflareOperation.updateMembership,
                      detail,
                      initial: row,
                      targetId: '${row['group_id']}/${row['user_id']}',
                    ),
                    child: const Text('Edit membership'),
                  ),
                if ({'payees', 'accounts', 'journals'}.contains(name))
                  TextButton(
                    onPressed: () => context.go(
                      '${name == 'payees'
                          ? '/admin/payees'
                          : name == 'accounts'
                          ? '/admin/ledger-accounts'
                          : '/admin/ledgers'}/${row['id']}',
                    ),
                    child: const Text('Open record'),
                  ),
                if (detail.canManage &&
                    name == 'allocations' &&
                    !detail.usesCanonicalEvidence &&
                    !(detail.related['journals'] ?? []).any(
                      (journal) => journal['allocation_id'] == row['id'],
                    ) &&
                    _can('ledger.manage'))
                  TextButton(
                    onPressed: () => _action(
                      CloudflareOperation.createJournal,
                      detail,
                      fixed: {
                        'group_id': detail.resource['group_id'],
                        'allocation_id': row['id'],
                      },
                      initial: {
                        'group_id_label':
                            detail.resource['group_title'] ??
                            detail.resource['group_id'],
                        'allocation_id_label': adminFormatWholeAmount(
                          row['amount_rwf'],
                        ),
                      },
                    ),
                    child: const Text('Create linked journal draft'),
                  ),
              ],
            );
          },
        ),
    ],
  );
}

typedef _PendingOperatingRequest = ({
  CloudflareOperation operation,
  AdminPendingAttemptCheckpoint checkpoint,
  String targetId,
});

/// A completed change can remove its action (posting, closing, archiving).
/// Keep receipt recovery available independently of that current eligibility.
/// This entry point only checks an original same-session request with GET.
class _OperatingPendingRequests extends ConsumerStatefulWidget {
  const _OperatingPendingRequests({
    required this.type,
    required this.id,
    super.key,
  });
  final String type, id;

  @override
  ConsumerState<_OperatingPendingRequests> createState() =>
      _OperatingPendingRequestsState();
}

class _OperatingPendingRequestsState
    extends ConsumerState<_OperatingPendingRequests> {
  List<_PendingOperatingRequest> _pending = [];
  final _resolved = <String, _PendingOperatingRequest>{};
  final _receipts = <String, CloudflareOperationReceipt>{};
  final _statuses = <String, String>{};
  Object? _authority;
  String? _checking, _message;
  bool _restoring = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    ref.listenManual(adminPendingAttemptStoreProvider, (_, _) {
      if (mounted && !_restoring) setState(_restore);
    });
    ref.listenManual(cloudflareAdminSessionProvider, (_, _) {
      if (mounted && !_restoring) setState(_restore);
    });
    _restore();
  }

  void _restore() {
    _restoring = true;
    try {
      final user = ref.read(cloudflareAdminSessionProvider).asData?.value;
      if (_authority != user?.authorityKey) {
        _epoch++;
        _checking = _message = null;
        _resolved.clear();
        _receipts.clear();
        _statuses.clear();
      }
      _authority = user?.authorityKey;
      _pending = [];
      if (user == null ||
          user.role == AdminAccountRole.staff ||
          !user.expiresAt.isAfter(DateTime.now())) {
        return;
      }
      final store = ref.read(adminPendingAttemptStoreProvider);
      for (final operation in CloudflareOperation.values) {
        if (!operation.needsVersion ||
            operation == CloudflareOperation.allocateTransaction ||
            !user.permissions.contains(operation.permission)) {
          continue;
        }
        if (operation == CloudflareOperation.updateMembership &&
            {'groups', 'users'}.contains(widget.type)) {
          for (final checkpoint in store.restoreFamily(
            family: 'operating-updatemembership',
            permission: operation.permission,
            schema: _operatingRecoverySchema(operation),
          )) {
            final ids = checkpoint.resourceId.split(':');
            final uuid = RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
              caseSensitive: false,
            );
            if (ids.length == 2 &&
                ids.every(uuid.hasMatch) &&
                ids[widget.type == 'groups' ? 0 : 1] == widget.id) {
              _pending.add((
                operation: operation,
                checkpoint: checkpoint,
                targetId: ids.join('/'),
              ));
            }
          }
          continue;
        }
        if (operation.resource != widget.type) continue;
        final checkpoint = store.restore(
          family: 'operating-${operation.name.toLowerCase()}',
          resourceId: widget.id,
          schema: _operatingRecoverySchema(operation),
        );
        if (checkpoint != null &&
            checkpoint.permission == operation.permission) {
          _pending.add((
            operation: operation,
            checkpoint: checkpoint,
            targetId: widget.id,
          ));
        }
      }
      if (_checking != null &&
          !_pending.any((entry) => entry.checkpoint.requestKey == _checking)) {
        _epoch++;
        _checking = _message = null;
      }
    } finally {
      _restoring = false;
    }
  }

  bool _current(
    Object? authority,
    int epoch,
    _PendingOperatingRequest attempt,
  ) {
    if (!mounted) return false;
    final user = ref.read(cloudflareAdminSessionProvider).asData?.value;
    if (user == null) return false;
    return mounted &&
        epoch == _epoch &&
        authority != null &&
        authority == user.authorityKey &&
        user.role != AdminAccountRole.staff &&
        user.expiresAt.isAfter(DateTime.now()) &&
        user.permissions.contains(attempt.operation.permission) &&
        attempt.checkpoint.expiresAt.isAfter(DateTime.now()) &&
        _pending.any(
          (entry) =>
              entry.checkpoint.requestKey == attempt.checkpoint.requestKey,
        );
  }

  Future<void> _check(_PendingOperatingRequest attempt) async {
    if (_checking != null ||
        !_pending.any(
          (entry) =>
              entry.checkpoint.requestKey == attempt.checkpoint.requestKey,
        )) {
      return;
    }
    final authority = _authority, epoch = ++_epoch;
    if (!_current(authority, epoch, attempt)) return;
    final key = attempt.checkpoint.requestKey;
    setState(() {
      _checking = key;
      _message = null;
    });
    try {
      final result = await _repository(ref).operatingRequest(key);
      if (!_current(authority, epoch, attempt)) return;
      if (result['status'] == 'succeeded') {
        final receipt = CloudflareOperationReceipt.parse(
          Map<String, dynamic>.from(result['receipt'] as Map),
        );
        final version = attempt.checkpoint.intent['expected_version'];
        if (version is! int ||
            version < 1 ||
            version > 9007199254740990 ||
            receipt.resourceType != attempt.operation.resource ||
            receipt.resourceId != attempt.targetId ||
            receipt.version != version + 1) {
          throw const FormatException('The original receipt does not match.');
        }
        ref
            .read(adminPendingAttemptStoreProvider)
            .clear(
              family: attempt.checkpoint.family,
              resourceId: attempt.checkpoint.resourceId,
            );
        setState(() {
          _resolved[key] = attempt;
          _receipts[key] = receipt;
          _statuses[key] = 'Saved';
          _checking = _message = null;
        });
      } else {
        setState(() {
          _statuses[key] = switch (result['status']) {
            'not_found' => 'Not found',
            'failed' => 'Failed',
            _ => 'Pending',
          };
          _message = switch (result['status']) {
            'not_found' =>
              'No completed request was found for the original reference. Check again before making another change.',
            'failed' =>
              'The server recorded a failed request. Keep the original reference and review the record before another change.',
            _ =>
              'The request is still pending. Check its original reference again before continuing.',
          };
        });
      }
    } catch (error) {
      if (_current(authority, epoch, attempt)) {
        setState(() => _message = _safeOperatingError(error));
      }
    } finally {
      if (_current(authority, epoch, attempt)) {
        setState(() => _checking = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(cloudflareAdminSessionProvider).asData?.value;
    if (_authority == null ||
        _authority != user?.authorityKey ||
        user == null ||
        !user.expiresAt.isAfter(DateTime.now()) ||
        (_pending.isEmpty && _resolved.isEmpty)) {
      return const SizedBox.shrink();
    }
    final attempts = [..._pending, ..._resolved.values];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Request recovery', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Check original requests retained by this session. This does not repeat a change or grant permission to edit this record.',
        ),
        const SizedBox(height: 12),
        AdminDataTable(
          tableLabel: 'Requests retained for this record',
          rows: [
            for (final attempt in attempts)
              AdminTableRowData(
                id: attempt.checkpoint.requestKey,
                title: attempt.checkpoint.requestKey,
                subtitle: '',
                status: '',
                amount: '',
                extra: {
                  'action': _actionTitle(attempt.operation),
                  'version': attempt.checkpoint.intent['expected_version'],
                  'created_at': attempt.checkpoint.createdAt.toIso8601String(),
                  'status': _checking == attempt.checkpoint.requestKey
                      ? 'Checking…'
                      : _statuses[attempt.checkpoint.requestKey] ??
                            'Unconfirmed',
                },
              ),
          ],
          columns: [
            AdminTableColumn(
              label: 'Action',
              value: (row) => '${row.extra['action']}',
            ),
            AdminTableColumn(
              label: 'Original request',
              selectable: true,
              value: (row) => row.id,
            ),
            AdminTableColumn(
              label: 'Submitted version',
              numeric: true,
              value: (row) => '${row.extra['version'] ?? '—'}',
            ),
            AdminTableColumn(
              label: 'Created',
              value: (row) => adminKigaliDateTime(
                DateTime.tryParse('${row.extra['created_at']}'),
              ),
              compare: operatingDateComparator('created_at'),
            ),
            AdminTableColumn(
              label: 'Status',
              value: (row) => '${row.extra['status']}',
            ),
          ],
          trailingBuilder: (row) {
            final attempt = _pending
                .where((entry) => entry.checkpoint.requestKey == row.id)
                .firstOrNull;
            return attempt == null
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: _checking != null ? null : () => _check(attempt),
                    child: const Text('Check request status'),
                  );
          },
        ),
        if (_message != null) _OperatingMessage(_message!, error: true),
        for (final receipt in _receipts.values) ...[
          const SizedBox(height: 16),
          CloudflareReceiptView(receipt: receipt),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _OperatingConfirmationTables extends StatelessWidget {
  const _OperatingConfirmationTables({
    required this.body,
    required this.accountLabel,
  });
  final Map<String, dynamic> body;
  final String Function(String?) accountLabel;

  @override
  Widget build(BuildContext context) {
    final facts = <String, dynamic>{
      for (final entry in body.entries)
        if (!{'entries', 'evidence', 'receiver'}.contains(entry.key))
          entry.key: entry.value,
      if (body['receiver'] is Map)
        for (final entry in (body['receiver'] as Map).entries)
          'receiver_${entry.key}': entry.value,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminDataTable(
          tableLabel: 'Change confirmation',
          rows: [
            AdminTableRowData(
              id: 'confirmation',
              title: '',
              subtitle: '',
              status: '',
              amount: '',
              extra: facts,
            ),
          ],
          columns: [for (final key in facts.keys) _operatingColumn(key)],
        ),
        if (body['evidence'] is Map) ...[
          const SizedBox(height: 16),
          AdminDataTable(
            tableLabel: 'Evidence confirmation',
            rows: [
              AdminTableRowData(
                id: 'evidence',
                title: '',
                subtitle: '',
                status: '',
                amount: '',
                extra: Map<String, dynamic>.from(body['evidence'] as Map),
              ),
            ],
            columns: [
              for (final key in ['kind', 'reference', 'sha256'])
                _operatingColumn(key),
            ],
          ),
        ],
        if (body['evidence'] is String) ...[
          const SizedBox(height: 16),
          AdminDataTable(
            tableLabel: 'Retained evidence confirmation',
            rows: [
              AdminTableRowData(
                id: 'retained-evidence',
                title: '',
                subtitle: '',
                status: '',
                amount: '',
                extra: {
                  'evidence_text': body['evidence'],
                  'sha256': sha256
                      .convert(utf8.encode(body['evidence'] as String))
                      .toString(),
                },
              ),
            ],
            columns: [
              for (final key in ['evidence_text', 'sha256'])
                _operatingColumn(key),
            ],
          ),
        ],
        if (body['entries'] is List) ...[
          const SizedBox(height: 16),
          const Text('Journal lines'),
          AdminDataTable(
            tableLabel: 'Journal confirmation',
            rows: [
              for (final (index, entry) in (body['entries'] as List).indexed)
                AdminTableRowData(
                  id: 'journal-$index',
                  title: '',
                  subtitle: '',
                  status: '',
                  amount: '',
                  extra: Map<String, dynamic>.from(entry as Map),
                ),
            ],
            columns: [
              AdminTableColumn(
                label: 'Account',
                value: (row) =>
                    accountLabel(row.extra['account_id'] as String?),
              ),
              for (final key in [
                'account_id',
                'debit_rwf',
                'credit_rwf',
                'description',
              ])
                _operatingColumn(key),
            ],
          ),
        ],
      ],
    );
  }
}
