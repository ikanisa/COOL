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
  var _lastRealtimeTick = 0;

  _AdminListSpec get _spec => _AdminListSpec.forRpc(widget.rpcName);

  @override
  void initState() {
    super.initState();
    _future = _load();
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

  void _refresh({bool resetPage = false}) {
    setState(() {
      if (resetPage) _page = 0;
      _future = _load();
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
  });

  final String title;
  final String subtitle;
  final List<AdminFilterOption> statusOptions;
  final List<AdminFilterOption> sortOptions;
  final List<_AdminQueueSignal> prioritySignals;

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
}
