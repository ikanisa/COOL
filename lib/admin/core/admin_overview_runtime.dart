part of 'admin_runtime.dart';

class _OverviewPermissionDenied implements Exception {
  const _OverviewPermissionDenied();
}

final adminReceiptOverviewProvider =
    FutureProvider.autoDispose<AdminReceiptOverview>((ref) async {
      final scope = ref.watch(adminAuthSessionScopeProvider);
      final country = ref.watch(adminCountryScopeProvider);
      ref.watch(adminRealtimeTickProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (identity?.permissions.contains('overview.read') != true) {
        throw const _OverviewPermissionDenied();
      }
      final raw = await repository.receiptOverview(
        countryCode: country.rpcCode,
      );
      if (!current ||
          ref.read(adminAuthSessionScopeProvider) != scope ||
          !identical(ref.read(adminRepositoryProvider), repository)) {
        throw const AdminSessionChanged();
      }
      return AdminReceiptOverview.parse(raw);
    });

final adminOverviewOperationalHealthProvider =
    FutureProvider.autoDispose<AdminOperationalHealth>((ref) async {
      final scope = ref.watch(adminAuthSessionScopeProvider);
      ref.watch(adminRealtimeTickProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (identity?.permissions.contains('system_health.read') != true) {
        throw const _OverviewPermissionDenied();
      }
      final raw = await repository.detail('admin_system_health', 'system');
      if (!current ||
          ref.read(adminAuthSessionScopeProvider) != scope ||
          !identical(ref.read(adminRepositoryProvider), repository)) {
        throw const AdminSessionChanged();
      }
      return AdminOperationalHealth.parse(raw);
    });

final adminOverviewSmsHealthProvider =
    FutureProvider.autoDispose<AdminSmsQueueHealth>((ref) async {
      final scope = ref.watch(adminAuthSessionScopeProvider);
      ref.watch(adminRealtimeTickProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (identity?.permissions.contains('notifications.read') != true) {
        throw const _OverviewPermissionDenied();
      }
      final raw = await repository.smsQueueHealth();
      if (!current ||
          ref.read(adminAuthSessionScopeProvider) != scope ||
          !identical(ref.read(adminRepositoryProvider), repository)) {
        throw const AdminSessionChanged();
      }
      return AdminSmsQueueHealth.parse(raw);
    });

final _adminOverviewWorkspaceProvider = FutureProvider<_AdminOverviewWorkspace>((
  ref,
) async {
  var current = true;
  ref.onDispose(() => current = false);
  final session = ref.watch(adminAuthSessionScopeProvider);
  ref.watch(adminRealtimeTickProvider);
  final countryScope = ref.watch(adminCountryScopeProvider);
  final repository = ref.watch(adminRepositoryProvider);
  // Catch each read independently: unavailable metrics/SLA must never turn a
  // loaded attention queue or allocation record into a whole-page error.
  final values = await Future.wait<AsyncValue<Object?>>([
    AsyncValue.guard(() async => await repository.overviewMetrics()),
    AsyncValue.guard(
      () async => await repository.list(
        'admin_list_collect_reconciliations',
        limit: 3,
        offset: 0,
        sortBy: 'created_at_desc',
        countryCode: countryScope.rpcCode,
      ),
    ),
    AsyncValue.guard(
      () async => await repository.list(
        'admin_list_collect_ledgers',
        limit: 4,
        offset: 0,
        sortBy: 'created_at_desc',
        countryCode: countryScope.rpcCode,
      ),
    ),
    AsyncValue.guard(
      () async =>
          await repository.queueSla('admin_list_collect_reconciliations'),
    ),
  ]);
  if (!current ||
      ref.read(adminAuthSessionScopeProvider) != session ||
      !identical(ref.read(adminRepositoryProvider), repository) ||
      ref.read(adminCountryScopeProvider) != countryScope) {
    throw const AdminSessionChanged();
  }
  if (values.every((value) => value.hasValue && !value.hasError)) {
    ref.read(adminLastSuccessfulRefreshProvider.notifier).state = ref.read(
      adminClockProvider,
    )();
  }
  final attention = values[1].whenData(
    (raw) => _scopeOverviewResult(
      raw! as AdminListResult,
      countryScope,
      visibleLimit: 3,
    ),
  );
  final allocations = values[2].whenData(
    (raw) => _scopeOverviewResult(
      raw! as AdminListResult,
      countryScope,
      visibleLimit: 4,
    ),
  );
  // Samples are for the queues below. Global counts and money come only
  // from the authoritative overview RPC, never a loaded page or filtered list.
  final metrics = values[0].whenData((raw) => raw! as List<AdminMetric>);
  return _AdminOverviewWorkspace(
    metrics: metrics,
    attention: attention,
    allocations: allocations,
    sla: values[3].whenData((value) => value as AdminQueueSla?),
  );
});

AdminListResult _scopeOverviewResult(
  AdminListResult result,
  AdminCountryScope scope, {
  required int visibleLimit,
}) {
  final matching = result.rows
      .where((row) => adminRowMatchesCountryScope(row, scope))
      .toList(growable: false);
  return AdminListResult(
    rows: matching.take(visibleLimit).toList(growable: false),
    total: result.total,
  );
}

class _AdminOverviewWorkspace {
  const _AdminOverviewWorkspace({
    required this.metrics,
    required this.attention,
    required this.allocations,
    required this.sla,
  });
  final AsyncValue<List<AdminMetric>> metrics;
  final AsyncValue<AdminListResult> attention, allocations;
  final AsyncValue<AdminQueueSla?> sla;
}

class AdminOverviewContent extends ConsumerStatefulWidget {
  const AdminOverviewContent({super.key});
  @override
  ConsumerState<AdminOverviewContent> createState() =>
      _AdminOverviewContentState();
}

class _AdminOverviewContentState extends ConsumerState<AdminOverviewContent> {
  Timer? _freshnessTimer;
  @override
  void initState() {
    super.initState();
    _freshnessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(adminReceiptOverviewProvider);
    ref.invalidate(adminReceiptOperationalTelemetryProvider);
    ref.invalidate(adminOverviewOperationalHealthProvider);
    ref.invalidate(adminOverviewSmsHealthProvider);
    ref.invalidate(_adminOverviewWorkspaceProvider);
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(_adminOverviewWorkspaceProvider);
    final receipt = ref.watch(adminReceiptOverviewProvider);
    final health = ref.watch(adminOverviewOperationalHealthProvider);
    final sms = ref.watch(adminOverviewSmsHealthProvider);
    final now = ref.watch(adminClockProvider)();
    return RefreshIndicator(
      onRefresh: () async {
        _refresh();
        await ref.read(_adminOverviewWorkspaceProvider.future);
      },
      child: ListView(
        key: const Key('admin-overview-workspace'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
        children: [
          workspace.when(
            loading: () =>
                const AdminLoadingState(title: 'Loading system totals'),
            error: (error, _) => _OverviewReadFailure(
              title: 'Queue totals',
              error: error,
              onRefresh: _refresh,
            ),
            data: (data) => data.metrics.when(
              loading: () =>
                  const AdminLoadingState(title: 'Loading system totals'),
              error: (error, _) => _OverviewReadFailure(
                title: 'Queue totals',
                error: error,
                onRefresh: _refresh,
              ),
              data: (metrics) => AdminOverviewTotals(metrics: metrics),
            ),
          ),
          const SizedBox(height: 16),
          _OverviewPostingPanel(
            sample: receipt,
            now: now,
            onRefresh: () => ref.invalidate(adminReceiptOverviewProvider),
          ),
          const SizedBox(height: 16),
          _OverviewServicePanel(
            health: health,
            sms: sms,
            now: now,
            onRefresh: () {
              ref.invalidate(adminOverviewOperationalHealthProvider);
              ref.invalidate(adminOverviewSmsHealthProvider);
            },
          ),
          const SizedBox(height: 16),
          const AdminReceiptTelemetryCard(compact: true),
          const SizedBox(height: 16),
          workspace.when(
            loading: () =>
                const AdminLoadingState(title: 'Loading operation queues'),
            error: (error, _) =>
                AdminSafeErrorPanel(error: error, onRetry: _refresh),
            data: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                data.attention.when(
                  loading: () =>
                      const AdminLoadingState(title: 'Loading attention queue'),
                  error: (error, _) => _OverviewReadFailure(
                    title: 'Needs attention',
                    error: error,
                    onRefresh: _refresh,
                  ),
                  data: (result) => LayoutBuilder(
                    builder: (context, constraints) {
                      final queue = _AttentionQueue(
                        result: result,
                        totalOverride: result.total,
                      );
                      final queueHealth = _QueueHealth(
                        metrics: data.metrics.valueOrNull ?? [],
                        result: result,
                        sla: data.sla.valueOrNull,
                      );
                      if (constraints.maxWidth < 980) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            queue,
                            const SizedBox(height: 16),
                            queueHealth,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: queue),
                          const SizedBox(width: 16),
                          SizedBox(width: 292, child: queueHealth),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                data.allocations.when(
                  loading: () => const AdminLoadingState(
                    title: 'Loading recent allocations',
                  ),
                  error: (error, _) => _OverviewReadFailure(
                    title: 'Recent allocations',
                    error: error,
                    onRefresh: _refresh,
                  ),
                  data: (result) => _RecentAllocations(result: result),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionQueue extends StatelessWidget {
  const _AttentionQueue({required this.result, required this.totalOverride});

  final AdminListResult result;
  final int? totalOverride;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final rows = result.rows.take(3).toList(growable: false);
    final total = totalOverride ?? result.total ?? rows.length;
    return Semantics(
      container: true,
      label: 'Needs attention queue, $total records',
      child: DecoratedBox(
        decoration: _overviewPanelDecoration(colors),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PanelHeading(
              title: 'Needs attention',
              count: total,
              subtitle: '',
              actionLabel: 'View all exceptions',
              onAction: () => context.go('/admin/reconciliations'),
            ),
            Divider(height: 1, color: colors.borderSoft),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: AdminEmptyState(
                  title: 'Queue is clear',
                  message: 'No payment allocation exceptions require review.',
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 720) {
                    return Column(
                      children: [
                        for (var index = 0; index < rows.length; index++) ...[
                          _AttentionCompactRow(row: rows[index]),
                          if (index != rows.length - 1)
                            Divider(height: 1, color: colors.borderSoft),
                        ],
                      ],
                    );
                  }
                  return _AttentionTable(rows: rows);
                },
              ),
            if (total > rows.length) ...[
              Divider(height: 1, color: colors.borderSoft),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton.outlined(
                    tooltip: 'Open full exceptions queue',
                    onPressed: () => context.go('/admin/reconciliations'),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttentionTable extends StatelessWidget {
  const _AttentionTable({required this.rows});

  final List<AdminTableRowData> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.9),
        1: FlexColumnWidth(1.4),
        2: FlexColumnWidth(1.1),
        3: FlexColumnWidth(1.45),
        4: FlexColumnWidth(0.75),
        5: FlexColumnWidth(1.5),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(color: colors.borderSoft),
      ),
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: colors.surfaceRaised.withValues(alpha: 0.58),
          ),
          children: const [
            _TableHeader('Record'),
            _TableHeader('MoMo number'),
            _TableHeader('Amount'),
            _TableHeader('Status'),
            _TableHeader('Age'),
            _TableHeader('Action'),
          ],
        ),
        for (final row in rows)
          TableRow(
            children: [
              _RecordSummary(row: row, referenceFirst: true),
              _TableValue(_sender(row)),
              _TableValue(_amount(row), strong: true),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AdminStatusChip(label: row.status),
                ),
              ),
              _TableValue(_age(row)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton.outlined(
                      tooltip: 'Review reconciliation',
                      onPressed: () => context.go('/admin/reconciliations'),
                      icon: const Icon(Icons.arrow_outward_rounded, size: 18),
                    ),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: PopupMenuButton<String>(
                        tooltip: 'More record actions',
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        onSelected: (_) => context.go('/admin/reconciliations'),
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'open',
                            child: Text('Open record'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _AttentionCompactRow extends StatelessWidget {
  const _AttentionCompactRow({required this.row});

  final AdminTableRowData row;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                _reference(row),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
              AdminStatusChip(label: row.status),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            _sender(row),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                _amount(row),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(_age(row)),
                  IconButton.outlined(
                    tooltip: 'Review reconciliation',
                    onPressed: () => context.go('/admin/reconciliations'),
                    icon: const Icon(Icons.arrow_outward_rounded, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QueueHealth extends StatelessWidget {
  const _QueueHealth({
    required this.metrics,
    required this.result,
    required this.sla,
  });

  final List<AdminMetric> metrics;
  final AdminListResult result;
  final AdminQueueSla? sla;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final review = _metricValue(
      metrics,
      'Open reconciliations',
      fallback: '${result.total ?? result.rows.length}',
    );
    final approvals = _metricValue(
      metrics,
      'Awaiting approvals',
      fallback: 'Not available',
    );
    final oldest = _oldestAge(result.rows);
    return DecoratedBox(
      decoration: _overviewPanelDecoration(colors),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Queue health',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: CollectTypography.weightBold,
              ),
            ),
            const SizedBox(height: 12),
            _HealthRow(
              label: 'SLA target',
              value: _compactSla(sla?.target),
              valueColor: colors.successForeground,
            ),
            _HealthRow(
              label: 'Oldest visible item',
              value: oldest,
              valueColor: colors.warningForeground,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: colors.borderSoft),
            ),
            _HealthRow(
              label: 'Open reconciliations',
              value: review,
              valueColor: colors.warningForeground,
            ),
            _HealthRow(
              label: 'Awaiting approvals',
              value: approvals,
              valueColor: colors.warningForeground,
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              softWrap: true,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: valueColor ?? colors.textPrimary,
                fontWeight: CollectTypography.weightBold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentAllocations extends StatelessWidget {
  const _RecentAllocations({required this.result});

  final AdminListResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final rows = result.rows.take(4).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent allocations',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Open ledgers',
              onPressed: () => context.go('/admin/ledgers'),
              icon: const Icon(Icons.open_in_new_rounded, size: 17),
            ),
          ],
        ),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: _overviewPanelDecoration(colors),
          child: rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: AdminEmptyState(
                    title: 'No ledger allocations yet',
                    message: 'Allocated transactions will appear here.',
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 760;
                    return Column(
                      children: [
                        if (compact)
                          for (var index = 0; index < rows.length; index++) ...[
                            _AllocationCompactRow(row: rows[index]),
                            if (index != rows.length - 1)
                              Divider(height: 1, color: colors.borderSoft),
                          ]
                        else
                          _AllocationTable(rows: rows),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AllocationTable extends StatelessWidget {
  const _AllocationTable({required this.rows});

  final List<AdminTableRowData> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.8),
        1: FlexColumnWidth(1.35),
        2: FlexColumnWidth(1.15),
        3: FlexColumnWidth(1.1),
        4: FlexColumnWidth(1.8),
        5: FlexColumnWidth(1.55),
        6: FlexColumnWidth(1.0),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(color: colors.borderSoft),
      ),
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: colors.surfaceRaised.withValues(alpha: 0.58),
          ),
          children: const [
            _TableHeader('Record'),
            _TableHeader('MoMo number'),
            _TableHeader('Amount'),
            _TableHeader('Status'),
            _TableHeader('Proposed group'),
            _TableHeader('Requested'),
            _TableHeader('Maker / checker'),
          ],
        ),
        for (final row in rows)
          TableRow(
            children: [
              _RecordSummary(row: row),
              _TableValue(_sender(row)),
              _TableValue(_amount(row), strong: true),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AdminStatusChip(label: row.status),
                ),
              ),
              _TableValue(_allocatedTo(row)),
              _TableValue(_dateTime(row.createdAt)),
              _TableValue(_operator(row)),
            ],
          ),
      ],
    );
  }
}

class _AllocationCompactRow extends StatelessWidget {
  const _AllocationCompactRow({required this.row});

  final AdminTableRowData row;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: CollectTypography.weightBold,
                  ),
                ),
              ),
              AdminStatusChip(label: row.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_amount(row)} · ${_sender(row)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            '${_allocatedTo(row)} · ${_operator(row)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
