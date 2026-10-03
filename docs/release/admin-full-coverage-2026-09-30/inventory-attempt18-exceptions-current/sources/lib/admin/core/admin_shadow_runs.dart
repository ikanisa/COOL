import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/collect_components.dart';
import '../../core/data/exact_json_values.dart';
import '../shared/components/admin_status_chip.dart';
import 'admin_auth_guard.dart';
import 'admin_display_formatters.dart';
import 'admin_repository_base.dart';
import 'admin_sms_queue_health.dart';

const _safeInteger = 9007199254740991;

// Seconds distinguish observation/completion and the fixed 120-second lease.
String _historyTime(DateTime value) =>
    '${adminKigaliDate(value)} · ${adminKigaliTime(value)}:${value.second.toString().padLeft(2, '0')} · Africa/Kigali';

Never _invalid() =>
    throw const FormatException('Shadow run history could not be validated.');

Map<Object?, Object?> _object(Object? value, Set<String> keys) {
  if (value is! Map ||
      value.length != keys.length ||
      value.keys.any((key) => key is! String || !keys.contains(key))) {
    _invalid();
  }
  return value;
}

int _integer(Object? value, {int min = 0, int max = _safeInteger}) {
  if (value is! int || value < min || value > max) _invalid();
  return value;
}

String _uuid(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value)) {
    _invalid();
  }
  return value.toLowerCase();
}

DateTime _instant(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$',
      ).hasMatch(value)) {
    _invalid();
  }
  try {
    return exactJsonTimestamp(value, field: 'shadow history timestamp');
  } on FormatException {
    _invalid();
  }
}

T _enum<T extends Enum>(Object? value, List<T> values) =>
    values.firstWhere((candidate) => candidate.name == value, orElse: _invalid);

enum AdminShadowLeaseState { idle, active, expired }

enum AdminShadowRunStatus { running, completed, expired }

enum AdminShadowObservation { ok, unknown, attention }

class AdminShadowRunsCursor {
  const AdminShadowRunsCursor({required this.startedAt, required this.runId});
  final DateTime startedAt;
  final String runId;

  factory AdminShadowRunsCursor._parse(Object? value) {
    final json = _object(value, {'started_at', 'run_id'});
    return AdminShadowRunsCursor(
      startedAt: _instant(json['started_at']),
      runId: _uuid(json['run_id']),
    );
  }

  int _compare(AdminShadowRunsCursor other) {
    final time = startedAt.compareTo(other.startedAt);
    return time != 0 ? time : runId.compareTo(other.runId);
  }
}

class AdminShadowLease {
  const AdminShadowLease._({
    required this.state,
    required this.fenceVersion,
    required this.activeRunId,
    required this.expiresAt,
  });
  final AdminShadowLeaseState state;
  final int fenceVersion;
  final String? activeRunId;
  final DateTime? expiresAt;

  factory AdminShadowLease._parse(Object? value, DateTime checkedAt) {
    final json = _object(value, {
      'state',
      'fence_version',
      'active_run_id',
      'lease_expires_at',
    });
    final state = _enum(json['state'], AdminShadowLeaseState.values);
    final fence = _integer(json['fence_version'], max: 1000000000);
    final runId = json['active_run_id'] == null
        ? null
        : _uuid(json['active_run_id']);
    final expiry = json['lease_expires_at'] == null
        ? null
        : _instant(json['lease_expires_at']);
    if (state == AdminShadowLeaseState.idle) {
      if (runId != null || expiry != null) _invalid();
    } else if (runId == null || expiry == null || fence == 0) {
      _invalid();
    } else if ((state == AdminShadowLeaseState.active) !=
        expiry.isAfter(checkedAt)) {
      _invalid();
    }
    return AdminShadowLease._(
      state: state,
      fenceVersion: fence,
      activeRunId: runId,
      expiresAt: expiry,
    );
  }
}

class AdminShadowSummary {
  const AdminShadowSummary._({
    required this.observation,
    required this.alertCounts,
    required this.smsEnabled,
    required this.smsCounts,
  });
  final AdminShadowObservation observation;
  final Map<String, int> alertCounts;
  final bool smsEnabled;
  final Map<String, int> smsCounts;

  static const alertLabels = {
    'ok': 'Checks OK',
    'unknown': 'Checks unknown',
    'attention': 'Checks needing attention',
    'not_applicable': 'Checks not applicable',
  };

