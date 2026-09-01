part of 'admin_runtime.dart';

enum CollectAdminOperation { payees, transactions, reconciliations, ledgers }

extension CollectAdminOperationSpec on CollectAdminOperation {
  String get title => switch (this) {
    CollectAdminOperation.payees => 'Payees',
    CollectAdminOperation.transactions => 'Transactions',
    CollectAdminOperation.reconciliations => 'Reconciliations',
    CollectAdminOperation.ledgers => 'Ledgers',
  };

  String get subtitle => switch (this) {
    CollectAdminOperation.payees =>
      'Who can receive group contributions and where each payment is sent.',
    CollectAdminOperation.transactions =>
      'Every received payment message, its parsed details, and linked payee.',
    CollectAdminOperation.reconciliations =>
      'Only exceptions and payments that still need a payee allocation.',
    CollectAdminOperation.ledgers =>
      'Balanced debit and credit entries for every allocated transaction.',
  };

  String get rpcName => switch (this) {
    CollectAdminOperation.payees => 'admin_list_collect_payees',
    CollectAdminOperation.transactions => 'admin_list_collect_transactions',
    CollectAdminOperation.reconciliations =>
      'admin_list_collect_reconciliations',
    CollectAdminOperation.ledgers => 'admin_list_collect_ledgers',
  };

  String? get detailPath => switch (this) {
    CollectAdminOperation.transactions => '/admin/transactions',
    _ => null,
  };

  String? get actionKind => switch (this) {
    CollectAdminOperation.payees => 'collect_payee_manage',
    CollectAdminOperation.reconciliations => 'collect_allocate',
    _ => null,
  };

  String get valueLabel => switch (this) {
    CollectAdminOperation.payees => 'Payment route',
    CollectAdminOperation.transactions ||
    CollectAdminOperation.reconciliations => 'Amount',
    CollectAdminOperation.ledgers => 'Debit = credit',
  };
}

class AdminCollectOperationsPage extends StatelessWidget {
  const AdminCollectOperationsPage({required this.operation, super.key});

  final CollectAdminOperation operation;

  @override
  Widget build(BuildContext context) => AdminRpcListPage(
    title: operation.title,
    rpcName: operation.rpcName,
    detailPathPrefix: operation.detailPath,
    actionKind: operation.actionKind,
    subtitleOverride: operation.subtitle,
    valueLabelOverride: operation.valueLabel,
    minimal: true,
  );
}

class AdminRpcListPage extends ConsumerStatefulWidget {
  const AdminRpcListPage({
    required this.title,
    required this.rpcName,
    this.detailPathPrefix,
    this.actionKind,
    this.subtitleOverride,
    this.valueLabelOverride,
    this.minimal = false,
    super.key,
  });

  final String title;
  final String rpcName;
  final String? detailPathPrefix;
  final String? actionKind;
  final String? subtitleOverride;
  final String? valueLabelOverride;
  final bool minimal;

  @override
  ConsumerState<AdminRpcListPage> createState() => _AdminRpcListPageState();
}

class _AdminRpcListPageState extends ConsumerState<AdminRpcListPage> {
  static const _pageSize = 25;

