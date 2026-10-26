part of 'admin_runtime.dart';

final adminReceiptOperationalTelemetryProvider =
    FutureProvider.autoDispose<AdminReceiptOperationalTelemetry>((ref) async {
      final session = ref.watch(adminAuthSessionScopeProvider);
      ref.watch(_adminIdentityRevisionProvider);
      ref.watch(adminRealtimeTickProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var retained = true;
      ref.onDispose(() => retained = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!retained) throw const AdminSessionChanged();
      if (session == null ||
          identity?.userId != session.key.userId ||
          !_receiptWorkerCanRead(identity)) {
        throw const AdminExceptionDenied();
      }
      final revision = ref.read(_adminIdentityRevisionProvider);
      final roles = Set.of(identity!.roles);
      final permissions = Set.of(identity.permissions);
      bool current() {
        if (!retained) return false;
        final actor = _adminResolvedIdentity(ref.read(adminIdentityProvider));
        return ref.read(adminAuthSessionScopeProvider) == session &&
            identical(ref.read(adminRepositoryProvider), repository) &&
            ref.read(_adminIdentityRevisionProvider) == revision &&
            actor?.userId == identity.userId &&
            actor!.roles.length == roles.length &&
            roles.containsAll(actor.roles) &&
            actor.permissions.length == permissions.length &&
            permissions.containsAll(actor.permissions);
      }

      if (!current()) throw const AdminSessionChanged();
      try {
        final raw = await repository.receiptOperationalTelemetry().timeout(
          const Duration(seconds: 15),
        );
        if (!current()) throw const AdminSessionChanged();
        return AdminReceiptOperationalTelemetry.parse(raw);
      } catch (_) {
        if (!current()) throw const AdminSessionChanged();
        rethrow;
      }
    });

class AdminReceiptTelemetryCard extends ConsumerStatefulWidget {
  const AdminReceiptTelemetryCard({
    super.key,
    this.compact = false,
    this.embedded = false,
  });
  final bool compact, embedded;

  @override
  ConsumerState<AdminReceiptTelemetryCard> createState() =>
      _AdminReceiptTelemetryCardState();
}

class _AdminReceiptTelemetryCardState
    extends ConsumerState<AdminReceiptTelemetryCard> {
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
    final session = ref.watch(adminAuthSessionScopeProvider);
    final identityState = ref.watch(adminIdentityProvider);
    final identity = _adminResolvedIdentity(identityState);
    final allowed =
        session != null &&
        identity?.userId == session.key.userId &&
        _receiptWorkerCanRead(identity);
    final sample = allowed
        ? ref.watch(adminReceiptOperationalTelemetryProvider)
        : null;
    final report = sample?.isLoading == false ? sample?.asData?.value : null;
    final fresh = report?.isFresh(ref.watch(adminClockProvider)()) == true;
    final scope = _AdminActionScope(ref);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded) ...[
          Semantics(
            header: true,
            child: Text(
              'Receipt operations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (identityState.isLoading)
          const Text('Checking receipt operations access…')
        else if (!allowed)
          const Text(
            'A current platform owner with payment, notification and system health read access is required.',
          )
        else ...[
          if (sample!.isLoading)
            Semantics(
              liveRegion: true,
              child: const Text('Loading legacy receipt measurements…'),
            )
          else if (sample.hasError)
            const Text(
              'Legacy receipt measurements could not be verified. Refresh and check current access.',
            )
          else if (!fresh)
            const Text(
              'Legacy receipt measurements expired. Refresh for current evidence.',
            )
          else if (report != null) ...[
            Text(
              '${report.mode} · Policy revision ${report.policyRevision} · '
              '${report.configuredCollectionCount} configured collections',
            ),
            if (report.emergencyStop) const Text('Emergency stop is active.'),
            Text('Checked ${adminKigaliDateTime(report.checkedAt)}'),
            Text(
              '24-hour window: ${adminKigaliDateTime(report.windowStart)} '
              'to ${adminKigaliDateTime(report.windowEnd)}',
            ),
            const SizedBox(height: 16),
            if (!report.measurementAvailable)
              Semantics(
                liveRegion: true,
                child: Text(_telemetryUnavailable(report.evidenceLimitCodes)),
              )
            else if (widget.compact)
              _ReceiptTelemetryMetrics(
                dashboard: true,
                values: {
                  'unhandled_events': report.backlog!['unhandled_events'],
                  'oldest_unhandled_age_seconds':
                      report.backlog!['oldest_unhandled_age_seconds'],
                  'latency_p95_ms': report.handling!['latency_p95_ms'],
                  'uncertain_attempts': report.unknown!['uncertain_attempts'],
                },
              )
            else ...[
              _ReceiptTelemetryGroup(title: 'Backlog', values: report.backlog!),
              _ReceiptTelemetryGroup(
                title: 'Durable event handling',
                values: report.handling!,
              ),
              _ReceiptTelemetryGroup(
                title: 'Global UTC-day budget limits',
                values: {
                  for (final key in [
                    'actions_reserved',
                    'actions_cap',
                    'sms_segments_reserved',
                    'sms_segments_cap',
                  ])
                    key: report.budgets![key] as int,
                },
              ),
              _ReceiptTelemetryGroup(
                title: 'Authenticated callback observations',
                values: report.callbacks!,
              ),
              _ReceiptTelemetryGroup(
                title: 'Unknown outcomes and callback gaps',
                values: report.unknown!,
              ),
              const Text(
                'Unknown-outcome and callback-gap categories can overlap.',
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Handling measures durable event work. Callback coverage does not '
              'confirm carrier delivery. Budget limits do not measure capacity. '
              'Costs have not been measured.',
            ),
            if (report.alerts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('No retained alert observations in this sample.'),
              )
            else ...[
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(
                  'Retained alert observations',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final alert in report.alerts)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${alert.label} · ${_telemetryAlertStatus(alert.status)}',
                      ),
                      Text(alert.responseLabel),
                      Text(
                        'Episode ${alert.episode} · Revision ${alert.revision} · '
                        'Observed ${adminKigaliDateTime(alert.observedAt)}',
                      ),
                      if (alert.exceptionId != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton(
                            key: ValueKey('telemetry-investigate-${alert.id}'),
                            onPressed: () {
                              final current = ref.read(
                                adminReceiptOperationalTelemetryProvider,
                              );
                              if (!scope.isCurrent ||
                                  current.isLoading ||
                                  !identical(current.asData?.value, report) ||
                                  !report.isFresh(
                                    ref.read(adminClockProvider)(),
                                  )) {
                                return;
                              }
                              unawaited(
                                _showAdminExceptionFollowUp(
                                  context,
                                  scope,
                                  alert.exceptionId!,
                                ),
                              );
                            },
                            child: const Text('Investigate retained exception'),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],
          if (widget.compact)
            const AdminReceiptCallbackDeadlineCard(aggregateOnly: true)
          else
            AdminReceiptCallbackDeadlineCard(
              onFollowUp: (id) async {
                if (scope.isCurrent) {
                  await _showAdminExceptionFollowUp(context, scope, id);
                }
              },
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: sample.isLoading
                    ? null
                    : () {
                        if (scope.isCurrent) {
                          ref.invalidate(
                            adminReceiptOperationalTelemetryProvider,
                          );
                        }
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh receipt operations'),
              ),
              if (widget.compact)
                TextButton(
                  onPressed: () {
                    if (scope.isCurrent) context.go('/admin/automations');
                  },
                  child: const Text('View receipt operations'),
                ),
            ],
          ),
        ],
      ],
    );
    return widget.embedded
        ? content
        : widget.compact
        ? Card(
            child: Padding(padding: const EdgeInsets.all(20), child: content),
          )
        : AdminDataSection(
            child: Padding(padding: const EdgeInsets.all(20), child: content),
          );
  }
}

String _telemetryAlertStatus(String status) => switch (status) {
  'active' => 'Active',
  'clear' => 'Source cleared',
  'superseded' => 'Superseded',
  _ => throw const FormatException('Invalid telemetry alert status.'),
};

String _telemetryUnavailable(Set<String> codes) {
  final reasons = <String>[];
  const labels = {
    'no_configured_scope': 'No collections are configured for measurement.',
    'measurement_timeout': 'Measurement timed out.',
    'measurement_unavailable': 'The measurement source is unavailable.',
    'policy_changed': 'Policy changed during measurement.',
  };
  for (final entry in labels.entries) {
    if (codes.contains(entry.key)) reasons.add(entry.value);
  }
  return 'Legacy measurements unavailable. ${reasons.join(' ')}';
}

class _ReceiptTelemetryGroup extends StatelessWidget {
  const _ReceiptTelemetryGroup({required this.title, required this.values});
  final String title;
  final Map<String, int?> values;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 12),
        _ReceiptTelemetryMetrics(values: values),
      ],
    ),
  );
}

class _ReceiptTelemetryMetrics extends StatelessWidget {
  const _ReceiptTelemetryMetrics({
    required this.values,
    this.dashboard = false,
  });
  final Map<String, int?> values;
  final bool dashboard;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!dashboard) {
        return Column(
          children: [
            for (final metric in values.entries)
              AdminDataFieldRow(
                label:
                    AdminReceiptOperationalTelemetry.metricLabels[metric.key]!,
                value: _telemetryMetricValue(metric.key, metric.value),
              ),
          ],
        );
      }
      final columns = constraints.maxWidth >= 900
          ? 4
          : constraints.maxWidth >= 500
          ? 2
          : 1;
      final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final metric in values.entries)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AdminReceiptOperationalTelemetry.metricLabels[metric.key]!,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _telemetryMetricValue(metric.key, metric.value),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

String _telemetryMetricValue(String key, int? value) {
  if (value == null) {
    return key == 'oldest_unhandled_age_seconds'
        ? 'No unhandled events'
        : 'No handled events';
  }
  if (key.endsWith('_seconds')) return '$value seconds';
  if (key.endsWith('_ms')) return '$value ms';
  return '$value';
}