  factory AdminShadowSummary._parse(Object? value) {
    final json = _object(value, {
      'health_status',
      'alert_counts',
      'sms_queue',
      'checks_recorded',
      'samples_recorded',
      'business_mutations',
      'provider_sends',
    });
    if (_integer(json['checks_recorded']) != 13 ||
        _integer(json['samples_recorded']) != 1 ||
        _integer(json['business_mutations']) != 0 ||
        _integer(json['provider_sends']) != 0) {
      _invalid();
    }
    final alerts = _object(json['alert_counts'], alertLabels.keys.toSet());
    final counts = {
      for (final name in alertLabels.keys)
        name: _integer(alerts[name], max: 13),
    };
    if (counts.values.reduce((a, b) => a + b) != 13) _invalid();
    final sms = _object(json['sms_queue'], {
      'enabled',
      ...AdminSmsQueueHealth.countLabels.keys,
    });
    if (sms['enabled'] is! bool) _invalid();
    final smsCounts = {
      for (final name in AdminSmsQueueHealth.countLabels.keys)
        name: _integer(sms[name]),
    };
    final observation = _enum(
      json['health_status'],
      AdminShadowObservation.values,
    );
    final expected =
        counts['attention']! > 0 ||
            smsCounts['uncertain']! > 0 ||
            smsCounts['send_started']! > 0
        ? AdminShadowObservation.attention
        : counts['unknown']! > 0
        ? AdminShadowObservation.unknown
        : AdminShadowObservation.ok;
    if (observation != expected) _invalid();
    return AdminShadowSummary._(
      observation: observation,
      alertCounts: Map.unmodifiable(counts),
      smsEnabled: sms['enabled'] as bool,
      smsCounts: Map.unmodifiable(smsCounts),
    );
  }
}

class AdminShadowRun {
  const AdminShadowRun._({
    required this.runId,
    required this.requestId,
    required this.fenceVersion,
    required this.status,
    required this.startedAt,
    required this.leaseExpiresAt,
    required this.sampledAt,
    required this.completedAt,
    required this.summary,
  });
  final String runId, requestId;
  final int fenceVersion;
  final AdminShadowRunStatus status;
  final DateTime startedAt, leaseExpiresAt;
  final DateTime? sampledAt, completedAt;
  final AdminShadowSummary? summary;

  AdminShadowRunsCursor get cursor =>
      AdminShadowRunsCursor(startedAt: startedAt, runId: runId);

  factory AdminShadowRun._parse(Object? value, DateTime checkedAt) {
    final json = _object(value, {
      'run_id',
      'request_id',
      'fence_version',
      'status',
      'started_at',
      'lease_expires_at',
      'sampled_at',
      'completed_at',
      'summary',
    });
    final status = _enum(json['status'], AdminShadowRunStatus.values);
    final started = _instant(json['started_at']);
    final expires = _instant(json['lease_expires_at']);
    final sampled = json['sampled_at'] == null
        ? null
        : _instant(json['sampled_at']);
    final completed = json['completed_at'] == null
        ? null
        : _instant(json['completed_at']);
    final summary = json['summary'] == null
        ? null
        : AdminShadowSummary._parse(json['summary']);
    if (expires.difference(started) != const Duration(seconds: 120) ||
        started.isAfter(checkedAt) ||
        (sampled == null) != (summary == null) ||
        (sampled != null &&
            (sampled.isBefore(started) ||
                !sampled.isBefore(expires) ||
                sampled.isAfter(checkedAt)))) {
      _invalid();
    }
    if (status == AdminShadowRunStatus.completed) {
      if (completed == null ||
          sampled == null ||
          completed.isBefore(sampled) ||
          !completed.isBefore(expires) ||
          completed.isAfter(checkedAt)) {
        _invalid();
      }
    } else if (completed != null ||
        (status == AdminShadowRunStatus.running) !=
            expires.isAfter(checkedAt)) {
      _invalid();
    }
    return AdminShadowRun._(
      runId: _uuid(json['run_id']),
      requestId: _uuid(json['request_id']),
      fenceVersion: _integer(json['fence_version'], min: 1, max: 1000000000),
      status: status,
      startedAt: started,
      leaseExpiresAt: expires,
      sampledAt: sampled,
      completedAt: completed,
      summary: summary,
    );
  }
}

/// Strict adapter of the persisted history RPC, never a client-created run.
class AdminShadowRunsSnapshot {
  const AdminShadowRunsSnapshot._({
    required this.checkedAt,
    required this.lease,
    required this.rows,
    required this.total,
    required this.nextCursor,
  });
  final DateTime checkedAt;
  final AdminShadowLease lease;
  final List<AdminShadowRun> rows;
  final int total;
  final AdminShadowRunsCursor? nextCursor;

