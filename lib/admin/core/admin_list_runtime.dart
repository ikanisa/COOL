part of 'admin_runtime.dart';

class AdminRpcListPage extends ConsumerStatefulWidget {
  const AdminRpcListPage({
    required this.title,
    required this.rpcName,
    this.detailPathPrefix,
    this.actionKind,
    super.key,
  });

  final String title;
  final String rpcName;
  final String? detailPathPrefix;
  final String? actionKind;

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

  _AdminListSpec get _spec => _AdminListSpec.forRpc(widget.rpcName);

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
    return AdminPage(
      title: widget.title,
      subtitle: _spec.subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminFilterBar(
            searchController: _search,
            status: _status,
            sortBy: _sortBy,
            statusOptions: _spec.statusOptions,
            sortOptions: _spec.sortOptions,
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
          _AdminQueueSummary(spec: _spec),
          const SizedBox(height: 16),
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
                  AdminDataTable(
                    rows: rows,
                    onOpen: _openRow,
                    trailingBuilder: widget.actionKind == null
                        ? null
                        : (row) => _AdminRowActions(
                            row: row,
                            actionKind: widget.actionKind!,
                            onDone: () => _refresh(),
                          ),
                  ),
                  const SizedBox(height: 12),
                  _AdminQueueExportBar(spec: _spec, rows: rows),
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
                  const SizedBox(height: 16),
                  _AdminWorkflowSteps(spec: _spec),
                  const SizedBox(height: 16),
                  _AdminSlaPanel(spec: _spec, future: _slaFuture),
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
    context.go('$prefix/${row.id}');
  }
}

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

