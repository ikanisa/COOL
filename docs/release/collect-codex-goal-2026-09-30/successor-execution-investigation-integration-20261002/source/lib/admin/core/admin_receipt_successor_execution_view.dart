import 'dart:async';
import 'package:flutter/material.dart';
import 'admin_receipt_successor_execution_controller.dart';

String _state(Object? value) => switch (value) {
  'not_materialized' => 'Approved · awaiting execution',
  'unarmed_granted' => 'Granted · awaiting final authority',
  'unarmed_expired' => 'Grant expired · outcome retained',
  'unarmed_revoked' => 'Revoked before final authority',
  'armed_unknown' => 'Final authority recorded · outcome unknown',
  'observed_sent' => 'Sent callback observed',
  'uncertain' => 'Uncertain · investigation required',
  _ => 'Execution unavailable',
};

class AdminReceiptSuccessorExecutionView extends StatefulWidget {
  const AdminReceiptSuccessorExecutionView({
    required this.controller,
    required this.now,
    super.key,
  });
  final AdminReceiptSuccessorExecutionController controller;
  final DateTime Function() now;
  @override
  State<AdminReceiptSuccessorExecutionView> createState() =>
      _ExecutionViewState();
}

class _ExecutionViewState extends State<AdminReceiptSuccessorExecutionView> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(widget.controller.refresh());
  }

  @override
  void didUpdateWidget(AdminReceiptSuccessorExecutionView old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      unawaited(widget.controller.refresh());
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  Widget _evidence(String label, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        SelectableText(value?.toString() ?? 'Unavailable'),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final c = widget.controller, snapshot = c.snapshot;
    final execution = snapshot?.execution, route = execution?['route'] as Map?;
    final attempt = execution?['attempt'] as Map?,
        archive = execution?['archive'] as Map?;
    final events = execution?['execution_events'] as List? ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Retry execution',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: c.loading ? null : c.refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh evidence'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Investigate the approved retry and its callback evidence. The original receipt remains retained.',
            ),
            if (c.loading) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: const Text('Loading execution evidence…'),
              ),
              const LinearProgressIndicator(),
            ],
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(liveRegion: true, child: Text(c.error!)),
              ),
            if (snapshot != null && !snapshot.available)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'This approval’s execution evidence is unavailable.',
                ),
              ),
            if (snapshot?.available == true) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  _state(snapshot!.state),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (!snapshot.fresh(widget.now()))
                const Text(
                  'The current state sample has expired. Refresh evidence for a current view.',
                ),
              _evidence('Approval', c.approvalId),
              _evidence('Original receipt', c.primaryReceiptId),
              if (route != null)
                _evidence('Retry job', route['dispatch_job_id']),
              if (attempt != null) ...[
                _evidence('Attempt', attempt['attempt_id']),
                _evidence('Run', attempt['run_id']),
                _evidence(
                  'Shared budget reservation',
                  attempt['reservation_id'],
                ),
                _evidence('Grant expiry', attempt['expires_at']),
              ],
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: Text(
                  'Execution timeline',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (events.isEmpty)
                const Text(
                  'No execution job has been materialized for this approval.',
                ),
              for (final event in events)
                _evidence(
                  event['event_kind'] == 'grant'
                      ? 'Grant recorded'
                      : 'Final authority recorded',
                  '${event['recorded_at']} · revision ${event['lineage_after']}\nRequest ${event['request_id']}',
                ),
              if (execution?['revocation'] != null)
                _evidence(
                  'Revocation recorded',
                  (execution!['revocation'] as Map)['recorded_at'],
                ),
              if (archive != null) ...[
                _evidence('Journal acknowledgement', archive['archive_ack_id']),
                _evidence('Acknowledgement recorded', archive['recorded_at']),
              ],
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: Text(
                  'Callback evidence',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                'Showing ${c.observations.length} observations through revision ${snapshot.cutoff}. The retained total is unknown.',
              ),
              if (c.observations.isEmpty)
                const Text(
                  'No callback observations are recorded in this evidence window.',
                ),
              for (final row in c.observations)
                ExpansionTile(
                  key: ValueKey(row['request_id']),
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    '${row['callback_kind'] == 'sent' ? 'Sent' : 'Delivery'} callback · segment ${(row['segment_index'] as int) + 1}',
                  ),
                  subtitle: Text(
                    '${_state(row['observed_state'])} · result ${row['result_code']}\n${row['recorded_at']}',
                  ),
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  children: [
                    _evidence('Original callback request', row['request_id']),
                    _evidence('Callback', row['callback_id']),
                    _evidence('Observed at', row['occurred_at']),
                    _evidence('Lineage revision', row['lineage_after']),
                    if (row['tp_status'] != null)
                      _evidence('Framework status', row['tp_status']),
                  ],
                ),
              if (c.next != null)
                TextButton.icon(
                  onPressed: c.historyBusy ? null : c.more,
                  icon: const Icon(Icons.expand_more),
                  label: Text(
                    c.historyBusy
                        ? 'Loading callback evidence…'
                        : 'Load more callback evidence',
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Framework callbacks and a journal acknowledgement do not prove carrier delivery or authorize another send.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