  factory AdminShadowRunsSnapshot.parse(
    Map<String, dynamic> value, {
    int limit = 20,
    DateTime? beforeStartedAt,
    String? beforeRunId,
  }) {
    if (limit < 1 ||
        limit > 50 ||
        (beforeStartedAt == null) != (beforeRunId == null)) {
      _invalid();
    }
    final before = beforeStartedAt == null
        ? null
        : AdminShadowRunsCursor(
            startedAt: beforeStartedAt.toUtc(),
            runId: _uuid(beforeRunId),
          );
    final json = _object(value, {
      'contract_version',
      'mode',
      'scope',
      'checked_at',
      'lease',
      'rows',
      'total',
      'next_cursor',
    });
    if (_integer(json['contract_version']) != 1 ||
        json['mode'] != 'shadow' ||
        json['scope'] != 'collect_platform') {
      _invalid();
    }
    final checked = _instant(json['checked_at']);
    final lease = AdminShadowLease._parse(json['lease'], checked);
    if (json['rows'] is! List || (json['rows'] as List).length > limit) {
      _invalid();
    }
    final rows = [
      for (final row in json['rows'] as List)
        AdminShadowRun._parse(row, checked),
    ];
    final total = _integer(json['total']);
    if (total < rows.length) _invalid();
    final ids = <String>{};
    AdminShadowRunsCursor? previous = before;
    for (final row in rows) {
      if (!ids.add(row.runId) ||
          row.fenceVersion > lease.fenceVersion ||
          (previous != null && row.cursor._compare(previous) >= 0)) {
        _invalid();
      }
      if (row.runId == lease.activeRunId &&
          (row.fenceVersion != lease.fenceVersion ||
              row.leaseExpiresAt != lease.expiresAt ||
              row.status !=
                  (lease.state == AdminShadowLeaseState.active
                      ? AdminShadowRunStatus.running
                      : AdminShadowRunStatus.expired))) {
        _invalid();
      }
      previous = row.cursor;
    }
    final cursor = json['next_cursor'] == null
        ? null
        : AdminShadowRunsCursor._parse(json['next_cursor']);
    if (before == null && cursor == null && total != rows.length) _invalid();
    if (cursor != null &&
        (rows.length != limit ||
            total <= rows.length ||
            cursor._compare(rows.last.cursor) != 0)) {
      _invalid();
    }
    return AdminShadowRunsSnapshot._(
      checkedAt: checked,
      lease: lease,
      rows: List.unmodifiable(rows),
      total: total,
      nextCursor: cursor,
    );
  }

  /// Freshness of this history read; old completed observations stay historical.
  bool isFresh(DateTime now) =>
      !now.toUtc().isBefore(checkedAt.subtract(const Duration(seconds: 5))) &&
      now.toUtc().isBefore(checkedAt.add(const Duration(seconds: 60)));
}

class AdminShadowRunsQuery {
  const AdminShadowRunsQuery({
    this.limit = 20,
    this.beforeStartedAt,
    this.beforeRunId,
  });
  final int limit;
  final DateTime? beforeStartedAt;
  final String? beforeRunId;
  @override
  bool operator ==(Object other) =>
      other is AdminShadowRunsQuery &&
      limit == other.limit &&
      beforeStartedAt == other.beforeStartedAt &&
      beforeRunId == other.beforeRunId;
  @override
  int get hashCode => Object.hash(limit, beforeStartedAt, beforeRunId);
}

class AdminShadowRunsDenied implements Exception {
  const AdminShadowRunsDenied();
}

