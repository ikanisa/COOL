part of 'admin_runtime.dart';

String _historyTime(Object? value) =>
    adminKigaliDateTime(historyInstant(value));

String _historyUsageLabel(String key) => switch (key) {
  'run_actions' => 'Actions reserved for this run',
  'run_sms_segments' => 'SMS segments reserved for this run',
  'global_actions' => 'Global actions reserved',
  'global_sms_segments' => 'Global SMS segments reserved',
  'device_actions' => 'Device actions reserved',
  'device_sms_segments' => 'Device SMS segments reserved',
  _ => throw StateError('Unknown reservation usage field'),
};

class AdminReceiptOperationalHistoryCard extends StatelessWidget {
  const AdminReceiptOperationalHistoryCard({super.key});
  @override
  Widget build(BuildContext context) => const AdminReceiptHistoryPager();
}

/// Each section owns a complete query/cursor; departure hides stale history.
class AdminReceiptHistoryPager extends ConsumerStatefulWidget {
  const AdminReceiptHistoryPager({
    this.runId,
    this.section,
    this.pageSize = 20,
    super.key,
  });
  final String? runId;
  final AdminReceiptHistorySection? section;
  final int pageSize;
  @override
  ConsumerState<AdminReceiptHistoryPager> createState() =>
      _AdminReceiptHistoryPagerState();
}

class _AdminReceiptHistoryPagerState
    extends ConsumerState<AdminReceiptHistoryPager> {
  AdminReceiptHistoryQuery? _query;
  final _previous = <AdminReceiptHistoryQuery>[];
  Object? _scope;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final identityState = ref.watch(adminIdentityProvider),
        identity = _adminResolvedIdentity(identityState),
        session = ref.watch(adminAuthSessionScopeProvider);
    final boundary = (
      session,
      ref.watch(adminRepositoryProvider),
      ref.watch(_adminIdentityRevisionProvider),
      identity?.userId,
      identity?.roles.join('|'),
      identity?.permissions.join('|'),
      widget.runId,
      widget.section,
      widget.pageSize,
    );
    if (boundary != _scope) {
      _scope = boundary;
      _previous.clear();
      _query = AdminReceiptHistoryQuery(
        runId: widget.runId,
        section: widget.section,
        limit: widget.pageSize,
      );
    }
    final query = _query!;
    try {
      query.validate();
    } on FormatException {
      return const Text('Operational history link is unavailable.');
    }
    final allowed =
        session != null &&
        identity?.userId == session.key.userId &&
        adminReceiptOperationalHistoryCanRead(identity);
    if (identityState.isLoading) {
      return const Text('Checking operational history access…');
    }
    if (!allowed) {
      return const Text(
        'A current platform owner with payment, notification and system health read access is required.',
      );
    }
    final sample = ref.watch(adminReceiptHistoryPageProvider(query)),
        scope = _AdminActionScope(ref);
    final page = sample.isLoading ? null : sample.asData?.value,
        fresh = page?.isFresh(ref.watch(adminClockProvider)()) == true;
    void refresh() {
      if (!scope.isCurrent) return;
      final first = AdminReceiptHistoryQuery(
        runId: widget.runId,
        section: widget.section,
        limit: widget.pageSize,
      );
      setState(() {
        _previous.clear();
        _query = first;
      });
      ref.invalidate(adminReceiptHistoryPageProvider(first));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sample.isLoading)
          const Text('Loading operational history…')
        else if (sample.hasError)
          Text(
            sample.error is AdminReceiptHistoryDenied
                ? 'Operational history access denied.'
                : sample.error is AdminSessionChanged
                ? 'Admin session changed. Reopen the history.'
                : 'Operational history could not be verified. Refresh for current evidence.',
          )
        else if (!fresh)
          const Text(
            'Operational history expired. Refresh before following evidence links.',
          )
        else if (page != null) ...[
          Text('Checked ${adminKigaliDateTime(page.checkedAt)}'),
          const Text(
            'Retained history is partial. An empty page does not establish that all work was processed. Refusals that roll back, including operations_budget_conflict, leave no retained request row.',
          ),
          if (!page.available)
            const Text('Run scope is unavailable. No evidence is inferred.')
          else if (page.rows.isEmpty)
            const Text('No retained evidence in this page.')
          else
            for (final row in page.rows) ...[
              const SizedBox(height: 12),
              _ReceiptHistoryRowView(
                row: row,
                section: widget.section,
                sample: page,
              ),
              const Divider(),
            ],
        ],
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: sample.isLoading ? null : refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh operational history'),
            ),
            if (_previous.isNotEmpty)
              TextButton(
                onPressed: fresh && scope.isCurrent
                    ? () {
                        if (scope.isCurrent &&
                            page!.isFresh(ref.read(adminClockProvider)())) {
                          setState(() => _query = _previous.removeLast());
                        }
                      }
                    : null,
                child: const Text('Newer history'),
              ),
            if (page?.nextCursor != null)
              TextButton(
                onPressed: fresh && scope.isCurrent
                    ? () {
                        if (scope.isCurrent &&
                            page!.isFresh(ref.read(adminClockProvider)())) {
                          setState(() {
                            _previous.add(query);
                            _query = AdminReceiptHistoryQuery(
                              runId: query.runId,
                              section: query.section,
                              limit: query.limit,
                              before: page.nextCursor,
                            );
                          });
                        }
                      }
                    : null,
                child: const Text('Older history'),
              ),
          ],
        ),
      ],
    );
  }
}

