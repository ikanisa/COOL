part of 'admin_runtime.dart';

final _adminOverviewWorkspaceProvider = FutureProvider<_AdminOverviewWorkspace>(
  (ref) async {
    ref.watch(adminRealtimeTickProvider);
    final countryScope = ref.watch(adminCountryScopeProvider);
    final repository = ref.watch(adminRepositoryProvider);
    final metricsFuture = repository.overviewMetrics();
    final attentionFuture = repository.list(
      'admin_list_collect_reconciliations',
      limit: 3,
      offset: 0,
      sortBy: 'created_at_desc',
      countryCode: countryScope.rpcCode,
    );
    final allocationsFuture = repository.list(
      'admin_list_collect_ledgers',
      limit: 4,
      offset: 0,
      sortBy: 'created_at_desc',
      countryCode: countryScope.rpcCode,
    );
    final payeesFuture = repository.list(
      'admin_list_collect_payees',
      status: 'active',
      limit: 1,
      offset: 0,
      sortBy: 'created_at_desc',
      countryCode: countryScope.rpcCode,
    );
    final slaFuture = repository.queueSla('admin_list_collect_reconciliations');
    final values = await Future.wait<Object?>([
      metricsFuture,
      attentionFuture,
      allocationsFuture,
      payeesFuture,
      slaFuture,
      repository.list(
        'admin_list_collect_transactions',
        status: 'unallocated',
        limit: 1,
        offset: 0,
        sortBy: 'created_at_desc',
        countryCode: countryScope.rpcCode,
      ),
      repository.list(
        'admin_list_collect_ledgers',
        status: 'balanced',
        limit: 1,
        offset: 0,
        sortBy: 'created_at_desc',
        countryCode: countryScope.rpcCode,
      ),
    ]);
    final rawMetrics = values[0]! as List<AdminMetric>;
    final rawAttention = values[1]! as AdminListResult;
    final rawAllocations = values[2]! as AdminListResult;
    final rawPayees = values[3]! as AdminListResult;
    ref.read(adminLastSuccessfulRefreshProvider.notifier).state = ref.read(
      adminClockProvider,
    )();
    final attention = _scopeOverviewResult(
      rawAttention,
      countryScope,
      visibleLimit: 3,
    );
    final allocations = _scopeOverviewResult(
      rawAllocations,
      countryScope,
      visibleLimit: 4,
    );
    final payees = _scopeOverviewResult(
      rawPayees,
      countryScope,
      visibleLimit: 100,
    );
    return _AdminOverviewWorkspace(
      metrics: countryScope == AdminCountryScope.all
          ? rawMetrics
          : _scopedOverviewMetrics(
              rawMetrics,
              openReconciliations: attention.total ?? attention.rows.length,
              unallocatedTransactions:
                  (values[5]! as AdminListResult).total ?? 0,
              allocations: (values[6]! as AdminListResult).total ?? 0,
              payees: payees.total ?? payees.rows.length,
            ),
      attention: attention,
      allocations: allocations,
      sla: values[4] as AdminQueueSla?,
    );
  },
);

AdminListResult _scopeOverviewResult(
  AdminListResult result,
  AdminCountryScope scope, {
  required int visibleLimit,
}) {
  if (scope == AdminCountryScope.all) return result;
  final matching = result.rows
      .where((row) => adminRowMatchesCountryScope(row, scope))
      .toList(growable: false);
  return AdminListResult(
    rows: matching.take(visibleLimit).toList(growable: false),
    total: result.total ?? matching.length,
  );
}

List<AdminMetric> _scopedOverviewMetrics(
  List<AdminMetric> source, {
  required int openReconciliations,
  required int unallocatedTransactions,
  required int allocations,
  required int payees,
}) {
  return [
    for (final metric in source)
      AdminMetric(
        label: metric.label,
        value: switch (metric.label) {
          'Open reconciliations' => '$openReconciliations',
          'Unallocated transactions' => '$unallocatedTransactions',
          'Balanced ledgers' => '$allocations',
          'Active payees' => '$payees',
          _ => metric.value,
        },
        status: metric.status,
      ),
  ];
}