  final _search = TextEditingController();
  var _status = '';
  var _sortBy = 'created_at_desc';
  var _page = 0;
  late Future<AdminListResult> _future;
  late Future<AdminQueueSla?> _slaFuture;
  var _lastRealtimeTick = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _slaFuture = _loadSla();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final realtimeTick = ref.watch(adminRealtimeTickProvider);
    if (_lastRealtimeTick != realtimeTick) {
      _lastRealtimeTick = realtimeTick;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
    final runtimeConfig = ref.watch(adminRuntimeConfigProvider).valueOrNull;
    final spec = _AdminListSpec.forRpc(
      widget.rpcName,
      runtimeConfig: runtimeConfig,
    );
    final usesOperationsTable =
        widget.rpcName == 'admin_list_collect_transactions' ||
        widget.rpcName == 'admin_list_collections' ||
        widget.rpcName == 'admin_list_members' ||
        widget.rpcName == 'admin_list_non_member_users';
    return AdminPage(
      title: widget.title,
      subtitle: widget.subtitleOverride ?? spec.subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.rpcName == 'admin_list_collect_payees') ...[
            _AdminPayeeWorkspaceActions(
              onDone: () => _refresh(resetPage: true),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.rpcName == 'admin_list_collections') ...[
            _AdminGroupWorkspaceActions(
              onDone: () => _refresh(resetPage: true),
            ),
            const SizedBox(height: 16),
          ],
          if (!widget.minimal)
            _AdminBankQueueActions(
              rpcName: widget.rpcName,
              onDone: () => _refresh(resetPage: true),
            ),
          AdminFilterBar(
            searchController: _search,
            status: _status,
            sortBy: _sortBy,
            statusOptions: spec.statusOptions,
            sortOptions: spec.sortOptions,
            onStatusChanged: (value) => setState(() {
              _status = value;
              _page = 0;
              _future = _load();
            }),
            onSortChanged: (value) => setState(() {
              _sortBy = value;
              _page = 0;
              _future = _load();
            }),
            onRefresh: () => _refresh(resetPage: true),
          ),
          const SizedBox(height: 16),
          if (!widget.minimal && !usesOperationsTable) ...[
            _AdminQueueSummary(spec: spec),
            const SizedBox(height: 16),
          ],
          FutureBuilder<AdminListResult>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return AdminLoadingState(
                  title: 'Loading ${widget.title.toLowerCase()}',
                  message: 'Fetching the latest rows and filters.',
                );
              }
              if (snapshot.hasError) {
                return AdminSafeErrorPanel(error: snapshot.error!);
              }
              final result = snapshot.data;
              final rows = result?.rows ?? const [];
              if (rows.isEmpty) {
                return AdminEmptyState(
                  title: 'No ${widget.title.toLowerCase()}',
                  message: 'Try another filter or refresh this queue.',
                );
              }
              final total = result?.total ?? rows.length;
              final maxPage = total == 0
                  ? 0
                  : ((total - 1) / _pageSize).floor();
              final page = _page.clamp(0, maxPage);
              final start = page * _pageSize;
              final end = (start + rows.length).clamp(0, total);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.rpcName == 'admin_list_collect_transactions')
                    _AdminTransactionWorkspace(
                      rows: rows,
                      onOpen: widget.detailPathPrefix == null ? null : _openRow,
                    )
                  else if (widget.rpcName == 'admin_list_collections')
                    _AdminGroupsWorkspace(
                      rows: rows,
                      onOpen: widget.detailPathPrefix == null ? null : _openRow,
                    )
                  else if (widget.rpcName == 'admin_list_members' ||
                      widget.rpcName == 'admin_list_non_member_users')
                    _AdminMembersWorkspace(
                      rows: rows,
                      onOpen: widget.detailPathPrefix == null ? null : _openRow,
                      scopeLabel:
                          widget.rpcName == 'admin_list_non_member_users'
                          ? 'Users'
                          : 'Members',
                    )
                  else
                    AdminDataTable(
                      rows: rows,
                      onOpen: widget.detailPathPrefix == null ? null : _openRow,
                      valueLabel:
                          widget.valueLabelOverride ??
                          _adminQueueValueLabel(widget.rpcName),
                      trailingBuilder: widget.actionKind == null
                          ? null
                          : (row) => _AdminRowActions(
                              row: row,
                              actionKind: widget.actionKind!,
                              onDone: () => _refresh(),
                            ),
                    ),
                  if (!widget.minimal) ...[
                    const SizedBox(height: 12),
                    _AdminQueueExportBar(spec: spec, rows: rows),
                  ],
                  const SizedBox(height: 12),
                  _AdminPaginationBar(
                    start: start + 1,
                    end: end,
                    total: total,
                    canGoBack: page > 0,
                    canGoNext: page < maxPage,
                    onPrevious: () => setState(() {
                      _page = page - 1;
                      _future = _load();
                    }),
                    onNext: () => setState(() {
                      _page = page + 1;
                      _future = _load();
                    }),
                  ),
                  if (!widget.minimal) ...[
                    const SizedBox(height: 16),
                    _AdminWorkflowSteps(spec: spec),
                    const SizedBox(height: 16),
                    _AdminSlaPanel(spec: spec, future: _slaFuture),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<AdminListResult> _load() {
    return ref
        .read(adminRepositoryProvider)
        .list(
          widget.rpcName,
          search: _search.text,
          status: _status,
          limit: _pageSize,
          offset: _page * _pageSize,
          sortBy: _sortBy,
        );
  }

  Future<AdminQueueSla?> _loadSla() {
    return ref.read(adminRepositoryProvider).queueSla(widget.rpcName);
  }

  void _refresh({bool resetPage = false}) {
    setState(() {
      if (resetPage) _page = 0;
      _future = _load();
      _slaFuture = _loadSla();
    });
  }

  void _openRow(AdminTableRowData row) {
    final prefix = widget.detailPathPrefix;
    if (prefix == null) return;
    context.go('$prefix/${Uri.encodeComponent(row.id)}');
  }
}

String _adminQueueValueLabel(String rpcName) => switch (rpcName) {
  'admin_list_collections' => 'Members',
  'admin_list_notifications' => 'Deliveries',
  'admin_list_admin_users' => 'Roles',
  'admin_list_bank_destinations' ||
  'admin_list_bank_destination_change_requests' ||
  'admin_list_reconciliation_runs' ||
  'admin_list_reconciliation_exceptions' => 'Detail',
  'admin_list_users' ||
  'admin_list_members' ||
  'admin_list_non_member_users' ||
  'admin_list_audit_logs' ||
  'admin_list_settings' ||
  'admin_list_feature_flags' => 'Detail',
  _ => 'Amount',
};

class _AdminQueueExportBar extends StatelessWidget {
  const _AdminQueueExportBar({required this.spec, required this.rows});

