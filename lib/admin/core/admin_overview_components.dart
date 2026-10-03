part of 'admin_runtime.dart';

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
          header: true,
          excludeSemantics: true,
          child: Row(
            children: [
              Icon(
                _adminOverviewHeaderIcon(label),
                size: 17,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
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
  if (target == null || target.trim().isEmpty) return 'Not available';
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

class _OverviewReadFailure extends StatelessWidget {
  const _OverviewReadFailure({
    required this.title,
    required this.error,
    required this.onRefresh,
  });
  final String title;
  final Object error;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) {
    final denied =
        error is _OverviewPermissionDenied ||
        error is PostgrestException &&
            (error as PostgrestException).code == '42501';
    return DecoratedBox(
      decoration: _overviewPanelDecoration(context.collectColors),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title · ${denied ? 'Access denied' : 'Unavailable'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              denied
                  ? 'Current read permission is required for this measurement.'
                  : 'This measurement could not be verified. Other sections remain available.',
            ),
            TextButton(
              onPressed: onRefresh,
              child: const Text('Refresh measurement'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewPostingPanel extends StatelessWidget {
  const _OverviewPostingPanel({
    required this.sample,
    required this.now,
    required this.onRefresh,
  });
  final AsyncValue<AdminReceiptOverview> sample;
  final DateTime now;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) {
    if (sample.isLoading) {
      return const AdminLoadingState(
        title: 'Loading today’s payments and receipts',
      );
    }
    if (sample.hasError) {
      return _OverviewReadFailure(
        title: 'Payments and receipts',
        error: sample.error!,
        onRefresh: onRefresh,
      );
    }
    final data = sample.valueOrNull;
    if (data == null || !data.isFresh(now)) {
      return _OverviewReadFailure(
        title: 'Payments and receipts · Stale',
        error: StateError('stale'),
        onRefresh: onRefresh,
      );
    }
    final colors = context.collectColors;
    final queue = data.receipts;
    final age = queue?.oldestPendingAt == null
        ? 'No pending receipts'
        : _overviewDuration(data.checkedAt.difference(queue!.oldestPendingAt!));
    return DecoratedBox(
      key: const Key('admin-overview-posted-payments'),
      decoration: _overviewPanelDecoration(colors),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Today · ${adminKigaliDate(data.dayStart)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text('Africa/Kigali · Rwanda MoMo · all groups'),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 16,
                runSpacing: 14,
                children: [
                  _OverviewReading(
                    label: 'Posted payments today',
                    value: '${data.postedCount}',
                    width: math.min(280, constraints.maxWidth),
                  ),
                  _OverviewReading(
                    label: 'Posted value today',
                    value: adminFormatRwfAmount('RWF ${data.postedValueRwf}'),
                    width: math.min(330, constraints.maxWidth),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Payments still posted at this check; reversed payments are excluded.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 14),
            Divider(color: colors.borderSoft),
            const SizedBox(height: 8),
            Semantics(
              header: true,
              child: Text(
                'Assisted SMS receipt queue',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            if (queue == null)
              const Text(
                'Receipt measurements · Access denied. notifications.read is required.',
              )
            else ...[
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 18,
                  runSpacing: 14,
                  children: [
                    _OverviewReading(
                      label: 'Receipts pending',
                      value: '${queue.pending}',
                      width: math.min(180, constraints.maxWidth),
                    ),
                    _OverviewReading(
                      label: 'Oldest pending',
                      value: age,
                      width: math.min(210, constraints.maxWidth),
                    ),
                    _OverviewReading(
                      label: 'Definite no-send failures',
                      value: '${queue.failedNoSend}',
                      width: math.min(240, constraints.maxWidth),
                    ),
                    _OverviewReading(
                      label: 'Unknown send outcome',
                      value: '${queue.uncertain}',
                      width: math.min(210, constraints.maxWidth),
                    ),
                    _OverviewReading(
                      label: 'Send started, unresolved',
                      value: '${queue.sendStarted}',
                      width: math.min(245, constraints.maxWidth),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${queue.queued} queued · ${queue.awaitingConfirmation} awaiting confirmation. '
                'Queue counts cover current receipt records; they do not attest handset delivery.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (queue.queued > 0)
                    TextButton(
                      onPressed: () =>
                          context.go('/admin/sms-receipts?status=queued'),
                      child: const Text('Review queued receipts'),
                    ),
                  if (queue.awaitingConfirmation > 0)
                    TextButton(
                      onPressed: () => context.go(
                        '/admin/sms-receipts?status=awaiting_confirmation',
                      ),
                      child: const Text('Review confirmations'),
                    ),
                  if (queue.failedNoSend > 0)
                    TextButton(
                      onPressed: () => context.go(
                        '/admin/sms-receipts?status=failed_no_send',
                      ),
                      child: const Text('Review definite failures'),
                    ),
                  if (queue.uncertain > 0)
                    TextButton(
                      onPressed: () =>
                          context.go('/admin/sms-receipts?status=uncertain'),
                      child: const Text('Investigate unknown outcomes'),
                    ),
                  if (queue.sendStarted > 0)
                    TextButton(
                      onPressed: () =>
                          context.go('/admin/sms-receipts?status=send_started'),
                      child: const Text('Review unresolved sends'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  'Checked ${adminKigaliDateTime(data.checkedAt)}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
                ),
                OutlinedButton(
                  onPressed: onRefresh,
                  child: const Text('Refresh payments and receipts'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _overviewDuration(Duration age) {
  if (age.inDays > 0) return '${age.inDays}d ${age.inHours % 24}h';
  if (age.inHours > 0) return '${age.inHours}h ${age.inMinutes % 60}m';
  return '${age.inMinutes}m ${age.inSeconds % 60}s';
}

class _OverviewReading extends StatelessWidget {
  const _OverviewReading({
    required this.label,
    required this.value,
    required this.width,
  });
  final String label, value;
  final double width;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.collectColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: CollectTypography.weightBold,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

class _OverviewServicePanel extends StatelessWidget {
  const _OverviewServicePanel({
    required this.health,
    required this.sms,
    required this.now,
    required this.onRefresh,
  });
  final AsyncValue<AdminOperationalHealth> health;
  final AsyncValue<AdminSmsQueueHealth> sms;
  final DateTime now;
  final VoidCallback onRefresh;

  String _measurementState<T>(AsyncValue<T> measurement, bool fresh) {
    if (measurement.isLoading) return 'Loading';
    if (measurement.hasError) {
      final error = measurement.error;
      if (error is _OverviewPermissionDenied ||
          error is PostgrestException && error.code == '42501') {
        return 'Access denied';
      }
      return 'Unavailable';
    }
    return fresh ? 'Observed' : 'Stale · refresh required';
  }

  String _healthState(AdminOperationalHealth sample, Iterable<String> keys) {
    final states = keys.map((key) => sample.alerts[key]);
    if (states.contains('attention')) return 'Attention';
    if (states.contains('unknown')) return 'Unknown';
    return 'OK';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final operational = !health.isLoading && !health.hasError
        ? health.valueOrNull
        : null;
    final queue = !sms.isLoading && !sms.hasError ? sms.valueOrNull : null;
    final healthFresh = operational?.isFresh(now) == true;
    final smsFresh = queue?.isFresh(now) == true;
    const paymentKeys = [
      'receipt_parse_backlog',
      'receipt_parse_age',
      'receipt_parse_failure',
      'receipt_parser_lease_expired',
      'payment_unmatched',
      'payment_review_age',
      'reconciliation_exception',
    ];
    const pushKeys = [
      'push_queue_age',
      'push_expired_lease',
      'push_missing_lease',
      'push_attempt_failure',
      'push_scheduler_stale',
    ];
    return DecoratedBox(
      decoration: _overviewPanelDecoration(colors),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Operational measurements',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Platform scope · each service is checked independently',
            ),
            const SizedBox(height: 12),
            _OverviewServiceReading(
              label: 'Payment processing',
              value: healthFresh
                  ? 'Observed queue checks: ${_healthState(operational!, paymentKeys)}'
                  : _measurementState(health, healthFresh),
            ),
            _OverviewServiceReading(
              label: 'Assisted SMS receipts',
              value: smsFresh
                  ? '${queue!.enabled ? 'Gate enabled' : 'Gate closed'} · '
                        '${queue.counts['queued']} queued · ${queue.counts['active_workers']} recent operator heartbeats'
                  : _measurementState(sms, smsFresh),
            ),
            _OverviewServiceReading(
              label: 'Push notifications',
              value: healthFresh
                  ? 'Observed queue checks: ${_healthState(operational!, pushKeys)} · '
                        'scheduler ${operational.schedulerState} · provider configuration unverified'
                  : _measurementState(health, healthFresh),
            ),
            const _OverviewServiceReading(
              label: 'SMS gateway',
              value:
                  'Unavailable · sender/device/network diagnostics are not connected',
            ),
            const _OverviewServiceReading(
              label: 'Codex supervisor',
              value:
                  'Manual shadow history available to review · unattended execution is unavailable',
            ),
            const SizedBox(height: 8),
            Text(
              'An enabled gate or recent heartbeat does not confirm sender availability or delivery.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            if (healthFresh)
              Text(
                'Health checked ${adminKigaliDateTime(operational!.checkedAt)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
              ),
            if (smsFresh)
              Text(
                'SMS checked ${adminKigaliDateTime(queue!.observedAt)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: onRefresh,
                  child: const Text('Refresh operational status'),
                ),
                TextButton(
                  onPressed: () => context.go('/admin/system-health'),
                  child: const Text('View system health'),
                ),
                TextButton(
                  onPressed: () => context.go('/admin/automations'),
                  child: const Text('View manual monitoring'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewServiceReading extends StatelessWidget {
  const _OverviewServiceReading({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(value),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 190,
              child: Text(label, style: Theme.of(context).textTheme.titleSmall),
            ),
            Expanded(child: Text(value)),
          ],
        );
      },
    ),
  );
}