class _ReceiptHistoryRowView extends ConsumerWidget {
  const _ReceiptHistoryRowView({
    required this.row,
    required this.sample,
    this.section,
  });
  final AdminReceiptHistoryPage sample;
  final AdminReceiptHistoryRow row;
  final AdminReceiptHistorySection? section;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = row.data, scope = _AdminActionScope(ref);
    bool current() =>
        scope.isCurrent && sample.isFresh(ref.read(adminClockProvider)());
    Widget link(String label, String path) => TextButton(
      onPressed: () {
        if (current()) context.push(path);
      },
      child: Text(label),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section == null) ...[
          Text('${d['code']} · ${d['mode']} · ${d['run_state']}'),
          Text('Start request recorded ${_historyTime(d['recorded_at'])}'),
          SelectableText('Request ${d['request_id']}'),
          SelectableText('Principal ${d['principal_id']}'),
          if (row.runId != null)
            link(
              'Open operational run evidence',
              adminReceiptOperationalRunPath(row.runId!),
            ),
          if (d['run_state'] == 'no_run')
            const Text('This start request created no run.'),
          if (d['run_state'] == 'unavailable')
            const Text('Associated run scope is unavailable.'),
        ] else if (section == AdminReceiptHistorySection.events) ...[
          SelectableText('Event ${d['event_id']}'),
          Text(
            d['assigned_at'] == null
                ? 'No assignment retained for this outcome.'
                : 'Assigned ${_historyTime(d['assigned_at'])}',
          ),
          if (d['outcome'] == null)
            const Text('Assigned and unprocessed in this run.')
          else ...[
            Text('Immutable run outcome: ${(d['outcome'] as Map)['code']}'),
            Text(
              (d['outcome'] as Map)['business_handled'] == true
                  ? 'This run durably handled this event.'
                  : 'This run did not durably handle this event.',
            ),
            Text(
              'Outcome recorded ${_historyTime((d['outcome'] as Map)['recorded_at'])}',
            ),
          ],
          if (d['first_handled'] == null)
            const Text('No first durable handling proof retained.')
          else ...[
            Text(
              'First durable handling: ${(d['first_handled'] as Map)['code']} · ${_historyTime((d['first_handled'] as Map)['handled_at'])}',
            ),
            link(
              'Open first handling run',
              adminReceiptOperationalRunPath(
                (d['first_handled'] as Map)['run_id'] as String,
              ),
            ),
          ],
          if (d['current_deferral'] != null)
            Text(
              'Current mutable deferral: ${(d['current_deferral'] as Map)['code']} · next check ${_historyTime((d['current_deferral'] as Map)['next_check_at'])}',
            )
          else
            const Text(
              'No current deferral recorded. This alone does not prove completion.',
            ),
        ] else if (section == AdminReceiptHistorySection.reservations) ...[
          SelectableText('Reservation ${d['evidence_id']}'),
          if (d['snapshot_id'] != null) ...[
            SelectableText('Original backlog snapshot ${d['snapshot_id']}'),
            const Text(
              'This globally retained snapshot reservation belongs to the original run. A later run can refuse this identifier with operations_budget_conflict; no recovery is inferred.',
            ),
          ],
          Text(
            'Actions ${d['actions']} · SMS segments ${d['sms_segments']} · Fence ${d['fence_version']}',
          ),
          SelectableText('Collection ${d['collection_id']}'),
          if (d['device_id'] != null)
            SelectableText('Device ${d['device_id']}'),
        ] else ...[
          SelectableText('Snapshot ${d['snapshot_id']}'),
          Text(
            '${d['code']} · ${d['business_handled'] == true ? 'durably handled' : 'not durably handled'}',
          ),
          if (d['request_id'] != null)
            SelectableText(
              'Original budget refusal request ${d['request_id']}',
            ),
        ],
        if (section != null)
          Text('Evidence recorded ${_historyTime(d['recorded_at'])}'),
        if (d['source_status'] == 'unavailable')
          const Text(
            'Current source scope unavailable; joined references are withheld.',
          ),
        if (d['transaction_sms_id'] != null)
          link(
            'Open transaction investigation',
            '/admin/transactions/momo:${d['transaction_sms_id']}',
          ),
        if (d['receipt_id'] != null)
          link(
            'Open receipt evidence',
            '/admin/sms-receipts/${d['receipt_id']}',
          ),
        for (final id in d['exception_ids'] as List? ?? const [])
          TextButton(
            onPressed: () {
              if (current()) {
                _showAdminExceptionFollowUp(context, scope, id as String);
              }
            },
            child: const Text('Open operational exception'),
          ),
      ],
    );
  }
}

