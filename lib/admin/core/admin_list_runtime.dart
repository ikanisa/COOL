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
    return AdminPage(
      title: widget.title,
      subtitle: spec.subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          _AdminQueueSummary(spec: spec),
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
                  _AdminQueueExportBar(spec: spec, rows: rows),
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
                  _AdminWorkflowSteps(spec: spec),
                  const SizedBox(height: 16),
                  _AdminSlaPanel(spec: spec, future: _slaFuture),
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
              child: TextButton(
                onPressed: () => _reparse(context, ref),
                child: const Text('Reparse'),
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
              child: TextButton(
                onPressed: () => _setFeatureFlag(
                  context,
                  ref,
                  enabled: row.status != 'enabled',
                ),
                child: Text(row.status == 'enabled' ? 'Disable' : 'Enable'),
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