class _AdminOverviewWorkspace {
  const _AdminOverviewWorkspace({
    required this.metrics,
    required this.attention,
    required this.allocations,
    required this.sla,
  });

  final List<AdminMetric> metrics;
  final AdminListResult attention;
  final AdminListResult allocations;
  final AdminQueueSla? sla;
}

class AdminOverviewContent extends ConsumerWidget {
  const AdminOverviewContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(_adminOverviewWorkspaceProvider);
    return workspace.when(
      loading: () => const AdminLoadingState(
        title: 'Loading operations overview',
        message: 'Refreshing queues.',
      ),
      error: (error, _) => Center(child: AdminSafeErrorPanel(error: error)),
      data: (data) {
        if (data.metrics.isEmpty) {
          return const AdminEmptyState(
            title: 'No admin metrics yet',
            message: 'Metrics appear after the platform has live activity.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(_adminOverviewWorkspaceProvider);
            await ref.read(_adminOverviewWorkspaceProvider.future);
          },
          child: ListView(
            key: const Key('admin-overview-workspace'),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
            children: [
              _OverviewSummary(metrics: data.metrics),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumn = constraints.maxWidth >= 980;
                  final queue = _AttentionQueue(
                    result: data.attention,
                    totalOverride: _metricInt(
                      data.metrics,
                      'Open reconciliations',
                    ),
                  );
                  final health = _QueueHealth(
                    metrics: data.metrics,
                    result: data.attention,
                    sla: data.sla,
                  );
                  if (!twoColumn) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [queue, const SizedBox(height: 16), health],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: queue),
                      const SizedBox(width: 16),
                      SizedBox(width: 292, child: health),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              _RecentAllocations(result: data.allocations),
            ],
          ),
        );
      },
    );
  }
}

class _OverviewSummary extends StatelessWidget {
  const _OverviewSummary({required this.metrics});