  final _AdminListSpec spec;
  final List<AdminTableRowData> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceReadable.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderAccent),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${spec.title} export: current page CSV',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Export ${spec.title} current page CSV',
              hint: 'Copies the currently loaded admin queue rows as CSV.',
              child: OutlinedButton.icon(
                onPressed: rows.isEmpty
                    ? null
                    : () => _copyQueueCsv(context, spec.title, rows),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export CSV'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyQueueCsv(
    BuildContext context,
    String title,
    List<AdminTableRowData> rows,
  ) async {
    await Clipboard.setData(ClipboardData(text: _adminRowsToCsv(rows)));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$title CSV copied for export')));
  }
}

class _AdminPaginationBar extends StatelessWidget {
  const _AdminPaginationBar({
    required this.start,
    required this.end,
    required this.total,
    required this.canGoBack,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  final int start;
  final int end;
  final int total;
  final bool canGoBack;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceReadable.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderAccent),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Showing $start-$end of $total',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Previous admin results page',
              hint: canGoBack
                  ? 'Shows the previous page of admin queue results.'
                  : 'Unavailable on the first page.',
              enabled: canGoBack,
              child: IconButton.outlined(
                tooltip: 'Previous page',
                onPressed: canGoBack ? onPrevious : null,
                icon: const Icon(Icons.chevron_left),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: 'Next admin results page',
              hint: canGoNext
                  ? 'Shows the next page of admin queue results.'
                  : 'Unavailable on the last page.',
              enabled: canGoNext,
              child: IconButton.outlined(
                tooltip: 'Next page',
                onPressed: canGoNext ? onNext : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminRowActions extends ConsumerWidget {
  const _AdminRowActions({
    required this.row,
    required this.actionKind,
    required this.onDone,
  });

  final AdminTableRowData row;
  final String actionKind;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    final List<Widget> actions = switch (actionKind) {
      'payment_event_reparse'
          when _adminHasPermission(identity, 'payment_events.reparse') =>
        [
          IconButton.filledTonal(
            tooltip: 'Reparse ${row.title}',
            onPressed: () => _reparse(context, ref),
            icon: const Icon(Icons.refresh_outlined, size: 18),
          ),
        ],
      'feature_flag_toggle'
          when _adminHasPermission(identity, 'feature_flags.manage') =>
        [
          IconButton.filledTonal(
            tooltip:
                '${row.status == 'enabled' ? 'Disable' : 'Enable'} feature flag ${row.title}',
            onPressed: () =>
                _setFeatureFlag(context, ref, enabled: row.status != 'enabled'),
            icon: Icon(
              row.status == 'enabled'
                  ? Icons.toggle_off_outlined
                  : Icons.toggle_on_outlined,
              size: 18,
            ),
          ),
        ],
      'collect_allocate'
          when (_adminHasPermission(identity, 'payments.allocate') ||
                  _adminHasPermission(identity, 'bank_allocations.propose')) &&
              (row.extra['can_allocate'] == true ||
                  '${row.extra['event_id'] ?? ''}'.isNotEmpty ||
                  '${row.extra['transaction_id'] ?? ''}'.isNotEmpty) =>
        [
          IconButton.filledTonal(
            tooltip: 'Allocate ${row.title}',
            onPressed: () => _allocate(context, ref),
            icon: const Icon(Icons.account_tree_outlined, size: 18),
          ),
        ],
      'collect_payee_manage'
          when _adminHasPermission(identity, 'receivers.manage') =>
        [
          IconButton.outlined(
            tooltip: 'Edit ${row.title}',
            onPressed: () =>
                editAdminPayee(context, ref, row: row, onDone: onDone),
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
          IconButton.outlined(
            tooltip:
                '${row.status == 'active' ? 'Deactivate' : 'Activate'} ${row.title}',
            style: IconButton.styleFrom(
              foregroundColor: row.status == 'active'
                  ? context.collectColors.dangerForeground
                  : context.collectColors.successForeground,
              side: BorderSide(
                color: row.status == 'active'
                    ? context.collectColors.dangerForeground
                    : context.collectColors.successForeground,
              ),
            ),
            onPressed: () => setAdminPayeeActive(
              context,
              ref,
              row: row,
              active: row.status != 'active',
              onDone: onDone,
            ),
            icon: Icon(
              row.status == 'active'
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
              size: 18,
            ),
          ),
        ],
      _ => const [],
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          actions[index],
        ],
      ],
    );
  }

  Future<void> _reparse(BuildContext context, WidgetRef ref) async {
    final reason = await showAdminReasonDialog(
      context,
      title: 'Request MoMo SMS reparse',
      actionLabel: 'Request reparse',
    );
    if (reason == null) return;
    await ref.read(adminRepositoryProvider).action(
      'admin_reparse_payment_event',
      {'p_event_id': row.id, 'p_reason': reason},
    );
    onDone();
  }

  Future<void> _setFeatureFlag(
    BuildContext context,
    WidgetRef ref, {
    required bool enabled,
  }) async {
    final reason = await showAdminReasonDialog(
      context,
      title: enabled ? 'Enable feature flag' : 'Disable feature flag',
      actionLabel: enabled ? 'Enable flag' : 'Disable flag',
    );
    if (reason == null) return;
    await ref.read(adminRepositoryProvider).action('admin_set_feature_flag', {
      'p_key': row.title,
      'p_enabled': enabled,
      'p_reason': reason,
    });
    onDone();
  }

  Future<void> _allocate(BuildContext context, WidgetRef ref) async {
    final isRwanda = row.extra['rail'] == 'rw_momo';
    final targetId = TextEditingController(
      text:
          '${row.extra[isRwanda ? 'collection_id' : 'payment_intent_id'] ?? ''}',
    );
    final reason = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      builder: (dialogContext) => AlertDialog(
        title: Text(isRwanda ? 'Allocate transaction' : 'Propose allocation'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: targetId,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: isRwanda
                      ? 'Group UUID'
                      : 'Group contribution intent UUID',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Allocation reason',
                  helperText: 'Required for the audit trail.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(isRwanda ? 'Allocate' : 'Submit for approval'),
          ),
        ],
      ),
    );
    if (submitted != true) {
      targetId.dispose();
      reason.dispose();
      return;
    }
    try {
      if (isRwanda) {
        await ref
            .read(adminRepositoryProvider)
            .action('admin_manual_allocate_payment', {
              'p_event_id': row.extra['event_id'],
              'p_collection_id': targetId.text.trim(),
              'p_payment_intent_id': row.extra['payment_intent_id'],
              'p_reason': reason.text.trim(),
            });
      } else {
        await ref
            .read(adminRepositoryProvider)
            .action('admin_propose_bank_allocation', {
              'p_bank_transaction_id': row.extra['transaction_id'],
              'p_bank_transfer_intent_id': targetId.text.trim(),
              'p_reason': reason.text.trim(),
            });
      }
      onDone();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRwanda
                ? 'Transaction allocated'
                : 'Allocation submitted for independent approval',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Allocation could not be completed. Review the inputs.',
          ),
        ),
      );
    } finally {
      targetId.dispose();
      reason.dispose();
    }
  }
}