  factory _AdminListSpec.forRpc(String rpcName) {
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
      'admin_list_payments' => const _AdminListSpec(
        title: 'Payment intents',
        subtitle: 'Review MoMo intent states.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'All'),
          AdminFilterOption(value: 'pending', label: 'Pending'),
          AdminFilterOption(value: 'confirmed', label: 'Confirmed'),
          AdminFilterOption(value: 'needs_review', label: 'Review'),
          AdminFilterOption(value: 'expired', label: 'Expired'),
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

class _AdminQueueSignal {
  const _AdminQueueSignal(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _AdminQueueSummary extends StatelessWidget {
  const _AdminQueueSummary({required this.spec});

  final _AdminListSpec spec;

  @override
  Widget build(BuildContext context) {
    if (spec.prioritySignals.isEmpty) return const SizedBox.shrink();
    final colors = context.collectColors;
    final maxChipWidth = math.max(
      0.0,
      math.min(260.0, MediaQuery.sizeOf(context).width - 48),
    );
    return Semantics(
      container: true,
      label: '${spec.title} operator workflow signals',
      hint: spec.subtitle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.textPrimary.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: colors.surfaceReadable.withValues(alpha: 0.12),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final signal in spec.prioritySignals)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceReadable.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(CollectRadius.md),
                    border: Border.all(
                      color: colors.surfaceReadable.withValues(alpha: 0.14),
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxChipWidth),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            signal.icon,
                            size: 18,
                            color: colors.surfaceReadable,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              signal.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: colors.surfaceReadable,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ],
                      ),
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

class _AdminWorkflowSteps extends StatelessWidget {
  const _AdminWorkflowSteps({required this.spec});

  final _AdminListSpec spec;

  @override
  Widget build(BuildContext context) {
    if (spec.workflowSteps.isEmpty) return const SizedBox.shrink();
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label: '${spec.title} operator workflow',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceReadable.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.borderAccent),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var index = 0; index < spec.workflowSteps.length; index += 1)
                _AdminWorkflowStepChip(
                  index: index + 1,
                  signal: spec.workflowSteps[index],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

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
                  fontWeight: FontWeight.w800,
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

class _AdminSlaPanel extends StatelessWidget {
  const _AdminSlaPanel({required this.spec, required this.future});

  final _AdminListSpec spec;
  final Future<AdminQueueSla?> future;

  @override
  Widget build(BuildContext context) {
    final fallback = _slaForAdminQueue(spec.title);
    return FutureBuilder<AdminQueueSla?>(
      future: future,
      initialData: fallback,
      builder: (context, snapshot) {
        return _AdminSlaContent(
          spec: spec,
          sla: snapshot.hasError ? fallback : snapshot.data ?? fallback,
        );
      },
    );
  }
}

class _AdminSlaContent extends StatelessWidget {
  const _AdminSlaContent({required this.spec, required this.sla});

  final _AdminListSpec spec;
  final AdminQueueSla sla;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label: '${spec.title} SLA state',
      hint: '${sla.target}. ${sla.escalation}.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceReadable.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.borderAccent),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _AdminSlaChip(
                icon: Icons.timer_outlined,
                label: 'Target',
                value: sla.target,
              ),
              _AdminSlaChip(
                icon: Icons.assignment_ind_outlined,
                label: 'Owner',
                value: sla.owner,
              ),
              _AdminSlaChip(
                icon: Icons.escalator_warning_outlined,
                label: 'Escalation',
                value: sla.escalation,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminSlaChip extends StatelessWidget {
  const _AdminSlaChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceMuted.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(CollectRadius.md),
          border: Border.all(color: colors.borderAccent),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: colors.textSecondary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$label: $value',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.textPrimary,
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

AdminQueueSla _slaForAdminQueue(String title) {
  return switch (title) {
    'SMS parsing' => const AdminQueueSla(
      target: 'Review ambiguous SMS within 4 business hours',
      owner: 'Payments operations',
      escalation: 'Escalate failed allocation after same-day retry',
    ),
    'Allocations' => const AdminQueueSla(
      target: 'Clear allocation reviews by next business day',
      owner: 'Payments operations',
      escalation: 'Escalate mismatched ledger impact immediately',
    ),
    'Exceptions' => const AdminQueueSla(
      target: 'Triage open exceptions within 4 business hours',
      owner: 'Payments support',
      escalation: 'Escalate unresolved member impact same day',
    ),
    'SMS metadata' => const AdminQueueSla(
      target: 'Review failed parser metadata within 1 business day',
      owner: 'Compliance support',
      escalation: 'Escalate raw reveal requests to compliance owner',
    ),
    'Groups' => const AdminQueueSla(
      target: 'Respond to group support requests within 1 business day',
      owner: 'Group operations',
      escalation: 'Escalate receiver-readiness blockers same day',
    ),
    'Members' => const AdminQueueSla(
      target: 'Respond to account support requests within 1 business day',
      owner: 'Member support',
      escalation: 'Escalate identity or access risk immediately',
    ),
    'Payment intents' => const AdminQueueSla(
      target: 'Review pending or expired intents within 1 business day',
      owner: 'Payments support',
      escalation: 'Escalate duplicate or disputed intent same day',
    ),
    'Receivers' => const AdminQueueSla(
      target: 'Review receiver setup changes within 1 business day',
      owner: 'Group operations',
      escalation: 'Escalate inactive receiver routes before launch',
    ),
    'Ledger' => const AdminQueueSla(
      target: 'Review ledger exceptions within 1 business day',
      owner: 'Finance operations',
      escalation: 'Escalate correction path before member messaging',
    ),
    'Audit logs' => const AdminQueueSla(
      target: 'Review sensitive audit events daily',
      owner: 'Compliance owner',
      escalation: 'Escalate unexplained sensitive access immediately',
    ),
    'Settings' => const AdminQueueSla(
      target: 'Review config changes before release window',
      owner: 'Platform owner',
      escalation: 'Escalate unapproved production change immediately',
    ),
    'Feature flags' => const AdminQueueSla(
      target: 'Review rollout flags before activation',
      owner: 'Product operations',
      escalation: 'Escalate degraded health signal immediately',
    ),
    'Admin users' => const AdminQueueSla(
      target: 'Review operator access weekly',
      owner: 'Platform owner',
      escalation: 'Revoke stale or overbroad access immediately',
    ),
    _ => const AdminQueueSla(
      target: 'Review queue daily',
      owner: 'Operations',
      escalation: 'Escalate stale review items',
    ),
  };
}

String _adminRowsToCsv(List<AdminTableRowData> rows) {
  final buffer = StringBuffer('id,title,subtitle,status,amount,created_at\n');
  for (final row in rows) {
    buffer.writeln(
      [
        row.id,
        row.title,
        row.subtitle,
        row.status,
        row.amount,
        row.createdAt?.toIso8601String() ?? '',
      ].map(_csvCell).join(','),
    );
  }
  return buffer.toString();
}

String _csvCell(String value) {
  final escaped = value.replaceAll('"', '""');
  if (escaped.contains(',') ||
      escaped.contains('"') ||
      escaped.contains('\n') ||
      escaped.contains('\r')) {
    return '"$escaped"';
  }
  return escaped;
}

class _AdminWorkflowStepChip extends StatelessWidget {
  const _AdminWorkflowStepChip({required this.index, required this.signal});

  final int index;
  final _AdminQueueSignal signal;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceMuted.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(CollectRadius.md),
          border: Border.all(color: colors.borderAccent),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.textPrimary,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: 28,
                  child: Center(
                    child: Text(
                      '$index',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.surfaceReadable,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(signal.icon, size: 18, color: colors.textSecondary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  signal.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.textPrimary,
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
                  fontWeight: FontWeight.w800,
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

class _AdminOverviewSignalCard extends StatelessWidget {
  const _AdminOverviewSignalCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return SizedBox(
      width: 260,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceReadable.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.borderAccent),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.textPrimary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.privacy_tip_outlined,
                    color: colors.surfaceReadable,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Sensitive data gated',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Raw details stay gated.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
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
    return Wrap(
      spacing: 8,
      children: switch (actionKind) {
        'payment_event_reparse'
            when _adminHasPermission(identity, 'payment_events.reparse') =>
          [
            Semantics(
              container: true,
              button: true,
              label: 'Request SMS reparse for ${row.title}',
              hint: 'Opens a reason dialog before queuing a reparse action.',
              child: ExcludeSemantics(
                child: TextButton(
                  onPressed: () => _reparse(context, ref),
                  child: const Text('Reparse'),
                ),
              ),
            ),
          ],
        'feature_flag_toggle'
            when _adminHasPermission(identity, 'feature_flags.manage') =>
          [
            Semantics(
              container: true,
              button: true,
              label:
                  '${row.status == 'enabled' ? 'Disable' : 'Enable'} feature flag ${row.title}',
              hint: 'Opens a reason dialog before changing this feature flag.',
              child: ExcludeSemantics(
                child: TextButton(
                  onPressed: () => _setFeatureFlag(
                    context,
                    ref,
                    enabled: row.status != 'enabled',
                  ),
                  child: Text(row.status == 'enabled' ? 'Disable' : 'Enable'),
                ),
              ),
            ),
          ],
        _ => const [],
      },
    );
  }

  Future<void> _reparse(BuildContext context, WidgetRef ref) async {
    final reason = await showAdminReasonDialog(
      context,
      title: 'Request SMS reparse',
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
}