class AdminReceiptOperationalRunPage extends ConsumerStatefulWidget {
  const AdminReceiptOperationalRunPage({required this.runId, super.key});
  final String runId;
  @override
  ConsumerState<AdminReceiptOperationalRunPage> createState() =>
      _AdminReceiptOperationalRunPageState();
}

class _AdminReceiptOperationalRunPageState
    extends ConsumerState<AdminReceiptOperationalRunPage> {
  AdminReceiptHistorySection _section = AdminReceiptHistorySection.events;
  Timer? _timer;
  Object? _boundary;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      historyUuid(widget.runId);
    } on FormatException {
      return const AdminPage(
        title: 'Operational run',
        child: Text('Operational run link is unavailable.'),
      );
    }
    final session = ref.watch(adminAuthSessionScopeProvider),
        identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider)),
        repository = ref.watch(adminRepositoryProvider);
    final boundary = (
      session,
      repository,
      identity?.userId,
      identity?.roles.join('|'),
      identity?.permissions.join('|'),
      widget.runId,
    );
    if (boundary != _boundary) {
      _boundary = boundary;
      _section = AdminReceiptHistorySection.events;
    }
    final allowed =
        session != null &&
        identity?.userId == session.key.userId &&
        adminReceiptOperationalHistoryCanRead(identity);
    final sample = allowed
            ? ref.watch(adminReceiptOperationalRunProvider(widget.runId))
            : null,
        scope = _AdminActionScope(ref);
    final detail = sample?.isLoading == false ? sample?.asData?.value : null,
        fresh = detail?.isFresh(ref.watch(adminClockProvider)()) == true;
    return AdminPage(
      title: 'Operational receipt run',
      subtitle: 'Rwanda · Africa/Kigali',
      leading: IconButton(
        tooltip: 'Back to Automations',
        onPressed: () => {
          if (scope.isCurrent) context.go('/admin/automations'),
        },
        icon: const Icon(Icons.arrow_back),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!allowed)
            const Text(
              'A current platform owner with payment, notification and system health read access is required.',
            )
          else if (sample!.isLoading)
            const Text('Loading operational run evidence…')
          else if (sample.hasError)
            const Text(
              'Operational run could not be authorized, loaded or validated.',
            )
          else if (!fresh)
            const Text(
              'Operational run evidence expired. Refresh for current evidence.',
            )
          else if (detail != null && !detail.available)
            const Text(
              'Current run scope is unavailable. No run or source evidence is inferred.',
            )
          else if (detail != null) ...[
            SelectableText('Run ${detail.id}'),
            Text(
              '${detail.run!['mode']} · ${detail.run!['state']} · Policy revision ${detail.run!['policy_revision']} · Fence ${detail.run!['fence_version']}',
            ),
            Text(
              'Started ${_historyTime(detail.run!['started_at'])} · Lease ends ${_historyTime(detail.run!['expires_at'])}',
            ),
            const Text(
              'A closed run may retain deferred work. Receipt sending and delivery have separate evidence.',
            ),
            if (detail.completion == null)
              const Text('Original complete_run summary unavailable.')
            else ...[
              Text(
                'Original close summary: handled ${detail.completion!['handled_count']} · deferred ${detail.completion!['deferred_count']}',
              ),
              Text(
                'Original reserved actions ${detail.completion!['action_count']} · SMS segments ${detail.completion!['sms_segments']}',
              ),
              Text(
                detail.completion!['business_handled'] == true
                    ? 'Original summary records business handling.'
                    : 'Original summary does not record complete business handling.',
              ),
            ],
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                'Historical budgets',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (detail.historicalConfig == null)
              const Text(
                'Historical configuration unavailable. No current budget limit is substituted.',
              )
            else ...[
              Text(
                'Exact configure request ${detail.historicalConfig!['request_id']} · Revision ${detail.historicalConfig!['revision']}',
              ),
              for (final e in (detail.historicalConfig!['caps'] as Map).entries)
                Text('${_capLabel(e.key as String)}: ${e.value}'),
            ],
            const SizedBox(height: 12),
            Semantics(
              header: true,
              child: Text(
                'Reserved usage',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              'Immutable reservation usage through ${_historyTime(detail.quotaUsage!['window_end'])}; UTC day starts ${_historyTime(detail.quotaUsage!['window_start'])}',
            ),
            for (final key in [
              'run_actions',
              'run_sms_segments',
              'global_actions',
              'global_sms_segments',
              'device_actions',
              'device_sms_segments',
            ])
              Text(
                '${_historyUsageLabel(key)}: ${detail.quotaUsage![key] ?? 'unavailable'}',
              ),
            for (final g in detail.quotaUsage!['groups'] as List)
              Text(
                'Collection ${g['collection_id']} · shared actions ${g['actions']} · SMS segments ${g['sms_segments']}',
              ),
            Wrap(
              spacing: 8,
              children: [
                AdminEntityAuditLink(
                  kind: AdminAuditEntityKind.receiptOperationRun,
                  id: detail.id,
                ),
                AdminEntityAuditLink(
                  kind: AdminAuditEntityKind.supervisorIdentity,
                  id: detail.run!['principal_id'] as String,
                ),
                const AdminEntityAuditLink(
                  kind: AdminAuditEntityKind.receiptOperationsPolicy,
                  id: receiptOperationsPolicyAuditId,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final section in AdminReceiptHistorySection.values)
                  ChoiceChip(
                    label: Text(section.label),
                    selected: _section == section,
                    onSelected: (_) {
                      if (scope.isCurrent) setState(() => _section = section);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            AdminReceiptHistoryPager(
              key: ValueKey((detail.id, _section)),
              runId: detail.id,
              section: _section,
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: allowed && sample?.isLoading != true
                ? () {
                    if (scope.isCurrent) {
                      ref.invalidate(
                        adminReceiptOperationalRunProvider(widget.runId),
                      );
                      ref.invalidate(adminReceiptHistoryPageProvider);
                    }
                  }
                : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh run evidence'),
          ),
        ],
      ),
    );
  }
}