  final List<AdminMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: _overviewPanelDecoration(colors),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final available = constraints.maxWidth;
            final metricWidth = math.max(150.0, (available - 12) / 2);
            final metricsWrap = Wrap(
              spacing: 0,
              runSpacing: 12,
              children: [
                for (var index = 0; index < metrics.length; index++)
                  SizedBox(
                    width: metricWidth,
                    child: _OverviewMetric(
                      metric: metrics[index],
                      divided: false,
                      compact: true,
                    ),
                  ),
              ],
            );
            final action = IconButton.filled(
              key: const Key('admin-review-next-exception'),
              tooltip: 'Review next exception',
              onPressed: () => context.go('/admin/reconciliations'),
              style: IconButton.styleFrom(
                backgroundColor: colors.onImagePrimary,
                foregroundColor: CollectColors.referenceChromeBlack,
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 19),
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [metricsWrap, const SizedBox(height: 10), action],
              );
            }
            final metricsRow = Row(
              children: [
                for (var index = 0; index < metrics.length; index++)
                  Expanded(
                    child: _OverviewMetric(
                      metric: metrics[index],
                      divided: index > 0,
                      compact: false,
                    ),
                  ),
              ],
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                metricsRow,
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.metric,
    required this.divided,
    required this.compact,
  });

  final AdminMetric metric;
  final bool divided;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final tone = _metricTone(metric.status);
    final iconColor = colors.statusForeground(tone);
    return Container(
      padding: EdgeInsets.only(left: divided ? 16 : 0, right: compact ? 4 : 12),
      decoration: divided
          ? BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: colors.onImagePrimary.withValues(alpha: 0.12),
                ),
              ),
            )
          : null,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.11),
              shape: BoxShape.circle,
              border: Border.all(color: iconColor.withValues(alpha: 0.28)),
            ),
            child: SizedBox.square(
              dimension: compact ? 36 : 40,
              child: Icon(
                _metricIcon(metric.label),
                color: iconColor,
                size: 20,
              ),
            ),
          ),
          SizedBox(width: compact ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (compact
                              ? Theme.of(context).textTheme.labelMedium
                              : Theme.of(context).textTheme.labelLarge)
                          ?.copyWith(
                            color: colors.onImagePrimary.withValues(
                              alpha: 0.68,
                            ),
                            fontWeight: CollectTypography.weightMedium,
                          ),
                ),
                const SizedBox(height: 3),
                Text(
                  metric.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: colors.onImagePrimary,
                    fontWeight: CollectTypography.weightBold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  _reference(row),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: CollectTypography.weightBold,
                  ),
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
          Row(
            children: [
              Text(
                _amount(row),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
              const Spacer(),
              Text(_age(row)),
              const SizedBox(width: 12),
              IconButton.outlined(
                tooltip: 'Review reconciliation',
                onPressed: () => context.go('/admin/reconciliations'),
                icon: const Icon(Icons.arrow_outward_rounded, size: 18),
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
      fallback: '0',
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
              label: 'Oldest item age',
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

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    this.count,
  });

  final String title;
  final int? count;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 500;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                (compact
                                        ? Theme.of(
                                            context,
                                          ).textTheme.titleMedium
                                        : Theme.of(
                                            context,
                                          ).textTheme.titleLarge)
                                    ?.copyWith(
                                      color: colors.textPrimary,
                                      fontWeight: CollectTypography.weightBold,
                                    ),
                          ),
                        ),
                        if (count != null) ...[
                          const SizedBox(width: 8),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.surfaceRaised,
                              shape: BoxShape.circle,
                              border: Border.all(color: colors.borderSoft),
                            ),
                            child: SizedBox.square(
                              dimension: 26,
                              child: Center(
                                child: Text(
                                  '$count',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: colors.textSecondary,
                                        fontWeight:
                                            CollectTypography.weightBold,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: actionLabel,
                onPressed: onAction,
                icon: const Icon(Icons.open_in_new_rounded, size: 17),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Semantics(
          label: label,
          excludeSemantics: true,
          child: Icon(
            _adminOverviewHeaderIcon(label),
            size: 17,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

IconData _adminOverviewHeaderIcon(String label) => switch (label) {
  'Record' => Icons.receipt_long_outlined,
  'MoMo number' => Icons.phone_android_outlined,
  'Amount' => Icons.payments_outlined,
  'Status' => Icons.fact_check_outlined,
  'Age' => Icons.schedule_outlined,
  'Action' => Icons.tune_outlined,
  'Proposed group' => Icons.groups_outlined,
  'Requested' => Icons.calendar_today_outlined,
  'Maker / checker' => Icons.verified_user_outlined,
  _ => Icons.info_outline,
};

class _TableValue extends StatelessWidget {
  const _TableValue(this.value, {this.strong = false});

  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: strong ? colors.textPrimary : colors.textSecondary,
          fontWeight: strong
              ? CollectTypography.weightBold
              : CollectTypography.weightRegular,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _RecordSummary extends StatelessWidget {
  const _RecordSummary({required this.row, this.referenceFirst = false});

  final AdminTableRowData row;
  final bool referenceFirst;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            referenceFirst ? _reference(row) : row.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: CollectTypography.weightBold,
            ),
          ),
          if (!referenceFirst) ...[
            const SizedBox(height: 2),
            Text(
              _reference(row),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

BoxDecoration _overviewPanelDecoration(CollectColors colors) {
  return BoxDecoration(
    color: colors.surfaceReadable,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: colors.borderSoft),
    boxShadow: [
      BoxShadow(
        color: CollectColors.publicBlack.withValues(alpha: 0.08),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

CollectStatusTone _metricTone(String status) {
  final normalized = status.toLowerCase();
  if (normalized.contains('active') || normalized.contains('allocated')) {
    return CollectStatusTone.success;
  }
  if (normalized.contains('review') || normalized.contains('pending')) {
    return CollectStatusTone.warning;
  }
  return CollectStatusTone.info;
}

IconData _metricIcon(String label) {
  final normalized = label.toLowerCase();
  if (normalized.contains('exception')) return Icons.report_problem_outlined;
  if (normalized.contains('approval')) return Icons.fact_check_outlined;
  if (normalized.contains('unreconciled')) {
    return Icons.pending_actions_outlined;
  }
  if (normalized.contains('evidence')) return Icons.verified_outlined;
  return Icons.account_balance_outlined;
}

String _metricValue(
  List<AdminMetric> metrics,
  String label, {
  required String fallback,
}) {
  for (final metric in metrics) {
    if (metric.label.toLowerCase() == label.toLowerCase()) return metric.value;
  }
  return fallback;
}

int? _metricInt(List<AdminMetric> metrics, String label) {
  final value = _metricValue(metrics, label, fallback: '');
  return int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
}

String _extraString(AdminTableRowData row, String key, String fallback) {
  final value = row.extra[key];
  if (value == null) return fallback;
  final text = '$value'.trim();
  return text.isEmpty ? fallback : text;
}

String _sender(AdminTableRowData row) {
  if (_rail(row) != 'rw_momo') return '—';
  return _momoSender(row);
}

String _reference(AdminTableRowData row) {
  return adminCompactTransactionReference(
    _extraString(row, 'reference', 'Ref ${row.id}'),
  );
}

String _allocatedTo(AdminTableRowData row) {
  return _extraString(row, 'allocated_to', 'Verified group');
}

String _operator(AdminTableRowData row) {
  return _extraString(row, 'operator', 'Operations');
}

String _age(AdminTableRowData row) {
  final explicit = _extraString(row, 'age', '');
  if (explicit.isNotEmpty) return _compactAge(explicit);
  final createdAt = row.createdAt;
  if (createdAt == null) return '—';
  final duration = DateTime.now().toUtc().difference(createdAt);
  if (duration.isNegative) return 'just now';
  if (duration.inMinutes < 60) return '${math.max(1, duration.inMinutes)}m';
  if (duration.inHours < 24) {
    return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
  }
  return '${duration.inDays}d';
}

String _compactAge(String value) {
  final normalized = value.trim();
  final postgresInterval = RegExp(
    r'^(?:(\d+)\s+days?\s+)?(\d{1,2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$',
  ).firstMatch(normalized);
  if (postgresInterval == null) return normalized;

  final days = int.tryParse(postgresInterval.group(1) ?? '') ?? 0;
  final hours = int.tryParse(postgresInterval.group(2) ?? '') ?? 0;
  final minutes = int.tryParse(postgresInterval.group(3) ?? '') ?? 0;
  if (days > 0) return '${days}d';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${math.max(1, minutes)}m';
}

String _oldestAge(List<AdminTableRowData> rows) {
  if (rows.isEmpty) return '—';
  var oldest = rows.first;
  var oldestMinutes = _ageMinutes(_age(oldest));
  for (final row in rows.skip(1)) {
    final minutes = _ageMinutes(_age(row));
    if (minutes > oldestMinutes) {
      oldest = row;
      oldestMinutes = minutes;
    }
  }
  return _age(oldest);
}

int _ageMinutes(String value) {
  final hours = RegExp(r'(\d+)h').firstMatch(value);
  final minutes = RegExp(r'(\d+)m').firstMatch(value);
  final days = RegExp(r'(\d+)d').firstMatch(value);
  return (int.tryParse(days?.group(1) ?? '') ?? 0) * 1440 +
      (int.tryParse(hours?.group(1) ?? '') ?? 0) * 60 +
      (int.tryParse(minutes?.group(1) ?? '') ?? 0);
}

String _amount(AdminTableRowData row) {
  return _transactionDisplayAmount(row);
}

String _dateTime(DateTime? value) {
  if (value == null) return '—';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)} ${_month(value.month)} ${value.year}, ${two(value.hour)}:${two(value.minute)}';
}

String _month(int value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months[value.clamp(1, 12) - 1];
}

String _compactSla(String? target) {
  if (target == null || target.trim().isEmpty) return '< 4h';
  if (RegExp(r'next\s+business\s+day', caseSensitive: false).hasMatch(target)) {
    return 'Next business day';
  }
  final match = RegExp(
    r'(\d+)\s*(?:business\s*)?hours?',
    caseSensitive: false,
  ).firstMatch(target);
  if (match != null) return '< ${match.group(1)}h';
  return target;
}