final adminShadowRunsProvider = FutureProvider.autoDispose
    .family<AdminShadowRunsSnapshot, AdminShadowRunsQuery>((ref, query) async {
      ref.watch(adminAuthSessionScopeProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (identity?.permissions.contains('system_health.read') != true ||
          identity?.permissions.contains('notifications.read') != true) {
        throw const AdminShadowRunsDenied();
      }
      Map<String, dynamic> result;
      try {
        result = await repository.shadowRuns(
          limit: query.limit,
          beforeStartedAt: query.beforeStartedAt,
          beforeRunId: query.beforeRunId,
        );
      } on PostgrestException catch (error) {
        if (!current) throw const AdminSessionChanged();
        if (error.code == '42501') throw const AdminShadowRunsDenied();
        if (error.code == 'PGRST202' || error.code == '42883') {
          throw UnsupportedError('Persisted shadow history is unavailable.');
        }
        rethrow;
      }
      if (!current) throw const AdminSessionChanged();
      return AdminShadowRunsSnapshot.parse(
        result,
        limit: query.limit,
        beforeStartedAt: query.beforeStartedAt,
        beforeRunId: query.beforeRunId,
      );
    });

/// Read-only history. Pagination changes the viewed window, never starts a run.
class AdminShadowRunsView extends ConsumerStatefulWidget {
  const AdminShadowRunsView({required this.now, this.pageSize = 20, super.key});
  final DateTime now;
  final int pageSize;
  @override
  ConsumerState<AdminShadowRunsView> createState() =>
      _AdminShadowRunsViewState();
}

class _AdminShadowRunsViewState extends ConsumerState<AdminShadowRunsView> {
  late AdminShadowRunsQuery _query = AdminShadowRunsQuery(
    limit: widget.pageSize,
  );
  final _previous = <AdminShadowRunsQuery>[];
  Object? _scope;

  void _refresh() {
    final newest = AdminShadowRunsQuery(limit: widget.pageSize);
    setState(() {
      _previous.clear();
      _query = newest;
    });
    ref.invalidate(adminShadowRunsProvider(newest));
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(adminAuthSessionScopeProvider);
    if (_scope != scope) {
      _scope = scope;
      _previous.clear();
      _query = AdminShadowRunsQuery(limit: widget.pageSize);
    }
    final identity = ref.watch(adminIdentityProvider);
    if (identity.isLoading) return const _HistoryLoading();
    if (identity.valueOrNull?.permissions.contains('system_health.read') !=
            true ||
        identity.valueOrNull?.permissions.contains('notifications.read') !=
            true) {
      return const _HistoryDenied();
    }
    final history = ref.watch(adminShadowRunsProvider(_query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Scope: Collect platform · All groups'),
        const SizedBox(height: 8),
        const Text(
          'Manual shadow monitoring records observations only. A completed run does not establish a healthy service, an attested Codex client or message delivery.',
        ),
        const SizedBox(height: 16),
        history.when(
          skipLoadingOnRefresh: false,
          loading: () => const _HistoryLoading(),
          error: (error, _) => error is AdminShadowRunsDenied
              ? const _HistoryDenied()
              : _HistoryMessage(
                  label: error is UnsupportedError
                      ? 'Run telemetry unavailable'
                      : 'Run history read failed',
                  message: error is UnsupportedError
                      ? 'Persisted manual shadow run history is unavailable from this service.'
                      : error is AdminSessionChanged
                      ? 'Your Admin session changed. Reopen this page to read history.'
                      : 'Run history could not be loaded or validated. Other service measurements remain separate.',
                ),
          data: (snapshot) => _data(snapshot),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: history.isLoading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh history'),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Native Codex schedules are managed in Codex. Gateway internet, telephony, SIM permissions and carrier delivery callbacks are not measured by this history.',
        ),
      ],
    );
  }

  Widget _data(AdminShadowRunsSnapshot snapshot) {
    final fresh = snapshot.isFresh(widget.now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('History checked ${_historyTime(snapshot.checkedAt)}'),
        const SizedBox(height: 12),
        if (!fresh)
          const _HistoryMessage(
            label: 'History read expired',
            message:
                'Refresh history to check the lease and reload persisted observations. Previous measurements are hidden.',
          )
        else ...[
          _LeaseView(lease: snapshot.lease, now: widget.now),
          const SizedBox(height: 16),
          Text('${snapshot.total} persisted monitoring runs'),
          const SizedBox(height: 8),
          if (snapshot.rows.isEmpty)
            const _HistoryMessage(
              label: 'No monitoring runs in this history window',
              message:
                  'This service returned no persisted run records. This does not establish service health or connectivity.',
            )
          else
            for (var index = 0; index < snapshot.rows.length; index++) ...[
              _RunView(
                key: ValueKey(snapshot.rows[index].runId),
                run: snapshot.rows[index],
                now: widget.now,
                expanded: index == 0,
              ),
              const SizedBox(height: 8),
            ],
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (_previous.isNotEmpty)
                OutlinedButton(
                  onPressed: () =>
                      setState(() => _query = _previous.removeLast()),
                  child: const Text('Newer runs'),
                ),
              if (snapshot.nextCursor case final cursor?)
                OutlinedButton(
                  onPressed: () => setState(() {
                    _previous.add(_query);
                    _query = AdminShadowRunsQuery(
                      limit: widget.pageSize,
                      beforeStartedAt: cursor.startedAt,
                      beforeRunId: cursor.runId,
                    );
                  }),
                  child: const Text('Older runs'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LeaseView extends StatelessWidget {
  const _LeaseView({required this.lease, required this.now});
  final AdminShadowLease lease;
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final elapsed =
        lease.state == AdminShadowLeaseState.active &&
        !lease.expiresAt!.isAfter(now.toUtc());
    final label = elapsed
        ? 'Lease elapsed; refresh history'
        : switch (lease.state) {
            AdminShadowLeaseState.idle => 'Lease idle',
            AdminShadowLeaseState.active => 'Lease active',
            AdminShadowLeaseState.expired => 'Lease expired',
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminStatusChip(label: label),
        if (lease.expiresAt != null) ...[
          const SizedBox(height: 8),
          Text('Lease expiry ${_historyTime(lease.expiresAt!)}'),
        ],
      ],
    );
  }
}

class _RunView extends StatelessWidget {
  const _RunView({
    required this.run,
    required this.now,
    required this.expanded,
    super.key,
  });
  final AdminShadowRun run;
  final DateTime now;
  final bool expanded;
  @override
  Widget build(BuildContext context) {
    final summary = run.summary;
    final status = switch (run.status) {
      AdminShadowRunStatus.completed => 'Monitoring finished',
      AdminShadowRunStatus.expired => 'Run lease expired',
      AdminShadowRunStatus.running =>
        run.leaseExpiresAt.isAfter(now.toUtc())
            ? 'Monitoring in progress'
            : 'Run lease elapsed since history check',
    };
    final observation = switch (summary?.observation) {
      AdminShadowObservation.ok => 'Observed checks OK',
      AdminShadowObservation.unknown => 'Observation unknown',
      AdminShadowObservation.attention => 'Observation needs review',
      null => 'No sample recorded',
    };
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: CollectRadius.cardBorder,
      ),
      child: ExpansionTile(
        initiallyExpanded: expanded,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Run ${run.runId.substring(0, 8)}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AdminStatusChip(label: status),
                AdminStatusChip(label: observation),
              ],
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Started ${_historyTime(run.startedAt)}'),
        ),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Lease expiry ${_historyTime(run.leaseExpiresAt)}'),
              if (run.sampledAt != null)
                Text('Observed ${_historyTime(run.sampledAt!)}'),
              if (run.completedAt != null)
                Text('Completed ${_historyTime(run.completedAt!)}'),
              const SizedBox(height: 12),
              if (summary == null)
                const Text(
                  'No persisted observation is available for this run.',
                )
              else ...[
                const Text(
                  'Historical observation · Checks recorded 13 · Samples recorded 1 · Business changes 0 · Provider sends 0',
                ),
                const SizedBox(height: 12),
                _Counts(
                  labels: AdminShadowSummary.alertLabels,
                  counts: summary.alertCounts,
                ),
                const SizedBox(height: 12),
                Text(
                  summary.smsEnabled
                      ? 'SMS receipt gate was enabled at observation'
                      : 'SMS receipt dispatch was disabled at observation',
                ),
                const SizedBox(height: 12),
                _Counts(
                  labels: AdminSmsQueueHealth.countLabels,
                  counts: summary.smsCounts,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Counts extends StatelessWidget {
  const _Counts({required this.labels, required this.counts});
  final Map<String, String> labels;
  final Map<String, int> counts;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 24,
      runSpacing: 12,
      children: [
        for (final entry in labels.entries)
          SizedBox(
            width: constraints.maxWidth < 200 ? constraints.maxWidth : 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.value, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  '${counts[entry.key]}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _HistoryLoading extends StatelessWidget {
  const _HistoryLoading();
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Loading persisted run history',
    child: const LinearProgressIndicator(),
  );
}

class _HistoryDenied extends StatelessWidget {
  const _HistoryDenied();
  @override
  Widget build(BuildContext context) => const _HistoryMessage(
    label: 'Run history access denied',
    message:
        'Both system health and notification read permissions are required. The backend also verifies current platform-owner authority.',
  );
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({required this.label, required this.message});
  final String label, message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminStatusChip(label: label),
        const SizedBox(height: 12),
        Text(message),
      ],
    ),
  );
}
